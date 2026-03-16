---
name: lfx-preflight
description: >
  Pre-PR validation for any LFX repo — license headers, format, lint, build,
  and protected file check. Adapts to repo type (Angular or Go). Use before
  submitting any PR.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Pre-Submission Preflight Check

You are running a comprehensive validation before the contributor submits a pull request. Adapt checks based on the repo type.

**Mode:** By default, auto-fix issues where possible (formatting, license headers). If the user says "report only" or "dry run", just report without fixing.

## Repo Type Detection

```bash
if [ -f apps/lfx-one/angular.json ] || [ -f turbo.json ]; then
  echo "REPO_TYPE=angular"
elif [ -f go.mod ]; then
  echo "REPO_TYPE=go"
fi
```

## Check 0: Working Tree Status

```bash
git status
git diff --stat origin/main...HEAD
git log --format="%h %s%n%b" origin/main...HEAD
```

**Evaluate:**

- **Uncommitted changes?** — Ask the contributor: commit now or stash?
- **No commits ahead of main?** — The branch has nothing to validate.
- **Commit messages missing JIRA ticket?** — Flag commits without `LFXV2-` references.
- **Commits missing `--signoff`?** — Flag any commits without `Signed-off-by:` lines.

## Check 1: License Headers

**Angular repos:**
```bash
./check-headers.sh
```

Every source file (`.ts`, `.html`, `.scss`) must have the license header.

**If missing headers are found (auto-fix mode):**
- For `.ts` files, prepend: `// Copyright The Linux Foundation and each contributor to LFX.\n// SPDX-License-Identifier: MIT\n\n`
- For `.html` files, prepend: `<!-- Copyright The Linux Foundation and each contributor to LFX. -->\n<!-- SPDX-License-Identifier: MIT -->\n\n`
- For `.scss` files, prepend: `// Copyright The Linux Foundation and each contributor to LFX.\n// SPDX-License-Identifier: MIT\n\n`

**Go repos:**
Check for license headers in `.go` files. The standard Go license header format varies by repo — check existing files for the pattern.

## Check 2: Formatting

**Angular repos:**
```bash
yarn format
```

This auto-fixes formatting. If files changed, report which ones were formatted.

**Go repos:**
```bash
gofmt -l .
# If files need formatting (auto-fix mode):
gofmt -w .
```

## Check 3: Linting

**Angular repos:**
```bash
yarn lint
```

**Go repos:**
```bash
go vet ./...
# If golangci-lint is available:
golangci-lint run ./...
```

**If lint errors are found (auto-fix mode):**
1. Read the error output carefully
2. For auto-fixable issues (import order, unused imports), fix them directly
3. For non-auto-fixable issues (logic errors, type mismatches), report them and ask the contributor

### Re-validation

If fixes were applied in Checks 1-3, re-run lint to confirm:

**Angular:** `yarn lint`
**Go:** `go vet ./...`

## Check 4: Build Verification

**Angular repos:**
```bash
yarn build
```

**Go repos:**
```bash
go build ./...
# If Goa design was modified:
make apigen
go build ./...
```

**If build fails:**
1. Read the error output
2. Identify the file and line
3. If it's a simple fix (missing import, typo), fix it in auto-fix mode
4. If it's a structural issue, report it with context

## Check 5: Tests (if available)

**Angular repos:**
```bash
# Check if tests exist for modified files
git diff --name-only origin/main...HEAD | grep '\.spec\.ts$'
# If test files exist:
# yarn test --watch=false (only if the user confirms — tests can be slow)
```

**Go repos:**
```bash
# Run tests for packages with changes
go test ./...
```

Report test results but don't block on test failures unless the user asks.

## Check 6: Protected Files Check

```bash
git diff --name-only origin/main...HEAD
```

**Angular repos — flag changes to:**

- `apps/lfx-one/src/server/server.ts`
- `apps/lfx-one/src/server/server-logger.ts`
- `apps/lfx-one/src/server/middleware/*`
- `apps/lfx-one/src/server/services/logger.service.ts`
- `apps/lfx-one/src/server/services/microservice-proxy.service.ts`
- `apps/lfx-one/src/server/services/nats.service.ts`
- `apps/lfx-one/src/server/services/snowflake.service.ts`
- `apps/lfx-one/src/server/services/supabase.service.ts`
- `apps/lfx-one/src/server/services/ai.service.ts`
- `apps/lfx-one/src/server/services/project.service.ts`
- `apps/lfx-one/src/server/services/etag.service.ts`
- `apps/lfx-one/src/server/helpers/error-serializer.ts`
- `apps/lfx-one/src/app/app.routes.ts`
- `.husky/*`
- `eslint.config.*`
- `.prettierrc*`
- `turbo.json`
- `apps/lfx-one/angular.json`
- `CLAUDE.md`
- `check-headers.sh`
- `package.json` / `*/package.json`
- `yarn.lock`

**Go repos — flag changes to:**

- `gen/` (should only change via `make apigen`)
- `charts/` (deployment config — review carefully)
- `go.mod` / `go.sum` (dependency changes need review)
- `Makefile` (build system changes)

## Check 7: Commit Verification

```bash
git status
git log --format="%h %s%n%b" origin/main...HEAD
```

- **All changes committed?** — If auto-fixes created uncommitted changes, prompt to commit them
- **Commit messages follow conventions?** — `type(scope): description` format
- **`--signoff` on all commits?**
- **JIRA ticket referenced?**

## Check 8: Change Summary

```bash
git diff --stat origin/main...HEAD
```

List:

1. **New files created** — with their purpose
2. **Modified files** — with what changed
3. **Shared package changes** (Angular) or **Domain model changes** (Go)
4. **Backend changes** — controllers/services/routes (Angular) or Goa design/service (Go)
5. **Frontend changes** (Angular only)
6. **Helm chart changes** (Go repos with `charts/`)

## Results Report

**Start with a one-line plain-language verdict** before any details:

```text
═══════════════════════════════════════════
PREFLIGHT RESULTS
═══════════════════════════════════════════

YOUR CHANGES LOOK GOOD AND ARE READY FOR REVIEW!
(or: FOUND 2 ISSUES THAT NEED ATTENTION — see below)

─────────────────────────────────────────
Detailed checks:
✓ Working tree        — Clean, N commits ahead of main
✓ License headers     — All files have headers (2 auto-fixed)
✓ Formatting          — Applied (3 files reformatted)
✓ Linting             — No errors
✓ Build               — Succeeded
✓ Tests               — N/A (no test files for changed code)
✓ Protected files     — None modified
✓ Commits             — Conventions followed, signed off
═══════════════════════════════════════════

Changes summary:
  - 2 files modified in packages/shared/
  - 3 files modified in apps/lfx-one/src/app/modules/committees/
  - 0 protected files touched

Auto-fixes applied:
  - Added license header to member-form.component.ts
  - Added license header to member-form.component.html
  - Reformatted 3 files with prettier

READY FOR PR ✓
═══════════════════════════════════════════
```

### If Fixes Created Uncommitted Changes

After auto-fixing, check for uncommitted changes:

```bash
git status --porcelain
```

If there are uncommitted changes from auto-fixes, ask:
> "Preflight auto-fixed some issues (formatting, license headers). Would you like me to commit these fixes?"

### If All Checks Pass

> "Your changes look good and are ready for review! Would you like me to create the pull request?"

### If Checks Fail

Report failures in plain language, explaining what each means:
> "Found 2 issues that need attention:
> 1. **Build error**: [plain explanation of what went wrong and whether it can be auto-fixed]
> 2. **Missing signoff**: [plain explanation and what the user needs to do]
>
> Want me to fix what I can automatically?"

## Scope Boundaries

**This skill DOES:**
- Run format, lint, build checks
- Auto-fix formatting and license headers
- Report protected file changes
- Verify commit conventions
- Offer to create PR after passing

**This skill does NOT:**
- Generate new code (use `/lfx-backend-builder` or `/lfx-ui-builder`)
- Make architectural decisions (use `/lfx-product-architect`)
- Research upstream APIs (use `/lfx-research`)
