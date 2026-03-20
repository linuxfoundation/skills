<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Kubernetes Reference

---

## Environment-to-MCP Mapping

| Environment | MCP prefix | Kubeconfig |
|---|---|---|
| dev | `mcp__k8s_dev__` | `~/.kube/dev-config` |
| stag | `mcp__k8s_stag__` | `~/.kube/staging-config` |
| prod | `mcp__k8s_prod__` | `~/.kube/prod-config` |

All Kubernetes MCPs run with `--read-only`. Write operations will fail.

---

## Available Tools

| Tool | When to use |
|---|---|
| `namespaces_list` | First step when you don't already know the service's namespace |
| `pods_list_in_namespace` | List pods in a namespace — check status and restart counts |
| `pods_get` | Detailed pod info: conditions, events, termination reason |
| `pods_log` | Get logs from a specific pod or container |
| `pods_top` | Live CPU/memory usage per pod |
| `events_list` | Kubernetes events — OOMKilled, CrashLoopBackOff, scheduling failures |
| `resources_get` | Inspect a specific resource (Deployment, ConfigMap, HPA, etc.) |
| `resources_list` | List resources of a type in a namespace |
| `nodes_top` | Node-level CPU/memory — use when checking resource pressure |
| `nodes_stats_summary` | Detailed node stats |
| `configuration_view` | View the kubeconfig being used (useful to confirm environment) |

---

## Namespace Layout

### Service Namespaces (one namespace per service)

Each lfx-v2 service has its own namespace. The namespace name matches the service
component name — `lfx-v2-` prefix is dropped.

| Namespace | Datadog service | Notes |
|---|---|---|
| `auth-service` | `lfx-v2-auth-service` | |
| `committee-service` | `lfx-v2-committee-service` | |
| `mailing-list-service` | `lfx-v2-mailing-list-service` | |
| `meeting-service` | `lfx-v2-meeting-service` | |
| `member-service` | `lfx-v2-member-service` | |
| `project-service` | `lfx-v2-project-service` | |
| `query-service` | `lfx-v2-query-service` | |
| `survey-service` | `lfx-v2-survey-service` | |
| `voting-service` | `lfx-v2-voting-service` | |
| `ui` | `lfx-v2-ui` | Main UI deployment |
| `ui-pr-{number}` | `lfx-v2-ui` | PR preview deployments |
| `changelog` | `lfx-changelog` | |
| `mcp-server` | `lfx-mcp-server` | |
| `v1-sync-helper` | `lfx-v1-sync-helper` | |
| `intercom-auth` | — | |

### The `lfx` Namespace — Shared Platform Components

The `lfx` namespace hosts shared infrastructure components that support all services.
It is **not** the first place to look when troubleshooting a specific service issue,
but is commonly checked when investigating platform-wide problems or when a service
shows symptoms that suggest a shared dependency is failing.

Components in `lfx`: Heimdall (auth gateway), OpenFGA (authorization), fga-sync,
indexer-service, access-check.

### Infrastructure Namespaces

These are platform-level components. Rarely the starting point for service
troubleshooting, but relevant when the issue points to infrastructure.

| Namespace | Purpose |
|---|---|
| `argocd` | GitOps — manages deployments from IaC repos |
| `cert-manager` | TLS certificate management |
| `datadog` | Datadog agent (metrics/logs/traces collection) |
| `external-secrets` | Syncs secrets from AWS Secrets Manager |
| `traefik` | Ingress controller |
| `reloader` | Watches ConfigMaps/Secrets and restarts pods on change |
| `kube-system` | Kubernetes system components |

### Other Namespaces

`backstage`, `pcc`, `lfit-litellm` — internal tooling, not LFX platform services.

### Default Namespace

Nothing should be deployed here. If you see pods in `default`, that is unexpected.

---

## Finding a Service's Namespace

If the user gives you a service name but not a namespace, the fastest path is:

1. Check the service-to-namespace table above
2. If not listed, run `namespaces_list` and look for a name matching the service

Do not assume a service is in a namespace without verifying — when in doubt,
list namespaces first.

---

## Common Investigation Sequence

```
1. namespaces_list               → confirm namespace exists
2. pods_list_in_namespace        → check pod status and restart count
3. events_list (namespace scope) → look for OOMKilled, CrashLoopBackOff, etc.
4. pods_log                      → get recent log output from crashing pod
5. pods_get                      → termination reason, resource requests/limits
6. pods_top                      → live resource usage (if memory/CPU suspected)
7. resources_get Deployment      → replica count, image version, env vars
```

---

## Making Changes in Dev

The Kubernetes MCP is read-only. To test a fix directly in dev, use `kubectl`
with the appropriate kubeconfig:

```bash
kubectl --kubeconfig ~/.kube/dev-config -n <namespace> <command>
```

Always pair any manual change with an IaC commit — dev is reconciled continuously
and manual changes will be overwritten. See [iac-repos.md](iac-repos.md) for
where to make the permanent change.

For staging and production, direct changes are not permitted. All changes must
go through ArgoCD via an IaC pull request.
