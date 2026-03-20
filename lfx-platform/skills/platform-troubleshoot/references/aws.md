<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# AWS Reference

This file documents AWS-specific patterns for troubleshooting LFX services.

---

## When to Use the AWS MCP

The AWS MCP is a zoom-out tool — not a starting point. Reach for it when:
- Logs or traces point to a specific AWS service failure (database, Secrets Manager, S3, OpenSearch)
- You suspect EKS-level issues (control plane, node groups)
- There's evidence of IAM/permission problems
- Network-level issues suggest VPC, security group, or routing problems

Do not reach for AWS as a general first step. Start with Datadog, escalate to
Kubernetes, then AWS if the evidence points there.

---

## Environment-to-MCP Mapping

| Environment | MCP prefix |
|---|---|
| dev | `mcp__AWS_lfx_dev__` |
| stag | `mcp__AWS_lfx_stag__` |
| prod | `mcp__AWS_lfx_prod__` |

Both the AWS and Kubernetes MCPs are **read-only**. Use them for investigation only.

---

## Key AWS Services in LFX

**TODO:** Fill in the specific AWS services used by the LFX platform.

| Service | What it does in LFX | How to investigate |
|---|---|---|
| EKS | Kubernetes cluster hosting | Check control plane logs, node group status |
| RDS / Aurora | <!-- TODO: which databases? --> | Connection errors, slow queries, failover events |
| OpenSearch | Search index (query service) | Cluster health, index status, shard errors |
| Secrets Manager | Service credentials | Secret existence, version, IAM access |
| S3 | <!-- TODO: what buckets? --> | Access errors, lifecycle policies |
| <!-- add others --> | | |

---

## AWS Account Structure

**TODO:** Fill in account IDs and any cross-account patterns.

| Environment | Account | Notes |
|---|---|---|
| dev | <!-- account ID or alias --> | |
| stag | <!-- account ID or alias --> | |
| prod | <!-- account ID or alias --> | |

---

## Common Investigation Patterns

**TODO:** Document common AWS investigation patterns specific to LFX.

Examples to fill in:
- How to check RDS instance status and recent events
- How to verify Secrets Manager secret exists and is accessible
- How to check EKS node group status
- How to review security group rules for connectivity issues
- How to check OpenSearch cluster health
