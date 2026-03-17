---
name: lfx-pr-catchup
description: >
  Morning PR catch-up dashboard — shows unresolved comments, status changes,
  stale PRs, and approved-but-not-merged PRs across all your open PRs.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# PR Catch-Up Dashboard

You generate a compact terminal dashboard of the user's open pull requests, highlighting what needs attention — unresolved comments, status changes, stale PRs, and approved-but-not-merged PRs.

**This skill is read-only. It never modifies code, creates branches, or pushes commits.**

## Step 1: Verify GitHub CLI Authentication

```bash
gh auth status 2>&1
```

If authentication fails, tell the user:

```
GitHub CLI is not authenticated. Please run:

  gh auth login

Then try /lfx-pr-catchup again.
```

**Stop here if auth fails.**

## Step 2: Optional Configuration

**Do NOT ask the user for preferences. Proceed immediately with defaults.**

Defaults:
- `ORG_FILTER` — empty string (all orgs)
- `STALE_DAYS` — 7

The user can override these by including preferences in their initial message when invoking the skill (e.g., "/lfx-pr-catchup linuxfoundation" or "/lfx-pr-catchup stale=14"). If the user's message includes an org name, set `ORG_FILTER` to `--owner <org>`. If it includes a number for stale days, set `STALE_DAYS` accordingly. Otherwise, use defaults and move straight to Step 3.

## Step 3: Fetch Open PRs

```bash
gh search prs --author=@me --state=open --limit=50 --json repository,number,title,url,updatedAt,createdAt ${ORG_FILTER}
```

### Edge cases

- **No PRs found**: Display a friendly message:
  ```
  No open PRs found! You're all caught up.
  ```
  If an org filter was used, suggest: "Try without the org filter to check all repos."
  **Stop here.**

- **50 PRs returned** (hit the limit): Warn the user:
  ```
  You have 50+ open PRs — showing the first 50. Consider filtering by org to narrow results.
  ```

## Step 4: Enrich Each PR via GraphQL

For each PR, fetch detailed review and thread data using a single GraphQL call. Process PRs in batches to avoid rate limiting.

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      title
      url
      updatedAt
      mergeable
      reviewDecision
      reviewThreads(first: 50) {
        nodes {
          isResolved
          comments(first: 1) {
            nodes {
              author { login }
              createdAt
            }
          }
        }
      }
      reviews(last: 10) {
        nodes {
          state
          author { login }
          submittedAt
        }
      }
      reviewRequests(first: 10) {
        nodes {
          requestedReviewer {
            ... on User { login }
            ... on Team { name }
          }
        }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F number=$NUMBER
```

### Rate limiting

After each batch of 10 GraphQL calls, check the rate limit:

```bash
gh api rate_limit --jq '.resources.graphql'
```

If `remaining` is below 100:
- Stop enrichment immediately
- Display partial results with a warning:
  ```
  GitHub API rate limit approaching — showing partial results.
  Rate limit resets at [reset time].
  ```

### Inaccessible repos

If a GraphQL call fails for a specific PR (403/404), skip it and add a note:
```
  (skipped — repo not accessible)
```
Do not fail the entire dashboard.

### GraphQL failure fallback

If GraphQL calls fail entirely (e.g., auth scope issue), fall back to REST enrichment:

```bash
gh pr view $NUMBER --repo $OWNER/$REPO --json reviews,reviewDecision,reviewRequests
```

Note: REST fallback loses `isResolved` accuracy for review threads. Mention this in output:
```
  (Note: using REST fallback — unresolved comment counts may be approximate)
```

## Step 5: Classify Signals

For each PR, classify zero or more signals. A PR can have multiple signals.

### HIGH priority (action needed — prefix with `!!`)

| Signal | Condition |
|--------|-----------|
| Unresolved comments | `reviewThreads` has nodes where `isResolved == false` |
| Changes requested | `reviews` contains a review with `state == "CHANGES_REQUESTED"` that is not superseded by a newer review from the same author |

### MEDIUM priority (informational — prefix with `**`)

| Signal | Condition |
|--------|-----------|
| Approved but not merged | `reviewDecision == "APPROVED"` and PR is still open |
| Stale | `updatedAt` is older than `STALE_DAYS` days ago |

### LOW priority (noted inline, no prefix)

| Signal | Condition |
|--------|-----------|
| No reviewers assigned | `reviewRequests` is empty AND `reviews` is empty |

### Classification rules

- A PR with zero HIGH or MEDIUM signals goes in "All Clear"
- A PR with any HIGH or MEDIUM signal goes in "Needs Attention"
- Within "Needs Attention", sort by: HIGH signals first, then MEDIUM
- Within "All Clear", sort by most recently updated first

## Step 6: Render Dashboard

Output the dashboard directly as text. Use box-drawing characters for visual structure.

```
═══════════════════════════════════════════════════════════
PR CATCH-UP — [current date, e.g., March 17, 2026]
═══════════════════════════════════════════════════════════

[N] open PRs across [M] repos  |  [X] need attention  |  [Y] all clear

─── NEEDS ATTENTION ───────────────────────────────────────

[owner/repo]
  #[number]  [title]
        !! [count] unresolved comments (from @[author1], @[author2])
        !! Changes requested by @[reviewer] ([N] days ago)
        [url]

  #[number]  [title]
        ** Approved but not merged (approved [N] days ago)
        [url]

─── ALL CLEAR ─────────────────────────────────────────────

[owner/repo]
  #[number]  [title] — [short status summary]
  #[number]  [title] — [short status summary]

═══════════════════════════════════════════════════════════
```

### Formatting rules

- Group PRs by `owner/repo`
- "Needs attention" section comes first with full details and URLs
- "All clear" section is compact — one line per PR, no URLs
- `!!` prefix = action needed (HIGH signals)
- `**` prefix = informational (MEDIUM signals)
- Short status summaries for "All Clear" PRs: "approved, CI passing", "review in progress", "just opened", "no reviewers yet"
- If there are no "Needs attention" PRs, omit that section entirely
- If there are no "All clear" PRs, omit that section entirely

## Step 7: Offer Drill-Down

After rendering the dashboard, offer:

```
Want to dive deeper into any PR? Give me a number (e.g., #142) and I'll show:
  - Full comment threads
  - CI status details
  - File diff summary
```

If the user provides a PR number, fetch and display:

```bash
# Review comments
gh pr view $NUMBER --repo $OWNER/$REPO --json comments,reviews,statusCheckRollup --template '...'

# CI status
gh pr checks $NUMBER --repo $OWNER/$REPO
```

Present the drill-down in a readable format, then offer to drill into another PR or end.

## Scope Boundaries

**This skill DOES:**
- Fetch and display PR status information
- Classify PRs by urgency/attention needed
- Show review threads, approval status, staleness
- Offer drill-down into individual PRs

**This skill does NOT:**
- Modify any code or PR
- Merge, approve, or request changes on PRs
- Create or close PRs
- Push commits or branches
- Comment on PRs
