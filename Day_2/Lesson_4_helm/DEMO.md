# Demo: Helm Chart Templating + Release Lifecycle

This demo walks you through how Helm templates are rendered and how a Helm release moves through install, upgrade, rollback, and uninstall.

## Learning Goals

By the end of this demo, you should be able to:

- Inspect a chart and understand where values are injected.
- Render manifests locally before deploying.
- Install a release into Kubernetes.
- Upgrade a release with changed values.
- Roll back to a previous revision.
- Uninstall and clean up.

---

## Prerequisites

- A running Kubernetes cluster (`kubectl` context set correctly)
- Helm v3 installed
- You are in this lesson directory:
  `Day_2/Lesson_4_helm`

Optional (recommended): use a dedicated namespace for the demo.

---

## 1) Explore the chart structure

Expected chart path in this lesson:

- `chart/values.yaml`
- `chart/templates/pod.yaml`
- `chart/templates/_helpers.tpl`

Review the key files to identify:

- Image values in `values.yaml`
- Templating in `templates/pod.yaml`:
  - `.Release.Name`
  - `.Values.image.repository`
  - `.Values.image.tag`
- Shared labels from `templates/_helpers.tpl`

---

## 2) Render templates locally (no cluster changes)

Run from `Day_2/Lesson_4_helm`:

```sh
helm template demo-release ./chart
```

What to check in output:

- Pod name includes release name (example: `demo-release-pod`)
- Image is built from values (example: `nginx:1.25.1`)
- Labels from helper template are present

---

## 3) Dry-run install (debug before apply)

```sh
helm install --debug --dry-run demo-release ./chart
```

This validates render + install logic without creating resources.

---

## 4) Install the release

```sh
helm install demo-release ./chart
```

Verify:

```sh
helm list
kubectl get pods
```

If using a namespace, add `-n <namespace>` to Helm and kubectl commands.

---

## 5) Inspect release metadata and rendered manifest

```sh
helm status demo-release
helm get manifest demo-release
helm history demo-release
```

---

## 6) Upgrade the release (change image tag)

Example upgrade with inline override:

```sh
helm upgrade demo-release ./chart --set image.tag=1.25.2
```

Verify the updated manifest:

```sh
helm get manifest demo-release
kubectl get pods
```

You can also verify revision increment:

```sh
helm history demo-release
```

---

## 7) Roll back to previous revision

First identify the revision number from history, then:

```sh
helm rollback demo-release 1
```

Check status/history again:

```sh
helm status demo-release
helm history demo-release
```

---

## 8) Uninstall and cleanup

```sh
helm uninstall demo-release
helm list
kubectl get pods
```

---

## Demo Talking Points

- Helm charts are parameterized Kubernetes manifests.
- `helm template` is your safest first step to understand output.
- Releases are versioned; upgrade/rollback is part of normal operations.
- `values.yaml` + `--set` let you reuse one chart across environments.
