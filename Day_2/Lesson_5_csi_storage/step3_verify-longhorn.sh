#!/bin/bash
set -euo pipefail

PVC_NAME="longhorn-verify-pvc"
POD_NAME="storage-checker"
LH_NS="longhorn-system"
PVC_NS="default"

BASE_SC="longhorn"                 # existing Longhorn SC name
STALEREPLICATETIMEOUT="30"
FS_TYPE="ext4"
DATA_LOCALITY="disabled"

echo "--- 0. Cluster/Longhorn sanity ---"
kubectl get nodes -o wide
echo "--- Longhorn nodes (nodes.longhorn.io) ---"
kubectl -n "$LH_NS" get nodes.longhorn.io -o wide || true

LH_NODE_COUNT="$(kubectl -n "$LH_NS" get nodes.longhorn.io --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ -z "$LH_NODE_COUNT" ] || [ "$LH_NODE_COUNT" -lt 1 ]; then
  echo "ERROR: Could not determine Longhorn node count."
  kubectl -n "$LH_NS" get nodes.longhorn.io -o wide || true
  exit 1
fi

DESIRED_REPLICAS="$(( LH_NODE_COUNT < 2 ? LH_NODE_COUNT : 2 ))"
echo "--- Using DESIRED_REPLICAS=$DESIRED_REPLICAS (Longhorn nodes=$LH_NODE_COUNT) ---"

LH_NODE_NAME="$(kubectl -n "$LH_NS" get nodes.longhorn.io -o jsonpath='{.items[0].metadata.name}')"
echo "--- Pinning test Pod to Longhorn node: $LH_NODE_NAME ---"

# New StorageClass name (avoid immutable-parameter updates)
SC_NAME="longhorn-rep-${DESIRED_REPLICAS}"
echo "--- 1. Patch Longhorn setting default-replica-count to $DESIRED_REPLICAS ---"
kubectl -n "$LH_NS" patch settings.longhorn.io default-replica-count \
  --type merge -p "{\"value\":\"$DESIRED_REPLICAS\"}" || true

echo "--- 2. Create a new StorageClass $SC_NAME with replica parameters (immutable-safe) ---"
kubectl delete sc "$SC_NAME" --ignore-not-found=true || true

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${SC_NAME}
provisioner: driver.longhorn.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "${DESIRED_REPLICAS}"
  staleReplicaTimeout: "${STALEREPLICATETIMEOUT}"
  fsType: "${FS_TYPE}"
  dataLocality: "${DATA_LOCALITY}"
  fromBackup: ""
EOF

echo "--- 2b. Current StorageClass values (for reference) ---"
kubectl get sc "${BASE_SC}" "${SC_NAME}" -o wide || true

echo "--- 3. Cleanup: delete Pod + PVC (namespaced) ---"
kubectl delete pod "$POD_NAME" -n "$PVC_NS" --ignore-not-found=true || true
kubectl delete pvc "$PVC_NAME" -n "$PVC_NS" --ignore-not-found=true || true
kubectl wait --for=delete "pvc/${PVC_NAME}" -n "$PVC_NS" --timeout=60s || true

echo "--- 4. Create PVC using StorageClass ${SC_NAME} ---"
cat <<EOF | kubectl apply -n "$PVC_NS" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${SC_NAME}
  resources:
    requests:
      storage: 1Gi
EOF

echo "--- 5. Deploy Test Pod (pinned) ---"
cat <<EOF | kubectl apply -n "$PVC_NS" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  nodeName: ${LH_NODE_NAME}
  containers:
  - name: nginx
    image: nginx:stable
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
EOF

echo "--- 6. Wait for PVC Bound ---"
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" -n "$PVC_NS" --timeout=180s
kubectl get pvc "$PVC_NAME" -n "$PVC_NS" -o wide

echo "--- 7. Wait for Pod Ready (with debug on failure) ---"
set +e
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$PVC_NS" --timeout=240s
POD_RC=$?
set -e

if [ "$POD_RC" -ne 0 ]; then
  echo "ERROR: Pod did NOT become Ready in time."

  echo "---- Pod wide ----"
  kubectl get pod "$POD_NAME" -n "$PVC_NS" -o wide || true

  echo "---- Pod describe (events included) ----"
  kubectl describe pod "$POD_NAME" -n "$PVC_NS" | sed -n '/Events:/,$p' || true

  echo "---- PVC describe ----"
  kubectl describe pvc "$PVC_NAME" -n "$PVC_NS" || true

  echo "---- Longhorn Volumes ----"
  kubectl -n "$LH_NS" get volumes.longhorn.io -o wide || true

  echo "---- Longhorn Replicas ----"
  kubectl -n "$LH_NS" get replicas.longhorn.io -o wide || true

  echo "---- Longhorn Manager logs (tail) ----"
  kubectl -n "$LH_NS" logs deploy/longhorn-manager --tail=200 || true

  exit 1
fi

echo "--------------------------------------------------------"
echo "Your PVC is BOUND and your Pod is READY."
kubectl -n "$PVC_NS" get pvc "$PVC_NAME" -o wide
kubectl -n "$PVC_NS" get pod "$POD_NAME" -o wide
echo "--------------------------------------------------------"