#!/bin/bash
set -e

# Check for untracked files in specific directories.
UNTRACKED=$(git ls-files --others --exclude-standard | grep -E '^(packages/|apps/)' || true)

if [ -n "$UNTRACKED" ]; then
  echo "Build gate failed: Untracked files found in tracked directories:"
  echo "$UNTRACKED"
  echo ""
  echo "Please either:"
  echo "  1. Add these files with 'git add'"
  echo "  2. Add to .gitignore if they should not be tracked"
  echo "  3. Move to build/ or other ignored directory"
  exit 1
fi

echo "No untracked files in tracked directories"

