<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# LFX Quickstart Examples

Three real workflow examples showing how to use `/lfx` from start to finish.

---

## Example 1: "Add a field to committee members"

**Scenario:** You want committee members to have a bio field that appears on their profile card and can be edited in the member form.

### What you type:

```
/lfx
Add a bio field to committee members
```

### What happens:

**LFX detects your environment:**
> I can see you're working in the lfx-v2-ui repository (Angular frontend).
> You're on the main branch with no uncommitted changes.

**LFX routes to the coordinator and presents a plan:**
> Here's what I'm going to do:
> 1. Add the "bio" data field to the committee Go service
> 2. Update the shared data definitions so both frontend and backend know about it
> 3. Add a bio text input to the member edit form
> 4. Display the bio on the member profile card
>
> Shall I proceed?

**You say:** yes

**LFX builds everything in parallel, then reports:**
> **What was done:**
> - Committee members now have a bio text field
> - The bio appears on the member profile card
> - The bio can be edited in the member form
>
> **What happens next:**
> - Run `/lfx-preflight` to validate your changes
> - Create a pull request for code review

**You say:** run preflight

**LFX validates and reports:**
> Your changes look good and are ready for review!
> All checks passed: formatting, linting, build, and license headers.
> Would you like me to create the pull request?

---

## Example 2: "Understand how meeting data works"

**Scenario:** You want to understand the data flow for meetings before planning a new feature.

### What you type:

```
/lfx
How does the meeting data flow work?
```

### What happens:

**LFX routes to the product architect:**
> Here's how meeting data flows through the system:
>
> **When a user views meetings:**
> 1. The Angular frontend calls `/api/meetings/...`
> 2. The Express proxy forwards this to the meeting Go service
> 3. For listing/searching, it actually goes to the query service, which reads from OpenSearch (a search engine that has indexed copies of meeting data)
>
> **When a user creates or edits a meeting:**
> 1. The frontend sends the data to the Express proxy
> 2. The proxy forwards to the meeting Go service
> 3. The Go service saves it and sends a message via NATS (the messaging system)
> 4. Other services react: the indexer updates OpenSearch, the permissions system updates access rules
>
> **Key files:**
> - Frontend components: `apps/lfx-one/src/app/modules/meetings/`
> - Express proxy: `apps/lfx-one/src/server/services/meeting.service.ts`
> - Go service: `lfx-v2-meeting-service` (separate repo)

**You say:** Great, now I want to add an attendance tracking feature to meetings

**LFX routes to the coordinator** and starts the build workflow.

---

## Example 3: "Check if my changes are ready"

**Scenario:** You've made some changes (or a skill made them for you) and want to make sure everything is good before submitting a pull request.

### What you type:

```
/lfx
Are my changes ready for a PR?
```

### What happens:

**LFX runs preflight validation:**
> Checking your changes...
>
> **Your changes look good and are ready for review!**
>
> - Formatting: All files properly formatted
> - Linting: No errors found
> - Build: Succeeded
> - License headers: All present (2 were auto-fixed)
> - Protected files: None modified
> - Commits: Properly signed off with JIRA reference
>
> Auto-fixes applied:
> - Added license headers to 2 new files
>
> Would you like me to commit the auto-fixes and create the pull request?

**If something is wrong:**
> Found 2 issues that need attention:
>
> 1. **Build error**: The `MemberCardComponent` is trying to use `member.bio` but the import for the updated interface is missing. I can fix this automatically.
> 2. **Missing signoff**: Your last commit doesn't have a `Signed-off-by` line. You'll need to amend it with `git commit --amend --signoff`.
>
> Want me to fix issue #1 automatically?

---

## Tips

- **You don't need to know which skill to use.** Just describe what you want to `/lfx` and it figures out the right workflow.
- **You don't need to provide technical details.** The system auto-detects your repo, branch, and domain.
- **You can chain workflows.** After building, say "check my changes" to run preflight. After preflight, say "create the PR."
- **If you see unfamiliar terms,** just ask: "What does Goa mean?" or "What's a protected file?" and LFX will explain in plain language.
