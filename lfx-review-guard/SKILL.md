---
name: lfx-review-guard
description: >
  After development, before preflight — self-review checklist that catches
  common reviewer blockers. Runs 9 checks based on patterns flagged across
  15+ PRs by reviewers MRashad26 and asithade.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# Review Guard — Self-Review for Reviewer Blockers

You are running a self-review checklist that catches the patterns most commonly flagged by reviewers before a PR is submitted. This skill runs **after development** and **before `/preflight`**.

**Mode:** Report only — this skill does not auto-fix. It reports findings so the contributor can address them before reviewers see the code.

## Step 0: Determine Changed Files

```bash
git diff --name-only origin/main...HEAD
```

Scope all checks to **changed files only**. If no files have changed, report that and exit.

Separate changed files into categories for targeted checks:

- **Templates:** `*.html`
- **Components:** `*.component.ts`
- **Services/other TS:** `*.ts` (excluding `*.spec.ts`)
- **All changed files** for general checks

---

## Check 1: No Raw HTML Form Elements (MOST COMMON blocker)

Search **changed `.html` files** for raw form elements that must use LFX wrappers:

| Raw Element | Required Wrapper |
| --- | --- |
| `<input` | `lfx-input-text` (or other `lfx-input-*` variant) |
| `<select` | `lfx-select` |
| `<textarea` | `lfx-textarea` |
| `<div` with `animate-pulse` class | `<p-skeleton>` from PrimeNG |

**Exceptions:** Elements inside comments, or `<input type="hidden">` are acceptable.

**Note:** LFX wrappers require `FormGroup` + `FormControl` — `ngModel` is not supported.

**Severity:** BLOCKER — reviewers will always flag this.

---

## Check 2: No Dead Code

Search **all changed `.ts` files** for:

- **Unused providers** — `providers: [...]` entries in component metadata where the service is never injected via `inject()` or constructor
- **Unused imports** — imported symbols not referenced in the file body
- **Unused methods** — private methods not called anywhere in the file; public methods in services not called from any changed file
- **Unused signals** — signals declared but never read (called) in the template or class
- **Removed `console.error` without replacement** — if a `console.error` was removed (check `git diff`), ensure it was replaced with `logger` service usage, not silently dropped

**Severity:** BLOCKER for unused providers/imports. DISCUSS for unused methods (may be used externally).

---

## Check 3: Component Responsibility (God Components)

Search **changed `*.component.ts` files** for service injection count:

```typescript
// Count inject() calls and constructor injections
```

- **4+ service injections** → Flag for discussion. This often means the component is doing too much.
- **Multiple independent edit workflows** in a single component (e.g., separate forms that don't share state) → Suggest extracting sub-components.

**Severity:** DISCUSS — guideline, not a hard rule. Flag but don't block.

---

## Check 4: Loading States

Search **changed `.html` templates** for patterns that indicate missing loading guards:

- **Stats or counts rendered without loading check** — look for interpolations like `{{ count() }}` or `{{ stats().total }}` without a surrounding `@if (loading())` or `@if (!loading())` guard. These show `0` during loading instead of a placeholder.
- **Missing loading branch** — components that fetch data but have no `@if (loading())` / `@else` pattern.
- **Content that jumps** — `@for` loops rendering data without a loading skeleton before data arrives.

Every data display that starts empty and populates asynchronously needs an explicit loading branch showing `—`, `<p-skeleton>`, or equivalent.

**Severity:** BLOCKER — reviewers consistently flag `0` showing during load.

---

## Check 5: Type Safety in Templates

Search **changed `.html` templates** for:

- **Non-null assertions (`!`)** — patterns like `data()!.field` or `item!.property` in templates. These cause runtime crashes when the value is null/undefined.
- **Missing null safety** — property access on potentially null signals without `?.` or `?? fallback`.

**Correct patterns:**

```html
<!-- Guard with @if + as -->
@if (committee(); as c) {
  <span>{{ c.name }}</span>
}

<!-- Optional chaining -->
<span>{{ committee()?.name ?? '—' }}</span>
```

**Severity:** BLOCKER — `!` assertions in templates are always flagged.

---

## Check 6: Error Handling

Search **changed `.ts` files** for:

- **Silent `catchError`** — `catchError(() => of([]))` or `catchError(() => EMPTY)` without any logging before the fallback. Every `catchError` should log via `logger` service or `console.error` at minimum.
- **Inconsistent fallback values** — mixing `EMPTY` and `of([])` in the same service. Pick one pattern and stick with it.
- **Removed error logging** — check `git diff` for removed `console.error` or `logger.error` calls that weren't replaced.

**Severity:** BLOCKER for silent catchError. DISCUSS for inconsistent fallbacks.

---

## Check 7: Signal Pattern Compliance

Search **changed `*.component.ts` and `*.service.ts` files** for:

- **`BehaviorSubject` for simple state** — should use `signal()` instead. `BehaviorSubject` is only appropriate for complex async streams.
- **`cdr.detectChanges()` or `ChangeDetectorRef`** — not needed in zoneless Angular 20. The framework handles change detection.
- **`effect()` writing to forms** — any `effect()` that calls `patchValue()`, `setValue()`, or `reset()` on a form needs `allowSignalWrites: true` in the effect options.
- **Signals not initialized inline** — per `component-organization.md`, simple `WritableSignal`s must be initialized directly (e.g., `loading = signal(false)`), not in the constructor.

**Severity:** BLOCKER for BehaviorSubject misuse and missing `allowSignalWrites`. DISCUSS for ChangeDetectorRef (may be legacy code being modified).

---

## Check 8: Upstream API Alignment

This check requires judgment. Search **changed `.ts` files** for API calls and verify:

- **Parameter names match upstream** — known divergences:
  - Meetings API uses `limit` for pagination
  - Votes/Surveys APIs use `page_size` for pagination
  - Don't mix these up
- **No invented fields** — if the code references a field in an API response, verify it exists in the upstream contract. Look at the service file's proxy calls and the interfaces used.
- **No UI for non-existent backend fields** — form fields or display elements bound to data that the API doesn't actually return.

If you cannot verify the upstream contract from the local codebase, flag the items for manual verification rather than passing them silently.

**Severity:** BLOCKER for clearly wrong parameter names. DISCUSS for fields that need upstream verification.

---

## Check 9: PR Description Completeness

Check the **git log and diff** for changes that need explicit documentation in the PR description:

```bash
git log --format="%s%n%b" origin/main...HEAD
git diff origin/main...HEAD
```

Flag if the diff contains any of these without corresponding mention in commit messages:

- **Removed UI elements** — deleted components, removed buttons/fields/sections from templates. Reviewers need to know what was removed and why.
- **Permission check changes** — modifications to FGA checks, role guards, or auth logic. Security-sensitive changes must be called out.
- **Error handling behavior changes** — changed fallback values, modified retry logic, altered error messages. Reviewers need the rationale.

**Severity:** DISCUSS — flag items the contributor should document in the PR description.

---

## Results Report

After running all 9 checks, produce this report:

```text
REVIEW GUARD RESULTS
─────────────────────────────────
✓ Raw HTML elements     — No raw inputs/selects/textareas found
✓ Dead code             — No unused providers, imports, or methods
⚠ Component size        — overview.component.ts has 5 injections (discuss)
✓ Loading states        — All data displays have loading guards
✓ Type safety           — No non-null assertions in templates
✓ Error handling        — All catchError blocks have logging
✓ Signal patterns       — No BehaviorSubject or manual CD
✓ API alignment         — Parameters match upstream contracts
✓ PR description        — Behavioral changes documented
─────────────────────────────────
REVIEW READY (1 discussion item)
```

**Legend:**

- `✓` — Pass. No issues found.
- `⚠` — Discuss. Not a blocker, but should be considered.
- `✗` — Blocker. Must be fixed before submitting the PR.

**Final verdict line:**

- All `✓` → `REVIEW READY`
- Has `⚠` only → `REVIEW READY (N discussion items)`
- Has any `✗` → `NOT READY — N blockers must be fixed`

### If Blockers Are Found

For each blocker, provide:

1. **File and line** where the issue occurs
2. **What's wrong** in plain language
3. **How to fix it** with a concrete example

```text
✗ Raw HTML elements — 2 blockers found

  1. member-form.component.html:24
     Raw <input> element — must use <lfx-input-text> wrapper
     Fix: Replace <input formControlName="name"> with
          <lfx-input-text formControlName="name" label="Name" />

  2. settings.component.html:56
     Raw <select> element — must use <lfx-select> wrapper
     Fix: Replace <select> with <lfx-select [options]="options" formControlName="type" />
```

### After Reporting

> "Review guard complete. Would you like me to fix the blockers, or would you prefer to address them yourself?"

If all checks pass:

> "Your code looks good — no common reviewer blockers found. Run `/preflight` next to validate formatting, linting, and build."

## Scope Boundaries

**This skill DOES:**

- Scan changed files for the 9 most common reviewer blocker patterns
- Report findings with file locations and fix suggestions
- Offer to fix blockers if the contributor wants

**This skill does NOT:**

- Auto-fix issues (reports only — contributor decides)
- Run formatting, linting, or build (use `/preflight` for that)
- Generate new code (use `/develop` or `/lfx-ui-builder`)
- Make architectural decisions (use `/lfx-product-architect`)
- Validate upstream APIs live (flags for manual verification)
