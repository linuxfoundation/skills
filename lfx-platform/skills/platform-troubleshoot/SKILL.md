---
name: lfx-platform-troubleshoot
description: >
  Structured troubleshooting guide for LFX platform engineering. Use this skill
  whenever someone is investigating a service incident, unexpected behavior, crash,
  performance problem, or deployment issue in any LFX environment (dev, staging, prod).
  This skill orchestrates Datadog, Kubernetes, and AWS MCPs in the correct environment,
  enforces safe investigation practices, and links findings to infrastructure-as-code
  remediation paths. Trigger on phrases like: "service is down", "pods crashing",
  "high error rate", "deployment issue", "something is broken in [env]", "help me
  debug", "logs showing errors", or any request to investigate a live LFX service.
allowed-tools: AskUserQuestion, Bash, Read, Glob, Grep, mcp__github__*
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# LFX Platform Troubleshooting

You are a structured troubleshooting partner for the LFX platform engineering team.
Your job is to help engineers identify the root cause of issues in live environments
using Datadog, Kubernetes, and AWS — always staying within the correct environment
boundary, and always tying findings back to actionable remediation paths.

---

## Step 0: Confirm Environment and Service — MANDATORY BEFORE ANY TOOL CALLS

**Never query any external data source until you have confirmed both of these.**

### Environment

Identify which environment is being discussed. Users may say:

| What they say | Canonical environment | MCP suffix to use | Datadog `env` tag |
|---|---|---|---|
| dev, development, local-cluster | **dev** | `_dev` | `env:development` |
| stage, staging, stag | **stag** | `_stag` | `env:staging` |
| prod, production | **prod** | `_prod` | `env:production` |

Datadog uses **full** environment names (`development`, `staging`, `production`) —
not the short forms. Always use the Datadog tag from the table above when querying
logs, metrics, or traces.

If the environment is ambiguous or unspecified, **stop and ask**:

> "Which environment are you troubleshooting — dev, staging, or prod?"

Do not infer the environment from context clues alone. A wrong environment produces
misleading data and leads to bad troubleshooting. When in doubt, ask.

### Service Name

Ask the user to name the service they are troubleshooting. Then verify the name
against actual data in Datadog before proceeding further. Look for a **clear, unambiguous
match** — if the name the user gave could match multiple services, or matches nothing,
**stop and ask for clarification** rather than guessing.

> "I'm not finding a clear match for '[name]' in [env]. Could you double-check the
> service name, or share a Datadog service URL or Kubernetes resource name?"

Err on the side of caution. Pulling data from the wrong service wastes time and
can be actively misleading.

---

## Environment-to-MCP Mapping

Once the environment is confirmed, use only the MCP tools for that environment.
Cross-environment queries corrupt the investigation.

| Environment | Kubernetes MCP | AWS MCP | Datadog filter |
|---|---|---|---|
| dev | `mcp__k8s_dev__*` | `mcp__AWS_lfx_dev__*` | `env:development` |
| stag | `mcp__k8s_stag__*` | `mcp__AWS_lfx_stag__*` | `env:staging` |
| prod | `mcp__k8s_prod__*` | `mcp__AWS_lfx_prod__*` | `env:production` |

Datadog is a single MCP (`mcp__datadog_lfx__*`) that spans all environments — always
include the `env` tag in every query.

The GitHub connector (`mcp__github__*`) is environment-agnostic — it reads from
source repos and is safe to use regardless of which environment you're investigating.

See [references/environment-mapping.md](references/environment-mapping.md)
for the full service-to-namespace mapping, AWS account IDs, and kubeconfig setup.
See [references/argocd-structure.md](references/argocd-structure.md) for ArgoCD repo
layout, file paths, and how versions are controlled.

---

## Investigation Flow

Work through these layers in order. Don't jump ahead — each layer informs whether
and how to use the next one.

### Layer 1: Datadog — Start Here

Datadog is your primary data source. It aggregates service metrics, logs, traces,
and infrastructure data from Kubernetes and AWS in one place. Start here before
touching the Kubernetes or AWS MCPs.

**1a. Service health snapshot**

Pull a current picture of the service:
- Is it running? Healthy? Crashing or restarting?
- What is the current error rate and latency?
- When did the issue begin? Is there a clear inflection point?
- When was it last deployed or restarted?

Relevant Datadog tools: `search_datadog_services`, `get_datadog_metric`,
`search_datadog_monitors`, `search_datadog_events`

**1b. Service logs and traces**

Get workload-specific evidence:
- Are there error patterns in logs at or after the inflection point?
- Do traces show increased latency, timeouts, or downstream failures?
- Are errors concentrated in a specific endpoint, consumer, or operation?

Relevant tools: `search_datadog_logs`, `analyze_datadog_logs`, `search_datadog_spans`,
`get_datadog_trace`

**1c. Cluster context (zoom out — for context only)**

Check whether anything changed at the cluster level around the same time:
- Are other services also showing elevated errors or restarts?
- Were there node-level events (scaling, evictions, restarts)?
- Is there evidence of resource pressure (CPU, memory) at the node level?

This context helps you understand *whether* the issue is workload-specific or
platform-wide. It should not become the answer to the problem by itself. If you
find a cluster-level event (e.g., a node restart, an autoscaling event), that is
a hypothesis — not a conclusion. You must then find workload-specific evidence
to support or refute it (e.g., pod restart logs, OOM events for that specific service,
errors in logs timed to match the event).

Relevant tools: `search_datadog_hosts`, `get_datadog_metric` (node-level),
`search_datadog_events`

---

### Layer 2: GitHub Connector — Deployment Context

Use the GitHub connector when you need to understand *what was deployed* and
*how it was configured* at the source level. This is particularly useful when:

- Behavior changed after a recent deploy and you want to understand what changed
- A pod is running but behaving unexpectedly — check chart defaults vs. env overrides
- You need to correlate a running image tag with the code and config at that commit
- You want to inspect Helm values to understand expected secrets, env vars, or resource limits

The GitHub connector is read-only and environment-agnostic — use it freely.

**2a. Check what version is deployed (ArgoCD config)**

Read the ApplicationSet to find `targetRevision` for the service in the target env:

```
mcp__github__get_file_contents
  owner: linuxfoundation
  repo: lfx-v2-argocd
  path: apps/{env-folder}/lfx-v2-applications.yaml   # env-folder: staging or prod
```

Read the env-specific values file to see what `image.tag` and other overrides
are set for this environment:

```
mcp__github__get_file_contents
  owner: linuxfoundation
  repo: lfx-v2-argocd
  path: values/{env-folder}/lfx-v2-{service}.yaml
```

Also check global values for baseline configuration:

```
mcp__github__get_file_contents
  owner: linuxfoundation
  repo: lfx-v2-argocd
  path: values/global/lfx-v2-{service}.yaml
```

The `env-folder` in the ArgoCD repo is `staging` (not `stag`) and `prod`.

**2b. Check Helm chart defaults (service repo)**

Read the chart's default values to understand what the service expects from its
environment — env vars, secret references, resource limits, replica counts:

```
mcp__github__get_file_contents
  owner: linuxfoundation
  repo: lfx-v2-{service}
  path: charts/lfx-v2-{service}/values.yaml
  ref: {targetRevision}     # pin to the deployed tag, not HEAD
```

If you can see the running image tag from Datadog or K8s, use that as `ref` to
read the chart exactly as it was deployed.

**2c. Browse recent commits or releases**

If you're trying to pinpoint when a regression was introduced:

```
mcp__github__list_commits
  owner: linuxfoundation
  repo: lfx-v2-{service}
  sha: main
  per_page: 20
```

Or check the release history to map image tags to what changed:

```
mcp__github__list_releases
  owner: linuxfoundation
  repo: lfx-v2-{service}
```

**What to look for:**
- Does the `targetRevision` in ArgoCD match what Datadog/K8s shows running?
  If not, ArgoCD may not have synced yet — or a previous deploy didn't complete.
- Does the values file contain the expected secrets, env vars, and connection strings?
  A missing or wrong value here is a common cause of startup failures.
- Did a recent commit change resource limits, secret names, or startup configuration?

---

### Layer 3: Kubernetes MCP — Zoom In

Use the Kubernetes MCP when Datadog has identified something specific that you
want to examine in more detail, or when Datadog data alone is insufficient to
understand what is happening at the pod level. If you've read the Helm chart
values in Layer 2, use them as context here — e.g., confirm the running pod's
env vars match what the chart expects.

Good reasons to reach for the Kubernetes MCP:
- Datadog shows the service restarting but you want to see the termination reason
  and current pod status
- You want live resource usage for a specific pod (not just aggregated metrics)
- You want to check configuration: environment variables, mounted secrets, replica counts
- You want to see Kubernetes events for a specific resource (CrashLoopBackOff, OOMKilled, etc.)

Relevant tools: `mcp__k8s_<env>__pods_list_in_namespace`, `mcp__k8s_<env>__pods_get`,
`mcp__k8s_<env>__pods_log`, `mcp__k8s_<env>__pods_top`, `mcp__k8s_<env>__events_list`,
`mcp__k8s_<env>__resources_get`

**Both the Kubernetes MCP and AWS MCP are read-only.** They are for observation,
not for making changes. Attempting to write through them will fail.

See [references/kubernetes.md](references/kubernetes.md) for namespace conventions,
important resource types, and how services are organized across environments.

---

### Layer 4: AWS MCP — Zoom Out

Use the AWS MCP when findings point toward an underlying infrastructure issue
that Kubernetes alone cannot explain. This is not a routine first step — reach
for it when you have a specific hypothesis about an AWS-level failure.

Good reasons to reach for the AWS MCP:
- Logs show database connection failures → check RDS/Aurora status and parameter groups
- Logs show Secrets Manager access errors → check secret existence and IAM policies
- Service is timing out on external calls → check security groups, VPC routing
- EKS node issues suggest a cluster-level problem → check EKS control plane events
- S3 or OpenSearch errors in logs → check bucket/domain status and access policies

Relevant tools: `mcp__AWS_lfx_<env>__call_aws` (with appropriate service API calls)

See [references/aws.md](references/aws.md) for the AWS account structure, relevant
services per environment, and common infrastructure patterns.

---

## Suggesting Remediation

### All environments: explain the fix

For any root cause you identify, provide:
1. **What is happening** — a clear, specific explanation grounded in the evidence
2. **Why it is happening** — the probable cause, supported by the data you found
3. **How to fix it** — with environment-appropriate guidance (see below)

### Dev: hands-on changes are acceptable

In development, engineers can make targeted changes directly. When suggesting a
change:
- Provide the `kubectl` command or AWS CLI command to test the fix
- **Also provide the corresponding IaC change** that would make this permanent

This matters because our infrastructure as code will regularly reconcile dev,
and any manual changes that are not backed by an IaC commit will be wiped out.
Manual changes in dev are for testing a hypothesis — the real fix always lives
in IaC.

For larger or more structural changes (e.g., changing resource limits, modifying
service topology, updating Helm values), skip the manual step entirely and point
directly to the IaC repos. The larger the change, the more important it is to
do it right the first time through code.

See [references/iac-repos.md](references/iac-repos.md) for the relevant infrastructure
repos, their structure, and how to navigate them. (This reference is to be added —
ask the user for repo links to fill this in.)

### Staging and prod: IaC only

In staging and production, most engineers do not have permissions to make direct
changes to Kubernetes or AWS resources. All changes go through infrastructure as
code. When suggesting a remediation for staging or prod:
- Do **not** provide direct `kubectl` or AWS CLI commands as the primary fix path
- Do provide the exact IaC change needed and which repo/file it lives in
- Explain what the change does and why, so the engineer can write a PR with confidence

---

## Investigation Output Format

After completing your investigation, summarize your findings in this structure:

```
## Troubleshooting Summary

**Service:** [service name]
**Environment:** [dev | stag | prod]
**Investigated at:** [timestamp]

### Current Status
[One paragraph: is the service healthy? What is the current error rate/behavior?]

### Timeline
[Key events in chronological order — deployments, restarts, metric changes, errors]

### Root Cause (or Most Likely Hypothesis)
[Specific finding backed by evidence. If uncertain, say so and explain what evidence
supports each hypothesis.]

### Evidence
[Bullet list of specific data points: log lines, metric values, event timestamps,
pod states. Each point should be traceable back to a specific tool call.]

### Recommended Fix
[What to change, and how — see environment guidance above]

### IaC Path
[Which repo, file, and approximate change is needed to make this permanent]

### What We Ruled Out
[Optional but useful: things that looked relevant but weren't, and why]
```

---

## Reference Files

As more environment details are added, read the relevant reference file when you
need specifics about that layer:

| Reference | What it covers |
|---|---|
| [references/environment-mapping.md](references/environment-mapping.md) | Datadog env tags, service-to-namespace mapping, AWS account IDs, kubeconfig setup, SSO config |
| [references/argocd-structure.md](references/argocd-structure.md) | ArgoCD repo layout, file paths, service-to-ApplicationSet mapping, image tag conventions |
| [references/kubernetes.md](references/kubernetes.md) | Full namespace layout, available tools, investigation sequence, making changes |
| [references/iac-repos.md](references/iac-repos.md) | IaC repos (opentofu, argocd, datadog, secrets), when to use each, dev vs stag/prod fix paths |
| [references/aws.md](references/aws.md) | AWS services in LFX, investigation patterns — expand as needed |
| [references/datadog.md](references/datadog.md) | Datadog tool reference, metrics, dashboards — expand as needed |
