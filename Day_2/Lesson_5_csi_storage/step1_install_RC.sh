#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"
CEPH_CLUSTER_NAME="my-cluster"

echo "--- 0. Repair any interrupted dpkg/apt state ---"
sudo dpkg --configure -a || true
sudo apt -f install -y || true

echo "--- 1. Host deps ---"
sudo apt update
sudo apt install -y docker.io lvm2 thin-provisioning-tools linux-modules-extra-$(uname -r)
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

echo "--- 1.1 Install loopback helpers (util-linux) ---"
sudo apt-get update -y >/dev/null 2>&1 || true
sudo apt-get install -y util-linux >/dev/null 2>&1 || true

echo "--- 1.2 Create loopback device(s) for OSDs (>=5GB) ---"
# This lab typically needs loopback devices because Kind mounts host /dev into the node.
# Create one 20G loop file and attach it.
LOOP_IMG="/tmp/rook-ceph-loop.img"
LOOP_SIZE="20G"

sudo rm -f "$LOOP_IMG" || true
sudo losetup -D || true

# Prefer fallocate if present; fallback to dd.
if command -v fallocate >/dev/null 2>&1; then
  sudo fallocate -l "$LOOP_SIZE" "$LOOP_IMG"
else
  sudo dd if=/dev/zero of="$LOOP_IMG" bs=1M count=20480
fi

# Attach the file to the first free /dev/loopX
sudo losetup -fP "$LOOP_IMG"

echo "--- Attached loops ---"
sudo losetup -a || true

echo "--- 2. Install kind & kubectl ---"
if ! command -v kind &>/dev/null; then
  curl -fLo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &>/dev/null; then
  sudo snap install kubectl --classic
fi

echo "--- 3. Create kind cluster ---"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

cat <<'EOF' > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev
    containerPath: /dev
EOF

kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml --wait 0s

echo "--- 4. Wait for nodes Ready ---"
kubectl --context "$KIND_CONTEXT" wait --for=condition=Ready nodes --all --timeout=300s

echo "--- 5. Install rook-ceph (pinned release) ---"
ROOK_URL="https://raw.githubusercontent.com/rook/rook/release-1.13/deploy/examples"

kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/common.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/crds.yaml"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/operator.yaml"

echo "Waiting for rook-ceph-operator..."
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 5.1 Enable CSI RBD + allow loop devices in operator ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" set env deployment/rook-ceph-operator \
  ROOK_CSI_ENABLE_RBD=true \
  ROOK_CSI_DISABLE_DRIVER=false \
  ROOK_USE_CSI_OPERATOR=true \
  ROOK_CEPH_ALLOW_LOOP_DEVICES=true || true

kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout restart deployment/rook-ceph-operator || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 6. Apply CephCluster (test mode) ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 6.1 Patch Ceph version for squid minimum workaround ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19.2.0"}}}' >/dev/null 2>&1 || true

echo "--- 6.2 Restrict CephCluster device selection to /dev/loop* only ---"
# This avoids VM partitions and ensures OSD provisioning uses loop devices.
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"storage":{"useAllDevices":false,"deviceFilter":"^\\/dev\\/loop[0-9]+$"}}}' >/dev/null 2>&1 || true

echo "--- 7. Apply RBD StorageClass ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/csi/rbd/storageclass-test.yaml"

echo "--- 7.1 Set rook-ceph-block as default StorageClass ---"
kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true

echo "--- 8. Waiting for MON running + at least one OSD pod exists (quorum-style live printout) ---"
timeout_seconds=900
start_ts=$(date +%s)

while true; do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for MON/OSD startup signals."
    echo "---- Current rook-ceph pods (mon/osd) ----"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods | egrep 'rook-ceph-(mon|osd)' || true
    echo "---- CephCluster status ----"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster "$CEPH_CLUSTER_NAME" | tail -n 120 || true
    exit 1
  fi

  # READY column is $2, STATUS column is $3
  mon_running=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
    | awk '$1 ~ /^rook-ceph-mon/ && $2=="1\/1" && $3=="Running"{c++} END{print (c?c:0)}')

  # Count only real OSD pods (exclude osd-prepare)
  osd_pod_count=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
    | awk '$1 ~ /^rook-ceph-osd-[^-]/ {c++} END{print (c?c:0)}')

  echo "  [${elapsed}s] MON Running: ${mon_running} | OSD pod count: ${osd_pod_count}"

  if [ "${mon_running}" -ge 1 ] && [ "${osd_pod_count}" -ge 1 ]; then
    echo "--- MON running and at least one OSD pod exists ---"
    break
  fi

  sleep 5
done

echo "--- 9. Signal: wait for CephBlockPool replicapool object to exist ---"
until kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool &>/dev/null; do
  echo -n "."
  sleep 5
done
echo ""

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "Cluster: $CLUSTER_NAME"
echo "Context: $KIND_CONTEXT"
echo "--------------------------------------------------------"
kubectl --context "$KIND_CONTEXT" get storageclass | grep rook-ceph || true