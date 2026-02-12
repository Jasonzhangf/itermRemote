#!/bin/bash
# Host Daemon start script with stable app identity + log checking

set -euo pipefail

PORT=${ITERMREMOTE_WS_PORT:-8766}
LOG_FILE=${ITERMREMOTE_LOG_FILE:-/tmp/itermremote_host.log}
MODE="release"
REBUILD=0

for arg in "$@"; do
  case $arg in
    --port=*) PORT="${arg#*=}" ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
    --debug) MODE="debug" ;;
    --release) MODE="release" ;;
    --rebuild) REBUILD=1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/host_daemon"
RELEASE_APP="$APP_DIR/build/macos/Build/Products/Release/itermremote.app"
DEBUG_APP="$APP_DIR/build/macos/Build/Products/Debug/itermremote.app"

# Kill existing daemon
bash "$REPO_ROOT/scripts/stop_host_daemon.sh" 2>/dev/null || true

rm -f "$LOG_FILE"
mkdir -p "$(dirname "$LOG_FILE")"

echo "Starting Host Daemon..."
echo "Mode: $MODE"
echo "Port: $PORT"
echo "Log: $LOG_FILE"

if [ "$MODE" = "debug" ]; then
  (
    cd "$APP_DIR"
    flutter run -d macos --debug \
      --dart-define=ITERMREMOTE_WS_PORT=$PORT \
      --dart-define=ITERMREMOTE_REPO_ROOT=$REPO_ROOT \
      2>&1 | tee "$LOG_FILE"
  ) &
  WRAPPER_PID=$!
  echo $WRAPPER_PID > /tmp/itermremote_host.pid
else
  if [ $REBUILD -eq 1 ] || [ ! -d "$RELEASE_APP" ]; then
    (
      cd "$APP_DIR"
      flutter build macos --release 2>&1 | tee "$LOG_FILE"
    )
  fi

  # Launch stable bundle path (prevents repeated macOS permission prompts caused by volatile debug runs)
  open -gn "$RELEASE_APP"

  # Write PID file from real process
  sleep 1
  REAL_PID=$(pgrep -f "itermremote.app/Contents/MacOS/itermremote" | head -1 || true)
  if [ -n "$REAL_PID" ]; then
    echo "$REAL_PID" > /tmp/itermremote_host.pid
  fi
fi

# Wait for WS server
READY=0
for i in $(seq 1 30); do
  if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    READY=1
    echo "✅ Daemon started (WS ready on :$PORT)"
    break
  fi
  sleep 1
done

if [ $READY -ne 1 ]; then
  echo "❌ Daemon failed to listen on :$PORT"
  exit 1
fi

# Refresh log snapshot for release mode via unified macOS log stream
if [ "$MODE" = "release" ]; then
  log show --style compact --last 2m --predicate 'process == "itermremote"' > "$LOG_FILE" 2>/dev/null || true
fi

# Check logs for errors
if [ -f "$REPO_ROOT/scripts/check_app_logs.sh" ]; then
  bash "$REPO_ROOT/scripts/check_app_logs.sh" "$LOG_FILE" || exit 1
else
  echo "⚠️ check_app_logs.sh not found"
fi

REAL_PID_FILE="/tmp/itermremote_host_real.pid"
REAL_PID=$(pgrep -f "itermremote.app/Contents/MacOS/itermremote" | head -1 || true)
if [ -n "$REAL_PID" ]; then
  echo $REAL_PID > "$REAL_PID_FILE"
  echo "REAL_PID: $REAL_PID"
else
  echo "⚠️  Could not resolve real host_daemon PID"
fi

echo "PID: $(cat /tmp/itermremote_host.pid 2>/dev/null || echo unknown)"
echo "Logs: tail -f $LOG_FILE"
