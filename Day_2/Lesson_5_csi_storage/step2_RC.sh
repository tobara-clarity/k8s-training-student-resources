#!/bin/bash
set -euo pipefail

CLUSTER_NAME="rook-ceph-lab"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "--- [Script2] Rook-Ceph Verification ---"

RC_SC="rook-ceph-block"
echo "Checking for StorageClass: $RC_SC..."

kubectl --context "$KIND_CONTEXT" get sc "$RC_SC" &>/dev/null || {
  echo "ERROR: Rook-Ceph StorageClass ($RC_SC) not found! Did Script 1 finish successfully?"
  exit 1
}

echo "--- 2. Creating PVC and Verification Pod ---"
cat <<YAML | kubectl --context "$KIND_CONTEXT" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rook-ceph-verify-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: $RC_SC
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: rook-ceph-verify-writer
spec:
  restartPolicy: Never
  containers:
  - name: tester
    image: busybox:1.36
    command: ["sh","-c","echo \"Ceph-Storage-Verified-$(date)\" > /data/verify.txt; sleep 10"]
    volumeMounts:
    - name: ceph-vol
      mountPath: /data
  volumes:
  - name: ceph-vol
    persistentVolumeClaim:
      claimName: rook-ceph-verify-pvc
YAML

echo "--- 3. Waiting for Pod Ready ---"
kubectl --context "$KIND_CONTEXT" wait \
  --for=condition=Ready pod/rook-ceph-verify-writer \
  --timeout=300s

echo "--- 4. Verifying Data Integrity ---"
FILE_CONTENT=$(kubectl --context "$KIND_CONTEXT" exec pod/rook-ceph-verify-writer -- cat /data/verify.txt)

echo "--------------------------------------------------------"
echo "VERIFICATION SUCCESSFUL"
echo "Data read from Ceph: $FILE_CONTENT"
echo "--------------------------------------------------------"