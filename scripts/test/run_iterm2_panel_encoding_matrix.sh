#!/bin/bash
# Run iTerm2 panel encoding/bitrate matrix verification on macOS.
#
# This ports the local loopback matrix verifier from cloudplayplus_stone into
# this repo. It captures remote preview and track frames, and records inbound
# stats per (fps, bitrate) case.
#
# Usage:
#   ITERM2_PANEL_TITLE=1.1.8 FPS_LIST=60,30,15 BITRATE_KBPS_LIST=2000,1000,500 \
#     bash scripts/test/run_iterm2_panel_encoding_matrix.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ITERM2_PANEL_TITLE="${ITERM2_PANEL_TITLE:-1.1.8}"
FPS_LIST="${FPS_LIST:-60,30,15}"
BITRATE_KBPS_LIST="${BITRATE_KBPS_LIST:-2000,1000,500,250}"

cd "$REPO_ROOT/examples/host_test_app"

export ITERM2_PANEL_TITLE
export FPS_LIST
export BITRATE_KBPS_LIST

echo "ERROR: This matrix app is not yet ported into itermRemote." >&2
echo "Next step: implement a local verifier inside examples/host_test_app (no cloudplayplus imports)." >&2
exit 2
