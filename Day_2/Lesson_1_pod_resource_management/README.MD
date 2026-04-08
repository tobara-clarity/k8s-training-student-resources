# Lesson 1: Pod Resource Management

## Lesson Summary
In this lesson, you learn how Kubernetes manages CPU and memory at the Pod level, and why resource configuration is essential for cluster stability, performance, and fair scheduling.  
You’ll work with manifests that demonstrate `requests`, `limits`, `ResourceQuota`, and Kubernetes QoS classes (`BestEffort`, `Burstable`, `Guaranteed`).

## Why This Matters
Without resource boundaries, a single workload can consume too much memory or CPU and impact other applications.  
By setting resource requests and limits, you help Kubernetes:
- schedule Pods more predictably,
- protect critical workloads,
- and enforce namespace-level guardrails.

## Learning Goals
By the end of this lesson, you should be able to:

1. **Explain Requests vs Limits**
   - Understand how `requests` influence scheduling.
   - Understand how `limits` cap runtime resource usage.
   - Describe CPU throttling vs memory OOM kills.

2. **Apply Resource Settings to Pods/Deployments**
   - Read and modify manifests with CPU/memory `requests` and `limits`.
   - Deploy workloads that use realistic resource constraints.

3. **Understand and Identify QoS Classes**
   - Compare `BestEffort`, `Burstable`, and `Guaranteed`.
   - Predict eviction priority behavior during node pressure.

4. **Use Namespace Quotas**
   - Apply and inspect `ResourceQuota`.
   - Explain how quotas prevent over-allocation by teams or workloads.

5. **Debug Resource-Related Failures**
   - Diagnose `Pending` Pods due to unschedulable requests.
   - Identify OOM and resource pressure symptoms with `kubectl describe` and events.

## Lesson Artifacts
This lesson includes a `manifests/` folder with examples for:
- resource-constrained Pods,
- deployment-level resource policies,
- QoS class comparison,
- and namespace quota enforcement.

## Expected Outcomes
After completing the demos, you should be comfortable setting safe defaults for workload resources and explaining how those settings affect scheduling, performance, and reliability in Kubernetes.