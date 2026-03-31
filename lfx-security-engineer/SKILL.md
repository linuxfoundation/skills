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
# LFX Security Engineer

You are conducting a security review of LFX code changes. Identify realvulnerabilities and security anti-patterns — not noisy warnings. Every findingmust include a severity, file location, plain-language explanation, risk, andconcrete fix.

**Two phases:**

- **Phase 1: Automated Scan** — mechanical checks for known vulnerability patterns (all repo types)
- **Phase 2: Security Review** — judgment-based analysis of auth/authz, secrets, and data flows

**Modes:**

- **Default:** Run both phases.
- `--scan-only`**:** Run Phase 1 only. Useful for quick pre-commit checks.
- `--file <path>`**:** Scope the review to a specific file or directory.

## Repo Type Detection

Use a layered approach — no single file is foolproof, but combining signalsgives high confidence.

**Primary signal** (highest confidence): check the package manager manifest forframework-specific markers. Each ecosystem has its own manifest file:

```bash
# Detect primary application type
if [ -f package.json ] && grep -q '"@angular/core"' package.json; then
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

Rust is detected via `Cargo.toml` before the TypeScript BFF fallback — a`Cargo.toml` is unambiguous, whereas `package.json` requires content inspection.Terraform and migration checks run whenever those files are detected — even inrepos that also have application code (monorepos).

**Secondary signals — Angular** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| angular.json | Angular CLI workspace config — very strong signal |
| ng-package.json | Angular library built with ng-packagr |
| .angular/ directory | Angular CLI cache (v14+) |
| tsconfig.app.json | Angular CLI generates this specifically |
| src/main.ts containing bootstrapApplication or platformBrowserDynamic | Angular bootstrap entrypoint |
| src/app/app.module.ts or src/app/app.config.ts | Standard Angular app structure |

**Secondary signals — Vue** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| vue.config.js or vue.config.ts | Vue CLI project config — very strong signal |
| vite.config.* containing @vitejs/plugin-vue | Vite-based Vue project |
| src/main.ts or src/main.js containing createApp | Vue 3 bootstrap entrypoint |
| src/App.vue | Standard Vue root component |
| *.vue files present | Single-file components — Vue-specific format |

**Secondary signals — TypeScript BFF** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| src/main.ts or server.ts at root | Server entrypoint — strong signal |
| tsconfig.json with "module": "commonjs" or "noEmit": false | Node.js compilation target, not a browser bundle |
| nest-cli.json | NestJS project — very strong signal |
| Dockerfile exposing a port | Containerized server application |
| No index.html, src/app/, or *.vue files | Absence of frontend structure corroborates BFF |

The `typescript-bff` type applies the same access control, injection, auth, andlogging checks as `angular` — both are Node.js/TypeScript server environments.

**Secondary signals — Rust** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| Cargo.toml | Rust package manifest — definitive signal |
| Cargo.lock | Rust dependency lockfile |
| src/main.rs or src/lib.rs | Standard Rust binary or library entrypoint |
| build.rs | Cargo build script — often includes native deps or FFI |
| .cargo/config.toml | Workspace-level Cargo configuration |
| rust-toolchain or rust-toolchain.toml | Pinned Rust toolchain version |

**Secondary signals — Terraform/OpenTofu** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| .terraform.lock.hcl | Terraform or OpenTofu dependency lock — very strong signal |
| versions.tf | Explicit provider and Terraform version constraints |
| main.tf, variables.tf, outputs.tf | Standard Terraform module structure |
| .terraform/ directory | Terraform initialized working directory |
| .opentofu/ directory | OpenTofu initialized working directory |
| *.tfvars files | Variable value files — check if committed |

**Secondary signals — Database Migrations** (use to confirm if primary is ambiguous):

| File / Pattern | What it tells you |
| --- | --- |
| migrations/ or db/migrations/ directory | Standard migration directory layout |
| V*.sql files | Flyway versioned migration convention |
| *.up.sql / *.down.sql files | golang-migrate up/down migration convention |
| atlas.hcl or atlas.sum | Atlas schema management tool |
| flyway.conf or flyway.toml | Flyway migration configuration |
| liquibase.properties or changelog.xml | Liquibase migration configuration |

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

| Pattern | Severity |
| --- | --- |
| Hardcoded API keys or tokens | CRITICAL |
| Hardcoded passwords or connection strings | CRITICAL |
| AWS/GCP/Azure credentials (AKIA..., service account JSON) | CRITICAL |
| Private keys in source (-----BEGIN RSA PRIVATE KEY-----) | CRITICAL |

**Safe patterns (do not flag):**

- Environment variable references: `process.env.API_KEY`, `os.Getenv("API_KEY")`
- Obvious placeholders: `"your-api-key-here"`, `"<YOUR_KEY>"`
- Test fixtures with clearly fake values: `"test-secret-123"`

## Check 2: OWASP A01 — Broken Access Control

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

Search changed files for weak cryptography:

| Anti-Pattern | Secure Alternative | Severity |
| --- | --- | --- |
| MD5 or SHA1 for passwords | bcrypt, argon2 | CRITICAL |
| Math.random() for tokens or session IDs | crypto.randomBytes() | HIGH |
| JWT with alg: "none" or without algorithm enforcement | Always require and validate algorithm | CRITICAL |
| Non-HTTPS URLs in environment config | HTTPS endpoints only | HIGH |
| Short key or token lengths (< 128-bit) | 256-bit minimum | HIGH |

**Rust-specific patterns** — search changed `.rs` files and `Cargo.toml`:

| Anti-Pattern | Secure Alternative | Severity |
| --- | --- | --- |
| md5 or sha1 crates used for password hashing | argon2, bcrypt, or pbkdf2 crates | CRITICAL |
| rand::random() or rand::thread_rng() for security tokens | rand::rngs::OsRng with fill_bytes | HIGH |
| Custom crypto implementation (hand-rolled AES, RSA, etc.) | Audited crates: ring, rustls, aead | HIGH |
| openssl crate with verify_peer: false or disabled cert check | Always validate peer certificates | HIGH |

```bash
# Flag use of weak hash crates for passwords
git diff --name-only origin/main...HEAD | grep -E '(\.rs$|Cargo\.toml$)' | \
  xargs grep -nE 'extern crate md5|extern crate sha1|use md5::|use sha1::' 2>/dev/null

# Flag non-OS-seeded RNG for potential token generation
git diff --name-only origin/main...HEAD | grep -E '\.rs$' | \
  xargs grep -nE 'thread_rng\(\)|rand::random\(\)' 2>/dev/null
```

## Check 4: OWASP A03 — Injection

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

- `unsafe`** blocks** — flag every new `unsafe` block and verify it has a `// SAFETY:` commentexplaining why it cannot cause undefined behavior with attacker-controlled data
- **Command injection** — `Command::new()` or `std::process::Command` with values derivedfrom user input without allowlist validation
- **SQL injection** — `format!()` used to build query strings instead of parameterized queries(sqlx `query!` macro, Diesel typed queries, or sea-orm are safe alternatives)
- **Path traversal** — `std::fs` functions called with paths constructed from user input withoutcanonicalization and a prefix check

**Severity:** CRITICAL for all injection types.

## Check 5: OWASP A07 — Authentication Failures

Search changed authentication-related files (`auth`, `middleware`, `jwt`, `session`, `oauth`):

- **Weak JWT validation** — signature not verified, or expired tokens accepted
- **Missing token expiry** — JWTs issued without `exp` claim
- **Insecure cookie flags** — session cookies without `Secure`, `HttpOnly`, and `SameSite=Strict`
- **Brute force no protection** — login or password-reset endpoints without rate limiting
- **Predictable reset tokens** — password reset using timestamp, sequential ID, or `Math.random()`

## Check 6: OWASP A09 — Security Logging Failures

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

- FieldExamplesPasswords or secretspassword, passwd, secret, tokenFinancial datacreditCard, cardNumber, ssnContact infoemail, phone, addressIdentity datadob, dateOfBirth, birthDate, nationalIdDemographic datagender, sex, race, ethnicity
- **Stack traces in API responses** — `res.json({ error: err.stack })` exposes internals
- **Secrets or PII in URLs** — tokens, emails, or dates of birth in query strings appear in server logs and browser history
- **Over-returning data** — endpoints returning entire DB rows (including`email`, `dob`, `gender`, `race`, or other PII fields) when only a subset isneeded by the caller

## Check 8: Terraform/OpenTofu — Infrastructure Security

**Skip if **`HAS_TERRAFORM`** is not set.**

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

| Anti-Pattern | Fix | Severity |
| --- | --- | --- |
| S3 bucket without server_side_encryption_configuration | Add aws_s3_bucket_server_side_encryption_configuration resource | HIGH |
| RDS instance with storage_encrypted = false or missing | Set storage_encrypted = true | HIGH |
| aws_s3_bucket with acl = "public-read" | Remove public ACL; use bucket policies for intentional public access | HIGH |
| S3 block_public_acls = false or block_public_policy = false | Set all four block_public_* attributes to true | HIGH |

**Sensitive outputs:**

- `output` blocks exposing secrets (passwords, tokens, private keys) without `sensitive = true`

```hcl
# BAD — value visible in plan output and state
output "db_password" {
  value = aws_db_instance.main.password
}

# GOOD — redacted in output, still accessible programmatically
output "db_password" {
  value     = aws_db_instance.main.password
  sensitive = true
}
```

**Remote state security:**

- Backend configuration missing `encrypt = true` (S3, GCS backends)
- State stored locally (`backend "local"`) in a shared or CI environment

**Severity:** CRITICAL for committed `.tfvars` with real credentials. HIGH for open network rules and unencrypted storage.

## Check 9: Database Migrations — Schema Security

**Skip if **`HAS_MIGRATIONS`** is not set.**

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

| Column name pattern | Concern |
| --- | --- |
| password, passwd | Should be a hash — never plain text |
| ssn, tax_id, national_id | Should be encrypted at rest |
| credit_card, card_number, cvv | PCI DSS — should not be stored at all, or encrypted |
| dob, date_of_birth, birth_date | PII — consider column-level encryption |
| gender, race, ethnicity | Sensitive demographic — verify storage is intentional and documented |

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

**Skip if **`--scan-only`** was passed.**

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

# Results Report

```text
═══════════════════════════════════════════
SECURITY REVIEW RESULTS
═══════════════════════════════════════════

PHASE 1: AUTOMATED SCAN
═══════════════════════
✓ Secrets/credentials  — No hardcoded secrets found
✓ Access control       — All changed routes have auth middleware
✓ Cryptography         — No weak crypto patterns
✓ Injection            — No injection patterns detected
✓ Authentication       — JWT validation present, alg enforced
⚠ Logging             — Silent auth failure at auth.service.ts:42
✓ Data exposure        — No PII in logs or error responses
✓ Infrastructure       — No open rules, unencrypted storage, or public buckets  [if HAS_TERRAFORM]
✓ DB migrations        — No plain-text sensitive columns or broad grants         [if HAS_MIGRATIONS]

PHASE 2: SECURITY REVIEW
═════════════════════════
✓ Auth flow            — Token validation complete, expiry enforced
⚠ Authorization        — getCommittee at committee.service.ts:88 returns data
                         before FGA check for non-member role (discuss)
✓ Input validation     — Allowlist validation on all user-controlled fields
⚠ Security tests       — No 403 test for non-member fetching committee (discuss)

═══════════════════════════════════════════
REVIEW READY (3 discussion items)
═══════════════════════════════════════════
```

**Legend:**

- `✓` — Pass. No issues found.
- `⚠` — Discuss. Should be addressed before merge.
- `✗` — Blocker. Security vulnerability that must be fixed before PR.

**Final verdict:**

- All `✓` → `SECURITY APPROVED`
- Has `⚠` only → `REVIEW READY (N discussion items)`
- Has any `✗` → `NOT READY — N security blockers must be fixed`

### Finding Format

For each `✗` blocker:

```text
FINDING: [Check name]
File: path/to/file.ts:42
Severity: CRITICAL / HIGH / MEDIUM
What: Plain-language description of the vulnerability
Risk: What an attacker could do if exploited
Fix:
  // Before (vulnerable)
  const query = `SELECT * FROM users WHERE id = ${req.params.id}`;

  // After (safe)
  const query = 'SELECT * FROM users WHERE id = $1';
  const result = await db.query(query, [req.params.id]);
Reference: OWASP A03 — https://owasp.org/Top10/A03_2021-Injection/
```

## Scope Boundaries

**This skill DOES:**

- Scan changed files for OWASP Top 10 vulnerability patterns
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