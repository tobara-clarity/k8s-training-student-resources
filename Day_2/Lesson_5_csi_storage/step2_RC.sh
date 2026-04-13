#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ROOK_NS="rook-ceph"

NS="default"
CSIDRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
EXPECTED_PROVISIONER="rook-ceph.rbd.csi.ceph.com"

SUFFIX="$(date +%s)"
PVC_NAME="rook-ceph-verify-pvc-${SUFFIX}"
POD_NAME="rook-ceph-verify-writer-${SUFFIX}"

echo "--- [Script2] Rook-Ceph Verification (unique per run) ---"

echo "--- 0. Wait for CSIDriver registration (bounded) ---"
timeout_seconds=600
start_ts=$(date +%s)

until kubectl --context "$KIND_CONTEXT" get csidriver "$CSIDRIVER_NAME" >/dev/null 2>&1; do
  elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    echo "ERROR: Timed out waiting for CSIDriver: $CSIDRIVER_NAME"
    kubectl --context "$KIND_CONTEXT" get csidriver || true
    kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" describe cephcluster my-cluster | tail -n 120 || true
    exit 1
  fi
  echo "Waiting for CSIDriver..."
  sleep 5
done
echo "CSIDriver registered: $CSIDRIVER_NAME"

echo "--- 1. Discover RBD StorageClass by provisioner ---"
RC_SC="$(
  kubectl --context "$KIND_CONTEXT" get storageclass \
    -o jsonpath='{range .items[?(@.provisioner=="'"$EXPECTED_PROVISIONER"'")]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | head -n 1 | tr -d '\r'
)"

if [ -z "$RC_SC" ]; then
  echo "ERROR: No StorageClass found with provisioner $EXPECTED_PROVISIONER"
  kubectl --context "$KIND_CONTEXT" get storageclass || true
  exit 1
fi
echo "Using StorageClass: $RC_SC"

echo "--- 2. Create PVC + verification Pod (cleanup first) ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$KIND_CONTEXT" -n "$NS" delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true

kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f - <<YAML
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

echo "--- 3. Wait for PVC Bound (bounded) ---"
if ! kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Bound pvc/"$PVC_NAME" --timeout=10m; then
  echo "ERROR: PVC did not bind. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pvc/"$PVC_NAME" || true
  kubectl --context "$KIND_CONTEXT" -n "$NS" get events --sort-by=.metadata.creationTimestamp | tail -n 120 || true
  kubectl --context "$KIND_CONTEXT" -n "$ROOK_NS" get pods -o wide | egrep 'rook-ceph-(mon|osd)|csi-rbd' || true
  exit 1
fi

echo "--- 4. Wait for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=5m || {
  echo "ERROR: Pod not Ready. Diagnostics:"
  kubectl --context "$KIND_CONTEXT" -n "$NS" describe pod/"$POD_NAME" || true
  exit 1
}

echo "--- 5. Read evidence file back ---"
FILE_CONTENT="$(
  kubectl --context "$KIND_CONTEXT" -n "$NS" exec "$POD_NAME" -- cat /data/verify.txt
)"

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"