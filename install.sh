#!/usr/bin/env bash
# Copyright The Linux Foundation and each contributor to LFX.
# SPDX-License-Identifier: MIT

# LFX Skills Installer
# Symlinks all LFX skills into ~/.claude/skills/ so they're available globally in your AI coding assistant.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

echo "Installing LFX skills..."
echo ""

# Create the skills directory if it doesn't exist
mkdir -p "$SKILLS_DIR"

# Track results
installed=0
updated=0
failed=0

# Install each skill directory (lfx-* and lfx/)
for skill_path in "$SCRIPT_DIR"/lfx-*/ "$SCRIPT_DIR"/lfx/; do
  [ -d "$skill_path" ] || continue

  skill_name="$(basename "$skill_path")"
  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    # Symlink exists — update it
    rm "$target"
    ln -s "$skill_path" "$target"
    echo "  Updated  $skill_name"
    updated=$((updated + 1))
  elif [ -e "$target" ]; then
    # Something else exists at the target path
    echo "  Skipped  $skill_name (non-symlink already exists at $target)"
    failed=$((failed + 1))
  else
    ln -s "$skill_path" "$target"
    echo "  Installed  $skill_name"
    installed=$((installed + 1))
  fi
done

echo ""
echo "Done! $((installed + updated)) skills ready ($installed new, $updated updated)."

if [ $failed -gt 0 ]; then
  echo "$failed skills skipped due to conflicts — check the paths above."
fi

echo ""
echo "Next steps:"
echo "  1. Restart your AI coding assistant (or open a new session)"
echo "  2. Type /lfx to get started"
echo ""
echo "Available skills:"
for skill_path in "$SKILLS_DIR"/lfx*; do
  [ -e "$skill_path" ] || continue
  echo "  /$(basename "$skill_path")"
done
