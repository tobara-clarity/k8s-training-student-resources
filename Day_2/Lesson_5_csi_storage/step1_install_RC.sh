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

echo "--- 5.1 Force enable CSI RBD in the operator ---"
# These env vars match what rook operator uses in your earlier logs.
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" set env deployment/rook-ceph-operator \
  ROOK_CSI_ENABLE_RBD=true \
  ROOK_CSI_DISABLE_DRIVER=false \
  ROOK_USE_CSI_OPERATOR=true || true

kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout restart deployment/rook-ceph-operator || true
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" rollout status deployment/rook-ceph-operator --timeout=600s

echo "--- 6. Apply CephCluster (test mode) ---"
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" apply -f "${ROOK_URL}/cluster-test.yaml"

echo "--- 6.1 (Optional) Patch Ceph version for Squid minimum ---"
# If your earlier env still enforces ">= 19.2.0-0 squid", this is the usual workaround.
kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" patch cephcluster "$CEPH_CLUSTER_NAME" \
  --type merge \
  -p '{"spec":{"cephVersion":{"image":"quay.io/ceph/ceph:v19.2.0"}}}' >/dev/null 2>&1 || true

echo "--- 7. Apply RBD StorageClass (correct path) ---"
kubectl --context "$KIND_CONTEXT" apply -f "${ROOK_URL}/csi/rbd/storageclass-test.yaml"

echo "--- 7.1 Set rook-ceph-block as default StorageClass ---"
kubectl --context "$KIND_CONTEXT" patch storageclass rook-ceph-block \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true



echo "--- 8. Waiting for Ceph MON + OSD quorum signals (with live printout) ---"
timeout_seconds=600
start_ts=$(date +%s)

while true; do
  now_ts=$(date +%s)
  elapsed=$(( now_ts - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for MON/OSD quorum signals."
    echo "---- Current rook-ceph pods (MON/OSD) ----"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods | egrep 'rook-ceph-(mon|osd)' || true
    echo "---- CephCluster status ----"
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster "$CEPH_CLUSTER_NAME" | tail -n 120 || true
    exit 1
  fi

  # Count ready MONs and OSDs by READY column == 1/1
  mon_ready=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
  | awk '/rook-ceph-mon/ && $2=="1\/1" && $3=="Running"{c++} END{print (c?c:0)}')

  osd_ready=$(kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods --no-headers 2>/dev/null \
  | awk '/rook-ceph-osd/ && $2=="1\/1" && $3=="Running"{c++} END{print (c?c:0)}')

  echo "  [${elapsed}s] MON Ready: ${mon_ready} | OSD Ready: ${osd_ready}"

  # In test mode you typically have MON count = 1
  if [ "${mon_ready}" -ge 1 ] && [ "${osd_ready}" -ge 1 ]; then
    echo "--- Ceph MON/OSD quorum signals reached ---"
    break
  fi

  sleep 5
done



echo "--- 9. Done (operator/ceph may still be progressing) ---"
echo "Waiting for rook-ceph-blockpool replicapool to exist (signal only)..."
until kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get cephblockpool replicapool &>/dev/null; do
  echo -n "."
  sleep 5
done
echo ""

echo "INSTALLATION COMPLETE"
kubectl --context "$KIND_CONTEXT" get storageclass | grep rook-ceph || true