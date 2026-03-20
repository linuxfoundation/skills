<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Infrastructure as Code Repos

Changes to the LFX platform that are not committed to one of these repos will be
reconciled away — particularly in dev, which is continuously managed by ArgoCD.
When suggesting a fix, always provide the corresponding IaC change alongside any
manual test step.

---

## Repos

| Repo | What it controls | When to use it for fixes |
|---|---|---|
| [lfx-v2-opentofu](https://github.com/linuxfoundation/lfx-v2-opentofu) | AWS infrastructure — EKS clusters, RDS, OpenSearch, S3, IAM, networking | AWS-level issues: resource limits, database config, security groups, secret references |
| [lfx-v2-argocd](https://github.com/linuxfoundation/lfx-v2-argocd) | Kubernetes workload deployments — Helm values, replica counts, environment variables, resource limits | Most Kubernetes-level service config changes |
| [lfx-monitoring-terraform](https://github.com/linuxfoundation/lfx-monitoring-terraform) | Datadog dashboards, monitors, and alerting | Adding/fixing monitors, dashboards, alert thresholds |
| [lfx-secrets-management](https://github.com/linuxfoundation/lfx-secrets-management) | AWS Secrets Manager definitions and External Secrets sync config | Adding new secrets, rotating references, fixing secret access |

---

## Repo Details

### lfx-v2-argocd — Most Common for Service Issues

This is where most service-level configuration lives: environment variables,
resource requests/limits, replica counts, Helm chart values per environment.
When a fix involves changing how a service runs in Kubernetes, this is usually
the right repo.

ArgoCD continuously reconciles the cluster against this repo. Any manual `kubectl`
changes in dev that are not reflected here will be overwritten on the next sync.

### lfx-v2-opentofu — AWS Infrastructure

Use this when the issue is at the AWS layer: EKS node group configuration,
RDS parameter groups, OpenSearch domain settings, IAM roles and policies,
VPC/security group rules, or S3 bucket configuration.

### lfx-secrets-management — Secrets

When troubleshooting secret access issues, check this repo. The `secrets/lfx`
folder contains the LFX-specific secret definitions. Note that this repo also
contains non-LFX resources — stay within `secrets/lfx` when making LFX changes.

### lfx-monitoring-terraform — Datadog

Datadog monitors and dashboards are defined here as Terraform. LFX v2 standards
for monitor structure are still being established — check with the team before
adding new monitors to ensure consistency.

---

## Applying a Fix: Dev vs Stag/Prod

### In dev — test first, then commit

```
1. Identify the fix (e.g., wrong env var, insufficient memory limit)
2. Apply manually with kubectl for immediate testing:
   kubectl --kubeconfig ~/.kube/dev-config -n <namespace> \
     set env deployment/<name> KEY=VALUE
3. Verify the fix resolved the issue
4. Commit the equivalent change to lfx-v2-argocd (or opentofu for AWS changes)
5. Open a PR — ArgoCD will deploy from the merged change
```

For larger changes (topology, multiple services, new infrastructure), skip the
manual step entirely and go straight to an IaC PR to avoid inconsistency.

### In stag/prod — IaC only

Direct changes require elevated permissions most engineers don't have. The path is:

```
1. Identify the fix from investigation
2. Open a PR against the appropriate IaC repo
3. After review and merge, ArgoCD promotes the change
4. Verify in Datadog after deployment
```
