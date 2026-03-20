<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# ArgoCD Structure

This file documents how the LFX platform is deployed through ArgoCD, including
the exact repo layout, how versions are controlled, and what to change when
deploying a new release.

---

## Architecture Overview

ArgoCD uses an **app-of-apps** pattern. The root `app-of-apps` Application in each
cluster points at the ArgoCD repo and generates all other Applications.

Most LFX v2 services are managed by a single **ApplicationSet** named
`lfx-v2-applications`. Each service is a list element in that ApplicationSet.

**Key repos involved:**

| Repo | Role |
|---|---|
| `linuxfoundation/lfx-v2-argocd` | ApplicationSet definitions + all values files |
| `linuxfoundation/lfx-v2-{service}` | Helm chart lives here under `charts/` |

The Helm chart for each service lives **inside the service's own repo** at
`charts/{service-name}/` — not in the ArgoCD repo. This means releasing a new
version is a single operation: tag the service repo, and everything (Docker image
+ Helm chart) comes from the same commit.

---

## How Dev Auto-Deploys

In dev, every service has `targetRevision: HEAD`. ArgoCD continuously polls the
service repo's main branch and deploys changes automatically. There is no manual
deploy step for dev — merge to main is all that's needed.

---

## How Staging and Production Deploys Work

For staging and production, the ApplicationSet list element for each service has
`targetRevision` set to a specific semver tag (e.g., `1.5.0`). To deploy a new
version, you change that tag in the ArgoCD repo.

The values files in the ArgoCD repo also set `image.tag` explicitly for all
staging/production services — this field **must** be updated alongside
`targetRevision`. Tags use bare semver without a `v` prefix (e.g., `1.5.0` not
`v1.5.0`). This is a transitional state: once Helm chart version management is
fully automated, `image.tag` will be removed and only `targetRevision` will need
updating.

---

## ArgoCD Repo File Paths

### ApplicationSet files (one per environment, defines all services)

```
apps/dev/lfx-v2-applications.yaml
apps/staging/lfx-v2-applications.yaml     # may not exist yet for some services
apps/prod/lfx-v2-applications.yaml
```

Each file contains a `spec.generators[0].list.elements` array. Each element looks like:

```yaml
- name: lfx-v2-committee-service
  namespace: committee-service
  path: charts/lfx-v2-committee-service
  repoURL: https://github.com/linuxfoundation/lfx-v2-committee-service
  targetRevision: 1.5.0          # ← this is what you change for a deploy (bare semver, no v prefix)
```

In dev, `targetRevision: HEAD`.

### Values files (environment-specific overrides)

```
values/global/{service-name}.yaml     # shared across all environments
values/dev/{service-name}.yaml        # dev overrides (sets image.tag: development)
values/staging/{service-name}.yaml    # staging overrides
values/prod/{service-name}.yaml       # production overrides
```

Example: `values/dev/lfx-v2-committee-service.yaml` sets `image.tag: development`,
which is why dev uses the `:development` Docker tag.

For staging/production, the values file sets `image.tag` explicitly using bare
semver (e.g., `image.tag: 1.5.0`). **Always update this alongside `targetRevision`**
when deploying — both must match for the deployment to use the correct image.

---

## Service-to-ApplicationSet Mapping

All of these services are entries in `lfx-v2-applications`:

| ArgoCD Application name | Service repo | Helm chart path |
|---|---|---|
| `lfx-v2-auth-service` | `linuxfoundation/lfx-v2-auth-service` | `charts/lfx-v2-auth-service` |
| `lfx-v2-committee-service` | `linuxfoundation/lfx-v2-committee-service` | `charts/lfx-v2-committee-service` |
| `lfx-v2-mailing-list-service` | `linuxfoundation/lfx-v2-mailing-list-service` | `charts/lfx-v2-mailing-list-service` |
| `lfx-v2-meeting-service` | `linuxfoundation/lfx-v2-meeting-service` | `charts/lfx-v2-meeting-service` |
| `lfx-v2-member-service` | `linuxfoundation/lfx-v2-member-service` | `charts/lfx-v2-member-service` |
| `lfx-v2-project-service` | `linuxfoundation/lfx-v2-project-service` | `charts/lfx-v2-project-service` |
| `lfx-v2-query-service` | `linuxfoundation/lfx-v2-query-service` | `charts/lfx-v2-query-service` |
| `lfx-v2-survey-service` | `linuxfoundation/lfx-v2-survey-service` | `charts/lfx-v2-survey-service` |
| `lfx-v2-voting-service` | `linuxfoundation/lfx-v2-voting-service` | `charts/lfx-v2-voting-service` |
| `lfx-v2-ui` | `linuxfoundation/lfx-v2-ui` | `charts/lfx-v2-ui` |
| `lfx-v1-sync-helper` | `linuxfoundation/lfx-v1-sync-helper` | `charts/lfx-v1-sync-helper` |
| `lfx-changelog` | `linuxfoundation/lfx-changelog` | `charts/lfx-changelog` |
| `lfx-platform` | `linuxfoundation/lfx-v2-helm` | `charts/lfx-platform` |

---

## Individually Defined Applications (not in the ApplicationSet)

These are defined as standalone Application files in the ArgoCD repo:

| ArgoCD Application name | Notes |
|---|---|
| `app-of-apps` | Root app — do not modify directly |
| `identity-cookie-helper` | Part of `lfx-platform` group |
| `lfit-litellm` | Internal LF tooling, not an LFX v2 service |
| `lfx-mcp` | MCP server |

---

## Monitoring a Deployment

To check if ArgoCD has synced after merging a version bump PR, read the Application
resource directly from the cluster:

```
# Using K8s MCP:
mcp__k8s_{env}__resources_get
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  namespace: argocd
  name: {service-name}   # e.g., lfx-v2-committee-service
```

Look for:
- `status.sync.status: Synced` — ArgoCD has applied the new manifest
- `status.health.status: Healthy` — all resources are healthy
- `status.summary.images` — shows the current image tag running; confirm it matches the new version
- `status.operationState.phase: Succeeded` — last sync operation completed

---

## Image Tag Pattern

```
ghcr.io/linuxfoundation/{repo-name}/{binary-name}:{tag}
```

Examples:
- Dev: `ghcr.io/linuxfoundation/lfx-v2-committee-service/committee-api:development`
- Versioned: `ghcr.io/linuxfoundation/lfx-v2-committee-service/committee-api:1.5.0`

Note: production tags use bare semver without a `v` prefix.

The binary name within the image path (e.g., `committee-api`) is defined by the
service's CI/CD and Helm chart — it's not always predictable from the repo name.
The current image can always be found at `status.summary.images` in the ArgoCD
Application resource.
