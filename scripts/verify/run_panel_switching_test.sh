#!/bin/bash
# Multi-panel switching test: iterates through all iTerm2 panels
# Order is spatial row-major: top-to-bottom, left-to-right.
# Each panel is activated, evidence is captured (screenshot + crop + overlay),
# then we wait N seconds (default 5s) before switching to the next.
#
# Output: build/verify_panel_switching/<TS>/
#   - evidence_*.json / meta_*.json / screenshot_*.png / cropped_*.png / overlay_*.png
#   - summary.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_BASE="$REPO_ROOT/build/verify_panel_switching"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUT_BASE/$TS"
mkdir -p "$OUT_DIR"

log() {
  echo "[PanelSwitching] $*"
}

die() {
  echo "[PanelSwitching][ERROR] $*" >&2
  exit 2
}

WS_URL="${ITERMREMOTE_WS_URL:-ws://127.0.0.1:8766}"
CAPTURE_DURATION="${ITERMREMOTE_CAPTURE_DURATION:-5}"
PORT="${ITERMREMOTE_WS_PORT:-8766}"

log "Starting multi-panel switching test"
log "WS URL: $WS_URL"
log "Capture duration: ${CAPTURE_DURATION}s per panel"
log "Output: $OUT_DIR"

DAEMON_PID=""
cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    log "Stopping daemon (PID: $DAEMON_PID)"
    kill "$DAEMON_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Kill stale listeners that are clearly ours
set +e
lsof -tiTCP:"$PORT" -sTCP:LISTEN | while read -r PID; do
  CMD=$(ps -p "$PID" -o command= | tr '[:upper:]' '[:lower:]' || true)
  if echo "$CMD" | grep -q "itermremote"; then
    log "killing stale itermremote listener pid=$PID"
    kill -9 "$PID" || true
  fi
done
set -e

log "Starting host_daemon..."
cd "$REPO_ROOT/apps/host_daemon"
flutter pub get >/dev/null 2>&1
ITERMREMOTE_HEADLESS=1 ITERMREMOTE_WS_PORT="$PORT" flutter run -d macos --release >/dev/null 2>&1 &
DAEMON_PID=$!
cd "$REPO_ROOT"

log "Waiting for daemon to start..."
for i in {1..30}; do
  if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    log "Daemon ready (after ${i}s)"
    break
  fi
  sleep 1
done

if ! nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
  die "Daemon failed to start within 30s"
fi

log "Running panel switching test (spatial order)..."
python3 "$REPO_ROOT/scripts/test/iterm2_panel_switching_test.py" \
  --ws-url="$WS_URL" \
  --output-dir="$OUT_DIR" \
  --duration="$CAPTURE_DURATION"

log "Test complete"
log "Output: $OUT_DIR"
ls -lh "$OUT_DIR"/*.png "$OUT_DIR"/*.json 2>/dev/null || true

log "Done"
