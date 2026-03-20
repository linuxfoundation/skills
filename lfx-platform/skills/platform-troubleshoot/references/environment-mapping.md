<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Environment Mapping

This file defines how the three LFX environments (dev, stag, prod) map to specific
tool configurations across Datadog, Kubernetes, and AWS.

---

## MCP Tool Name Reference

MCP server names from `claude_desktop_config.json` are translated to tool prefixes
by replacing spaces with underscores and prepending `mcp__`.

| Environment | Kubernetes tools | AWS tools |
|---|---|---|
| dev | `mcp__k8s_dev__*` | `mcp__AWS_lfx_dev__*` |
| stag | `mcp__k8s_stag__*` | `mcp__AWS_lfx_stag__*` |
| prod | `mcp__k8s_prod__*` | `mcp__AWS_lfx_prod__*` |

Datadog spans all environments: `mcp__datadog_lfx__*`. Always filter by `env` tag.

---

## Datadog Environment Tags

Datadog uses full environment names. Always include the `env` tag in every query.

| User says | Canonical env | Datadog `env` tag |
|---|---|---|
| dev, development | dev | `env:development` |
| stag, staging | stag | `env:staging` |
| prod, production | prod | `env:production` |

**Verified:** `env:development` confirmed live. `env:staging` and `env:production`
follow the same full-name convention.

Host naming also follows this pattern: `{instance-id}-lfx-v2-{environment}`
(e.g., `i-0f96d19334698dacb-lfx-v2-development`).

---

## Datadog Service Names

Services are named `lfx-v2-{service}` in Datadog. Full list of known LFX v2 services:

| Datadog service name | Kubernetes namespace | Notes |
|---|---|---|
| `lfx-v2-auth-service` | `auth-service` | |
| `lfx-v2-committee-service` | `committee-service` | |
| `lfx-v2-fga-sync` | `lfx` | Shared platform component |
| `lfx-v2-indexer-service` | `lfx` | Shared platform component |
| `lfx-v2-mailing-list-service` | `mailing-list-service` | |
| `lfx-v2-meeting-service` | `meeting-service` | |
| `lfx-v2-member-service` | `member-service` | |
| `lfx-v2-project-service` | `project-service` | |
| `lfx-v2-query-service` | `query-service` | |
| `lfx-v2-ui` | `ui` | PR previews in `ui-pr-{number}` namespaces |
| `lfx-v2-access-check` | `lfx` | Shared platform component |
| `lfx-platform-heimdall.lfx` | `lfx` | Shared platform component |
| `lfx-platform-openfga` | `lfx` | Shared platform component |
| `lfx-changelog` | `changelog` | |
| `lfx-mcp-server` | `mcp-server` | |
| `lfx-v1-sync-helper` | `v1-sync-helper` | |

**Namespace naming pattern for v2 services:** the Kubernetes namespace matches the
service component name (e.g., `lfx-v2-committee-service` → namespace `committee-service`).
Shared platform components (fga-sync, indexer, access-check, heimdall, openfga) live
in the `lfx` namespace.

---

## Kubernetes Clusters and Kubeconfig Files

EKS cluster name is `lfx-v2` in every account.

| Environment | Kubeconfig path | EKS cluster | AWS profile |
|---|---|---|---|
| dev | `~/.kube/dev-config` | `lfx-v2` | `lfx-dev` |
| stag | `~/.kube/staging-config` | `lfx-v2` | `lfx-stag` |
| prod | `~/.kube/prod-config` | `lfx-v2` | `lfx-prod` |

**Generating kubeconfig files for a new machine** (run after AWS SSO login):

```bash
aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-dev \
  --kubeconfig ~/.kube/dev-config

aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-stag \
  --kubeconfig ~/.kube/staging-config

aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-prod \
  --kubeconfig ~/.kube/prod-config
```

Each file is generated with a single cluster and the default context set automatically.

---

## AWS Accounts

All LFX accounts are in `us-west-2`.

| Environment | MCP server | AWS SSO profile | Account ID | Role |
|---|---|---|---|---|
| dev | `AWS lfx dev` | `lfx-dev` | `788942260905` | PowerUser |
| stag | `AWS lfx stag` | `lfx-stag` | `844790888233` | Read-Only |
| prod | `AWS lfx prod` | `lfx-prod` | `372256339901` | Read-Only |

All AWS MCPs run with `READ_OPERATIONS_ONLY=true`.

**AWS SSO setup** — see [aws-sso-setup.md](aws-sso-setup.md) for the full walkthrough.
The short version: run `aws configure sso` with SSO start URL `https://lfx.awsapps.com/start`
and session name `okta-lfx`. Or copy the example config block below directly into
`~/.aws/config`:

```ini
[sso-session okta-lfx]
sso_start_url = https://lfx.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile lfx-dev]
sso_session = okta-lfx
sso_account_id = 788942260905
sso_role_name = PowerUser
region = us-west-2
output = json

[profile lfx-stag]
sso_session = okta-lfx
sso_account_id = 844790888233
sso_role_name = Read-Only
region = us-west-2
output = json

[profile lfx-prod]
sso_session = okta-lfx
sso_account_id = 372256339901
sso_role_name = Read-Only
region = us-west-2
output = json
```

Then authenticate: `aws sso login --profile lfx-dev` (one login covers all three
profiles for 12 hours).
