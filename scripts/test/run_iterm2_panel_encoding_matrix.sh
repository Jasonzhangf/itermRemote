#!/bin/bash
# Run iTerm2 panel encoding/bitrate matrix verification on macOS.
#
# Usage:
#   ITERM2_PANEL_TITLE=1.1.8 FPS_LIST=60,30,15 BITRATE_KBPS_LIST=2000,1000,500 \
#     bash scripts/test/run_iterm2_panel_encoding_matrix.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ITERM2_PANEL_TITLE="${ITERM2_PANEL_TITLE:-1.1.8}"
FPS_LIST="${FPS_LIST:-60,30,15}"
BITRATE_KBPS_LIST="${BITRATE_KBPS_LIST:-2000,1000,500,250}"
OUT_DIR="${ITERMREMOTE_MATRIX_OUT_DIR:-$REPO_ROOT/build/verify_matrix}"

cd "$REPO_ROOT/examples/host_test_app"

export ITERM2_PANEL_TITLE
export FPS_LIST
export BITRATE_KBPS_LIST
export ITERMREMOTE_MATRIX_OUT_DIR="$OUT_DIR"

flutter pub get >/dev/null

flutter run -d macos \
  -t lib/verify/iterm2_panel_encoding_matrix_app.dart
