#!/bin/bash
set -e

# Regenerate READMEs and ensure the repo stays clean.
bash scripts/gen_readme.sh

if ! git diff --quiet; then
  echo "Build gate failed: READMEs are out of date."
  echo "Run 'bash scripts/gen_readme.sh' and commit the changes."
  git diff --stat
  exit 1
fi

echo "READMEs are up to date"

