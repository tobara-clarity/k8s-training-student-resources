#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

NS="default"
PVC_NAME="rook-ceph-verify-pvc"
POD_NAME="rook-ceph-verify-writer"

echo "--- [Script2] Rook-Ceph Verification ---"

# 0) Discover a Rook RBD StorageClass (don’t assume its name)
echo "--- 0. Detecting Rook RBD StorageClass ---"
SC_DEFAULT="$(
  kubectl --context "$KIND_CONTEXT" get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
)"

SC_BY_PROVISIONER="$(
  kubectl --context "$KIND_CONTEXT" get storageclass \
    -o jsonpath='{range .items[?(@.provisioner=="rook-ceph.rbd.csi.ceph.com")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
)"

RC_SC=""

if [ -n "${SC_DEFAULT}" ]; then
  # confirm it’s the expected provisioner; otherwise fall back
  if kubectl --context "$KIND_CONTEXT" get sc "${SC_DEFAULT%%$'\n'*}" -o jsonpath='{.provisioner}' 2>/dev/null | grep -q '^rook-ceph\.rbd\.csi\.ceph\.com$'; then
    RC_SC="${SC_DEFAULT%%$'\n'*}"
  fi
fi

if [ -z "$RC_SC" ] && [ -n "$SC_BY_PROVISIONER" ]; then
  RC_SC="${SC_BY_PROVISIONER%%$'\n'*}"
fi

if [ -z "$RC_SC" ]; then
  echo "ERROR: Could not find a StorageClass for provisioner rook-ceph.rbd.csi.ceph.com."
  echo "Existing StorageClasses:"
  kubectl --context "$KIND_CONTEXT" get storageclass || true
  echo
  echo "Fix: ensure Script1 successfully applied ${ROOK_URL}/csi/rbd/storageclass-test.yaml"
  exit 1
fi

echo "Using StorageClass: $RC_SC"

# 1) Clean up any leftover resources from previous attempts (safe)
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pod "$POD_NAME" --ignore-not-found
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pvc "$PVC_NAME" --ignore-not-found

# 2) Create PVC + Pod that mounts it
echo "--- 1. Creating PVC and Verification Pod ---"
cat <<YAML | kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${RC_SC}
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  restartPolicy: Never
  containers:
  - name: tester
    image: busybox:1.36
    command:
      - sh
      - -c
      - 'echo "Ceph-Storage-Verified-$(date -u)" > /data/verify.txt; sleep 10'
    volumeMounts:
    - name: ceph-vol
      mountPath: /data
  volumes:
  - name: ceph-vol
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
YAML

# 3) Wait for PVC to be Bound (real gate)
echo "--- 2. Waiting for PVC to be Bound ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m || {
  echo "ERROR: PVC did not bind. Dumping diagnostics..."
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n rook-ceph get pods || true
  kubectl --context "$KIND_CONTEXT" get csidriver || true
  exit 1
}

# 4) Wait for Pod Ready
echo "--- 3. Waiting for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m

# 5) Verify readback
echo "--- 4. Verifying data integrity ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"