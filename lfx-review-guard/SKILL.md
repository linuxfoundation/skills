---
name: lfx-review-guard
description: >
  After development, before preflight — self-review checklist that catches
  common reviewer blockers. Runs 15 checks based on patterns flagged across
  20+ PRs by reviewers MRashad26 and asithade.
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
- **Unbound component outputs** — when a template uses a child component (e.g., `<lfx-votes-table>`), check if that component emits outputs (e.g., `viewVote`, `rowClick`, `refresh`) that the parent template doesn't bind. Missing output bindings mean user interactions silently do nothing.

**Severity:** BLOCKER for unused providers/imports and unbound outputs. DISCUSS for unused methods (may be used externally).

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

Also search **changed `.ts` files** for:

- **Loading not reset on re-fetch** — `loading` signal set to `false` after a fetch completes, but never set back to `true` when a new fetch starts (e.g., inside `switchMap` when input changes). This causes stale data to display without a spinner during subsequent fetches. The fix is to set `loading.set(true)` at the start of each `switchMap` callback, and use `finalize(() => this.loading.set(false))` or `tap` to reset after completion.

**Severity:** BLOCKER — reviewers consistently flag `0` showing during load and stale loading states.

---

## Check 5: Type Safety in Templates

Search **changed `.html` templates** for:

- **Non-null assertions (`!`)** — patterns like `data()!.field` or `item!.property` in templates. These cause runtime crashes when the value is null/undefined.
- **Missing null safety** — property access on potentially null signals without `?.` or `?? fallback`.
- **Falsy `||` vs nullish `??`** — using `||` where `??` is needed. `value || null` treats `0`, `""`, and `false` as falsy — hiding valid zero counts (e.g., `total_members || null` hides `0` members). Use `??` to only coalesce on `null`/`undefined`.

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
- **Duplicate/layered error handling** — when a service method already has `catchError` that returns a default (e.g., `of([])`), a component-level `catchError` on the same stream is unreachable dead code. Handle errors in one place — either the service or the component, not both. Check if the service being called already catches errors before adding component-level `catchError`.

**Severity:** BLOCKER for silent catchError and unreachable catchError. DISCUSS for inconsistent fallbacks.

---

## Check 7: Signal Pattern Compliance

Search **changed `*.component.ts` and `*.service.ts` files** for:

- **`BehaviorSubject` for simple state** — should use `signal()` instead. `BehaviorSubject` is only appropriate for complex async streams.
- **`cdr.detectChanges()` or `ChangeDetectorRef`** — not needed in zoneless Angular 20. The framework handles change detection.
- **`effect()` writing to forms** — any `effect()` that calls `patchValue()`, `setValue()`, or `reset()` on a form needs `allowSignalWrites: true` in the effect options.
- **Signals not initialized inline** — per `component-organization.md`, simple `WritableSignal`s must be initialized directly (e.g., `loading = signal(false)`), not in the constructor.
- **`model()` for internal state** — `model()` creates a two-way bindable input/output on the component's public API. For internal-only state (e.g., dialog visibility, drawer toggles not exposed to parents), use `signal()` instead. Only use `model()` when the parent component needs two-way binding (e.g., `[(visible)]="childVisible"`).

**Severity:** BLOCKER for BehaviorSubject misuse and missing `allowSignalWrites`. DISCUSS for ChangeDetectorRef and `model()` misuse.

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

## Check 10: Accessibility (a11y)

Search **changed `.html` templates** for:

- **Missing `aria-pressed` on toggle buttons** — button groups that act as toggles (e.g., Upcoming/Past filter) must have `[attr.aria-pressed]="isActive()"` so screen readers announce which option is selected.
- **Nested interactive elements** — a clickable `<div (click)>` containing an `<lfx-button>` or `<a>` creates conflicting interaction targets. Either make the outer element non-interactive, or move the click handler to the inner element.
- **Focusable elements behind overlay/blur masks** — if a visitor blur mask or overlay covers content, the underlying links and buttons must not be focusable. Use `[attr.tabindex]="-1"`, `inert`, or conditionally render the elements (e.g., `@if (!isVisitor()) { <a ...> }`).
- **Missing `aria-label` on icon-only buttons** — buttons with only an icon and no visible text need `aria-label` for screen readers.

**Severity:** DISCUSS — accessibility issues are increasingly flagged by reviewers and are important for compliance.

---

## Check 11: Design Token Compliance

Search **changed `.html` templates and `.component.ts` files** for hardcoded color classes that should use LFX design tokens:

- **Hardcoded Tailwind color classes** — `bg-blue-50`, `text-gray-300`, `border-blue-100`, `text-blue-700`, etc. These should use LFX design tokens or semantic CSS variables (e.g., `--color-info-bg`, `--color-text-muted`).
- **Exception:** Tailwind utility classes that are part of the established design system (check `tailwind.config.js` for configured LFX colors like `lfx-*`) are acceptable.
- **How to check:** Look at the project's `tailwind.config.js` for the custom color palette. If a color is defined there (e.g., `lfx-blue-500`), it's a design token. Raw Tailwind defaults (`blue-50`, `gray-300`) are not.

**Severity:** DISCUSS — flag for consistency with the design system. Not a hard blocker but consistently raised.

---

## Check 12: N+1 API Patterns

Search **changed `.ts` files** (especially services and controllers) for per-item API calls inside loops:

- **Sequential or parallel per-item fetches** — patterns like `items.map(item => this.http.get('/api/' + item.id))` or `forkJoin(items.map(...))` where a batch endpoint exists. Common examples:
  - Per-committee `GET /committees/:uid` to check access → should use batch `/access-check` endpoint
  - Per-meeting registrant lookups → should use bulk query with filters
- **How to detect:** Look for `.map()` calls that produce an array of HTTP observables, or `for`/`forEach` loops containing API calls.
- **Backend too:** In Express controllers, look for `await` inside `for`/`forEach`/`.map()` loops that call `microserviceProxy.proxyRequest()`.

**Severity:** DISCUSS — performance concern. Flag with a note about whether a batch alternative exists.

---

## Check 13: Template/Config Completeness

Search **changed `.html` templates and `.component.ts` files** for mismatches between configuration and template rendering:

- **Missing `@switch` cases** — if a component defines tabs/routes/modes in a config array (e.g., `tabConfig`), every entry must have a corresponding `@case` in the template's `@switch` block. A tab in config without a matching case renders blank content when selected.
- **`activeTab` not constrained to visible set** — if tabs are conditionally visible (e.g., `visibleTabs` computed from permissions), ensure `activeTab` is reset to a valid tab when the visible set changes. Otherwise, `activeTab` can point at a hidden tab, showing blank content.
- **Partial feature wiring** — form controls, outputs, or config entries added but not fully connected. For example, a `chatPlatform` select whose value is never included in the save payload, or a tab button that sets state but has no corresponding panel.

**Severity:** BLOCKER for missing switch cases (broken UI). DISCUSS for partial wiring.

---

## Check 14: Stale Data During Navigation

Search **changed `*.component.ts` files** for patterns that can show stale data when route params or inputs change:

- **One-time initialization that should react to changes** — `if (!this.data())` guards that only load data on first render, not when the route `id` param changes. If the component stays mounted across navigations (e.g., tab components), data must re-fetch when the input changes.
- **Early returns that skip state reset** — guard clauses like `if (!committee?.uid) return` that exit before resetting `loading` or `saving` signals, leaving the UI in a stuck state.
- **`track $index` in `@for` loops** — using `track $index` causes unnecessary DOM churn when items are added/removed/reordered. Prefer tracking by a stable identifier (e.g., `track item.uid` or a composite key).

**Severity:** DISCUSS — stale data issues are subtle but consistently caught in review.

---

## Check 15: Visitor/Permission Gating

Search **changed `.html` templates** for permission-dependent UI that renders incorrectly during role resolution:

- **Content visible during role loading** — `@if (!isVisitor())` evaluates to `true` while `myRoleLoading()` is still `true` (because `isVisitor()` defaults to `false`). This flashes member-only content to visitors until role resolution completes. Fix: add `!myRoleLoading()` to the guard (e.g., `@if (!myRoleLoading() && !isVisitor())`).
- **Visitor blur bypass** — blur overlays that don't prevent keyboard/screen-reader access to the underlying content. See Check 10 (a11y) for the fix.
- **PR description omits permission changes** — if the diff adds, removes, or changes `canEdit()`, `isVisitor()`, `hasPMOAccess()` checks, flag for explicit documentation in the PR description (overlaps with Check 9).

**Severity:** BLOCKER for content flashing during role loading. DISCUSS for blur bypass.

---

## Results Report

After running all 15 checks, produce this report:

```text
REVIEW GUARD RESULTS
─────────────────────────────────────────
 1. ✓ Raw HTML elements     — No raw inputs/selects/textareas found
 2. ✓ Dead code             — No unused providers, imports, or methods
 3. ⚠ Component size        — overview.component.ts has 5 injections (discuss)
 4. ✓ Loading states        — All data displays have loading guards
 5. ✓ Type safety           — No non-null assertions or || vs ?? issues
 6. ✓ Error handling        — All catchError blocks have logging, no duplicates
 7. ✓ Signal patterns       — No BehaviorSubject, manual CD, or model() misuse
 8. ✓ API alignment         — Parameters match upstream contracts
 9. ✓ PR description        — Behavioral changes documented
10. ⚠ Accessibility         — Toggle buttons missing aria-pressed (discuss)
11. ⚠ Design tokens         — 3 files use hardcoded gray classes (discuss)
12. ✓ N+1 API patterns      — No per-item API calls in loops
13. ✓ Template completeness — All config entries have matching template cases
14. ✓ Stale data            — Components re-fetch on input changes
15. ✓ Visitor gating        — Permission guards include loading checks
─────────────────────────────────────────
REVIEW READY (3 discussion items)
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

- Scan changed files for the 15 most common reviewer blocker patterns
- Report findings with file locations and fix suggestions
- Offer to fix blockers if the contributor wants

**This skill does NOT:**

- Auto-fix issues (reports only — contributor decides)
- Run formatting, linting, or build (use `/preflight` for that)
- Generate new code (use `/develop` or `/lfx-ui-builder`)
- Make architectural decisions (use `/lfx-product-architect`)
- Validate upstream APIs live (flags for manual verification)
