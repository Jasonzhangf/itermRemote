#!/bin/bash
set -euo pipefail

# Build gate: fail if there are untracked files under apps/ or packages/.
# This enforces deterministic builds and avoids "works on my machine" artifacts.

UNTRACKED=$(/usr/bin/git ls-files --others --exclude-standard -- apps packages || true)

if [[ -n "$UNTRACKED" ]]; then
  echo "Build gate failed: Untracked files found under apps/ or packages/:"
  echo "$UNTRACKED"
  echo ""
  echo "Fix by either:"
  echo "  1) /usr/bin/git add <files>"
  echo "  2) Add ignores to .gitignore (only for true build artifacts)"
  exit 1
fi

echo "No untracked files under apps/ or packages/"

