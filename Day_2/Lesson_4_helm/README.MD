# Lesson 4: Helm Basics

## Lesson Overview

In this lesson, you’ll learn how **Helm** helps you package, install, and manage Kubernetes applications in a repeatable way.  
Instead of manually writing and applying many YAML files, Helm lets you define reusable templates and configurable values.

By the end of this lesson, you should understand how to:

- Create and use a simple Helm chart
- Deploy a chart as a named release
- Customize deployments with `values.yaml`
- Preview rendered manifests before deployment
- Upgrade, rollback, and uninstall a release

---

## Why Helm?

As Kubernetes apps grow, managing raw manifests becomes hard to maintain. Helm solves this by adding:

- **Templating**: Parameterize YAML with values
- **Reusability**: Reuse chart structure across environments
- **Release management**: Track versions and revisions of deployments
- **Safer workflows**: Dry-run and debug before applying changes

---

## Key Concepts

### 1. Chart
A **chart** is a package containing Kubernetes resource templates and metadata.

In this lesson, the chart lives under:

- `chart/`
  - `templates/`
  - `values.yaml`

---

### 2. Release
A **release** is a running instance of a chart in your cluster.

Example idea:
- Chart = blueprint
- Release = deployed building created from the blueprint

---

### 3. Templates
Templates are YAML files with placeholders, such as:

- `.Values.*` for custom values
- `.Release.*` for release metadata
- helper templates for shared labels or naming

---

### 4. Values
`values.yaml` provides default configuration for templates.

You can override these values at install/upgrade time to change behavior without editing templates directly.

---

### 5. Core Helm Lifecycle Commands

- `helm install <release-name> <chart-path>`
- `helm upgrade <release-name> <chart-path>`
- `helm rollback <release-name> <revision>`
- `helm uninstall <release-name>`
- `helm list`

---

## Debugging and Validation

Before installing, use dry-run rendering to inspect generated manifests:

- `helm install --debug --dry-run <release-name> <chart-path>`

This helps catch template and value issues early.

---

## What You’ll Practice in This Lesson

- Reading and understanding a minimal Helm chart
- Rendering chart templates with supplied values
- Installing a release and inspecting resulting Kubernetes resources
- Updating values and performing an upgrade
- Rolling back to a previous release revision

---

## Expected Outcome

After completing this lesson, you should be able to confidently use Helm for basic Kubernetes application packaging and deployment workflows, and explain how charts, templates, values, and releases work together.
