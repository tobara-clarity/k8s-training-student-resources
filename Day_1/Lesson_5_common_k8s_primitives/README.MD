# Lesson 5: Common Kubernetes Primitives

## Lesson Overview

In this lesson, you will work with the core Kubernetes building blocks used in almost every application deployment.  
You will apply and inspect real manifests to understand how workloads are created, exposed, configured, and self-healed in a cluster.

This lesson focuses on practical usage of:

- `Deployment` for managing stateless application replicas
- `Service` for stable in-cluster networking and discovery
- `ConfigMap` and `Secret` for separating configuration from container images

You will also observe how Kubernetes continuously reconciles desired state, including replacing failed Pods created by a Deployment.

---

## Learning Outcomes

By the end of this lesson, you should be able to:

1. Explain the purpose of common Kubernetes primitives and when to use each one.
2. Create a `Deployment` and verify replica management behavior.
3. Expose Pods with a `Service` using label selectors.
4. Define and apply a `ConfigMap` and `Secret`.
5. Inject configuration and secret values into containers as environment variables.
6. Describe how Kubernetes self-healing works in a Deployment-based workload.
7. Use `kubectl get`, `kubectl describe`, and `kubectl logs` to validate resource behavior.

---

## Lesson Assets

- Cheat sheet: `K8s_primitives_cheatsheet.md`
- Manifests:
  - `manifests/deployment-healing.yaml`
  - `manifests/service.yaml`
  - `manifests/config-and-secret.yaml`
  - `manifests/injection-deployment.yaml`

---

## Success Criteria

You have completed the lesson successfully when you can:

- Deploy and inspect application replicas with a Deployment
- Reach application Pods through a Service
- Confirm ConfigMap/Secret values are available in a running container
- Demonstrate or explain pod replacement/self-healing behavior

---

## Next Step

Use `DEMO.md` in this folder to run the hands-on walkthrough for the manifests in this lesson.