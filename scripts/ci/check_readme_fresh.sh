


#!/bin/bash
set -e

# Regenerate READMEs and ensure the repo stays clean.
bash scripts/gen_readme.sh

# Only check README.md files, ignore other transient changes (e.g. .dart_tool)
if ! git diff --quiet -- '**/README.md'; then
  echo "Build gate failed: READMEs are out of date."
  echo "Run 'bash scripts/gen_readme.sh' and commit the changes."
  git diff -- '**/README.md'
  exit 1
fi

echo "READMEs are up to date"
