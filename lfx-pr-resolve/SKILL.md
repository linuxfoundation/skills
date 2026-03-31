---
name: lfx-pr-resolve
description: >
  Address PR review comments — fetches unresolved threads, makes code changes,
  commits with a summary, responds to each comment, resolves threads, and posts
  a follow-up summary. Use whenever someone wants to address PR feedback, fix
  review comments, resolve PR threads, or iterate on a pull request after review.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Skill
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->
<!-- Tool names in this file use Claude Code vocabulary. See docs/tool-mapping.md for other platforms. -->

# PR Review Comment Resolver

You address PR review feedback end-to-end: read the comments, make the code changes, commit, respond to each reviewer, resolve the threads, and post a summary. The goal is to close the feedback loop completely — reviewers should see exactly what was done and why.

## Step 1: Identify the PR

Determine which PR to work on. The user may provide:

- A PR number (e.g., `#142`)
- A PR URL (e.g., `https://github.com/org/repo/pull/142`)
- Nothing — auto-detect from the current branch

### Verify GitHub CLI Authentication

Before making any `gh` calls, verify authentication:

```bash
gh auth status 2>&1
```

If auth fails, stop and tell the user to run `gh auth login`.

### Auto-detection

```bash
# Get current branch
BRANCH=$(git branch --show-current)

# Find PR for this branch
gh pr list --head "$BRANCH" --state open --json number,url,title --jq '.[0]'
```

If no PR is found for the current branch, ask:

> "I don't see an open PR for this branch. Which PR would you like to address? (Give me a number or URL)"

## Step 2: Fetch PR Details and Review Threads

### Derive Repository Variables

Extract the owner, repo, and PR number from the identified PR. If the user provided a URL, parse it. If auto-detected, derive from the current repo:

```bash
# From the current repo's remote
OWNER=$(gh repo view --json owner -q '.owner.login')
REPO=$(gh repo view --json name -q '.name')
# NUMBER comes from Step 1 (user input or auto-detection)
```

### Fetch Review Threads

Fetch the PR metadata and all review threads in a single GraphQL call:

```bash
gh api graphql -F query=@- -f owner="$OWNER" -f repo="$REPO" -F number=$NUMBER <<'GRAPHQL'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      title
      url
      baseRefName
      headRefName
      body
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          diffSide
          comments(first: 20) {
            nodes {
              id
              author { login }
              body
              createdAt
              path
              line
              startLine
            }
          }
        }
      }
      reviews(last: 20) {
        nodes {
          state
          author { login }
          body
          submittedAt
        }
      }
    }
  }
}
GRAPHQL
```

**Pagination note:** The query caps at 100 review threads and 20 comments per thread. This covers the vast majority of PRs. If a PR exceeds these limits, fetch additional pages using `pageInfo { hasNextPage endCursor }` and the `after` parameter.

### Filter to Actionable Threads

From the response, collect only **unresolved** threads (`isResolved == false`). Skip threads that are already resolved — someone else handled them or they were resolved in a previous iteration.

For each unresolved thread, extract:

| Field | Source |
|-------|--------|
| Thread ID | `id` (needed for resolving later) |
| File path | `path` |
| Line(s) | `line`, `startLine` |
| Reviewer | First comment's `author.login` |
| Comment body | All comments in the thread (the conversation) |
| Outdated? | `isOutdated` (file has changed since the comment was made) |

### Edge Cases

- **No unresolved threads**: Tell the user — "All review threads are already resolved! Nothing to address." Stop here.
- **Outdated threads**: Include them but flag them — the code may have shifted since the comment was made. Read the current file to determine if the feedback still applies.
- **General PR review comments** (not attached to a specific line): These appear as reviews with a `body` but no associated thread path. Collect these separately — they need responses but may not require code changes. You will respond to each of these later via a PR-level comment that `@mentions` the reviewer and references the commit that addresses their feedback (if any).

## Step 3: Validate Each Comment Against Repo Patterns

Before categorizing or acting on any comment, validate whether the reviewer's feedback is actually correct. Reviewers can make mistakes — they may misread the code, apply conventions from a different repo, or flag something that is already handled elsewhere. Blindly implementing every comment can introduce regressions.

For each unresolved thread and each collected general PR review comment:

1. **Read the actual code** at the referenced file and line — not just the diff snippet the reviewer saw. Read enough surrounding context (20-30 lines) to understand what the code is doing.
2. **Check the repo's existing patterns** — search for how similar code is written elsewhere in the codebase. If the reviewer says "use X pattern" but the rest of the repo uses Y pattern, that's a red flag.
   ```bash
   # Example: reviewer says "use BehaviorSubject" but check what the repo actually does
   grep -r "signal(" src/app/modules/ --include="*.ts" -l | head -10
   grep -r "BehaviorSubject" src/app/modules/ --include="*.ts" -l | head -10
   ```
3. **Cross-reference with project conventions** — check CLAUDE.md, eslint configs, or other style guides in the repo. The reviewer's suggestion may conflict with established conventions.
4. **Assess the comment's validity:**

| Assessment | Meaning | Action |
|------------|---------|--------|
| **Valid** | The reviewer is correct — the code needs to change | Proceed to categorize and address |
| **Likely false positive** | The reviewer appears to have misread the code or applied the wrong convention | Flag for user with your reasoning |
| **Partially valid** | The reviewer has a point but their suggested fix is wrong or incomplete | Flag with a recommended alternative |
| **Outdated** | The code has changed since the comment — the issue no longer exists | Flag as already addressed |

The goal is not to dismiss reviewer feedback — it's to catch cases where implementing the suggestion would make the code worse. When in doubt, lean toward implementing the change, but always surface your assessment to the user.

## Step 4: Categorize Comments

After validation, categorize each thread:

| Category | Description | Action |
|----------|-------------|--------|
| **Code change** | Reviewer requests a specific modification and the suggestion is valid | Make the change |
| **Question** | Reviewer asks "why did you...?" or "what about...?" | Respond with explanation |
| **Nitpick / style** | Minor formatting, naming suggestion, or preference | Make the change (quick wins build goodwill) |
| **Approval with comment** | "Looks good, but consider..." or "Nit: ..." with no blocking intent | Assess — fix if trivial, explain if not |
| **False positive** | Reviewer's suggestion conflicts with repo patterns or is based on a misread | Flag for user — recommend a polite response explaining why |
| **Discussion** | Architectural debate, trade-off, or open-ended feedback | Flag for user decision |

### Present the Plan

Before making any changes, present the categorized comments to the user. Include your validation assessment for each item so the user can make an informed decision:

```
═══════════════════════════════════════════
PR #[number] — REVIEW COMMENTS TO ADDRESS
═══════════════════════════════════════════

[N] unresolved threads from [reviewers]

CODE CHANGES NEEDED
───────────────────
1. ✓ @[reviewer] on [file]:[line] — "[summary of what they want]"
     Validated: [brief reason — e.g., "matches pattern in other components"]
2. ✓ @[reviewer] on [file]:[line] — "[summary of what they want]"
     Validated: [brief reason]

QUESTIONS TO ANSWER
───────────────────
3. @[reviewer] on [file]:[line] — "[the question]"

LIKELY FALSE POSITIVES
──────────────────────
4. ⚠ @[reviewer] on [file]:[line] — "[what they suggested]"
     Assessment: [why this appears incorrect — e.g., "Reviewer suggests
     BehaviorSubject but this repo uses signals for component-local state.
     Found 12 components using signal() vs 3 legacy BehaviorSubjects."]
     Recommendation: Respond explaining the repo convention. No code change.

NEEDS YOUR INPUT
────────────────
5. @[reviewer] on [file]:[line] — "[the discussion point]"
   → What would you like me to do here?

═══════════════════════════════════════════
Shall I proceed with items 1-2? Items 4-5 need your direction.
═══════════════════════════════════════════
```

**Wait for user approval before making changes.** The user has final say on whether to implement, push back, or discuss further — especially for items flagged as potential false positives.

### Responding to False Positives

When the user confirms a comment is a false positive, draft a respectful response that:
- Acknowledges the reviewer's intent ("Good eye on this — I can see why it looks off")
- Explains the repo convention or pattern with evidence ("This repo uses signals for component-local state — you can see the same pattern in `member-form.component.ts`, `attendance-list.component.ts`, etc.")
- Offers to discuss further if the reviewer disagrees ("Happy to discuss if you think we should approach this differently")

Never be dismissive. The reviewer took time to read the code — even a wrong comment shows engagement.

## Step 5: Address Each Comment

Work through the approved comments systematically.

### For Code Changes and Nitpicks

1. **Read the current file** at the relevant location to understand the context
2. **Make the change** using Edit — keep changes minimal and focused on what the reviewer asked
3. **Verify the change** — re-read the modified area to confirm it addresses the feedback
4. **Track what was done** — keep a running log of changes for the commit message and responses

### For Questions

1. **Read the relevant code** to understand the context
2. **Draft a response** that explains the reasoning — be specific, reference the code
3. **Ask the user to review the draft response** if the question touches on architectural decisions or trade-offs the user should weigh in on

### For Discussion Items

Only address these after the user provides direction in Step 3.

### Delegation to Builder Skills

For complex changes that span multiple files or require pattern knowledge (e.g., "refactor this to use signals instead of BehaviorSubject"), delegate to the appropriate builder skill:

```
Skill(skill: "lfx-ui-builder", args: "FIX PR REVIEW: [description of the change needed]. File: [path]. Context: reviewer asked for [what they said]. Follow the existing pattern in [example file].")
```

```
Skill(skill: "lfx-backend-builder", args: "FIX PR REVIEW: [description of the change needed]. Repo: [path]. Context: reviewer asked for [what they said].")
```

For simple, targeted fixes (rename a variable, add a null check, fix an import), make the change directly — no need to delegate.

## Step 6: Validate Changes

After all code changes are made, run validation. Delegate to preflight with `--skip-review` since this is an iteration, not a fresh PR:

```bash
# Quick validation — format, lint, build
yarn format && yarn lint && yarn build
# Or for Go repos:
go vet ./... && go build ./...
```

If validation fails, fix the issues before proceeding. Do not commit broken code.

## Step 7: Commit with Detailed Summary

Create a single commit that summarizes all changes made to address the review feedback.

### Commit Message Format

The commit message must clearly state what review feedback was addressed, so that both git history readers and PR reviewers can understand what happened:

```
fix(review): address PR #[number] review feedback

Address review comments from @[reviewer1], @[reviewer2]:

- [file]: [what was changed and why] (per @[reviewer])
- [file]: [what was changed and why] (per @[reviewer])
- [file]: responded to question about [topic]

Resolves [N] review threads.
```

Note: The `--signoff` flag automatically appends the `Signed-off-by:` trailer — do not include it manually in the message body.

### Commit Rules

- **One commit per review iteration** — don't create separate commits per comment. Reviewers want to see a single cohesive response to their feedback.
- **Reference the PR number** in the commit subject.
- **Credit the reviewer** — mention who asked for each change. This helps when reading git blame later.
- **Include `--signoff`** — required for all LFX commits.
- **List every change** — the commit body should be a complete record. Someone reading the commit message should know exactly what review feedback was addressed without needing to read the diff.

```bash
git add [specific files that were changed]
git commit --signoff -m "$(cat <<'EOF'
fix(review): address PR #[number] review feedback

Address review comments from @[reviewer1]:

- path/to/file.ts: renamed variable per reviewer suggestion
- path/to/component.html: added loading guard for stats display
- path/to/service.ts: explained error handling approach (no code change)

Resolves 3 review threads.
EOF
)"
```

## Step 8: Respond to Each Comment Thread

After committing, respond to each review thread on GitHub. This is the critical feedback loop — reviewers need to know their comments were heard and addressed.

### Response Format by Category

**For code changes made:**

```bash
gh api graphql -F query=@- -f threadId="$THREAD_ID" -f body="$RESPONSE_BODY" <<'GRAPHQL'
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId
    body: $body
  }) {
    comment { id }
  }
}
GRAPHQL
```

Response body:

```
Done — [specific description of the change made].

See commit [short SHA]: [one-line summary of what changed in this file].
```

**For questions answered (no code change):**

```
[Clear, specific answer to the question with code references where helpful].

No code change needed — [brief explanation of why the current approach is correct].
```

**For nitpicks fixed:**

```
Fixed — [what was changed]. Good catch!
```

**For discussion items where user provided direction:**

```
[Explanation of the decision and reasoning].

[Description of what was changed, or why no change was made].
```

**For false positives (user confirmed no change needed):**

```
Thanks for flagging this — I can see why it looks [wrong/inconsistent/off].

[Explanation with evidence: "This repo uses [pattern X] for [reason]. You can see
the same approach in [file1], [file2], etc."]

[If applicable: "Happy to discuss further if you think we should reconsider."]
```

### Response Rules

- **Be specific** — don't say "Fixed." Say what was fixed and how.
- **Reference the commit** — include the short SHA so reviewers can jump to the exact change.
- **Keep it concise** — one or two sentences for simple fixes, a short paragraph for questions or discussions.
- **Be professional and appreciative** — reviewers spent time reading the code. Acknowledge good catches.

## Step 9: Resolve Review Threads

After responding to each thread, resolve it. Only resolve threads where the feedback has been fully addressed — if a thread required user input and the user chose not to address it, leave it unresolved.

```bash
gh api graphql -F query=@- -f threadId="$THREAD_ID" <<'GRAPHQL'
mutation($threadId: ID!) {
  resolveReviewThread(input: {
    threadId: $threadId
  }) {
    thread { isResolved }
  }
}
GRAPHQL
```

### Do NOT Resolve If

- The comment was a discussion point and no conclusion was reached
- The user explicitly said to skip or defer a comment
- The change couldn't be made due to a technical constraint (explain why in the response, leave unresolved)
- You're unsure whether your change fully addresses the feedback — leave unresolved and let the reviewer confirm

## Step 10: Push Changes

Push the commit to the remote branch:

```bash
git push
```

If the push fails due to remote changes, pull and rebase first:

```bash
git pull --rebase origin $(git branch --show-current)
# Re-run quick validation after rebase
yarn lint && yarn build
git push
```

## Step 11: Post Summary Comment

After all threads are responded to and resolved, post a single summary comment on the PR. This gives reviewers a one-stop overview of everything that was addressed in this iteration:

```bash
gh pr comment $NUMBER --repo $OWNER/$REPO --body "$(cat <<'EOF'
## Review Feedback Addressed

Commit: [full SHA]

### Changes Made
- **[file]**: [what changed] (per @[reviewer])
- **[file]**: [what changed] (per @[reviewer])

### Questions Answered
- **[file]:[line]**: [brief answer] (asked by @[reviewer])

[If any comments were identified as false positives:]
### No Change Needed
- **[file]:[line]**: [brief explanation of why the current code is correct and what repo pattern it follows] (flagged by @[reviewer])

### Threads Resolved
[N] of [M] unresolved threads addressed in this iteration.

[If any threads were left unresolved:]
### Still Open
- **[file]:[line]**: [why it was left open — e.g., "deferred to follow-up PR", "awaiting reviewer confirmation"]
EOF
)"
```

### Summary Rules

- **List every thread** that was addressed, not just code changes
- **Group by action type** — changes made, questions answered, deferred
- **Include the commit SHA** so reviewers can see the full diff
- **Call out anything left open** — don't hide unresolved items
- **Credit reviewers** by @-mentioning them next to their feedback

## Step 12: Report to User

Present the final status:

```
═══════════════════════════════════════════
PR #[number] — REVIEW FEEDBACK ADDRESSED
═══════════════════════════════════════════

Commit: [SHA] — [commit subject]
Pushed to: [branch]

Threads addressed: [N] of [M]
  ✓ [N] code changes made
  ✓ [N] questions answered
  ✓ [N] threads resolved on GitHub
  [- [N] left open (needs reviewer input)]

Summary comment posted: [PR URL]

What's next:
  - Reviewers will be notified of your responses
  - Check back with /lfx-pr-catchup to monitor the PR
  [- [N] threads still need discussion — follow up with the reviewer]
═══════════════════════════════════════════
```

## Idempotency — Safe to Re-run

If the user runs this skill again on the same PR:

1. **Re-fetch threads** — only pick up threads that are still unresolved
2. **Skip already-resolved threads** — don't re-address or re-respond
3. **New comments since last run** — treat them as fresh feedback
4. Tell the user: "Found [N] new/remaining unresolved threads since the last iteration."

## Scope Boundaries

**This skill DOES:**
- Fetch and analyze PR review threads
- Categorize comments by type (code change, question, discussion)
- Make targeted code changes to address review feedback
- Commit with a detailed summary of what was addressed
- Respond to each review thread on GitHub
- Resolve addressed threads
- Post a summary comment on the PR
- Push changes to the remote branch
- Delegate complex changes to `/lfx-backend-builder` or `/lfx-ui-builder`

**This skill does NOT:**
- Create new PRs (use `/lfx-preflight` → create PR)
- Build new features from scratch (use `/lfx-coordinator`)
- Review code (use `/lfx-preflight` Phase 2)
- Merge PRs (the reviewer does that)
- Resolve threads where the feedback wasn't fully addressed
