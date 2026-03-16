---
name: lfx-setup
description: >
  Environment setup for any LFX repo — prerequisites, clone, install, env vars,
  and dev server. Adapts to repo type (Angular or Go). Use for getting started,
  first-time setup, broken environments, or install failures.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# LFX Environment Setup Guide

You are helping a contributor set up an LFX development environment from scratch. Walk through each step interactively, verifying success before moving on.

**Key principle:** Verify each step before proceeding to the next.

## What You'll Need (before we start)

Before diving into the technical steps, here's what you should have ready:

- **Access to the LFX GitHub organization** — you need to be able to clone LFX repositories. If you can visit `github.com/linuxfoundation` and see private repos, you're good.
- **Access to the team 1Password vault** — some configuration values (API keys, secrets) are stored in 1Password under the "LFX One Dev Environment" vault. Ask your team lead if you don't have access.
- **About 15 minutes** — first-time setup takes a bit for downloads and installs. Subsequent setups are faster.
- **A terminal app** — Terminal.app (macOS), iTerm2, or any terminal emulator.

Don't worry if you're not sure about any of these — I'll check each one as we go and help you get access if needed. Don't assume success — check.

## Repo Type Detection

```bash
if [ -f apps/lfx-one/angular.json ] || [ -f turbo.json ]; then
  echo "REPO_TYPE=angular"      # lfx-v2-ui
elif [ -f go.mod ]; then
  echo "REPO_TYPE=go"           # Go microservice
fi
```

---

## Angular Repo Setup (lfx-v2-ui)

### Step 1: Prerequisites

Check that the following are installed and verify versions:

```bash
echo "=== Prerequisites Check ==="
echo -n "Node.js: " && node --version 2>/dev/null || echo "NOT INSTALLED"
echo -n "Yarn: " && yarn --version 2>/dev/null || echo "NOT INSTALLED"
echo -n "Git: " && git --version 2>/dev/null || echo "NOT INSTALLED"
```

**Required versions:**
1. **Node.js v22+** — If wrong version: recommend `nvm install 22 && nvm use 22`
2. **Yarn v4.9.2+** — If missing: `corepack enable && corepack prepare yarn@4.9.2 --activate`
3. **Git** — Any recent version

> **Docker is NOT required** for local development. All services point to the shared dev environment.

**macOS-specific notes:**
- If `corepack enable` fails with permission errors: `sudo corepack enable`
- If using Homebrew Node: Homebrew doesn't always include corepack — `npm install -g corepack` first
- Xcode Command Line Tools must be installed: `xcode-select --install`

### Step 2: Clone the Repository

If not already cloned:

```bash
git clone <repository-url>
cd lfx-v2-ui
```

### Step 3: Environment Variables

1. **Copy the env template:**
   ```bash
   cp apps/lfx-one/.env.example apps/lfx-one/.env
   ```

2. **Get credentials from 1Password:**
   - Access the **LFX One Dev Environment** vault
   - Copy all required values into `apps/lfx-one/.env`

3. **Validate critical env vars:**
   ```bash
   echo "=== Env Var Check ==="
   missing=()
   for key in PCC_AUTH0_CLIENT_ID PCC_AUTH0_CLIENT_SECRET PCC_AUTH0_ISSUER_BASE_URL PCC_AUTH0_AUDIENCE PCC_AUTH0_SECRET PCC_BASE_URL LFX_V2_SERVICE; do
     if grep -qE "^${key}=.+" apps/lfx-one/.env 2>/dev/null; then
       echo "✓ $key"
     else
       echo "✗ $key — MISSING"
       missing+=("$key")
     fi
   done
   if [ ${#missing[@]} -gt 0 ]; then
     echo -e "\nMissing vars: ${missing[*]}"
     echo "Get these from 1Password → LFX One Dev Environment vault"
   else
     echo -e "\nAll critical env vars are populated ✓"
   fi
   ```

### Step 4: Install Dependencies

```bash
yarn install
```

**If `yarn install` fails:**
- `EACCES` errors → Don't use `sudo`. Check Node is installed via nvm, not system package
- Corepack errors → `corepack enable && corepack prepare yarn@4.9.2 --activate`
- Network errors → Check VPN/proxy settings, try `yarn config set httpProxy ...`
- `node-gyp` errors → Ensure Xcode Command Line Tools are installed: `xcode-select --install`

**Verify install succeeded:**
```bash
[ -d node_modules ] && echo "✓ node_modules exists" || echo "✗ node_modules missing"
[ -f yarn.lock ] && echo "✓ yarn.lock exists" || echo "✗ yarn.lock missing"
```

### Step 5: Start Development Server

```bash
yarn start
```

The app should be available at `http://localhost:4200`.

### Step 6: Verify

```bash
# Wait a few seconds for the server to start, then check
curl -s -o /dev/null -w "%{http_code}" http://localhost:4200
```

Expected: HTTP 200 or 302 (redirect to login).

**If the server fails to start:**
- Port 4200 in use → `lsof -i :4200` to find the process, kill it or use a different port
- Auth errors → Verify `.env` values match 1Password
- Build errors → Run `yarn build` separately to see detailed errors
- SSR errors → Check Node version is 22+

---

## Go Microservice Setup

### Step 1: Prerequisites

```bash
echo "=== Prerequisites Check ==="
echo -n "Go: " && go version 2>/dev/null || echo "NOT INSTALLED"
echo -n "Git: " && git --version 2>/dev/null || echo "NOT INSTALLED"
echo -n "Make: " && make --version 2>/dev/null | head -1 || echo "NOT INSTALLED"
```

**Required:**
1. **Go 1.22+** — `go version`
2. **Git** — `git --version`
3. **Make** — `make --version`
4. **Goa v3** — installed via Makefile (`make apigen` handles this)

Optional for full local stack:
- **Helm** — `helm version`
- **OrbStack or Docker** — for running the platform locally

### Step 2: Clone the Repository

```bash
git clone <repository-url>
cd lfx-v2-<service>-service
```

### Step 3: Environment Variables

Standard environment variables for running against the local stack:

```bash
export NATS_URL=nats://localhost:4222
export OPENSEARCH_URL=http://localhost:9200
export JWKS_URL=http://localhost:4457/.well-known/jwks
export LFX_ENVIRONMENT=lfx.
export PORT=8080
```

For running against the shared dev environment, get values from 1Password.

### Step 4: Build

```bash
go mod download
go build ./...
```

**If build fails:**
- Missing dependencies → `go mod tidy && go mod download`
- Wrong Go version → Check `go.mod` for required version
- CGO errors on macOS → `export CGO_ENABLED=0` if the service doesn't need CGO

**Verify:**
```bash
echo $? # Should be 0
```

### Step 5: Generate API Code (if applicable)

```bash
make apigen
```

**If apigen fails:**
- Goa not installed → The Makefile should auto-install it. If not: `go install goa.design/goa/v3/cmd/goa@v3.22.6`
- Design errors → Check `cmd/*/design/*.go` for syntax issues

### Step 6: Run

```bash
go run cmd/*-api/main.go
```

**Verify:**
```bash
curl -s http://localhost:8080/livez
# Expected: 200 OK
```

### Step 7: Local Platform Stack (Optional)

To run the full platform locally with all services:

```bash
# Clone the helm repo
git clone https://github.com/linuxfoundation/lfx-v2-helm
cd lfx-v2-helm

# Pull chart dependencies
helm dependency update charts/lfx-platform

# Create local values
cp charts/lfx-platform/values.local.example.yaml charts/lfx-platform/values.local.yaml
# Edit values.local.yaml — secrets are in 1Password

# Install
helm install -n lfx lfx-platform ./charts/lfx-platform \
  --values charts/lfx-platform/values.local.yaml
```

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `corepack enable` permission error | System Node | `sudo corepack enable` or use nvm |
| `yarn install` EACCES | Root-owned files | Don't use `sudo`. Reinstall Node via nvm |
| Port 4200 in use | Zombie process | `lsof -i :4200` then `kill <PID>` |
| Auth redirect loop | Wrong `.env` values | Re-copy from 1Password |
| `ERR_MODULE_NOT_FOUND` | Missing deps | `rm -rf node_modules && yarn install` |
| NATS connection refused | Local stack not running | Start the Helm platform stack |
| `make apigen` fails | Missing Goa | `go install goa.design/goa/v3/cmd/goa@v3.22.6` |
| Go build fails after Goa changes | Stale generated code | `make apigen && go build ./...` |

## Done

Once the app/service runs successfully:

```
═══════════════════════════════════════════
SETUP COMPLETE ✓
═══════════════════════════════════════════
Repo: [repo name]
Type: [Angular / Go microservice]
Running at: [URL]
═══════════════════════════════════════════
```

Suggest next steps:
- Explore the codebase: use `/lfx-product-architect` to understand how things work
- Build or modify a feature: use `/lfx-coordinator`
- Start focused code generation: use `/lfx-backend-builder` or `/lfx-ui-builder`
