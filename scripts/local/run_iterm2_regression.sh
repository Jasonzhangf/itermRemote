#!/bin/bash
# Local iTerm2 regression suite (panel switch / crop / loopback / screenshot verify).
# This is NOT suitable for CI (requires iTerm2, GUI session, Screen Recording permission).
#
# Usage (from repo root):
#   bash scripts/local/run_iterm2_regression.sh
#
# Output:
#   build/regression_evidence/<timestamp>/
#     - *.png (screenshots)
#     - *.json (metadata)
#     - summary.txt (pass/fail + commit info)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EVIDENCE_DIR="$REPO_ROOT/build/regression_evidence/$TIMESTAMP"
mkdir -p "$EVIDENCE_DIR"

echo "[iTerm2 Regression] Starting at $TIMESTAMP"
echo "[iTerm2 Regression] Evidence: $EVIDENCE_DIR"

# Write summary header
{
  echo "iTerm2 Regression - $(date)"
  echo "Commit: $(git rev-parse --short HEAD)"
  echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
  echo ""
} > "$EVIDENCE_DIR/summary.txt"

# TODO: Invoke real test scripts here, for example:
#   bash scripts/test/verify_iterm2_panels_loopback.sh "$EVIDENCE_DIR"
#   bash scripts/test/run_iterm2_panel_encoding_matrix.sh "$EVIDENCE_DIR"

# Run iTerm2-dependent unit tests (iterm2_bridge, stream_host)
echo "[iTerm2 Regression] Running iterm2_host tests (requires iTerm2)..."
cd "$REPO_ROOT/packages/iterm2_host"
if dart test test/iterm2/iterm2_bridge_test.dart test/streaming/stream_host_test.dart 2>&1 | tee "$EVIDENCE_DIR/unit_test.log"; then
  echo "✅ iterm2_host tests passed" >> "$EVIDENCE_DIR/summary.txt"
else
  echo "❌ iterm2_host tests failed" >> "$EVIDENCE_DIR/summary.txt"
fi
cd "$REPO_ROOT"

# Run panel switching / crop / loopback verification
echo "[iTerm2 Regression] Running panel loopback verification..."
if bash scripts/test/verify_iterm2_panels_loopback.sh 2>&1 | tee "$EVIDENCE_DIR/loopback.log"; then
  echo "✅ Panel loopback verification passed" >> "$EVIDENCE_DIR/summary.txt"
  # Copy evidence from verify script output to our evidence dir
  LATEST_VERIFY=$(ls -td "$REPO_ROOT"/build/verify_loopback/* 2>/dev/null | head -1 || true)
  if [[ -n "$LATEST_VERIFY" ]]; then
    cp -r "$LATEST_VERIFY" "$EVIDENCE_DIR/loopback_evidence"
  fi
else
  echo "❌ Panel loopback verification failed" >> "$EVIDENCE_DIR/summary.txt"
fi

# TODO: Add encoding matrix test when ready
# echo "[iTerm2 Regression] Running encoding matrix test..."
# bash scripts/test/run_iterm2_panel_encoding_matrix.sh "$EVIDENCE_DIR"

echo "[iTerm2 Regression] Evidence saved to $EVIDENCE_DIR"
echo "[iTerm2 Regression] ✅ Complete"
echo ""
echo "Review evidence at: $EVIDENCE_DIR/summary.txt"
