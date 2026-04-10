#!/usr/bin/env bash
# Full reset of Kubernetes + Rook-Ceph lab artifacts (no-hang version)
set +e

echo "========================================================"
echo "RESET START - Host: $(hostname) - User: $(whoami)"
echo "========================================================"

# -------------------------
# Helpers
# -------------------------
log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run_ign() { timeout 10s "$@" >/dev/null 2>&1 || true; }

# -------------------------
# 0) Kubernetes Cleanup (Non-blocking)
# -------------------------
if have kubectl && [ -f "$HOME/.kube/config" ]; then
    log "Attempting to delete namespace & StorageClasses (non-blocking)..."
    timeout 15s kubectl delete ns rook-ceph --wait=false --ignore-not-found=true 2>/dev/null || true
    timeout 5s kubectl delete storageclass rook-ceph-block --ignore-not-found=true 2>/dev/null || true
fi

# -------------------------
# 1) Mount Cleanup (Crucial for Ceph RBD)
# -------------------------
log "--- 1. Unmounting stale K8s/CSI mounts (best-effort) ---"
# Unmount anything that looks like kubelet/ceph/csi/rbd in /proc/mounts
grep -E 'kubelet|ceph|csi|rbd' /proc/mounts | cut -d' ' -f2 | sort -r | while read -r mount_path; do
    log "Unmounting $mount_path..."
    sudo umount -f -l "$mount_path" 2>/dev/null || true
done

# Additional best-effort unmount roots that often get stuck
for root in /var/lib/kubelet/plugins /var/lib/kubelet/pods /var/lib/ceph; do
  if [ -d "$root" ]; then
    mount | grep -E "^.* on $root" >/dev/null 2>&1 || true
    # Try unmount anything under that root via /proc/mounts patterns again
    grep -E "$root" /proc/mounts | cut -d' ' -f2 | sort -r | while read -r mp; do
      log "Unmounting $mp (root sweep)..."
      sudo umount -f -l "$mp" 2>/dev/null || true
    done
  fi
done

# -------------------------
# 2) Tear down kind clusters
# -------------------------
log "--- 2. Tearing down Kubernetes (kind) ---"
if have kind; then
    # Note: your kind config might be stored under different names; delete all clusters.
    timeout 30s kind delete clusters --all >/dev/null 2>&1 || true
    sudo rm -f /usr/local/bin/kind /bin/kind || true
fi

# Clean leftover Docker networks/volumes (helps avoid "stale CSI" style leftovers)
if have docker; then
  log "--- Docker cleanup (prune networks/volumes) ---"
  timeout 10s docker network prune -f >/dev/null 2>&1 || true
  timeout 10s docker volume prune -f >/dev/null 2>&1 || true
fi

# -------------------------
# 3) Remove Tooling
# -------------------------
log "--- 3. Removing tooling ---"
if have snap; then
    timeout 20s sudo snap remove kubectl 2>/dev/null || true
fi
sudo rm -f /usr/local/bin/kubectl /bin/kubectl || true

# kubeadm/kubelet purge if installed
run_ign sudo apt-get purge -y kubelet kubeadm kubectl 2>/dev/null

# -------------------------
# 4) Docker/Containerd (With kill protection)
# -------------------------
log "--- 4. Purging Docker/Runtime ---"
if have docker; then
    IDS=$(docker ps -aq 2>/dev/null)
    if [ -n "$IDS" ]; then
        log "Force-killing containers..."
        timeout 15s docker rm -f $IDS >/dev/null 2>&1 || true
    fi
fi

sudo systemctl stop docker.service docker.socket containerd 2>/dev/null || true
run_ign sudo apt-get purge -y docker.io containerd.io runc 2>/dev/null
run_ign sudo apt-get autoremove -y 2>/dev/null

# -------------------------
# 5) LVM & Storage Cleanup (Specific to Rook-Ceph)
# -------------------------
log "--- 5. Storage & LVM cleanup ---"
run_ign sudo apt-get purge -y lvm2 thin-provisioning-tools 2>/dev/null

# Best-effort remove LVs/VGs if present before purging (reduces conflicts on re-install)
if command -v lvs >/dev/null 2>&1 && command -v vgs >/dev/null 2>&1; then
  log "Best-effort removing LVs..."
  sudo lvremove -f $(sudo lvs --noheadings -o lv_path 2>/dev/null | awk '{print $1}' | tr '\n' ' ') >/dev/null 2>&1 || true

  log "Best-effort removing VGs..."
  sudo vgremove -f $(sudo vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}' | tr '\n' ' ') >/dev/null 2>&1 || true

  log "Best-effort wiping PV signatures..."
  # Only remove if pvscan/pvs exists; do not assume disks/loops.
  if command -v pvs >/dev/null 2>&1; then
    sudo wipefs -a $(sudo pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | tr '\n' ' ') >/dev/null 2>&1 || true
  fi
fi

# -------------------------
# 6) Deep Filesystem Wipe
# -------------------------
log "--- 6. Wiping all state directories (if present) ---"
DIRS=(
    # Rook/Ceph
    "/var/lib/rook"
    "/var/lib/ceph"
    "/etc/ceph"
    "/var/log/ceph"
    "/var/run/ceph"

    # Kubernetes / nodes
    "/var/lib/kubelet"
    "/etc/kubernetes"
    "/var/lib/kubelet/plugins"
    "/var/lib/kubelet/pods"

    # Container runtime
    "/var/lib/docker"
    "/var/lib/containerd"

    # Networking/CNI
    "/var/lib/cni"
    "/etc/cni"

    # kubeconfig
    "$HOME/.kube"
)

for dir in "${DIRS[@]}"; do
    if [ -e "$dir" ]; then
      log "Removing $dir..."
      sudo rm -rf "$dir" 2>/dev/null || true
    fi
done

# -------------------------
# 7) Networking Reset
# -------------------------
log "--- 7. Resetting Firewall/Networking (lab-only, best-effort) ---"
run_ign sudo iptables -F
run_ign sudo iptables -t nat -F
run_ign sudo iptables -t nat -X
run_ign sudo iptables -P FORWARD ACCEPT

# -------------------------
# 8) Final APT Cleanup
# -------------------------
log "--- 8. Final APT cleanup ---"
sudo apt-get clean 2>/dev/null || true

# -------------------------
# 9) Local Artifact Cleanup (YAML files)
# -------------------------
log "--- 9. Cleaning up local YAML manifests (in cwd) ---"
find . -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) -exec rm -v {} + || true

echo "========================================================"
echo "RESET COMPLETE. Please reboot to ensure kernel/modules are clean."
echo "========================================================"