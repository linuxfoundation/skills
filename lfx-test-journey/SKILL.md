---
name: lfx-test-journey
description: >
  Combine multiple feature branches across repos into worktrees for
  end-to-end journey testing. Create, refresh, and teardown integration
  environments that merge branches from multiple repos.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Journey Testing — Multi-Branch Integration Worktrees

You help the user combine feature branches from one or more repos into isolated git worktrees for end-to-end journey testing. You never modify the user's actual branches — you create temporary worktrees that merge everything together.

**Journeys are stored at `~/.lfx-journeys/`.**

## CRITICAL: Interactive Gates

**This skill is interactive. You MUST stop and wait for user input at each selection step. NEVER skip ahead.**

The create flow has THREE mandatory user gates:
1. **Repo selection** — present repos, STOP, wait for user to pick
2. **Branch selection** — present branches per repo, STOP, wait for user to pick (per repo)
3. **Journey naming** — STOP, wait for user to name the journey

**Do NOT proceed past any gate without the user's explicit response.** Do NOT auto-select branches, auto-name journeys, or skip selection steps. The whole point of this skill is that the USER chooses what to combine.

## Subcommand Router

Parse the user's input to determine which subcommand to run. If no subcommand is clear, default to `create`.

| If the user says... | Run... |
|----------------------|--------|
| "create", or invokes the skill with no args | → Go to **Create Journey** |
| "status" or "check" | → Go to **Status** |
| "refresh" followed by a journey name | → Go to **Refresh** |
| "edit" followed by a journey name | → Go to **Edit** |
| "teardown", "remove", "delete" followed by a journey name | → Go to **Teardown** |
| "list" | → Go to **List** |

If a subcommand requires a journey name and the user didn't provide one, run **List** first to show available journeys, then ask which one.

## Scope Boundaries

**This skill DOES:**
- Discover unmerged branches authored by the user
- Create git worktrees that merge multiple branches together
- Track journey state via manifest files
- Detect staleness and refresh worktrees
- Clean up worktrees and manifests

**This skill does NOT:**
- Run the application — it sets up worktrees, the user runs the app as usual
- Manage PRs or merge to main — purely local testing
- Persist across machines — worktrees and manifests are local
- Replay previous conflict resolutions — each refresh is a clean re-merge

---

## Create Journey

### Step 1: Discover Repos

Scan `~/lf/` for git repositories:

```bash
for dir in ~/lf/*/; do
  if [ -d "$dir/.git" ]; then
    echo "$dir"
  fi
done
```

Present as a numbered list and **STOP — use `AskUserQuestion` and wait for the user to respond before continuing**:

```
Scanning ~/lf/ for git repos...

Which repos are part of this journey? (type numbers, e.g. "1, 3")
  1. ~/lf/lfx-v2-ui
  2. ~/lf/lfx-v2-committee-service
  3. ~/lf/lfx-v2-meeting-service
```

**⛔ GATE: You MUST call `AskUserQuestion` here and wait for the user's response. Do NOT continue to Step 2 until the user has selected repos.** Parse their response (comma-separated numbers or repo names).

### Step 2: Fetch Latest Refs

For each selected repo, fetch to ensure refs are current:

```bash
cd <repo-path>
git fetch --all --prune
```

Report progress: "Fetching latest refs for <repo-name>..."

### Step 3: Discover Branches

For each selected repo, find the user's unmerged branches:

```bash
cd <repo-path>
# Get the git user name for filtering
GIT_USER=$(git config user.name)

# Use temp files to avoid clobbering across parallel runs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Find branches with recent work by this user, not yet merged to main
git log --author="$GIT_USER" --all --oneline --since='30 days ago' --format='%D' \
  | tr ',' '\n' \
  | sed 's/^ *//' \
  | grep -E '^origin/' \
  | sed 's|^origin/||' \
  | grep -v '^main$' \
  | grep -v '^HEAD$' \
  | sort -u > "$TMPDIR/author_branches.txt"

# Cross-reference with unmerged branches
git branch -r --no-merged origin/main \
  | sed 's|^ *origin/||' \
  | sort -u > "$TMPDIR/unmerged_branches.txt"

# Intersection: branches by user AND not merged
comm -12 "$TMPDIR/author_branches.txt" "$TMPDIR/unmerged_branches.txt"
```

For each branch found, get the last commit date for sorting:

```bash
git log -1 --format='%ci' origin/<branch-name>
```

Present as a numbered list sorted by most recent first, and **STOP — use `AskUserQuestion` and wait for the user to pick branches**:

```
Your unmerged branches in lfx-v2-ui (type numbers to include):
  1. feat/committee-invite-drawer (today)
  2. feat/committee-detail (1 day ago)
  3. feat/committee-list (3 days ago)
  4. feat/meeting-calendar (5 days ago)
```

**⛔ GATE: You MUST call `AskUserQuestion` for EACH repo separately and wait for the user's response. Do NOT continue to the next repo or to Step 4 until the user has selected branches for the current repo.** Parse comma-separated numbers.

**If no branches found for a repo:** Report it and skip: "No unmerged branches found for <repo>. Skipping."

### Step 4: Ask for Journey Name

**⛔ GATE: You MUST call `AskUserQuestion` here and wait for the user to name the journey. Do NOT auto-generate a name.**

```
AskUserQuestion: "Journey name?"
```

Validate: alphanumeric and hyphens only. **Reject** names containing `/`, `..`, spaces, or other special characters — the name is used in filesystem paths and git branch names. Suggest a name based on common branch prefixes if possible, but always wait for the user's response.

### Step 5: Create Worktrees

For each repo, create a worktree on a new branch:

```bash
cd <repo-path>

# Ensure journeys directory exists
mkdir -p ~/.lfx-journeys/<journey-name>

# Create worktree with a dedicated branch
# Use the full SHA of the base to avoid conflicts with checked-out branches
BASE_SHA=$(git rev-parse origin/main)
git worktree add ~/.lfx-journeys/<journey-name>/<repo-name> -b journey/<journey-name>/<repo-name> $BASE_SHA
```

**Important:** Use `$BASE_SHA` (not the branch name `main`) to avoid "already checked out" errors.

Record `BASE_SHA` for the manifest.

### Step 6: Merge Branches

In each worktree, merge the selected branches in order:

```bash
cd ~/.lfx-journeys/<journey-name>/<repo-name>

git merge origin/<branch-1> --no-edit
# Check exit code — if non-zero, go to Conflict Resolution
```

For each successful merge, record the branch SHA:

```bash
git rev-parse origin/<branch-name>
```

Report progress: "Merged <branch-name> into <repo-name> worktree."

**If a merge conflict occurs, go to the Conflict Resolution section below.**

### Step 7: Write Manifest

After all merges complete, write the manifest.

**IMPORTANT: The `Write` tool requires an absolute path — `~` will NOT work.** First resolve the home directory:

```bash
echo $HOME
```

Then use the `Write` tool with the **full absolute path**, e.g. `$HOME/.lfx-journeys/<journey-name>/manifest.yaml` (NOT `~/.lfx-journeys/...`).

All paths inside the manifest must also be absolute.

```yaml
name: <journey-name>
description: <journey-name> integration journey
created: <ISO 8601 timestamp>
last_refreshed: <ISO 8601 timestamp>

repos:
  - path: <absolute-repo-path>
    base: main
    base_sha: <sha>
    worktree: <absolute-worktree-path>
    branches:
      - name: <branch-name>
        sha: <sha>
        status: merged
      - name: <branch-name>
        sha: <sha>
        status: skipped
```

### Step 8: Print Summary

Print a clear, actionable summary. The most important thing is telling the user exactly what to do next — the `cd` command they need to run.

```
═══════════════════════════════════════════════════════
JOURNEY READY: <journey-name>
═══════════════════════════════════════════════════════

Branches merged: N/M (S skipped)

To start testing, run:

  cd ~/.lfx-journeys/<journey-name>/<repo-1>/
  <the normal dev server command for this repo, e.g. "yarn start" for Angular>

  cd ~/.lfx-journeys/<journey-name>/<repo-2>/
  <the normal dev server command for this repo>

─── What's next ──────────────────────────────────────

  /lfx-test-journey status                     Check for upstream changes
  /lfx-test-journey refresh <journey-name>     Re-merge with latest branch HEADs
  /lfx-test-journey edit <journey-name>        Add/remove branches
  /lfx-test-journey teardown <journey-name>    Clean up when done

═══════════════════════════════════════════════════════
```

**Important:** Include the full `cd` path for each worktree — do not make the user guess. If the repo is an Angular repo (has `angular.json`), suggest `yarn start`. If it's a Go repo (has `go.mod`), suggest `go run cmd/*/main.go` or the appropriate command.

---

## Conflict Resolution

When `git merge` exits with a non-zero code during create or refresh:

### Step 1: Report the Conflict

```bash
# Show which files have conflicts
git diff --name-only --diff-filter=U

# Show the conflict markers
git diff
```

Present to the user:

```
Merge conflict while merging <branch-name> into <repo-name>:

Conflicting files:
  1. src/app/modules/committees/committee-list.component.ts
  2. src/app/modules/committees/committee.service.ts

[Show the conflicting sections from git diff]
```

### Step 2: Ask the User What to Do

```
AskUserQuestion: "How would you like to handle this?
  1. I'll resolve it — show me the files (skill assists with resolution)
  2. Skip this branch — exclude it from the journey
  3. Abort — cancel the entire journey creation"
```

### Step 3: Handle the Response

**If "resolve" (1):**
- Use `Read` to show the conflicting files
- Let the user guide resolution (they may ask you to pick one side, or edit manually)
- After resolution, run:
  ```bash
  git add <resolved-files>
  git merge --continue
  ```
- Continue with the next branch

**If "skip" (2):**
- Abort the current merge:
  ```bash
  git merge --abort
  ```
- Record the branch as `status: skipped` in the manifest
- Continue with the next branch

**If "abort" (3):**
- Abort the merge:
  ```bash
  git merge --abort
  ```
- Clean up all worktrees created so far:
  ```bash
  cd <repo-path>
  git worktree remove ~/.lfx-journeys/<journey-name>/<repo-name> --force
  git branch -D journey/<journey-name>/<repo-name>
  ```
- Remove the journey directory:
  ```bash
  rm -rf ~/.lfx-journeys/<journey-name>
  ```
- Report: "Journey creation aborted. Everything cleaned up."
- **Stop here.**

---

## Status

Show staleness information for all journeys (or a specific one if named).

### Step 1: Find Journeys

```bash
find ~/.lfx-journeys -maxdepth 2 -name manifest.yaml 2>/dev/null
```

If no journeys found: "No active journeys. Use `/lfx-test-journey create` to start one."

If a specific journey was named, filter to just that one.

### Step 2: Fetch Latest Refs

For each repo referenced in the manifest(s):

```bash
cd <repo-path>
git fetch --all --prune
```

### Step 3: Compare SHAs

For each journey, read the manifest and compare:

**Branch staleness:**
```bash
cd <repo-path>
# Current SHA of the branch
CURRENT_SHA=$(git rev-parse origin/<branch-name> 2>/dev/null)
# Compare with stored SHA from manifest
```

- If branch no longer exists: report as "⚠ branch deleted upstream"
- If SHA matches: "✓ up to date"
- If SHA differs, count new commits:
  ```bash
  git rev-list <stored-sha>..<current-sha> --count
  ```
  Report as "⚠ N new commits"

**Base staleness:**
```bash
CURRENT_BASE=$(git rev-parse origin/main)
# Compare with stored base_sha
```

**Worktree health:**
```bash
# Check if worktree directory exists
ls -d <worktree-path> 2>/dev/null

# Check for uncommitted changes in worktree
cd <worktree-path>
git status --porcelain
```

### Step 4: Render Status

```
<journey-name> (created <relative-time>, refreshed <relative-time>)
  <repo-name>:
    <branch-1>        ✓ up to date
    <branch-2>        ⚠ 2 new commits
    <branch-3>        ✗ skipped
  <repo-name>:
    <branch-4>        ✓ up to date
  Base (main):        ⚠ 5 new commits
  Worktree:           ✓ exists [⚠ has uncommitted changes]

  → Refresh recommended
```

If everything is up to date: "→ All up to date, no refresh needed."

---

## List

Quick manifest-based overview. **No git calls** — this should be fast.

### Step 1: Find Journeys

```bash
find ~/.lfx-journeys -maxdepth 2 -name manifest.yaml 2>/dev/null
```

If no journeys found: "No active journeys. Use `/lfx-test-journey create` to start one."

### Step 2: Read Each Manifest

For each manifest, extract: name, repo count, total branch count, last_refreshed timestamp.

### Step 3: Render List

```
Active journeys:
  committee-onboarding   2 repos, 5 branches   refreshed 4 hours ago
  meeting-redesign       1 repo, 3 branches     refreshed 2 days ago
```

---

## Refresh

Re-merge all branches with their current HEADs.

### Step 1: Load Manifest

Read `~/.lfx-journeys/<journey-name>/manifest.yaml`.

If the journey doesn't exist, list available journeys and ask which one.

### Step 2: Check for Uncommitted Changes

For each repo worktree:

```bash
cd <worktree-path>
git status --porcelain
```

If any worktree has uncommitted changes:

```
AskUserQuestion: "Worktree for <repo-name> has uncommitted changes that will be lost on refresh:
  M src/app/modules/committees/list.component.ts
  M src/app/modules/committees/list.component.html

What would you like to do?
  1. Continue — discard changes and refresh
  2. Stash — save changes before refreshing (git stash)
  3. Abort — cancel refresh"
```

**If stash:** `git stash push -m "lfx-journey pre-refresh stash"`
**If abort:** Stop here.

### Step 3: Fetch Latest Refs

For each repo:

```bash
cd <repo-path>
git fetch --all --prune
```

### Step 4: Reset and Re-Merge

For each repo worktree, first check if the worktree directory exists:

```bash
ls -d <worktree-path> 2>/dev/null
```

**If the worktree is missing** (manually deleted), recreate it:

```bash
cd <repo-path>
BASE_SHA=$(git rev-parse origin/main)
git worktree add <worktree-path> -b journey/<journey-name>/<repo-name> $BASE_SHA
```

If the branch already exists (from a previous creation), force-reset it:

```bash
cd <repo-path>
git worktree remove <worktree-path> --force 2>/dev/null || true
git branch -D journey/<journey-name>/<repo-name> 2>/dev/null || true
BASE_SHA=$(git rev-parse origin/main)
git worktree add <worktree-path> -b journey/<journey-name>/<repo-name> $BASE_SHA
```

**If the worktree exists**, reset it:

```bash
cd <worktree-path>

# Reset to current base
git reset --hard origin/main
```

Then merge all branches (except `skipped`) in order, same as Create → Step 6.

**Handle conflicts the same way as Conflict Resolution above.**

### Step 5: Update Manifest

Update the manifest with new SHAs and `last_refreshed` timestamp.

```bash
# Get new base SHA
cd <repo-path>
git rev-parse origin/main
```

Update each branch SHA and the base_sha in the manifest. Write using the `Write` tool with the **full absolute path** (not `~`).

### Step 6: Report

```
Journey "<journey-name>" refreshed!

<repo-1>: N branches merged
<repo-2>: N branches merged (S skipped)

Last refreshed: just now
```

---

## Edit

Add or remove branches from an existing journey.

### Step 1: Load Manifest

Read `~/.lfx-journeys/<journey-name>/manifest.yaml`.

If the journey doesn't exist, list available journeys and ask which one.

### Step 2: Show Current State

Present the current journey branches as a numbered list:

```
Journey "committee-onboarding" currently includes:

lfx-v2-ui:
  1. feat/committee-list (merged)
  2. feat/committee-detail (merged)
  3. feat/committee-invite-drawer (skipped)

lfx-v2-committee-service:
  4. feat/invite-endpoint (merged)
  5. feat/role-permissions (merged)
```

### Step 3: Ask What to Change

```
AskUserQuestion: "What would you like to do?
  1. Add branches
  2. Remove branches (type numbers, e.g. '3, 5')
  3. Reorder merge sequence
  4. Add a new repo
  5. Done — refresh with changes"
```

**If add branches (1):**
- Run the branch discovery flow (Create → Steps 2-3) for the relevant repo(s)
- Let the user pick from discovered branches
- Add them to the manifest

**If remove branches (2):**
- Parse the numbers
- Remove those branches from the manifest

**If reorder (3):**
- Show the current merge order as a numbered list per repo
- Ask the user to type the new order (e.g., "3, 1, 2" to move branch 3 first)
- Update the branch order in the manifest

**If add new repo (4):**
- Run the full repo + branch discovery flow (Create → Steps 1-3)
- Add the new repo and its branches to the manifest

**If done (5):**
- Proceed to Step 4

Allow the user to make multiple changes (loop back to Step 3) until they choose "Done".

### Step 4: Refresh

After edits are complete, trigger an automatic refresh (go to **Refresh** flow) to rebuild the worktrees with the updated branch set.

---

## Teardown

Remove a journey's worktrees and manifest.

### Step 1: Identify Journey

If the user provided a journey name, use it. Otherwise, run **List** and ask which one.

### Step 2: Confirm

```
AskUserQuestion: "This will remove the journey 'committee-onboarding' and all its worktrees:
  ~/.lfx-journeys/committee-onboarding/lfx-v2-ui/
  ~/.lfx-journeys/committee-onboarding/lfx-v2-committee-service/

Proceed? (yes/no)"
```

### Step 3: Remove Worktrees

For each repo in the manifest:

```bash
cd <repo-path>

# Remove the worktree
git worktree remove <worktree-path> --force

# Delete the journey branch
git branch -D journey/<journey-name>/<repo-name>
```

If a worktree doesn't exist (already manually deleted), skip it without error:

```bash
git worktree remove <worktree-path> --force 2>/dev/null || true
git branch -D journey/<journey-name>/<repo-name> 2>/dev/null || true
```

### Step 4: Clean Up Files

```bash
rm -rf ~/.lfx-journeys/<journey-name>
```

### Step 5: Confirm

```
Journey "committee-onboarding" cleaned up.
  - 2 worktrees removed
  - 2 journey branches deleted
  - Manifest deleted
```
