#!/bin/bash
# Reset src/modules/blocks to a clean Dart package layout.

set -euo pipefail

cd "$(dirname "$0")/.."

# Clean root-level dart files in src/modules/blocks
rm -f src/modules/blocks/*.dart || true

# Replace lib directory with a clean copy from packages/itermremote_blocks
rm -rf src/modules/blocks/lib || true
mkdir -p src/modules/blocks/lib

rsync -a packages/itermremote_blocks/lib/ src/modules/blocks/lib/

echo "Blocks module reset complete"
