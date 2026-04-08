# Lesson 4: What is a Pod?

## Lesson Overview

In this lesson, you will learn the core Kubernetes building block: the **Pod**.  
A Pod is the smallest deployable unit in Kubernetes and represents one or more containers that run together as a single workload.

You will explore:

- What a Pod is and why it matters
- How containers in the same Pod share networking and storage
- How to create and inspect Pods with `kubectl`
- Typical Pod lifecycle and troubleshooting states
- Multi-container Pod patterns, including **init containers** and **sidecars**

This lesson includes hands-on examples in the `manifests/` folder so you can see Pod behavior in a real cluster.

---

## Learning Objectives

By the end of this lesson, you should be able to:

1. **Define a Pod** and explain its role in Kubernetes.
2. **Describe Pod structure**, including `metadata`, `spec`, and `containers`.
3. **Create and run a basic Pod** from a YAML manifest.
4. **Inspect and troubleshoot Pods** using commands like:
   - `kubectl get pods`
   - `kubectl describe pod <name>`
   - `kubectl logs <name>`
   - `kubectl exec -it <name> -- sh`
5. **Explain shared Pod context**, including:
   - Shared network namespace (same Pod IP)
   - Shared volumes between containers
6. **Understand multi-container Pod use cases**, including:
   - Init container setup work before app start
   - Sidecar-style helper containers running alongside the main app

---

## Lesson Artifacts

- `What_is_a_pod_cheatsheet.md` — quick reference for key concepts and commands
- `manifests/basic-pod.yaml` — simple single-container Pod example
- `manifests/multi-container-pod.yaml` — init container + multi-container Pod example

---

## Suggested Prerequisites

- Basic understanding of containers
- Access to a Kubernetes cluster
- `kubectl` configured to communicate with your cluster

---

## Expected Outcome

After completing this lesson, you should be comfortable reading and writing basic Pod manifests and confidently debugging common Pod startup and runtime issues.