#!/bin/bash
set -euo pipefail

PVC_NAME="longhorn-verify-pvc"
POD_NAME="storage-checker"
LH_NS="longhorn-system"
PVC_NS="default"

echo "--- 0. Cluster/Longhorn sanity ---"
kubectl get nodes -o wide
echo "--- Longhorn nodes (nodes.longhorn.io) ---"
kubectl -n "$LH_NS" get nodes.longhorn.io -o wide || true

# Determine desired replicas based on Longhorn nodes (avoid forcing 2 when only 1 exists)
LH_NODE_COUNT="$(kubectl -n "$LH_NS" get nodes.longhorn.io --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ -z "$LH_NODE_COUNT" ] || [ "$LH_NODE_COUNT" -lt 1 ]; then
  echo "ERROR: Could not determine Longhorn node count."
  kubectl -n "$LH_NS" get nodes.longhorn.io -o wide || true
  exit 1
fi

DESIRED_REPLICAS="$(( LH_NODE_COUNT < 2 ? LH_NODE_COUNT : 2 ))"
echo "--- Using DESIRED_REPLICAS=$DESIRED_REPLICAS (Longhorn nodes=$LH_NODE_COUNT) ---"

echo "--- 1. Patch Longhorn default replica count to DESIRED_REPLICAS ---"
kubectl -n "$LH_NS" patch settings.longhorn.io default-replica-count \
  --type merge -p "{\"value\":\"$DESIRED_REPLICAS\"}"

echo "--- 2. Patch StorageClass parameters to DESIRED_REPLICAS ---"
kubectl patch storageclass longhorn --type merge \
  -p "{\"parameters\":{\"numberOfReplicas\":\"$DESIRED_REPLICAS\"}}" || true

kubectl patch storageclass longhorn --type merge \
  -p "{\"parameters\":{\"replicaCount\":\"$DESIRED_REPLICAS\"}}" || true

echo "--- 2b. Current StorageClass (partial) ---"
kubectl get sc longhorn -o yaml | sed -n '1,200p' || true

echo "--- 3. Determinism: delete any existing Longhorn volume tied to this PVC ---"
# Longhorn typically labels volumes with longhornvolume=pvc-<uid> rather than pvc name,
# but some lesson setups do map label longhornvolume=<PVC_NAME>. We'll follow your existing approach.
EXISTING_VOLUMES="$(kubectl -n "$LH_NS" get volumes.longhorn.io \
  -l "longhornvolume=${PVC_NAME}" -o name 2>/dev/null || true)"

if [ -n "$EXISTING_VOLUMES" ]; then
  echo "Deleting existing Longhorn volumes: $EXISTING_VOLUMES"
  kubectl -n "$LH_NS" delete $EXISTING_VOLUMES --ignore-not-found=true || true
else
  echo "No existing Longhorn volumes found with label longhornvolume=${PVC_NAME}."
fi

echo "--- 4. Cleanup: delete Pod + PVC (namespaced) ---"
kubectl delete pod "$POD_NAME" -n "$PVC_NS" --ignore-not-found=true || true
kubectl delete pvc "$PVC_NAME" -n "$PVC_NS" --ignore-not-found=true || true

echo "--- 4b. Wait briefly for PVC deletion to settle (avoid delete/create race) ---"
kubectl wait --for=delete "pvc/${PVC_NAME}" -n "$PVC_NS" --timeout=60s || true

echo "--- 5. Create PVC ---"
cat <<EOF | kubectl apply -n "$PVC_NS" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

echo "--- 6. Deploy Test Pod ---"
cat <<EOF | kubectl apply -n "$PVC_NS" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
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

echo "--- 7. Wait for PVC Bound (with debug on failure) ---"
set +e
kubectl wait --for=jsonpath='{.status.phase}'=Bound "pvc/${PVC_NAME}" -n "$PVC_NS" --timeout=180s
WAIT_RC=$?
set -e

if [ "$WAIT_RC" -ne 0 ]; then
  echo "ERROR: PVC did NOT become Bound in time."
  echo "---- PVC describe ----"
  kubectl describe pvc -n "$PVC_NS" "$PVC_NAME" || true
  echo "---- PVC get ----"
  kubectl get pvc -n "$PVC_NS" "$PVC_NAME" -o wide || true

  echo "---- Events (PVC namespace) ----"
  kubectl get events -n "$PVC_NS" --sort-by=.lastTimestamp | tail -n 120 || true

  echo "---- Longhorn volumes matching PVC label (if any) ----"
  kubectl -n "$LH_NS" get volumes.longhorn.io -l "longhornvolume=${PVC_NAME}" -o wide || true

  echo "---- Longhorn pods (for context) ----"
  kubectl -n "$LH_NS" get pods -o wide || true

  exit 1
fi

echo "--- 8. Wait for Pod Ready (with debug on failure) ---"
set +e
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$PVC_NS" --timeout=240s
POD_RC=$?
set -e

if [ "$POD_RC" -ne 0 ]; then
  echo "ERROR: Pod did NOT become Ready in time. Debugging:"

  kubectl -n "$PVC_NS" get pod "$POD_NAME" -o wide || true
  kubectl -n "$PVC_NS" describe pod "$POD_NAME" || true

  echo "--- Events (pod namespace) ---"
  kubectl get events -n "$PVC_NS" --sort-by=.lastTimestamp | tail -n 120 || true

  echo "--- Longhorn volumes matching pvc label ---"
  kubectl -n "$LH_NS" get volumes.longhorn.io -l "longhornvolume=${PVC_NAME}" -o wide || true

  echo "Tip: if a Longhorn volume shows up, run:"
  echo "  kubectl -n $LH_NS describe volumes.longhorn.io <VOLUME_NAME>"

  exit 1
fi

echo "--------------------------------------------------------"
echo "Your PVC is BOUND and your Pod is READY."
kubectl get pvc -n "$PVC_NS" "$PVC_NAME"
kubectl -n "$PVC_NS" get pod "$POD_NAME" -o wide
echo "--------------------------------------------------------"