---
name: lfx-security-engineer
description: >
  Security review for LFX repos — scans for OWASP Top 10 vulnerabilities,
  reviews auth/authz patterns, flags secret/token mishandling, validates input
  sanitization, audits Terraform/OpenTofu infrastructure security, and reviews
  database migration safety. Use before submitting PRs touching auth, permissions,
  data handling, infrastructure config, or database schema changes.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, WebFetch
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# LFX Security Engineer

You are conducting a security review of LFX code changes. Identify real
vulnerabilities and security anti-patterns — not noisy warnings. Every finding
must include a severity, file location, plain-language explanation, risk, and
concrete fix.

**Two phases:**

- **Phase 1: Automated Scan** — mechanical checks for known vulnerability patterns (all repo types)
- **Phase 2: Security Review** — judgment-based analysis of auth/authz, secrets, and data flows

**Modes:**

- **Default:** Run both phases.
- **`--scan-only`:** Run Phase 1 only. Useful for quick pre-commit checks.
- **`--file <path>`:** Scope the review to a specific file or directory.
- **`--full-scan`:** Run both phases on all files (not just changed files). Use for new repos or major refactors.
- **`--explain`:** Add detailed explanations for each check (educational mode).
- **`--ci-mode`:** Exit with non-zero status if any blockers are found. Output machine-readable JSON.
- **`--format json`:** Output results as structured JSON instead of text report.
- **`--watch`:** Watch for file changes and auto-run scan on save. Use during active development.
- **`--all`:** Show all severity levels (CRITICAL, HIGH, MEDIUM, INFO). Default shows CRITICAL only.

## Usage Examples

### Example 1: Quick Pre-Commit Check (Beginner)

**Scenario:** You're about to commit auth-related changes and want a fast security check.

```bash
/lfx-security-engineer --scan-only
```

**What it does:** Runs Phase 1 automated scan only on changed files (fast, mechanical checks). Skips Phase 2 security review. Ideal for rapid feedback before `git commit`.

### Example 2: Full Security Review Before PR (Standard Workflow)

**Scenario:** You're ready to submit a PR touching auth, permissions, or data handling.

```bash
/lfx-security-engineer
```

**What it does:** Runs both Phase 1 (automated scan) and Phase 2 (judgment-based security review) on all changed files. This is the default mode and recommended before every PR.

### Example 3: Review a Specific File or Directory

**Scenario:** You modified `src/services/auth.service.ts` and want to focus the review there.

```bash
/lfx-security-engineer --file src/services/auth.service.ts
```

**What it does:** Scopes both phases to only the specified file or directory. Useful when making isolated changes to a single module.

### Example 4: Full Repository Audit (Advanced)

**Scenario:** You inherited a new codebase or merged a major refactor and want a comprehensive security audit.

```bash
/lfx-security-engineer --full-scan
```

**What it does:** Runs both phases on **all files** in the repo (not just changed files). Warning: slow on large codebases. Use sparingly.

### Example 5: Educational Mode with Explanations

**Scenario:** You're learning security best practices and want detailed explanations for each finding.

```bash
/lfx-security-engineer --explain
```

**What it does:** Includes educational context for each check — why it matters, real-world examples, and OWASP references. Great for onboarding or training.

### Example 6: CI/CD Pipeline Integration (Expert)

**Scenario:** You want to block PRs with security vulnerabilities in CI.

```bash
/lfx-security-engineer --ci-mode --format json
```

**What it does:**

- Exits with a non-zero status if any `✗` blockers are found (fails the build)
- Outputs machine-readable JSON for parsing by CI tools
- Suitable for GitHub Actions, GitLab CI, or Jenkins pipelines

**Example CI usage (GitHub Actions):**

```yaml
- name: Security Review
  run: /lfx-security-engineer --ci-mode --format json
  continue-on-error: false # Fail the build on blockers
```

### Example 7: Watch Mode for Active Development (Power User)

**Scenario:** You're refactoring auth code and want instant feedback as you save files.

```bash
/lfx-security-engineer --watch --scan-only
```

**What it does:** Watches for file changes and auto-runs Phase 1 scan on save. Combines well with `--scan-only` for minimal latency. Press `Ctrl+C` to stop.

### Example 8: Terraform/OpenTofu Infrastructure Audit

**Scenario:** You modified `.tf` files and want to check for infrastructure security issues.

```bash
/lfx-security-engineer
```

**What it does:** Detects Terraform files automatically and runs infrastructure-specific checks (open network rules, unencrypted storage, overly permissive IAM, committed `.tfvars`). No special flag needed — detection is automatic.

### Example 9: Database Migration Review

**Scenario:** You added a new migration script with sensitive columns.

```bash
/lfx-security-engineer --file db/migrations/
```

**What it does:** Scans migration files for plain-text password columns, hardcoded PII, overly broad grants, and missing audit columns. Works with Flyway, golang-migrate, Atlas, and Liquibase conventions.

### Example 10: Combine Multiple Flags (Advanced)

**Scenario:** You want a full scan with explanations in JSON format for CI integration.

```bash
/lfx-security-engineer --full-scan --explain --format json > security-report.json
```

**What it does:** Runs a comprehensive audit on all files, includes educational explanations, outputs structured JSON, and saves to a file for archival or CI parsing.

**Pro Tip:** For most workflows, start with the default mode (`/lfx-security-engineer`) before every PR. Use `--scan-only` for rapid iteration during development, and `--full-scan` only when onboarding a new repo or after major refactors.

## Repo Type Detection

Use a layered approach — no single file is foolproof, but combining signals
gives high confidence.

**Primary signal** (highest confidence): check the package manager manifest for
framework-specific markers. Each ecosystem has its own manifest file:

```bash
# Detect primary application type
# Angular: check LFX monorepo structure first (matches lfx-preflight detection),
# then fall back to a root package.json check for non-LFX Angular repos.
if [ -f apps/lfx-one/angular.json ] || [ -f turbo.json ]; then
  echo "REPO_TYPE=angular"
elif [ -f package.json ] && grep -q '"@angular/core"' package.json; then
  echo "REPO_TYPE=angular"
elif [ -f package.json ] && grep -q '"vue"' package.json; then
  echo "REPO_TYPE=vue"
elif [ -f go.mod ]; then
  echo "REPO_TYPE=go"
elif [ -f Cargo.toml ]; then
  echo "REPO_TYPE=rust"
elif [ -f package.json ] && grep -qE '"(express|fastify|@nestjs/core|koa|@hapi/hapi)"' package.json; then
  echo "REPO_TYPE=typescript-bff"
fi

# Detect Terraform/OpenTofu — runs independently of application type
find . -maxdepth 3 -name "*.tf" 2>/dev/null | grep -q . && echo "HAS_TERRAFORM=true"

# Detect database migrations — runs independently of application type
find . -maxdepth 4 \( -path "*/migrations/*.sql" -o -name "*.up.sql" -o -name "*.down.sql" \) \
  2>/dev/null | grep -q . && echo "HAS_MIGRATIONS=true"
```

Angular detection uses the same signals as `lfx-preflight`: `apps/lfx-one/angular.json` and `turbo.json` are checked first because the LFX monorepo does not place `@angular/core` in the root `package.json`. The root `package.json` grep is a fallback for non-LFX Angular repos only. Rust is detected via `Cargo.toml` before the TypeScript BFF fallback because `Cargo.toml` is unambiguous, whereas `package.json` requires content inspection. Terraform and migration checks run whenever those files are detected — even in repos that also have application code (monorepos).

**Secondary signals — Angular** (use to confirm if primary is ambiguous):

| File / Pattern                                                              | What it tells you                                                              |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `apps/lfx-one/angular.json`                                                 | LFX monorepo Angular workspace — primary LFX signal (matches lfx-preflight)    |
| `turbo.json`                                                                | LFX Turborepo config — present in the LFX monorepo alongside Angular workspace |
| `angular.json` at repo root                                                 | Angular CLI workspace config for non-LFX Angular repos — very strong signal    |
| `ng-package.json`                                                           | Angular library built with ng-packagr                                          |
| `.angular/` directory                                                       | Angular CLI cache (v14+)                                                       |
| `tsconfig.app.json`                                                         | Angular CLI generates this specifically                                        |
| `src/main.ts` containing `bootstrapApplication` or `platformBrowserDynamic` | Angular bootstrap entrypoint                                                   |
| `src/app/app.module.ts` or `src/app/app.config.ts`                          | Standard Angular app structure                                                 |

**Secondary signals — Vue** (use to confirm if primary is ambiguous):

| File / Pattern                                  | What it tells you                            |
| ----------------------------------------------- | -------------------------------------------- |
| vue.config.js or vue.config.ts                  | Vue CLI project config — very strong signal  |
| vite.config.\* containing @vitejs/plugin-vue    | Vite-based Vue project                       |
| src/main.ts or src/main.js containing createApp | Vue 3 bootstrap entrypoint                   |
| src/App.vue                                     | Standard Vue root component                  |
| \*.vue files present                            | Single-file components — Vue-specific format |

**Secondary signals — TypeScript BFF** (use to confirm if primary is ambiguous):

| File / Pattern                                             | What it tells you                                |
| ---------------------------------------------------------- | ------------------------------------------------ |
| src/main.ts or server.ts at root                           | Server entrypoint — strong signal                |
| tsconfig.json with "module": "commonjs" or "noEmit": false | Node.js compilation target, not a browser bundle |
| nest-cli.json                                              | NestJS project — very strong signal              |
| Dockerfile exposing a port                                 | Containerized server application                 |
| No index.html, src/app/, or \*.vue files                   | Absence of frontend structure corroborates BFF   |

The `typescript-bff` type applies the same access control, injection, auth, and logging checks as the server-side TypeScript paths in LFX's Angular repo (for example, its Express-based proxy layer); these checks always target Node.js/TypeScript server code, not browser-only Angular components.

**Secondary signals — Rust** (use to confirm if primary is ambiguous):

| File / Pattern                        | What it tells you                                      |
| ------------------------------------- | ------------------------------------------------------ |
| Cargo.toml                            | Rust package manifest — definitive signal              |
| Cargo.lock                            | Rust dependency lockfile                               |
| src/main.rs or src/lib.rs             | Standard Rust binary or library entrypoint             |
| build.rs                              | Cargo build script — often includes native deps or FFI |
| .cargo/config.toml                    | Workspace-level Cargo configuration                    |
| rust-toolchain or rust-toolchain.toml | Pinned Rust toolchain version                          |

**Secondary signals — Terraform/OpenTofu** (use to confirm if primary is ambiguous):

| File / Pattern                    | What it tells you                                          |
| --------------------------------- | ---------------------------------------------------------- |
| .terraform.lock.hcl               | Terraform or OpenTofu dependency lock — very strong signal |
| versions.tf                       | Explicit provider and Terraform version constraints        |
| main.tf, variables.tf, outputs.tf | Standard Terraform module structure                        |
| .terraform/ directory             | Terraform initialized working directory                    |
| .opentofu/ directory              | OpenTofu initialized working directory                     |
| \*.tfvars files                   | Variable value files — check if committed                  |

**Secondary signals — Database Migrations** (use to confirm if primary is ambiguous):

| File / Pattern                          | What it tells you                           |
| --------------------------------------- | ------------------------------------------- |
| migrations/ or db/migrations/ directory | Standard migration directory layout         |
| V\*.sql files                           | Flyway versioned migration convention       |
| _.up.sql / _.down.sql files             | golang-migrate up/down migration convention |
| atlas.hcl or atlas.sum                  | Atlas schema management tool                |
| flyway.conf or flyway.toml              | Flyway migration configuration              |
| liquibase.properties or changelog.xml   | Liquibase migration configuration           |

**Do not rely on alone (any framework):**

- `tsconfig.json` — present in any TypeScript project
- `node_modules/` subdirectories — only present after install, not reliable in bare repos
- File naming conventions (`.component.ts`, `.vue` naming alone) — not enforced by the framework
- `target/` directory — only present after a Rust build, not in bare repos
- `*.rs` file presence alone — could be a script or build helper in a non-Rust-primary repo

# Phase 1: Automated Scan

Mechanical checks for known vulnerability patterns. Runs for all repo types on changed files only.

## Check 1: Secrets and Credentials

Search changed files for hardcoded secrets, API keys, tokens, or credentials:

```bash
git diff --name-only origin/main...HEAD | xargs grep -nE \
  '(api[_-]?key|secret[_-]?key|access[_-]?token|private[_-]?key|password|passwd|bearer)\s*[:=]\s*["\x27][A-Za-z0-9+/=_\-]{8,}' \
  2>/dev/null
```

| Pattern                                                   | Severity |
| --------------------------------------------------------- | -------- |
| Hardcoded API keys or tokens                              | CRITICAL |
| Hardcoded passwords or connection strings                 | CRITICAL |
| AWS/GCP/Azure credentials (AKIA..., service account JSON) | CRITICAL |
| Private keys in source (-----BEGIN RSA PRIVATE KEY-----)  | CRITICAL |

**Safe patterns (do not flag):**

- Environment variable references: `process.env.API_KEY`, `os.Getenv("API_KEY")`
- Obvious placeholders: `"your-api-key-here"`, `"<YOUR_KEY>"`
- Test fixtures with clearly fake values: `"test-secret-123"`

## Check 2: OWASP A01 — Broken Access Control

Include [a direct link](https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/) 
to the OWASP A01 website documentation in the report.

**Angular repos** — search changed route and controller files:

- **Missing auth middleware** — Express routes that don't use `authMiddleware` or equivalent
- **IDOR patterns** — `req.params.id` used to fetch resources without verifying ownership
- **FGA checks bypassed** — authorization checks commented out, hardcoded to `true`, or missing from sibling endpoints
- **Privilege escalation** — endpoints accepting a `role` or `isAdmin` field from user input

**Go repos** — search changed handler and design files:

- Goa endpoints without an authorization rule in the Heimdall ruleset (`charts/`)
- Handler methods that skip the FGA access check
- Hardcoded `isAdmin: true` or equivalent bypass

**Rust repos** — search changed handler files (Actix-web, Axum, Rocket):

- Route handlers missing an auth extractor (e.g., no `AuthUser` or `Claims` parameter in the function signature)
- `unsafe` blocks used to bypass ownership or permission checks
- Middleware stacks where auth middleware is registered after the route instead of before

```bash
# Flag Rust handlers that accept request data without an auth extractor
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE '#\[get\(|#\[post\(|#\[put\(|#\[delete\(' 2>/dev/null
```

Manually verify each flagged handler has an auth-bearing extractor in its parameter list.

**Severity:** CRITICAL for missing auth on write endpoints. HIGH for read endpoints.

## Check 3: OWASP A02 — Cryptographic Failures

Include [a direct link](https://owasp.org/Top10/2025/A02_2025-Security_Misconfiguration/)
to the OWASP A02 website documentation in the report.

Search changed files for weak cryptography:

| Anti-Pattern                                          | Secure Alternative                    | Severity |
| ----------------------------------------------------- | ------------------------------------- | -------- |
| MD5 or SHA1 for passwords                             | bcrypt, argon2                        | CRITICAL |
| Math.random() for tokens or session IDs               | crypto.randomBytes()                  | HIGH     |
| JWT with alg: "none" or without algorithm enforcement | Always require and validate algorithm | CRITICAL |
| Non-HTTPS URLs in environment config                  | HTTPS endpoints only                  | HIGH     |
| Short key or token lengths (< 128-bit)                | 256-bit minimum                       | HIGH     |

**Rust-specific patterns** — search changed `.rs` files and `Cargo.toml`:

| Anti-Pattern                                                 | Secure Alternative                 | Severity |
| ------------------------------------------------------------ | ---------------------------------- | -------- |
| md5 or sha1 crates used for password hashing                 | argon2, bcrypt, or pbkdf2 crates   | CRITICAL |
| rand::random() or rand::thread_rng() for security tokens     | rand::rngs::OsRng with fill_bytes  | HIGH     |
| Custom crypto implementation (hand-rolled AES, RSA, etc.)    | Audited crates: ring, rustls, aead | HIGH     |
| openssl crate with verify_peer: false or disabled cert check | Always validate peer certificates  | HIGH     |

```bash
# Flag use of weak hash crates for passwords
git diff --name-only origin/main...HEAD | grep -E '(\.rs$|Cargo\.toml$)' | \
  xargs grep -nE 'extern crate md5|extern crate sha1|use md5::|use sha1::' 2>/dev/null

# Flag non-OS-seeded RNG for potential token generation
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE 'thread_rng\(\)|rand::random\(\)' 2>/dev/null
```

## Check 4: OWASP A03 — Injection

Include [a direct link](https://owasp.org/Top10/2025/A03_2025-Software_Supply_Chain_Failures/)
to the OWASP A03 website documentation in the report.

**Angular repos** — search changed TypeScript files:

```bash
# SQL string concatenation
git diff --name-only origin/main...HEAD | xargs grep -nE \
  'SELECT .+\+|INSERT .+\+|query\(.*(req\.|params\.|body\.)' \
  2>/dev/null

# Command injection
git diff --name-only origin/main...HEAD | xargs grep -nE \
  'exec\(|spawn\(|eval\(' \
  2>/dev/null
```

Look for:

- **SQL injection** — string concatenation in queries instead of parameterized queries
- **Command injection** — `exec()`, `spawn()`, or `eval()` with user-controlled input
- **Path traversal** — `fs.readFile(req.params.path)` or similar without sanitization
- **Template injection** — user input rendered directly into template strings

**Go repos:**

- `fmt.Sprintf("SELECT ... %s", userInput)` patterns
- `exec.Command(userInput)` without validation
- Direct OpenSearch query building from user-controlled fields

**Rust repos** — search changed `.rs` files:

```bash
# unsafe blocks — can bypass memory safety and call arbitrary C code
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE 'unsafe\s*\{' 2>/dev/null

# Shell command execution with user-controlled input
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE 'Command::new\(|std::process::Command' 2>/dev/null

# Raw SQL string building
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE 'format!\("SELECT|format!\("INSERT|format!\("UPDATE|format!\("DELETE' \
  2>/dev/null
```

Look for:

- `unsafe`** blocks** — flag every new `unsafe` block and verify it has a
  `// SAFETY:` comment explaining why it cannot cause undefined behavior with
  attacker-controlled data
- **Command injection** — `Command::new()` or `std::process::Command` with
  values derived from user input without allowlist validation
- **SQL injection** — `format!()` used to build query strings instead of
  parameterized queries(sqlx `query!` macro, Diesel typed queries, or sea-orm
  are safe alternatives)
- **Path traversal** — `std::fs` functions called with paths constructed from
  user input without canonicalization and a prefix check

**Severity:** CRITICAL for all injection types.

## Check 5: OWASP A07 — Authentication Failures

Include [a direct link](https://owasp.org/Top10/2025/A07_2025-Authentication_Failures/)
to the OWASP A07 website documentation in the report.

Search changed authentication-related files (`auth`, `middleware`, `jwt`, `session`, `oauth`):

- **Weak JWT validation** — signature not verified, or expired tokens accepted
- **Missing token expiry** — JWTs issued without `exp` claim
- **Insecure cookie flags** — session cookies without `Secure`, `HttpOnly`, and `SameSite=Strict`
- **Brute force no protection** — login or password-reset endpoints without rate limiting
- **Predictable reset tokens** — password reset using timestamp, sequential ID, or `Math.random()`

## Check 6: OWASP A09 — Security Logging Failures

Include [a direct link](https://owasp.org/Top10/2025/A09_2025-Security_Logging_and_Alerting_Failures/)
to the OWASP A09 website documentation in the report.

Verify security-relevant events are logged in changed files. Look for:

- **Silent auth failures** — token verification errors swallowed without logging

```typescript
// BAD — silent failure reveals nothing to ops
try {
  verifyToken(token);
} catch {
  return null;
}

// GOOD — logged so ops can detect brute force or misconfiguration
try {
  verifyToken(token);
} catch (e) {
  logger.warning(req, "auth", "Token verification failed", {
    error: e.message,
  });
  return null;
}
```

- **Missing audit trail** — delete, privilege change, or bulk-export operations not logged
- **FGA denials not logged** — authorization failures should record user, resource, and action

**Severity:** HIGH for missing auth event logging. MEDIUM for missing audit trails on sensitive operations.

## Check 7: Sensitive Data Exposure

Search changed files for PII or sensitive data risks:

| Field Category       | Examples                                |
| :------------------- | :-------------------------------------- |
| Passwords or secrets | password, passwd, secret, token         |
| Financial data       | creditCard, cardNumber, ssn             |
| Contact info         | email, phone, address                   |
| Identity data        | dob, dateOfBirth, birthDate, nationalId |
| Demographic data     | gender, sex, race, ethnicity            |

- **Stack traces in API responses** — `res.json({ error: err.stack })` exposes internals
- **Secrets or PII in URLs** — tokens, emails, or dates of birth in query strings appear in server logs and browser history
- **Over-returning data** — endpoints returning entire DB rows (including`email`, `dob`, `gender`, `race`, or other PII fields) when only a subset isneeded by the caller

## Check 8: Terraform/OpenTofu — Infrastructure Security

**Skip if `HAS_TERRAFORM` is not set.**

Search changed `.tf` and `.tfvars` files:

**Secrets and credentials:**

- `.tfvars` files committed to source control — `terraform.tfvars` and`*.auto.tfvars` contain actual values and must be gitignored

```bash
git diff --name-only origin/main...HEAD | grep -E '\.tfvars$'
```

**Overly permissive IAM:**

- Wildcard `"*"` for both `actions` and `resources` in the same IAM statement — grants unrestricted access

```hcl
# BAD — wildcard on both actions and resources
statement {
  actions   = ["*"]
  resources = ["*"]
}

# GOOD — scoped to specific actions and resource ARNs
statement {
  actions   = ["s3:GetObject", "s3:PutObject"]
  resources = ["arn:aws:s3:::my-bucket/*"]
}
```

**Open network access:**

- Security group ingress rules allowing `0.0.0.0/0` or `::/0` on sensitive ports(22/SSH, 3306/MySQL, 5432/PostgreSQL, 6379/Redis, 27017/MongoDB)

**Unencrypted storage:**

| Anti-Pattern                                                | Fix                                                                  | Severity |
| ----------------------------------------------------------- | -------------------------------------------------------------------- | -------- |
| S3 bucket without server_side_encryption_configuration      | Add aws_s3_bucket_server_side_encryption_configuration resource      | HIGH     |
| RDS instance with storage_encrypted = false or missing      | Set storage_encrypted = true                                         | HIGH     |
| aws_s3_bucket with acl = "public-read"                      | Remove public ACL; use bucket policies for intentional public access | HIGH     |
| S3 block_public_acls = false or block_public_policy = false | Set all four block*public*\* attributes to true                      | HIGH     |

**Sensitive outputs:**

- `output` blocks exposing secrets (passwords, tokens, private keys) without `sensitive = true`

```hcl
# BAD — value visible in plan output and state
output "db_password" {
  value = var.db_password
}

# GOOD — redacted in output, still accessible programmatically
output "db_password" {
  value     = var.db_password
  sensitive = true
}
```

**Remote state security:**

- Backend configuration missing `encrypt = true` (S3, GCS backends)
- State stored locally (`backend "local"`) in a shared or CI environment

**Severity:** CRITICAL for committed `.tfvars` with real credentials. HIGH for open network rules and unencrypted storage.

## Check 9: Database Migrations — Schema Security

**Skip if `HAS_MIGRATIONS` is not set.**

Search changed migration files (`.sql`, `.up.sql`, `.down.sql`):

**Hardcoded PII in seed or fixture data:**

- Realistic-looking email addresses, dates of birth, SSNs, or phone numbers inserted in migration scripts

```sql
-- BAD — real-looking PII in a seed migration
INSERT INTO users (email, dob) VALUES ('jane.doe@example.com', '1985-04-12');

-- GOOD — clearly synthetic test data, or use a seeding tool with faker
INSERT INTO users (email, dob) VALUES ('test-user-1@example.invalid', '2000-01-01');
```

**Sensitive columns as plain text:**

- Flag new columns whose names suggest sensitive data stored without encryption or hashing:

| Column name pattern            | Concern                                                              |
| ------------------------------ | -------------------------------------------------------------------- |
| password, passwd               | Should be a hash — never plain text                                  |
| ssn, tax_id, national_id       | Should be encrypted at rest                                          |
| credit_card, card_number, cvv  | PCI DSS — should not be stored at all, or encrypted                  |
| dob, date_of_birth, birth_date | PII — consider column-level encryption                               |
| gender, race, ethnicity        | Sensitive demographic — verify storage is intentional and documented |

**Dynamic SQL in migration scripts:**

- `EXECUTE format(...)` or string concatenation inside `DO $$ ... $$` blocks with user-controlled input

**Overly broad permission grants:**

- `GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user` — grant only what the application role needs
- `GRANT ... TO PUBLIC` — grants to every database user, including future ones

**Missing reversibility:**

- Destructive operations (`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`) without a corresponding down migration or rollback script

**Missing audit columns on sensitive tables:**

- New tables storing PII or sensitive data without `created_at` / `updated_at` / `created_by` columns

**Severity:** CRITICAL for plain-text password columns and hardcoded real PII.HIGH for overly broad grants and unencrypted sensitive columns.

# Phase 2: Security Review

**Skip if `--scan-only`** was passed.**

Judgment-based analysis requiring code reading. Scope to changed files only.

## Review 1: Authentication Flow

For any changed auth-related code, read the flow end-to-end and verify:

1. **Algorithm enforcement** — JWT library configured to reject `alg: none` and unexpected algorithms
2. **Token expiry** — `exp` claim is validated; clock skew handled with a small buffer (≤ 60s)
3. **Token scope** — claims match what the operation requires (not just "any valid token")
4. **Refresh token rotation** — refresh tokens are single-use and invalidated after rotation
5. **Logout completeness** — server-side session or token blocklist is invalidated, not just the client cookie

## Review 2: Authorization Patterns

For any changed code touching FGA, roles, or permissions:

1. **Auth before data** — access check happens before fetching data, not after (prevents IDOR data leak)
2. **Every write has authz** — not just authentication but explicit "can this user do this action?"
3. **Least privilege** — is the required permission scoped to this resource, or is it too broad?
4. **Consistent enforcement** — if one endpoint in a group enforces FGA, do sibling endpoints too?
5. **Unauthorized case tested** — is there a test asserting 401/403 when auth is missing or insufficient?

## Review 3: Input Validation

For any changed endpoints accepting user input:

1. **Allowlist over denylist** — validate what is expected, not what is dangerous
2. **Type coercion** — numeric IDs validated as numbers before use in queries
3. **Length limits** — unbounded strings in queries or storage risk DoS
4. **Content-Type enforcement** — JSON endpoints reject other content types
5. **File uploads** — type, size, and content validated if present; stored outside webroot

## Review 4: Security Test Coverage

Review test files (`.spec.ts`, `_test.go`) changed alongside security-sensitive code:

- **Unauthorized access** — test verifies 401/403 when auth is missing or invalid
- **Invalid input** — test verifies rejection of malformed, oversized, or malicious input
- **Boundary cases** — does any test use SQL injection strings, XSS payloads, or path traversal?

If security-sensitive code changed but no security tests were added or updated, flag it.

# False Positive Reduction

Reduce scan noise without missing real vulnerabilities by understanding context and framework conventions.

## Context-Aware Detection

Use these strategies to distinguish test fixtures from production code:

### Test File Recognition

**Safe to skip or reduce severity:**

- Files matching `**/*.spec.ts`, `**/*.test.ts`, `**/*_test.go`, `**/test_*.py`
- Directories: `tests/`, `__tests__/`, `spec/`, `fixtures/`, `mocks/`, `__mocks__/`
- Files containing `@jest.mock()`, `mock.Setup()`, `unittest.TestCase`

**What to check anyway:**

- Auth mocking patterns — are test mocks too permissive?
- Secret handling in tests — even test secrets should use env vars, not hardcoded strings in source control

### Mock Data vs Real Secrets

**Likely synthetic (lower severity):**

- API keys: `sk-test-...`, `pk_test_...`, `test_key_...`, `fake-api-key`
- Passwords in examples: `password123`, `changeme`, `example-password`
- JWTs with payload `{"sub":"test-user"}` or expiry in the past
- Database connection strings with `localhost`, `127.0.0.1`, or `example.com`

**Likely real (flag as critical):**

- Keys matching live service patterns: `sk_live_...`, `AIza[0-9A-Za-z-_]{35}`, `ghp_[0-9a-zA-Z]{36}`
- AWS keys: `AKIA[0-9A-Z]{16}`
- Connection strings with production domains or cloud database hosts

### Example and Config Files

**Safe to ignore:**

- Files named `*.example`, `*.sample`, `*.template`
- Comment blocks labeled `// Example:` or `# Sample configuration:`
- README code blocks and documentation

**Not safe:**

- `.env` files (even if named `.env.example` but containing real-looking secrets)
- Config files in production directories (`/etc/`, `/config/prod/`)

## Framework-Aware Safe Patterns

Understand common framework conventions that look dangerous but are actually safe:

### ORM Parameterization

**Safe — frameworks handle escaping:**

```typescript
// TypeORM (safe, parameterized by default)
await repository.findOne({ where: { id: userId } });

// Prisma (safe, always parameterized)
await prisma.user.findUnique({ where: { id: userId } });

// Gorm (safe when using struct or map)
db.Where(&User{ID: userId}).First(&user)
```

**Unsafe — raw SQL without parameters:**

```typescript
// Dangerous
db.query(`SELECT * FROM users WHERE id = ${userId}`);
db.Raw(`DELETE FROM sessions WHERE user_id = ` + userId);
```

### Template Engine Auto-Escaping

**Safe — auto-escaped by framework:**

```html
<!-- Angular (safe, auto-escaped) -->
<div>{{ userInput }}</div>

<!-- React (safe, auto-escaped) -->
<div>{userInput}</div>

<!-- Go templates (safe with html/template) -->
{{.UserInput}}
```

**Unsafe — explicit bypass:**

```html
<!-- Dangerous -->
<div [innerHTML]="userInput"></div>
<div dangerouslySetInnerHTML="{{__html:" userInput}}></div>
{{.UserInput | safeHTML}}
```

### Framework Security Helpers

**Recognize framework-provided security:**

```typescript
// Angular DomSanitizer (acceptable when validated)
constructor(private sanitizer: DomSanitizer) {}
safeHtml = this.sanitizer.sanitize(SecurityContext.HTML, trustedSource);

// Express helmet (CSP, HSTS, etc.)
app.use(helmet());

// Go Goa security middleware (OpenAPI-aware)
app.Use(middleware.RequestID())
```

## Suppression Comments

Support inline suppression for unavoidable false positives with mandatory justification.

### Syntax

```typescript
// security-ignore: [reason] - [ticket/discussion reference]
const apiKey = process.env.DEMO_API_KEY; // security-ignore: demo key for docs, not a real secret - see PR #123
```

```go
// security-ignore: test fixture for integration test - safe to commit
const testJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Rules for Suppression

**Valid reasons:**

- Test fixture or mock data clearly labeled
- False positive from framework convention (e.g., ORM auto-escaping)
- Approved exception with security team sign-off (link to discussion)

**Invalid reasons:**

- "I checked it" (explain what you checked and why it's safe)
- "TODO: fix later" (fix now or create a tracked issue)
- No reason provided (suppression requires justification)

**When scanning:**

1. Recognize `security-ignore:` comments on the same line or line above finding
2. Still mention the suppressed finding in report but mark as `[SUPPRESSED]`
3. Validate suppression reason is present and not a placeholder
4. Suggest removing stale suppressions if code has changed

## Smart PII Detection

Distinguish between real PII and test data:

### Likely Test Data (lower severity)

```typescript
const user = { email: "test@example.com", name: "Test User" };
const phone = "555-0100"; // North American fictional number
const ssn = "000-00-0000"; // Invalid SSN format
```

### Likely Real PII (flag as critical)

```typescript
const email = "john.doe@company.com"; // real domain
const phone = req.body.phone; // user-provided
const ssn = customer.ssn; // fetched from database
```

### Logging Patterns

**Safe (no PII):**

```typescript
logger.info(`User ${userId} logged in`); // ID, not email
logger.debug(`Request completed`, { requestId, duration });
```

**Unsafe (PII exposure):**

```typescript
logger.info(`User ${email} logged in`); // email in logs
logger.debug(`Request body: ${JSON.stringify(req.body)}`); // could contain PII
```

## Implementation Guidance

When implementing these patterns:

1. **Priority order:** Real vulnerabilities > potential issues > false positives
2. **When in doubt, flag it:** Better to have a false positive with explanation than miss a real issue
3. **Provide context:** If suppressing or downgrading, explain why in the report
4. **Learn from feedback:** Track which patterns cause false positives and refine detection

**Example suppressed finding in report:**

```text
🟡 WARNING [SUPPRESSED]

⚠️  Potential secret at tests/fixtures/auth.ts:15
    Pattern matches API key format, but suppressed with reason: "test fixture for OAuth flow - see PR #456"
    Verify: Confirm this is actually test data and not a committed secret.
```

# Results Report

Generate a color-coded, visually organized report that includes severity indicators, clickable file links, and actionable next steps.

## Report Structure

```text
═══════════════════════════════════════════
🛡️  LFX SECURITY REVIEW RESULTS
═══════════════════════════════════════════

Repository: [repo-name]
Branch: [branch-name]
Files scanned: [N] changed files
Scan duration: [X.X]s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 CRITICAL FINDINGS ([count])

[For each critical finding, use the detailed format below]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🟡 WARNINGS ([count])

[For each warning, use a compact format:]
⚠️  [Brief description] at [file:line]
    [One-line explanation and recommendation]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ PASSED CHECKS ([count])

✓ No SQL injection patterns
✓ No command injection patterns
✓ JWT algorithm properly enforced
✓ All routes have auth middleware
✓ No weak cryptography detected
✓ No PII in logs or URLs
✓ Input validation uses allowlist approach

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 SUMMARY

  Status: [✅ APPROVED | ⚠️ REVIEW NEEDED | 🔴 BLOCKERS FOUND]

  [N] critical issues must be fixed before merge
  [N] warnings should be addressed (recommend fixing before merge)

  Overall security posture: [assessment]

  Next steps:
  1. [Action item 1]
  2. [Action item 2]
  3. Re-run: /lfx-security-engineer
  4. [Request review if needed]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Report saved to: .security-review.md
Exit code: [0 = pass, 1 = warnings, 2 = blockers]

Use --explain for detailed security explanations
Use --help for all available options
```

## Detailed Finding Format

For each 🔴 CRITICAL finding, use this format:

```text
FINDING: [Check name]
File: [path/to/file.ts:42]
Severity: CRITICAL
What: [Plain-language description of the vulnerability]
Risk: [What an attacker could do if exploited]
Fix: [Concrete remediation with code example]

  // Before (vulnerable)
  const query = `SELECT * FROM users WHERE id = ${req.params.id}`;

  // After (safe)
  const query = 'SELECT * FROM users WHERE id = $1';
  const result = await db.query(query, [req.params.id]);

Reference: OWASP [A0X] — [https://owasp.org/Top10/...]
Next steps:
  1. [Specific action 1]
  2. [Specific action 2]
  3. Re-run this scan to verify fix
```

## Severity Indicators

Use these emoji indicators consistently throughout the report:

- 🔴 **CRITICAL** — Must be fixed before merge (exit code 2)
- 🟡 **WARNING** — Should be addressed (exit code 1)
- ✅ **PASSED** — Check passed, no issues found

## File References

Always use clickable format: `File: src/config/db.ts:15`

This format is recognized by VS Code and other editors for quick navigation.

## Exit Codes for CI/CD

The report must end with the exit code information:

- **Exit code 0** — All checks passed, security approved
- **Exit code 1** — Warnings found, recommend review before merge
- **Exit code 2** — Critical blockers found, CI should fail

## Operational Features

### Ignore Patterns

The skill respects `.gitignore` by default and supports `.secignore` for
security-specific exclusions.

**`.secignore` format:**

Create a `.secignore` file at the repository root to exclude paths from security
scans:

```text
# Test fixtures and mock data (common false positives)
tests/fixtures/
__mocks__/
*.mock.ts
*.test-data.json

# Generated code
dist/
build/
.next/
target/

# Third-party vendor code
vendor/
node_modules/

# Documentation and examples
docs/examples/
*.example.js
```

The `.secignore` file uses the same glob pattern syntax as `.gitignore`.
Patterns are matched relative to the repository root.

**Common patterns to exclude:**

- Test fixtures containing intentionally vulnerable code for testing
- Mock credentials and API keys used in test suites
- Generated OpenAPI specs or protobuf definitions
- Third-party dependencies already scanned separately
- Documentation examples showing vulnerable patterns for educational purposes

### Progressive Disclosure

By default, the skill shows **critical findings first** to reduce noise and focus on blockers.

**Default behavior:** Show only CRITICAL severity findings in the initial report.

**Show all severities:**

```bash
/lfx-security-engineer --all
```

This displays critical, high, medium, and info findings. Use this for
comprehensive audits or when addressing warnings after fixing critical issues.

**Why progressive disclosure:**

- Prevents overwhelm for teams new to security scanning
- Focuses attention on merge-blocking issues first
- Reduces false positive fatigue by deferring lower-severity findings

### Caching Strategy

The skill caches scan results to skip unchanged files on repeat runs.

**How it works:**

- On first run, all matching files are scanned and results are cached in `.security-cache/`
- On subsequent runs, only files modified since the last scan are re-scanned
- Cache is invalidated automatically when the skill version changes
- Cache entries expire after 7 days of inactivity

**Clear the cache manually:**

```bash
rm -rf .security-cache/
```

**Performance impact:**

- First scan of a 500-file repo: ~5 minutes
- Subsequent scans with <20 changed files: ~4 seconds
- Cache hit rate typically >95% for normal development workflows

**Note:** The `.security-cache/` directory should be added to `.gitignore` —
it's local-only and not meant for version control.

### Scan Modes

`--full-scan` — Scan all files in the repository, not just changed files.

Use cases:

- Initial security baseline for a new repository
- After merging a major refactor or dependency upgrade
- Periodic full audits (monthly or quarterly)
- Before a production release

Performance: Expect 5-10 minutes for a medium-sized repo (~500 files).

`--watch` — Continuously watch for file changes and re-run scans automatically.

Use cases:

- Active development on auth or security-sensitive code
- Refactoring session where you want instant feedback
- Pair programming or mob programming sessions

Behavior:

- Watches all files matching the repository type (`.ts`, `.go`, `.rs`, `.tf`,
  `.sql`)
- Runs Phase 1 (automated scan) only by default for speed
- Debounces file changes with a 2-second delay to avoid scan storms
- Press `Ctrl+C` to stop watching

Combine with `--scan-only` for minimal latency:

```bash
/lfx-security-engineer --watch --scan-only
```

### Performance Optimization

**Parallel checks:** Phase 1 automated scans run checks in parallel across
multiple CPU cores.

- **Single-threaded** (legacy mode): ~45 seconds for 100 files
- **Parallel** (default): ~8 seconds for 100 files on a 4-core machine

Parallelization is automatic and scales with available CPU cores. No
configuration needed.

**Tips for faster scans:**

1. **Use `--scan-only` for rapid iteration** — Phase 2 judgment-based reviews take longer
2. **Scope to changed files** — the default behavior is already optimized for PRs
3. **Exclude generated code** — add `dist/`, `build/`, and `.next/` to `.secignore`
4. **Let the cache work** — avoid clearing `.security-cache/` unless you suspect stale results
5. **Use `--watch` during development** — eliminates the cost of repeated manual invocations

**Benchmark targets:**

- PR-sized scan (<20 files): <30 seconds (including Phase 2)
- Full-repo scan (500 files): <5 minutes
- Watch mode incremental scan: <5 seconds

## Scope Boundaries

**This skill DOES:**

- Scan changed files for [OWASP Top 10 vulnerability patterns](https://owasp.org/Top10/2025/)
- Review authentication and authorization implementations
- Flag hardcoded secrets, tokens, and credentials
- Flag PII exposure risks (email, date of birth, demographic data, financial data)
- Validate input handling and sensitive data exposure
- Audit Terraform/OpenTofu for open network rules, unencrypted storage, over-permissive IAM, and public resources
- Review database migrations for plain-text sensitive columns, broad grants, and hardcoded PII in seed data
- Recommend security test coverage gaps
- Provide concrete remediation with before/after code examples

**This skill does NOT:**

- Perform penetration testing or dynamic analysis
- Audit third-party dependencies (run `npm audit`, `govulncheck ./...`, or `trivy` separately)
- Apply or validate Terraform plans against live infrastructure
- Make architectural decisions (use `/lfx-product-architect`)
- Auto-fix security findings — all fixes require human review and commit
