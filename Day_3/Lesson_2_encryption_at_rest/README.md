## Encrypting Confidential Data at Rest

This lab quickly shows how to configure encryption of confidential data at rest

### Section 1 - No Encryption

1. Stand up a kind cluster

```bash
kind create cluster
```

2. Deploy the secret

```bash
kubectl apply -f secret.yaml
```

3. View the secret in etcd

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/my-secret
```

_Notice how the secret value, `HelloWorld1234!!` is clearly visible in the content_

### Section 2 Encryption

1. Delete the cluster from the previous example

```bash
kind delete clusters --all
```

2. Create a cluster with Encryption

```bash
kind create cluster --config cluster.yaml
```

3. Deploy the secret

```bash
kubectl apply -f secret.yaml
```

4. View the secret in etcd

```bash
kubectl exec -n kube-system etcd-kind-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/default/my-secret
```