<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

---
description: Deploy an LFX v2 service to staging or production. Handles semver release creation on the service repo, ArgoCD version bump PR, deployment monitoring, and rollback. Use when an engineer wants to release a service, cut a new version, promote a build to staging or prod, or deploy a change. Trigger on phrases like "deploy to staging", "release to prod", "cut a release", "new version", "push to production", "promote to staging".
---

# LFX Platform Deploy

This command walks through the full release and deployment workflow for an LFX v2
service. It uses the `gh` CLI for GitHub operations and the Kubernetes MCP for
deployment monitoring.

**How it works:** The Helm chart for every LFX v2 service lives in the service's
own GitHub repo under `charts/`. In dev, ArgoCD tracks `HEAD` of the service repo
and deploys automatically. For staging and production, ArgoCD points at a specific
semver git tag — deploying means tagging the service repo and updating that tag
in the ArgoCD repo.

For full ArgoCD repo structure details, see
[../skills/platform-troubleshoot/references/argocd-structure.md](../skills/platform-troubleshoot/references/argocd-structure.md).

---

## Prerequisites

This command requires the **GitHub CLI (`gh`)** to be installed and authenticated.

### Check if you're ready

```bash
# Verify gh is installed
gh --version

# Verify you're authenticated and have access to the linuxfoundation org
gh auth status
gh api orgs/linuxfoundation --jq '.login'
```

If either command fails, set up `gh` before proceeding:

### Installing gh

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
sudo apt install gh

# Or download directly: https://cli.github.com
```

### Authenticating

```bash
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser
```

You need **write access** to the following repos for deploys to work:
- `linuxfoundation/lfx-v2-{service}` — to create tags and releases
- `linuxfoundation/lfx-v2-argocd` — to open the version-bump PR

If `gh api orgs/linuxfoundation --jq '.login'` returns a 403 or 404, you may need
to authorize the `gh` OAuth app for the `linuxfoundation` SSO organization:

```bash
# Open GitHub → Settings → Applications → Authorized OAuth Apps
# Find "GitHub CLI" and click "Configure SSO" → Grant linuxfoundation
open https://github.com/settings/applications
```

---

## Step 1: Identify service and target environment

Identify the service name and target environment from context. If not clear, ask.

| User says | Canonical env |
|---|---|
| dev / development | **dev** |
| stag / staging | **stag** |
| prod / production | **prod** |

**If the target is dev:** stop here.

> ArgoCD tracks the `main` branch of every service repo and deploys automatically.
> Just merge your PR to `main` — changes will be live in dev within a few minutes.
> To check sync status: look for the Application in the `argocd` namespace using
> the `mcp__k8s_dev__resources_get` tool with `kind: Application`.

**If the target is stag or prod:** continue.

---

## Step 2: Look up the service repo and current deployed version

Find the service's GitHub repo from the ArgoCD structure reference. The pattern is
`linuxfoundation/lfx-v2-{service}` for most services.

Check both pieces of information in parallel:

**A. Latest GitHub releases on the service repo:**
```bash
gh release list --repo linuxfoundation/lfx-v2-{service} --limit 10
```

**B. Currently deployed version in ArgoCD for the target environment:**

The ArgoCD repo folder name for staging is `staging` (not `stag`); for prod it is
`prod`. Read `apps/{env-folder}/lfx-v2-applications.yaml` and find the
`targetRevision` for this service:
```bash
gh api repos/linuxfoundation/lfx-v2-argocd/contents/apps/{env-folder}/lfx-v2-applications.yaml \
  --jq '.content' | base64 -d | grep -A5 "name: {service-name}"
```

Also read the env-specific values file — this always sets `image.tag` for
staging/prod and must be updated in sync with `targetRevision`:
```bash
gh api repos/linuxfoundation/lfx-v2-argocd/contents/values/{env-folder}/{service-name}.yaml \
  --jq '.content' | base64 -d
```
(This file may not exist for staging if staging hasn't been configured for this
service yet — that's OK, just note it.)

Present the user with:
- Current version deployed in `{env}` (from `targetRevision` in the ApplicationSet)
- Available GitHub releases newer than the deployed version

---

## Step 3: Determine the action

Ask:

> **{service}** is currently at `{current_version}` in {env}.
> Available newer releases: {list, or "none yet"}.
>
> Would you like to:
> 1. **Create a new release** from the current `main` branch
> 2. **Promote an existing release** to {env} — which version?

If they choose option 2, skip to Step 5.
If they choose option 1, continue to Step 4.

---

## Step 4: Create a new release

### 4a. Analyse changes since last release

```bash
LAST_TAG=$(gh release list --repo linuxfoundation/lfx-v2-{service} \
  --limit 1 --json tagName --jq '.[0].tagName')

# How much has changed?
gh api "repos/linuxfoundation/lfx-v2-{service}/compare/${LAST_TAG}...main" \
  --jq '{commits: .ahead_by, files: (.files | length)}'

# What changed?
gh api "repos/linuxfoundation/lfx-v2-{service}/compare/${LAST_TAG}...main" \
  --jq '[.commits[].commit.message] | .[:20][]'
```

### 4b. Recommend a version bump

Parse `{LAST_TAG}` as semver (e.g., `1.4.2` → major=1, minor=4, patch=2).
Tags use bare semver **without** a `v` prefix (e.g., `1.4.3` not `v1.4.3`).

- **Default: patch bump** → `1.4.3`
- **Suggest minor bump** if you see more than ~20 commits, more than ~10 files
  changed, or multiple `feat:` / `add:` commit messages indicating new features
- **Never recommend a major bump** — that's the engineer's call

Present your recommendation with a one-line rationale and ask for confirmation:

> Based on {N commits, N files changed} since `{LAST_TAG}`, I recommend a
> **{patch|minor}** release: **`{proposed_tag}`**. Good to go, or prefer a
> different version?

### 4c. Create the release

Once confirmed:
```bash
gh release create {new_tag} \
  --repo linuxfoundation/lfx-v2-{service} \
  --title "{new_tag}" \
  --generate-notes \
  --target main
```

### 4d. Monitor CI/CD — and start Step 5 in parallel

The release tag triggers GitHub Actions to build and push:
- Docker image: `ghcr.io/linuxfoundation/lfx-v2-{service}/{binary}:{new_tag}`
- Helm chart: packaged at `charts/lfx-v2-{service}` in the same tag

Monitor the run:
```bash
# Find the workflow triggered by the tag push
gh run list --repo linuxfoundation/lfx-v2-{service} --limit 5

RUN_ID=$(gh run list --repo linuxfoundation/lfx-v2-{service} \
  --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --repo linuxfoundation/lfx-v2-{service}
```

Tell the user CI/CD is underway, and **immediately proceed to Step 5** to prepare
the ArgoCD PR — don't wait for CI/CD to finish first.

---

## Step 5: Create the ArgoCD version bump PR

Clone the ArgoCD repo and make the version changes.

### 5a. Clone and branch

```bash
git clone https://github.com/linuxfoundation/lfx-v2-argocd.git /tmp/lfx-v2-argocd
cd /tmp/lfx-v2-argocd
git checkout -b deploy/{service}/{env}/{new_tag}
```

### 5b. Update the ApplicationSet — the main change

Edit `apps/{env-folder}/lfx-v2-applications.yaml` (where `{env-folder}` is
`staging` or `prod`). Find the list element for this service and update
`targetRevision`. Tags are bare semver without a `v` prefix:

```yaml
# Before:
- name: lfx-v2-{service}
  ...
  targetRevision: {current_tag}   # e.g., 0.4.1

# After:
- name: lfx-v2-{service}
  ...
  targetRevision: {new_tag}       # e.g., 0.4.2
```

### 5c. Update the values file — always required for staging/prod

Edit `values/{env-folder}/lfx-v2-{service}.yaml` and update `image.tag` to
match. This field exists in all staging/prod values files and **must be kept in
sync with `targetRevision`**:

```yaml
# Before:
image:
  tag: {current_tag}   # e.g., 0.4.1

# After:
image:
  tag: {new_tag}       # e.g., 0.4.2
```

If the staging values file doesn't exist yet for this service, no change needed
here — note it in the PR.

> **Note:** Explicit `image.tag` in values files is transitional. Once Helm chart
> version management is fully automated, only `targetRevision` will need updating.
> Until then, always update both.

### 5d. Commit and push

```bash
git add apps/{env-folder}/lfx-v2-applications.yaml
git add values/{env-folder}/lfx-v2-{service}.yaml   # always for prod; if exists for staging
git commit -m "chore({service}): bump {env} to {new_tag}"
git push origin deploy/{service}/{env}/{new_tag}
```

### 5e. Create the PR

```bash
gh pr create \
  --repo linuxfoundation/lfx-v2-argocd \
  --head deploy/{service}/{env}/{new_tag} \
  --base main \
  --title "chore({service}): bump {env} to {new_tag}" \
  --body "Deploys **{service}** to **{env}**.

| | |
|---|---|
| Previous version | \`{current_tag}\` |
| New version | \`{new_tag}\` |
| Files changed | \`apps/{env-folder}/lfx-v2-applications.yaml\`, \`values/{env-folder}/lfx-v2-{service}.yaml\` |

Auto-generated by \`/platform-deploy\`"
```

### 5f. Auto-merge if eligible

The ArgoCD repo has auto-approval for PRs that only change `targetRevision` and
`image.tag` fields. Review the diff:

```bash
gh pr diff --repo linuxfoundation/lfx-v2-argocd {pr_number}
```

**If the diff only touches `targetRevision` and/or `image.tag` values:** proceed
with auto-merge.
```bash
gh pr merge {pr_number} --repo linuxfoundation/lfx-v2-argocd --squash --auto
```

**If the diff contains any other changes:** stop and flag it:
> "This PR contains more than a version bump — it needs manual review before
> it can merge. PR: {url}"

---

## Step 6: Confirm CI/CD completed before monitoring

Before watching the cluster, confirm the CI/CD build from Step 4d succeeded:
```bash
gh run view $RUN_ID --repo linuxfoundation/lfx-v2-{service}
```

If it failed, surface the error immediately:
> "⚠️ CI/CD for `{new_tag}` failed — the ArgoCD PR has been created but ArgoCD
> won't be able to pull the new image or chart until the build passes.
> Check the workflow: {url}"

---

## Step 7: Monitor the deployment

Once the ArgoCD PR is merged, watch for sync and healthy status.
Use `mcp__k8s_stag__*` or `mcp__k8s_prod__*` depending on environment.

### 7a. Watch ArgoCD sync

Poll the Application resource (every ~30s):
```
mcp__k8s_{env}__resources_get
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  namespace: argocd
  name: lfx-v2-{service}
```

Watch for:
- `status.sync.status: Synced` — new manifest applied
- `status.health.status: Healthy` — all pods running
- `status.summary.images` — confirm the image tag shows `{new_tag}`, not the old one
- `status.operationState.phase: Succeeded` — last sync operation completed cleanly

### 7b. Watch pod startup

```
mcp__k8s_{env}__pods_list_in_namespace → {service-namespace}
mcp__k8s_{env}__events_list → {service-namespace}
```

Surface immediately if you see:
- `CrashLoopBackOff` — the new version is crashing
- `OOMKilled` — pod ran out of memory
- `ImagePullBackOff` — image tag doesn't exist yet (CI/CD may still be running)
- Pods stuck in `Pending` — node capacity or resource issue

### 7c. Check startup logs

Once new pods are Running (look for pods with a recent creation timestamp):
```
mcp__k8s_{env}__pods_log → most recently started pod in the namespace
```

Scan for ERROR-level messages in the first 60 seconds. Startup errors usually
indicate misconfiguration, missing secrets, or schema migration issues.

### 7d. Declare success or escalate

**Success:**
> ✅ `{service}` `{new_tag}` is live in {env}. All pods healthy.

**Issue found:** report the specific finding immediately — log lines, event details,
image tag mismatch. Don't wait for the full monitoring window.

---

## Step 8: Rollback (if requested)

To roll back, create a new PR reverting the version in the ApplicationSet (and
values file if applicable) to the previous tag. Same process as Step 5 — and
equally eligible for auto-merge if only version fields change.

```bash
git checkout -b rollback/{service}/{env}/{prev_tag}

# Revert targetRevision to {prev_tag} in the ApplicationSet
# Revert image.tag to {prev_tag} in values file if it was set

git commit -m "revert({service}): roll back {env} to {prev_tag}"
git push origin rollback/{service}/{env}/{prev_tag}

gh pr create \
  --repo linuxfoundation/lfx-v2-argocd \
  --head rollback/{service}/{env}/{prev_tag} \
  --base main \
  --title "revert({service}): roll back {env} to {prev_tag}" \
  --body "Emergency rollback of {service} in {env} from {new_tag} to {prev_tag}."
```

Then monitor as in Step 7.

---

## Staging considerations

Staging is still being built out. If you don't find a staging ApplicationSet for
a service:
> "I don't see a staging configuration for `{service}` yet. Would you like to:
> 1. Deploy directly to production only
> 2. Add staging configuration first (requires a separate PR that will need
>    manual review)"

For services where staging exists but the engineer wants to deploy stag and prod
simultaneously, create two PRs (one per environment) and run Step 7 monitoring
for both in parallel.
