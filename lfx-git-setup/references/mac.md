<!-- Copyright The Linux Foundation and each contributor to LFX. -->
<!-- SPDX-License-Identifier: MIT -->

# macOS: GPG + DCO Git Setup Guide

This guide walks you through setting up GPG-signed commits and DCO signoff on
macOS. You'll use **Homebrew** (the standard macOS package manager) and
optionally **GPG Suite** for a better experience with passphrases.

## Phase 1: Prerequisites

### 1.1 Check your Git version

```bash
git --version
```

You need Git 2.0.0 or newer. If you're below that, update Git first:

```bash
brew install git
```

### 1.2 Install GPG

#### Option A — GPG Suite (recommended for non-technical users)

Download from [gpgtools.org](https://gpgtools.org). This installs:

- `gpg` command-line tools
- A macOS Keychain integration so you don't need to re-enter your passphrase
  every time
- A graphical key manager app

#### Option B — Homebrew (recommended for developers)

```bash
brew install gnupg pinentry-mac
```

Then configure pinentry (the tool that shows passphrase prompts) so it works
on macOS:

```bash
mkdir -p ~/.gnupg
grep -q "pinentry-program" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
  echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
chmod 700 ~/.gnupg
```

Restart the GPG agent:

```bash
gpgconf --kill gpg-agent
```

### 1.3 Verify GPG is installed

```bash
gpg --version
```

You should see version output. GPG 2.1.17 or newer is recommended.

## Phase 2: Generate Your GPG Key

> Important: Use the same email address that is verified on your GitHub
> account. If you're not sure, check at
> [github.com/settings/emails](https://github.com/settings/emails).

### 2.1 Start Key Generation

```bash
gpg --full-generate-key
```

If your GPG version is older (before 2.1.17), use this instead:

```bash
gpg --default-new-key-algo rsa4096 --gen-key
```

### 2.2 Answer the Prompts

When asked, select these options:

| Prompt     | Recommended choice                                                |
| ---------- | ----------------------------------------------------------------- |
| Key type   | (1) RSA and RSA (the default)                                     |
| Key size   | 4096                                                              |
| Expiration | 0 (no expiration) — or set 1–2 years if you prefer                |
| Real name  | Your full name (as it appears on GitHub)                          |
| Email      | Your verified GitHub email address                                |
| Comment    | Leave blank (just press Enter)                                    |
| Passphrase | Optional, but recommended — choose a strong, memorable passphrase |

Confirm the info looks correct when prompted.

### 2.3 Find your key ID

```bash
gpg --list-secret-keys --keyid-format=long
```

Look for output like this:

```text
sec   rsa4096/3AA5C34371567BD2 2024-01-15 [SC]
      ABCDEF1234567890ABCDEF1234567890ABCDEF12
uid           [ultimate] Your Name <you@example.com>
```

Your **key ID** is the part after the `/` on the `sec` line: `3AA5C34371567BD2`

## Phase 3: Configure Git

### 3.1 Set Your Signing Key

```bash
git config --global user.signingkey 3AA5C34371567BD2
```

Use your actual key ID from Phase 2.

### 3.2 Enable Automatic GPG Signing for All Commits

```bash
git config --global commit.gpgSign true
git config --global tag.gpgSign true
```

### 3.3 Make Sure Your Name and Email Match

```bash
git config --global user.name "Your Full Name"
git config --global user.email "your-github-email@example.com"
```

### 3.4 Set GPG_TTY in Your Shell Profile

This ensures the passphrase prompt appears correctly in your terminal.

**For zsh (default on macOS Ventura and later):**

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.zshrc
source ~/.zshrc
```

**For bash:**

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.bash_profile
source ~/.bash_profile
```

### 3.5 Verify Your ~/.gitconfig Looks Right

```bash
cat ~/.gitconfig
```

You should see something like:

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

### 4.1 Export Your Public Key

```bash
gpg --armor --export 3AA5C34371567BD2
```

Use your actual key ID. This prints a block that looks like:

```text
-----BEGIN PGP PUBLIC KEY BLOCK-----
...lots of characters...
-----END PGP PUBLIC KEY BLOCK-----
```

Copy **everything** including the `-----BEGIN` and `-----END` lines.

### 4.2 Add the Key to GitHub

1. Go to [github.com/settings/keys](https://github.com/settings/keys)
2. Click **"New GPG key"**
3. Give it a name (e.g., "My MacBook - Work")
4. Paste your public key block into the **"Key"** field
5. Click **"Add GPG key"**
6. Confirm with your GitHub password if prompted

## Phase 5: Verify Everything Works

### 5.1 Test signing in a repo

```bash
# Go into any git repository (or create one for testing)
cd /tmp && git init test-signing && cd test-signing

# Make a test commit with both DCO signoff (-s) and GPG signature (-S)
# (with commit.gpgSign=true, -S is automatic — but you can add it explicitly)
git commit -s --allow-empty -m "test: verify DCO and GPG signing"
```

Enter your GPG passphrase when prompted.

### 5.2 Verify the Signature

```bash
git log --show-signature -1
```

You should see:

```text
gpg: Signature made Tue Jan 15 10:00:00 2024 PST
gpg:                using RSA key 3AA5C34371567BD2
gpg: Good signature from "Your Name <you@example.com>"
```

And the commit message body should contain:

```text
Signed-off-by: Your Name <you@example.com>
```

## Troubleshooting on macOS

### Common Issues

#### "error: gpg failed to sign the data"

```bash
export GPG_TTY=$(tty)
gpgconf --kill gpg-agent
```

Then try committing again.

#### Passphrase Prompt Never Appears

If you installed via Homebrew, make sure `pinentry-mac` is configured. The
command below adds the setting only if it isn't already present — it will not
overwrite other settings in your `gpg-agent.conf`:

```bash
grep -q "pinentry-program" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
  echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

> **Note:** If you want to fully reset `~/.gnupg/gpg-agent.conf` (for example,
> because it contains conflicting settings), back it up first:
> `cp ~/.gnupg/gpg-agent.conf ~/.gnupg/gpg-agent.conf.bak`

#### "No secret key" error

Verify your signing key matches exactly what
`gpg --list-secret-keys --keyid-format=long` shows.

#### GPG Suite passphrase stored in Keychain but not working

Open "GPG Keychain" app, find your key, right-click → "Change Passphrase".
Sometimes clearing and resetting the Keychain entry resolves issues.
