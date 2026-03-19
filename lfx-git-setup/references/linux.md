<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# Linux: GPG + DCO Git Setup Guide

This guide covers GPG-signed commits and DCO signoff on Linux. Commands are
shown for the most common distributions. Adjust package manager commands for
your distro.

## Phase 1: Prerequisites

### 1.1 Check your Git version

```bash
git --version
```

You need Git 2.0.0 or newer.

**Install or update Git:**

| Distro          | Command                                   |
| --------------- | ----------------------------------------- |
| Ubuntu / Debian | `sudo apt update && sudo apt install git` |
| Fedora          | `sudo dnf install git`                    |
| Arch Linux      | `sudo pacman -S git`                      |
| openSUSE        | `sudo zypper install git`                 |

### 1.2 Install GPG tools

Most Linux distributions ship with GPG already installed. Verify:

```bash
gpg --version
```

If not installed, or if you need `gpg2`:

| Distro          | Command                   |
| --------------- | ------------------------- |
| Ubuntu / Debian | `sudo apt install gnupg`  |
| Fedora          | `sudo dnf install gnupg2` |
| Arch Linux      | `sudo pacman -S gnupg`    |

> Note: On some distributions, the command is `gpg2` rather than `gpg`. If
> `gpg --version` fails, try `gpg2 --version`. Remember which one works —
> you'll need to tell Git about it in Phase 3.

### 1.3 Install pinentry

Pinentry is the tool that shows the passphrase dialog.

| Distro          | Command                                                                  |
| --------------- | ------------------------------------------------------------------------ |
| Ubuntu / Debian | `sudo apt install pinentry-curses` (terminal) or `pinentry-gnome3` (GUI) |
| Fedora          | `sudo dnf install pinentry`                                              |
| Arch Linux      | `sudo pacman -S pinentry`                                                |

## Phase 2: Generate Your GPG Key

> Important: Use the same email address that is verified on your GitHub
> account. Check at [github.com/settings/emails](https://github.com/settings/emails).

### 2.1 Start key generation

**GPG 2.1.17 or newer (recommended):**

```bash
gpg --full-generate-key
```

**Older GPG versions:**

```bash
gpg --default-new-key-algo rsa4096 --gen-key
```

Check your GPG version with `gpg --version` if you're unsure which command
to use.

### 2.2 Answer the prompts

| Prompt     | Recommended choice                                                |
| ---------- | ----------------------------------------------------------------- |
| Key type   | (1) RSA and RSA (the default)                                     |
| Key size   | 4096                                                              |
| Expiration | 0 (no expiration) — or set an expiry if you prefer                |
| Real name  | Your full name (as it appears on GitHub)                          |
| Email      | Your verified GitHub email address                                |
| Comment    | Leave blank (just press Enter)                                    |
| Passphrase | Optional, but recommended — choose a strong, memorable passphrase |

### 2.3 Find your key ID

```bash
gpg --list-secret-keys --keyid-format=long
```

If you're on a system where `gpg2` is the command:

```bash
gpg2 --list-secret-keys --keyid-format=long
```

You'll see output like:

```text
sec   rsa4096/3AA5C34371567BD2 2024-01-15 [SC]
      ABCDEF1234567890ABCDEF1234567890ABCDEF12
uid           [ultimate] Your Name <you@example.com>
```

Your **key ID** is the value after the `/` on the `sec` line:
`3AA5C34371567BD2`

## Phase 3: Configure Git

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

### 3.3 Make sure your name and email match

```bash
git config --global user.name "Your Full Name"
git config --global user.email "your-github-email@example.com"
```

### 3.4 If your system uses `gpg2` instead of `gpg`

Tell Git to use `gpg2`:

```bash
git config --global gpg.program gpg2
```

### 3.5 Set GPG_TTY in your shell profile

This is required for the passphrase prompt to appear correctly in terminal
sessions.

**For bash:**

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc
source ~/.bashrc
```

**For zsh:**

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.zshrc
source ~/.zshrc
```

### 3.6 Configure gpg-agent (optional but recommended)

```bash
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Set a passphrase cache timeout if not already set (86400 = 24 hours, adjust as you like)
grep -q "default-cache-ttl" ~/.gnupg/gpg-agent.conf 2>/dev/null || cat >> ~/.gnupg/gpg-agent.conf << 'EOF'
default-cache-ttl 86400
max-cache-ttl 86400
EOF

# Reload the agent
gpgconf --kill gpg-agent
```

### 3.7 Verify your ~/.gitconfig looks right

```bash
cat ~/.gitconfig
```

Expected output:

```ini
[user]
    name = Your Name
    email = you@example.com
    signingkey = 3AA5C34371567BD2
[commit]
    gpgSign = true
[tag]
    gpgSign = true
```

## Phase 4: Register Your Key with GitHub

### 4.1 Export your public key

```bash
gpg --armor --export 3AA5C34371567BD2
```

Or use `gpg2 --armor --export ...` if you're using `gpg2`.

Copy the full output — from `-----BEGIN PGP PUBLIC KEY BLOCK-----` through
`-----END PGP PUBLIC KEY BLOCK-----`, inclusive.

### 4.2 Add the key to GitHub

1. Go to [github.com/settings/keys](https://github.com/settings/keys)
2. Click **"New GPG key"**
3. Give it a descriptive name (e.g., "Linux Workstation - Home")
4. Paste your public key block into the **"Key"** field
5. Click **"Add GPG key"**
6. Confirm with your GitHub password if prompted

## Phase 5: Verify Everything Works

### 5.1 Test in a repository

```bash
# Create a temporary test repo
cd /tmp && git init test-signing && cd test-signing

# Test commit (DCO signoff + GPG sign)
git commit -s --allow-empty -m "test: verify DCO and GPG signing"
```

If a passphrase was set on the signing key, enter your passphrase when prompted.

### 5.2 Confirm the signature

```bash
git log --show-signature -1
```

Good output looks like:

```text
gpg: Signature made Tue Jan 15 10:00:00 2024 UTC
gpg:                using RSA key 3AA5C34371567BD2
gpg: Good signature from "Your Name <you@example.com>"
```

The commit message should include:

```text
Signed-off-by: Your Name <you@example.com>
```

## Troubleshooting on Linux

### Common issues

#### "gpg: signing failed: Inappropriate ioctl for device"

```bash
export GPG_TTY=$(tty)
```

Add this to your `~/.bashrc` or `~/.zshrc` permanently.

#### "gpg failed to sign the data" / passphrase prompt doesn't appear

```bash
gpgconf --kill gpg-agent
export GPG_TTY=$(tty)
```

Try the commit again. If it still fails, check that `pinentry` is installed.

#### "No secret key" / "secret key not available"

1. Run `gpg --list-secret-keys --keyid-format=long` again
2. Copy the exact key ID
3. Re-run: `git config --global user.signingkey <YOUR_KEY_ID>`

#### On servers / SSH sessions (no TTY)

Use `pinentry-curses` and ensure `SSH_TTY` is set:

```bash
export GPG_TTY=${SSH_TTY:-$(tty)}
```

#### Key generated but GitHub shows "Unverified"

- Verify the email on the GPG key matches a verified email on your GitHub
  account
- Check at [github.com/settings/emails](https://github.com/settings/emails)
- If needed, add the correct email to your key:
  `gpg --edit-key YOUR_KEY_ID` → `adduid`

#### "gpg: WARNING: unsafe permissions on homedir '/home/user/.gnupg'"

```bash
# 700 on directories
find ~/.gnupg -type d -exec chmod 700 {} \;
# 600 on files
find ~/.gnupg -type f -exec chmod 600 {} \;
```
