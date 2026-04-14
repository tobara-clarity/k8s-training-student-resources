#!/usr/bin/env bash
# Full reset of Kubernetes + Rook-Ceph lab artifacts (no-hang version)
set +euo pipefail

echo "========================================================"
echo "RESET START - Host: $(hostname) - User: $(whoami) - PID $$"
echo "========================================================"

# -------------------------
# Helpers
# -------------------------
log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

export DEBIAN_FRONTEND=noninteractive

run_ign() { timeout 10s "$@" >/dev/null 2>&1 || true; }
run_timeout() {
  # usage: run_timeout <seconds> <cmd...>
  local t="$1"; shift
  timeout "$t" "$@" || true
}

# Wait for dpkg/apt locks briefly (prevents "silent hangs")
wait_dpkg() {
  log "Ensuring dpkg/apt state is not locked..."
  run_timeout 60 sudo dpkg --configure -a || true
  run_timeout 30 sudo apt-get update -y || true
}

# -------------------------
# 0) Kubernetes Cleanup (Non-blocking)
# -------------------------
if have kubectl; then
  if [ -f "$HOME/.kube/config" ]; then
    log "Attempting to delete namespace rook-ceph & StorageClasses (best-effort, non-blocking)..."
    run_timeout 25 kubectl delete ns rook-ceph --wait=false --ignore-not-found=true 2>/dev/null || true
    run_timeout 25 kubectl delete storageclass rook-ceph-block --ignore-not-found=true 2>/dev/null || true
    run_timeout 25 kubectl delete storageclass rook-ceph-block-nbd --ignore-not-found=true 2>/dev/null || true
  fi
fi

# -------------------------
# 1) Mount Cleanup (Crucial for Ceph RBD)
# -------------------------
log "--- 1. Unmounting stale K8s/CSI mounts (fast timeout) ---"

# Unmount known roots quickly, using /proc/mounts parsing (avoid long grep->loop work)
UNMOUNT_ROOTS=(
  "/var/lib/kubelet"
  "/var/lib/ceph"
  "/var/run/ceph"
  "/var/lib/csi"
  "/csi"
)

# Collect mountpoints under these roots and try unmounting them with a short timeout.
# Note: mountpoints change while unmounting; keep it best-effort.
for root in "${UNMOUNT_ROOTS[@]}"; do
  if [ -d "$root" ]; then
    # List mountpoints under root (longest first) and unmount with timeout.
    mps="$(awk -v r="$root" '$2 ~ "^"r"/?" {print $2}' /proc/mounts 2>/dev/null | sort -r -u)"
    if [ -n "$mps" ]; then
      while IFS= read -r mp; do
        [ -z "$mp" ] && continue
        log "Unmounting $mp ..."
        run_timeout 8 sudo umount -f -l "$mp" 2>/dev/null || true
      done <<< "$mps"
    fi
  fi
done

# -------------------------
# 2) Tear down kind clusters
# -------------------------
log "--- 2. Tearing down Kubernetes (kind) ---"
if have kind; then
  run_timeout 180 kind delete clusters --all >/dev/null 2>&1 || true
  run_timeout 10 sudo rm -f /usr/local/bin/kind /bin/kind || true
fi

# -------------------------
# 3) Remove tooling (kubectl snap etc.)
# -------------------------
log "--- 3. Removing tooling ---"
if have snap; then
  run_timeout 60 sudo snap remove kubectl 2>/dev/null || true
fi

run_timeout 10 sudo rm -f /usr/local/bin/kubectl /bin/kubectl /usr/bin/kubectl 2>/dev/null || true

# kubelet/kubeadm/kubectl purge if installed
wait_dpkg
run_timeout 120 sudo apt-get purge -y kubelet kubeadm kubectl 2>/dev/null || true

# -------------------------
# 4) Docker/Containerd cleanup
# -------------------------
log "--- 4. Purging Docker/Runtime (timeout-protected, non-interactive) ---"
wait_dpkg

if have docker; then
  # Don’t let docker ps hang forever
  timeout 10s docker ps -aq >/tmp/reset_docker_ids 2>/dev/null || true
  IDS="$(cat /tmp/reset_docker_ids 2>/dev/null | tr -d '\n' || true)"
  rm -f /tmp/reset_docker_ids
  if [ -n "${IDS:-}" ]; then
    log "Force-killing Docker containers..."
    # shellcheck disable=SC2086
    run_timeout 60 sudo docker rm -f $IDS >/dev/null 2>&1 || true
  fi
  run_ign sudo systemctl stop docker.service docker.socket containerd 2>/dev/null || true
fi

# Purge packages (use longer timeout, but still bounded)
run_timeout 240 sudo apt-get purge -y docker.io containerd.io runc 2>/dev/null || true
run_timeout 120 sudo apt-get autoremove -y 2>/dev/null || true

# -------------------------
# 5) Storage & LVM cleanup
# -------------------------
log "--- 5. Storage & LVM cleanup ---"
wait_dpkg

run_timeout 120 sudo apt-get purge -y lvm2 thin-provisioning-tools 2>/dev/null || true

# LVM removal can be slow; only attempt if commands exist, and keep it bounded.
if command -v lvs >/dev/null 2>&1 && command -v vgs >/dev/null 2>&1; then
  log "Best-effort removing LVs/VGs (bounded)..."

  # Remove LVs
  LVPATHS="$(timeout 10s sudo lvs --noheadings -o lv_path 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)"
  if [ -n "${LVPATHS:-}" ]; then
    run_timeout 120 sudo lvremove -f $LVPATHS >/dev/null 2>&1 || true
  fi

  # Remove VGs
  VG_NAMES="$(timeout 10s sudo vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)"
  if [ -n "${VG_NAMES:-}" ]; then
    run_timeout 120 sudo vgremove -f $VG_NAMES >/dev/null 2>&1 || true
  fi

  # Wipe PV signatures (very best-effort; do not assume devices)
  if command -v pvs >/dev/null 2>&1; then
    PV_NAMES="$(timeout 10s sudo pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)"
    if [ -n "${PV_NAMES:-}" ]; then
      log "Best-effort wiping PV signatures..."
      run_timeout 120 sudo wipefs -a $PV_NAMES >/dev/null 2>&1 || true
    fi
  fi
fi

# -------------------------
# 6) Deep Filesystem Wipe (bounded per dir)
# -------------------------
log "--- 6. Wiping state directories (best-effort, bounded) ---"
DIRS=(
  "/var/lib/rook"
  "/var/lib/ceph"
  "/etc/ceph"
  "/var/log/ceph"
  "/var/run/ceph"
  "/var/lib/kubelet"
  "/etc/kubernetes"
  "/var/lib/cni"
  "/etc/cni"
  "/var/lib/docker"
  "/var/lib/containerd"
  "/var/lib/kubelet/plugins"
  "/var/lib/kubelet/pods"
  "$HOME/.kube"
)

for dir in "${DIRS[@]}"; do
  if [ -e "$dir" ]; then
    log "Removing $dir ..."
    run_timeout 60 sudo rm -rf "$dir" 2>/dev/null || true
  fi
done

# -------------------------
# 7) Networking Reset (lab-only)
# -------------------------
log "--- 7. Resetting firewall/iptables (best-effort) ---"
run_ign sudo iptables -F
run_ign sudo iptables -t nat -F
run_ign sudo iptables -t nat -X
run_ign sudo iptables -P FORWARD ACCEPT

# -------------------------
# 8) Final APT cleanup
# -------------------------
log "--- 8. Final APT cleanup ---"
run_timeout 60 sudo apt-get clean 2>/dev/null || true
run_timeout 60 sudo apt-get autoclean -y 2>/dev/null || true

# -------------------------
# 9) Local Artifact Cleanup (YAML files)
# -------------------------
log "--- 9. Cleaning up local YAML manifests (in cwd) ---"
find . -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) -exec rm -v {} + || true

echo "========================================================"
echo "RESET COMPLETE. Reboot recommended."
echo "========================================================"