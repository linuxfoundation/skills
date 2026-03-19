---
name: lfx-git-setup
description: >
  Interactive setup guide for LFX contributors to configure Git for DCO signoff
  and GPG-signed commits. Use this skill whenever someone asks about setting up
  Git signing, DCO signoff, GPG keys for commits, configuring `~/.gitconfig` for
  signing, adding a GPG key to GitHub, or any variation of “how do I sign my
  commits?”. Also trigger it when a user says their commits aren’t showing as
  “Verified” on GitHub, when they’re onboarding to an LFX project and need to
  meet contribution requirements, or when they ask about `git commit -s`,
  `--signoff`, `Signed-off-by`, or `commit.gpgSign`. This skill works for
  technical and non-technical users alike.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, WebFetch
---

<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# LFX git Setup: DCO Signoff & GPG Signed Commits

This skill walks contributors through two essential Git contribution
requirements used across Linux Foundation projects:

1. **DCO Signoff** (`--signoff` / `-s`) — Adds a `Signed-off-by: Your Name
   <email>` line to every commit, certifying you wrote the code and have the
   right to contribute it under the project's license. This is a legal
   agreement, not just a formality.
2. **GPG Signed Commits** (`-S`) — Cryptographically signs each commit with
   your personal GPG key so GitHub can display a green "Verified" badge,
   proving the commit genuinely came from you.

## Your First Step: Detect the User's Platform

Before doing anything else, check what operating system the user is on. The
steps are meaningfully different across platforms.

Ask the user (or check their context):

- **macOS** → Read `references/mac.md` for the full walkthrough
- **Linux** (Ubuntu, Fedora, Debian, Arch, etc.) → Read `references/linux.md`
- **Windows** → Read `references/windows.md` — note this is a supported but
  less common setup path; WSL2 (Windows Subsystem for Linux) users should
  follow Linux steps

If it's unclear which platform they're on, just ask: "What operating system
are you using — Mac, Linux, or Windows?"

## Overall Workflow (all platforms)

The end goal is a `~/.gitconfig` that looks roughly like this:

```ini
[user]
    name = your full name
    email = your-github-verified-email@example.com
    signingkey = abc123def456  # your gpg key id

[commit]
    gpgSign = true             # auto-sign every commit with -s

[tag]
    gpgSign = true             # auto-sign tags too
```

and a GPG key that:

- was generated with the same email address as your github account
- has its **public key** uploaded to GitHub (settings → ssh and gpg keys)

The DCO signoff (`-s`) is handled separately — see the **DCO signoff** section below.

### The Four Phases

- **phase 1 — Prerequisites**: install gpg tools and verify git version.
- **phase 2 — Generate GPG key**: create your personal signing key.
- **phase 3 — Configure git**: wire the key into `~/.gitconfig`.
- **phase 4 — Register with GitHub**: upload your public key so github can verify.

Each platform reference file covers all four phases with exact commands.

## DCO signoff

The DCO (`--signoff` or `-s`) flag is separate from gpg signing. it adds this line to your commit message:

```text
Signed-off-by: your name <your-email@example.com>
```

### Option A: Always Sign Off Manually (simplest)

```bash
git commit -s -S -m "your commit message"
```

Both flags together: `-s` for the DCO signoff, `-S` for the GPG signature.

### Option B: git alias (recommended for convenience)

Add a `c` shortcut (or something you will remember) to `~/.gitconfig` so `git c
-m "..."` does both automatically:

An example would be:

```bash
git config --global alias.c 'commit -s -S'
```

Then use: `git c -m "your commit message"`

### Option C: Global Commit Hook (fully automatic)

This approach automatically appends `Signed-off-by` to every commit message,
even in GUI tools:

```bash
# create global hooks directory
mkdir -p ~/.git-hooks

# create the hook script
cat > ~/.git-hooks/prepare-commit-msg << 'eof'
#!/bin/sh
# Auto-add DCO signed-off-by line
SOB=$(git var GIT_AUTHOR_IDENT | sed -n 's/^\(.*>\).*$/Signed-off-by: \1/p')
grep -Fqs "$SOB" "$1" || echo "$SOB" >> "$1"
eof

# Make the git hook executable
chmod +x ~/.git-hooks/prepare-commit-msg

# Tell git to use this global hooks directory
git config --global core.hookspath ~/.git-hooks
```

> ⚠️ Note: the global hook applies to ALL repositories on your machine. If you
> work on non-lfx projects, you may prefer option A or B instead.

## Verifying Everything Works

Once setup is complete, do a test commit:

```bash
# in any git repository
git commit -s -S --allow-empty -m "test: verify DCO and gpg signing setup"
git log --show-signature -1
```

You should see:

- `gpg: good signature from "your name <email>"` in the output
- a `Signed-off-by:` line in the commit message

On GitHub, after pushing, the commit will show a green **verified** badge.

## Troubleshooting Quick Reference

| problem                                    | likely cause                    | fix                                                                                               |
| ------------------------------------------ | ------------------------------- | ------------------------------------------------------------------------------------------------- |
| `error: gpg failed to sign the data`       | GPG agent issue                 | Run `export GPG_TTY=$(tty)` (macOS/Linux) and retry; on Windows, see the platform reference       |
| No Verified badge on GitHub                | key not uploaded or wrong email | Check key email matches GitHub verified email                                                     |
| `secret key not available`                 | key ID mismatch                 | Re-run `git config --global user.signingkey <ID>`                                                 |
| DCO check failing in CI                    | missing `Signed-off-by`         | Amend last commit: `git commit --amend -s`                                                        |
| GPG prompts not appearing                  | missing pinentry                | See platform reference file for pinentry setup                                                    |
| `gpg: signing failed: Inappropriate ioctl` | TTY not set                     | Add `export GPG_TTY=$(tty)` to your shell profile (macOS/Linux); on Windows, see platform ref     |

## Platform Reference Files

- **macos**: `references/mac.md`
- **linux**: `references/linux.md`
- **windows / wsl2**: `references/windows.md`

Read the appropriate file based on the user's OS before walking them through
setup.

## Communication Style

This skill serves both technical and non-technical users. Adjust your tone:

- If the user is clearly a developer (mentions terminal, dotfiles, brew, apt,
  etc.), go straight to commands with brief explanations.
- If the user seems newer to the command line, explain what each command _does_
  before showing it, and reassure them that these are one-time setup steps.
- Never assume the user knows what GPG, DCO, or `~/.gitconfig` are — briefly
  define each on first mention.
- After each phase, confirm it worked before moving on. ask: "Did that complete
  without errors?" before proceeding.
