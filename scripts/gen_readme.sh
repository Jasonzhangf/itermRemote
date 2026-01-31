#!/bin/bash
set -e

# Generate README.md for each module. CI will verify the output is committed.

MODULES=("packages/cloudplayplus_core" "packages/iterm2_host" "apps/android_client")

for module in "${MODULES[@]}"; do
  if [ -d "$module" ]; then
    echo "Generating README for $module..."
    dart run scripts/gen_readme.dart "$module" > "$module/README.md"
  fi
done

echo "README generation done"

