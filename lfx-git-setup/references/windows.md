<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Windows: GPG + DCO Git Setup Guide

> **Most LFX contributors on Windows use WSL2 (Windows Subsystem for Linux).**
> If that's you, follow the Linux guide instead (`references/linux.md`) —
> your WSL2 environment is a real Linux environment and all Linux steps apply.
>
> This guide covers **native Windows** (using Git Bash or PowerShell).

---

## Two Paths on Windows

### Path A: WSL2 (Strongly Recommended)

WSL2 gives you a full Linux environment running inside Windows. It's the
preferred setup for LFX contributors on Windows because:

- The tooling is identical to Linux
- It avoids many Windows-specific GPG quirks
- Most LFX documentation assumes a Unix-like environment

**To use WSL2:** Install WSL2
([docs.microsoft.com/en-us/windows/wsl/install](https://docs.microsoft.com/en-us/windows/wsl/install)),
then follow `references/linux.md`.

### Path B: Native Windows (Git Bash + Gpg4win)

If you need or prefer a native Windows setup, continue below.

---

## Phase 1: Prerequisites

### 1.1 Install Git for Windows

Download from [git-scm.com](https://git-scm.com/download/win). During
installation:

- Select **"Git Bash Here"** context menu option
- Use the default options unless you have a specific reason to change them

### 1.2 Install Gpg4win

Download from [gpg4win.org](https://www.gpg4win.org). This installs:

- `gpg` command-line tools
- **Kleopatra** — a graphical key manager (useful for non-technical users)
- Integration with Windows credential storage

During installation, install **Kleopatra** — it makes key management much
easier.

### 1.3 Verify installations

Open **Git Bash** (not Command Prompt or PowerShell — use Git Bash for all
commands):

```bash
git --version
gpg --version
```

Both should return version numbers.

---

## Phase 2: Generate Your GPG Key

> Use the same email address that is verified on your GitHub account.
> Check at [github.com/settings/emails](https://github.com/settings/emails).

### Option A: Using Kleopatra (graphical — easier for non-technical users)

1. Open **Kleopatra**
2. Click **"New Key Pair"**
3. Choose **"Create a personal OpenPGP key pair"**
4. Enter your name and the email address from your GitHub account
5. Set a strong passphrase
6. Click **"Create"**

After creation, right-click your key in Kleopatra → **"Details"** to find your
key ID (fingerprint).

### Option B: Command line in Git Bash

```bash
gpg --full-generate-key
```

Answer the prompts:

| Prompt | Recommended choice |
| --- | --- |
| Key type | `(1) RSA and RSA` |
| Key size | `4096` |
| Expiration | `0` (no expiration) |
| Real name | Your full name |
| Email | Your verified GitHub email |
| Comment | Leave blank |
| Passphrase | Optional, but recommended — choose a strong, memorable passphrase |

Find your key ID:

```bash
gpg --list-secret-keys --keyid-format=long
```

The key ID is after the `/` on the `sec` line (e.g., `3AA5C34371567BD2`).

---

## Phase 3: Configure Git

Open **Git Bash** and run these commands:

### 3.1 Set your signing key

```bash
git config --global user.signingkey 3AA5C34371567BD2
```

Replace this with your actual key ID.

### 3.2 Enable automatic GPG signing

```bash
git config --global commit.gpgSign true
git config --global tag.gpgSign true
```

### 3.3 Set your name and email

```bash
git config --global user.name "Your Full Name"
git config --global user.email "your-github-email@example.com"
```

### 3.4 Point Git at the correct gpg executable

On Windows, Git may not find `gpg` automatically. In **Git Bash**, locate
the Gpg4win installation with:

```bash
command -v gpg
```

> **Note:** `where gpg` is a CMD built-in and may not be available in Git
> Bash. Use `where.exe gpg` if you need the Windows equivalent, or stick with
> `command -v gpg` in Git Bash.

A common path is `C:/Program Files (x86)/GnuPG/bin/gpg.exe`. Tell Git:

```bash
git config --global gpg.program "$(command -v gpg)"
```

Or if you know the exact path, set it explicitly:

```bash
git config --global gpg.program "C:/Program Files (x86)/GnuPG/bin/gpg.exe"
```

### 3.5 Verify ~/.gitconfig

```bash
cat ~/.gitconfig
```

Should look like:

```ini
[user]
    name = Your Name
    email = you@example.com
    signingkey = 3AA5C34371567BD2
[commit]
    gpgSign = true
[tag]
    gpgSign = true
[gpg]
    program = C:/Program Files (x86)/GnuPG/bin/gpg.exe
```

---

## Phase 4: Register Your Key with GitHub

### 4.1 Export your public key

**Using Kleopatra:**

1. Select your key in Kleopatra
2. Click **"Export..."**
3. Save the `.asc` file and open it in Notepad
4. Copy all the text

**Using Git Bash:**

```bash
gpg --armor --export 3AA5C34371567BD2
```

Copy the full block including `-----BEGIN PGP PUBLIC KEY BLOCK-----` and
`-----END PGP PUBLIC KEY BLOCK-----`.

### 4.2 Add to GitHub

1. Go to [github.com/settings/keys](https://github.com/settings/keys)
2. Click **"New GPG key"**
3. Give it a name (e.g., "Windows Laptop")
4. Paste your public key block
5. Click **"Add GPG key"**

---

## Phase 5: Verify Everything Works

In **Git Bash**:

```bash
cd /tmp && git init test-signing && cd test-signing
git commit -s --allow-empty -m "test: verify DCO and GPG signing"
git log --show-signature -1
```

---

## Troubleshooting on Windows

### Common issues

#### "gpg: signing failed: No secret key"

Make sure the `gpg.program` path in `.gitconfig` is correct and points to the
Gpg4win installation. Run `command -v gpg` in Git Bash to confirm the path.

#### Passphrase prompt never appears

Gpg4win includes Kleopatra's Pinentry. Make sure Kleopatra is running (it can
run minimized in the system tray). If not, open Kleopatra and try again.

#### "error: gpg failed to sign the data"

Try running Git Bash as Administrator once to sign a test commit. If that
works, the issue is permissions. Contact your IT team if you can't run as
Administrator.

#### Commits not showing as "Verified" on GitHub

Check that the email on your GPG key exactly matches a verified email on
GitHub. In Kleopatra, you can see the email associated with each key under
"Details".

#### Using VS Code or another GUI editor on Windows

Git GUIs on Windows sometimes don't inherit the Git Bash environment. If
signing fails in a GUI but works in Git Bash, note that `GPG_TTY` usually is
not needed on Windows, but the `gpg.program` path should still be set globally
in `.gitconfig`.

---

## Note for Teams with Windows Developers

If your team has Windows developers who are struggling with native GPG setup,
strongly consider recommending **WSL2** instead. The Linux setup path is more
reliable, better documented, and more consistent with the CI environment where
DCO and signature checks run.
