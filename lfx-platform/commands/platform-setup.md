<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

---
description: Set up a local machine to use the LFX platform plugin. Installs and configures the GitHub CLI, AWS CLI, AWS SSO profiles, and kubeconfig files needed to run platform-deploy and platform-troubleshoot. Safe to re-run — detects what is already configured and skips those steps. Use when an engineer says "set up my machine", "configure platform access", "I can't run platform-deploy", or "getting started with LFX platform tooling".
---

# LFX Platform Setup

This command configures your local machine to use the LFX platform plugin. It
walks through each prerequisite in order, checks whether it is already in place,
and only performs the steps that are actually needed.

Run it end-to-end on a new machine, or re-run it at any time to verify or repair
your setup.

---

## Before starting

Tell the user what this command will do:

> "I'll check and configure the following on your machine:
> 1. Desktop Extensions — install the 6 `.mcpb` bundles for Kubernetes and AWS MCP servers
> 2. GitHub CLI (`gh`) — installed and authenticated with `linuxfoundation` org access
> 3. AWS CLI + `uv` — installed and configured with the three LFX SSO profiles
> 4. Kubeconfig files for dev, staging, and prod clusters
> 5. Cloud connectors — authorize Datadog and GitHub in Claude settings
>
> This will open your browser a few times for GitHub auth, AWS SSO, and connector
> authorization. Everything else is automated. Let me know when you're ready, or
> just say go."

Wait for confirmation before running any commands. Some steps open browser windows
and the user should be sitting at their machine.

---

## Step 1: Install Desktop Extensions

The Kubernetes and AWS MCP servers are distributed as Desktop Extensions (`.mcpb`
files) in the plugin's `extensions/` folder. Each extension, once installed,
automatically registers its MCP server in Claude Desktop — no manual config editing
required.

There are six extensions to install:

| File | What it provides |
|---|---|
| `k8s_dev.mcpb` | Kubernetes MCP — dev cluster |
| `k8s_stag.mcpb` | Kubernetes MCP — staging cluster |
| `k8s_prod.mcpb` | Kubernetes MCP — production cluster |
| `aws_lfx_dev.mcpb` | AWS API MCP — dev account (788942260905) |
| `aws_lfx_stag.mcpb` | AWS API MCP — staging account (844790888233) |
| `aws_lfx_prod.mcpb` | AWS API MCP — production account (372256339901) |

### 1a. Check which extensions are already installed

Try a lightweight call to each MCP server:
```
mcp__k8s_dev__namespaces_list
mcp__k8s_stag__namespaces_list
mcp__k8s_prod__namespaces_list
mcp__AWS_lfx_dev__suggest_aws_commands (prompt: "list s3 buckets")
mcp__AWS_lfx_stag__suggest_aws_commands (prompt: "list s3 buckets")
mcp__AWS_lfx_prod__suggest_aws_commands (prompt: "list s3 buckets")
```

Skip installation for any that respond successfully.

### 1b. Install missing extensions

For each extension that isn't responding, install it from the plugin's
`extensions/` folder. There are three ways to install a `.mcpb` file:

- **Double-click** the file in Finder/Files
- **Drag and drop** the file into Claude Desktop
- **File menu**: Claude Desktop → File → Install Extension → select the file

Tell the user which files to install and where to find them:

> "The `extensions/` folder is in the `lfx-platform` plugin directory inside
> your `lfx-skills` repo. Install these files: {list missing extensions}.
> Double-click each one, review the permissions, and click Install."

### 1c. Configure kubeconfig path during install

When installing a Kubernetes extension, Claude Desktop will prompt for a
**kubeconfig file path**. The defaults are pre-filled:

- `k8s_dev.mcpb` → `~/.kube/dev-config`
- `k8s_stag.mcpb` → `~/.kube/staging-config`
- `k8s_prod.mcpb` → `~/.kube/prod-config`

These files will be generated in Step 4. The user can accept the defaults now
and the paths will work once Step 4 is complete.

### 1d. Verify extensions loaded

After installation, Claude Desktop needs to restart to load the new MCP servers.
Ask the user to restart Claude Desktop, then re-run the checks from Step 1a.

---

## Step 2: Detect operating system (used throughout)

```bash
uname -s
```

Store the result:
- `Darwin` → macOS. Use `brew` for package installation.
- `Linux` → Linux. Detect the distro:
  ```bash
  cat /etc/os-release | grep -E '^ID='
  ```
  - `ubuntu`, `debian`, `pop` → use `apt`
  - `fedora`, `rhel`, `centos` → use `dnf`
  - anything else → skip package manager steps and provide manual install links

---

## Step 3: GitHub CLI

### 3a. Check if gh is installed

```bash
gh --version
```

**If installed:** print the version and skip to 2b.

**If not installed:**

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
sudo apt update && sudo apt install -y gh

# Linux (Fedora/RHEL)
sudo dnf install -y gh

# Manual install (all platforms)
# https://cli.github.com — download the binary for your platform
```

After installing, verify:
```bash
gh --version
```

### 3b. Check authentication status

```bash
gh auth status 2>&1
```

Parse the output:
- Contains `Logged in to github.com` → authenticated. Skip to 2c.
- Any other output or non-zero exit → not authenticated. Continue.

**If not authenticated:**

Tell the user:
> "I'll open GitHub in your browser to complete authentication. This will ask
> you to log in and authorize the GitHub CLI app."

Then run:
```bash
gh auth login --hostname github.com --git-protocol https --web
```

This opens a browser. Wait for the user to confirm it completed, then re-run
`gh auth status` to verify.

### 3c. Check linuxfoundation SSO authorization

```bash
gh api orgs/linuxfoundation --jq '.login' 2>&1
```

- Returns `linuxfoundation` → authorized. Step 2 complete.
- Returns `Resource not accessible` or a 403/404 → SSO authorization needed.

**If SSO authorization is needed:**

> "GitHub SSO is not yet authorized for the `linuxfoundation` organization.
> I'll open the settings page — look for **GitHub CLI** under Authorized OAuth Apps,
> click **Configure SSO**, and grant access to `linuxfoundation`."

```bash
# macOS
open https://github.com/settings/applications

# Linux
xdg-open https://github.com/settings/applications 2>/dev/null || \
  echo "Open this URL in your browser: https://github.com/settings/applications"
```

After the user confirms they've authorized it, re-run the check:
```bash
gh api orgs/linuxfoundation --jq '.login'
```

If it still fails, tell the user:
> "It can take a minute for SSO authorization to take effect. If this keeps
> failing, check that you're a member of the `linuxfoundation` GitHub org and
> that your account has been granted repo access."

---

## Step 4: AWS CLI and uv

The AWS MCP extensions require **uv** (specifically `uvx`) to run the AWS API
MCP server. The AWS CLI is needed to configure SSO profiles and generate
kubeconfig files.

### 4a. Check if uv is installed

```bash
uv --version 2>&1
```

**If installed:** print the version and skip to 4b.

**If not installed:**

```bash
# macOS and Linux (official installer)
curl -LsSf https://astral.sh/uv/install.sh | sh

# macOS (alternatively via brew)
brew install uv
```

After installing, add uv to PATH if needed (the installer will print instructions),
then verify:
```bash
uv --version && uvx --version
```

### 4b. Check if aws CLI is installed

```bash
aws --version 2>&1
```

**If installed:** print the version and skip to 3b.

**If not installed:**

```bash
# macOS
brew install awscli

# Linux (Debian/Ubuntu)
sudo apt update && sudo apt install -y awscli

# Linux (Fedora/RHEL)
sudo dnf install -y awscli
```

Verify:
```bash
aws --version
```

If the package manager version is below 2.x, the user should install from AWS
directly instead:
> "The version from your package manager is AWS CLI v1. AWS SSO requires v2.
> Download from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"

### 4c. Check AWS SSO config

Check whether the `~/.aws/config` file contains the LFX SSO profiles:

```bash
grep -l "okta-lfx\|lfx-dev\|lfx-stag\|lfx-prod" ~/.aws/config 2>/dev/null && \
  grep "sso_session\|sso_account_id" ~/.aws/config | head -20
```

**If all four blocks are present** (sso-session okta-lfx, profile lfx-dev,
profile lfx-stag, profile lfx-prod): skip to 3c.

**If missing or incomplete:** write the config.

Check if `~/.aws/config` exists:
```bash
ls -la ~/.aws/config 2>/dev/null || echo "not found"
```

If the file doesn't exist, create the directory and file:
```bash
mkdir -p ~/.aws
```

Then **append** the following block to `~/.aws/config` (use `>>` to avoid
overwriting any existing profiles the user may have for other projects):

```bash
cat >> ~/.aws/config << 'EOF'

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
EOF
```

Confirm the profiles were written:
```bash
aws configure list-profiles | grep lfx
```

### 4d. Authenticate via AWS SSO

Check if the current SSO session is still valid:
```bash
aws sts get-caller-identity --profile lfx-dev 2>&1
```

**If it returns an account ID:** the session is active. Skip to Step 5.

**If it returns an error** (expired token, not logged in, etc.):

Tell the user:
> "I'll open the AWS SSO login page in your browser. Sign in with your Okta
> credentials. One login covers all three LFX accounts for 12 hours."

```bash
aws sso login --profile lfx-dev
```

This opens a browser window. Wait for the user to confirm they've signed in,
then verify:
```bash
aws sts get-caller-identity --profile lfx-dev --query 'Account' --output text
aws sts get-caller-identity --profile lfx-stag --query 'Account' --output text
aws sts get-caller-identity --profile lfx-prod --query 'Account' --output text
```

Expected output:
```
788942260905
844790888233
372256339901
```

If any profile returns an error, note which ones failed and advise:
> "The `{profile}` profile isn't working. This usually means you don't have
> access to that AWS account yet — ask in #lfx-platform to get access granted."

---

## Step 5: Kubeconfig files

Kubeconfig files are generated from the EKS cluster using your AWS profiles.
Each environment uses a separate file to keep contexts isolated.

### 5a. Check which configs already exist

```bash
ls -la ~/.kube/dev-config ~/.kube/staging-config ~/.kube/prod-config 2>&1
```

For each file that already exists, verify it connects:
```bash
kubectl --kubeconfig ~/.kube/dev-config get nodes --no-headers 2>&1 | head -3
kubectl --kubeconfig ~/.kube/staging-config get nodes --no-headers 2>&1 | head -3
kubectl --kubeconfig ~/.kube/prod-config get nodes --no-headers 2>&1 | head -3
```

Skip generation for any environment where `get nodes` succeeds.

### 5b. Generate missing kubeconfig files

For any environment where the file is missing or the connection failed:

```bash
# Create ~/.kube directory if it doesn't exist
mkdir -p ~/.kube

# Dev
aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-dev \
  --kubeconfig ~/.kube/dev-config

# Staging
aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-stag \
  --kubeconfig ~/.kube/staging-config

# Prod
aws eks update-kubeconfig \
  --region us-west-2 --name lfx-v2 --profile lfx-prod \
  --kubeconfig ~/.kube/prod-config
```

Only run the commands for environments whose kubeconfig is missing or broken.

### 5c. Verify connections

```bash
kubectl --kubeconfig ~/.kube/dev-config get nodes --no-headers 2>&1 | head -3
kubectl --kubeconfig ~/.kube/staging-config get nodes --no-headers 2>&1 | head -3
kubectl --kubeconfig ~/.kube/prod-config get nodes --no-headers 2>&1 | head -3
```

Each should return a list of nodes. If any fail with `Unauthorized` or
`Unable to connect`, the AWS SSO token may have expired — re-run Step 3c,
then retry.

If `kubectl` itself is not installed:

```bash
# macOS
brew install kubectl

# Linux (Debian/Ubuntu)
sudo apt update && sudo apt install -y kubectl

# Or via the official binary:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
```

---

## Step 6: Cloud connector authorization

The platform plugin uses two types of MCP servers:

**Local servers** (Kubernetes, AWS) — defined in the plugin's `.mcp.json` and
started automatically by Claude when the plugin is loaded. These rely on the
kubeconfig files and AWS profiles configured in Steps 4 and 5. No additional
setup needed here.

**Cloud connectors** (Datadog, GitHub) — these are OAuth-based connectors that
must be authorized through Claude's connector settings. They don't require any
local installation, but they do need to be connected to the right accounts.

### 6a. Check if cloud connectors are already authorized

Try a lightweight call to each:

- Datadog: try `mcp__datadog_lfx__search_datadog_services`
- GitHub: try `mcp__github__get_file_contents` with `owner: linuxfoundation`,
  `repo: lfx-v2-argocd`, `path: README.md`

If both respond successfully, skip to Step 6.

### 6b. Connect the Datadog connector

If the Datadog connector is not responding:

> "Open Claude → Settings → Connectors. Find **Datadog** and click **Connect**.
> Sign in with your Datadog credentials and authorize access to the LFX
> organization's Datadog account. Once connected, come back here and I'll
> verify it's working."

After the user confirms, retry `mcp__datadog_lfx__search_datadog_services`.

**Note:** LFX uses Datadog US1 (`datadoghq.com`). Make sure to connect the
**Datadog** connector, not the Datadog (US3) one.

### 6c. Connect the GitHub connector

If the GitHub connector is not responding:

> "Open Claude → Settings → Connectors. Find **GitHub** and click **Connect**.
> Authorize the connector to access the `linuxfoundation` organization — you
> may need to grant org access separately under GitHub Settings → Applications
> → Authorized OAuth Apps → GitHub (Claude) → Configure SSO."

After the user confirms, retry the file read from 5a.

---

## Step 7: Health check summary

Once all steps are complete, print a summary:

```
## Platform Setup — Health Check

| Component                       | Type              | Status  | Details |
|---------------------------------|-------------------|---------|---------|
| Extension: k8s_dev              | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| Extension: k8s_stag             | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| Extension: k8s_prod             | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| Extension: aws_lfx_dev          | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| Extension: aws_lfx_stag         | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| Extension: aws_lfx_prod         | Desktop Extension | ✅ / ⚠️ | Installed via .mcpb |
| uv / uvx                        | Local tool        | ✅ / ⚠️ | v{version} — required by AWS extensions |
| GitHub CLI (gh)                 | Local tool        | ✅ / ⚠️ | Authenticated as {username}, linuxfoundation SSO: authorized |
| AWS CLI                         | Local tool        | ✅ / ⚠️ | v{version} |
| AWS SSO — lfx-dev               | Local credential  | ✅ / ⚠️ | Account 788942260905 |
| AWS SSO — lfx-stag              | Local credential  | ✅ / ⚠️ | Account 844790888233 |
| AWS SSO — lfx-prod              | Local credential  | ✅ / ⚠️ | Account 372256339901 |
| Kubeconfig — dev                | Local file        | ✅ / ⚠️ | {N} nodes reachable |
| Kubeconfig — staging            | Local file        | ✅ / ⚠️ | {N} nodes reachable |
| Kubeconfig — prod               | Local file        | ✅ / ⚠️ | {N} nodes reachable |
| MCP: k8s dev                    | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: k8s stag                   | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: k8s prod                   | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: AWS lfx dev                | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: AWS lfx stag               | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: AWS lfx prod               | via Extension     | ✅ / ⚠️ | Responding to tool calls |
| MCP: Datadog (cloud connector)  | Cloud connector   | ✅ / ⚠️ | Authorized via Claude settings |
| MCP: GitHub (cloud connector)   | Cloud connector   | ✅ / ⚠️ | Authorized via Claude settings |
```

Use ✅ for each component that passed, ⚠️ for anything that needs attention.
If everything is green, tell the user:

> "You're all set. You can now use `/platform-deploy` to release services and
> the `platform-troubleshoot` skill for incident investigation."

If there are ⚠️ items, summarize what's left and what to do about each one.

---

## Notes on re-running

This command is safe to run at any time:
- It checks before installing — nothing gets reinstalled unnecessarily
- AWS config is appended, not overwritten — existing profiles for other projects
  are preserved
- Kubeconfig files are regenerated only if missing or not connecting
- AWS SSO tokens expire after 12 hours — re-run Step 4d (or just
  `aws sso login --profile lfx-dev`) to refresh
