#!/bin/bash
# Host Daemon start script with stable app identity + log checking
#
# To avoid repeated macOS permission prompts:
# 1. App is built to build/macos/Build/Products/Release/
# 2. Copied to /Applications/itermremote.app (stable location)
# 3. Launched from stable location to preserve TCC permissions
#
# For custom app path: ITERMREMOTE_APP_PATH=/path/to/app.app ./start_host_daemon.sh

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
BUILD_APP="$APP_DIR/build/macos/Build/Products/Release/itermremote.app"
RELEASE_BIN="$BUILD_APP/Contents/MacOS/itermremote"
DEBUG_APP="$APP_DIR/build/macos/Build/Products/Debug/itermremote.app"

# Stable app location to preserve macOS permissions across rebuilds
# When app is copied to /Applications, macOS tracks it by path+bundle ID
# Adhoc signatures change on rebuild, but stable path helps TCC recognition
STABLE_APP="/Applications/itermremote.app"
RELEASE_APP="${ITERMREMOTE_APP_PATH:-$STABLE_APP}"

# Kill existing daemon
bash "$REPO_ROOT/scripts/stop_host_daemon.sh" 2>/dev/null || true

# Prevent legacy launchd jobs from auto-restarting /Applications copy during local debugging.
launchctl bootout "gui/$(id -u)" com.itermremote.host-daemon >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" itermremote.host-daemon >/dev/null 2>&1 || true
launchctl remove com.itermremote.host-daemon >/dev/null 2>&1 || true

rm -f "$LOG_FILE"
mkdir -p "$(dirname "$LOG_FILE")"

echo "Starting Host Daemon..."
echo "Mode: $MODE"
echo "Port: $PORT"
echo "Log: $LOG_FILE"

# Ensure token file is present for daemon_orchestrator fallback
if [ -n "${ITERMREMOTE_TOKEN:-}" ]; then
  echo -n "$ITERMREMOTE_TOKEN" > /tmp/itermremote_test_token.txt
  echo "Token: written to /tmp/itermremote_test_token.txt from env"
fi

# Check for token file (daemon_orchestrator will read it)
if [ -f /tmp/itermremote_test_token.txt ]; then
  echo "Token: found (/tmp/itermremote_test_token.txt)"
  token_len=$(wc -c < /tmp/itermremote_test_token.txt | tr -d ' ')
  echo "Token length: $token_len bytes"
else
  echo "Token: not found (relay will be disabled)"
fi

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
  # Force rebuild if --rebuild flag is set
  if [ $REBUILD -eq 1 ]; then
    echo "Forcing rebuild (--rebuild flag set)..."
    rm -rf "$RELEASE_APP"
    rm -rf "$BUILD_APP"
    (
      cd "$APP_DIR"
      flutter build macos --release 2>&1 | tee "$LOG_FILE"
    )

    # Copy to stable location to preserve macOS TCC permissions
    if [ -d "$BUILD_APP" ] && [ "$RELEASE_APP" != "$BUILD_APP" ]; then
      echo "Copying to stable location: $RELEASE_APP"
      rm -rf "$RELEASE_APP"
      cp -R "$BUILD_APP" "$RELEASE_APP"
    fi
  elif [ ! -d "$BUILD_APP" ] || [ -n "$(git -C "$REPO_ROOT" status --porcelain apps/host_daemon packages/itermremote_blocks packages/iterm2_host src/modules/daemon_ws 2>/dev/null)" ]; then
    echo "Building macOS application..."
    (
      cd "$APP_DIR"
      flutter build macos --release 2>&1 | tee "$LOG_FILE"
    )

    # Copy to stable location to preserve macOS TCC permissions
    # This helps avoid repeated permission prompts when adhoc signature changes
    if [ -d "$BUILD_APP" ] && [ "$RELEASE_APP" != "$BUILD_APP" ]; then
      echo "Copying to stable location: $RELEASE_APP"
      rm -rf "$RELEASE_APP"
      cp -R "$BUILD_APP" "$RELEASE_APP"
    fi
  fi

  # Verify app exists
  if [ ! -d "$RELEASE_APP" ]; then
    # If stable location is empty but build exists, copy it
    if [ -d "$BUILD_APP" ]; then
      echo "Copying to stable location: $RELEASE_APP"
      cp -R "$BUILD_APP" "$RELEASE_APP"
    else
      echo "❌ App not found: $RELEASE_APP"
      echo "   Build it first with: cd $APP_DIR && flutter build macos --release"
      exit 1
    fi
  fi

  # Use open to launch the .app bundle to preserve bundle ID and permissions
  # This ensures macOS screen recording permission is remembered across runs
  # Note: open command doesn't forward env vars reliably, so we use temp file approach
  nohup open -W -n "$RELEASE_APP" --args \
    --ITERMREMOTE_WS_PORT="$PORT" \
    --ITERMREMOTE_REPO_ROOT="$REPO_ROOT" \
    --ITERMREMOTE_HEADLESS=1 \
    --NSQuitAlwaysKeepsWindows=0 \
    >> "$LOG_FILE" 2>&1 &

  echo "Started daemon (waiting for initialization...)"

  # Wait for process to start and get PID
  sleep 2
  REAL_PID=$(pgrep -f "itermremote.app/Contents/MacOS/itermremote" | head -1 || true)
  if [ -n "$REAL_PID" ]; then
    echo "$REAL_PID" > /tmp/itermremote_host.pid
    echo "$REAL_PID" > /tmp/itermremote_host_real.pid
  else
    # Fallback: find by bundle ID
    REAL_PID=$(pgrep -f "com.itermremote.host-daemon" | head -1 || true)
    if [ -n "$REAL_PID" ]; then
      echo "$REAL_PID" > /tmp/itermremote_host.pid
      echo "$REAL_PID" > /tmp/itermremote_host_real.pid
    fi
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

# Show recent daemon logs from log stream (daemon uses print() which goes to stdout)
if [ "$MODE" = "release" ]; then
  echo ""
  echo "📋 Daemon stdout logs (last 30s):"
  log show --style compact --last 30s --predicate 'process == "itermremote"' 2>/dev/null | \
    grep -E "orchestrator|RelaySignaling|WebRTC|webrtc|Token|token" | \
    tail -20 || echo "  (no daemon logs found)"
fi

# Check logs for errors
if [ -f "$REPO_ROOT/scripts/check_app_logs.sh" ]; then
  bash "$REPO_ROOT/scripts/check_app_logs.sh" "$LOG_FILE" || exit 1
else
  echo "⚠️ check_app_logs.sh not found"
fi

# Show recent app logs
echo ""
echo "📋 Recent app logs (last 30s):"
log show --style compact --last 30s --predicate 'process == "itermremote"' 2>/dev/null | \
  grep -v "com.apple" | \
  grep -v "activating connection" | \
  grep -v "Connection returned" | \
  grep -v "xpc:" | \
  tail -30 || echo "  (no logs found)"

REAL_PID_FILE="/tmp/itermremote_host_real.pid"
REAL_PID=$(pgrep -f "$RELEASE_APP/Contents/MacOS/itermremote" | head -1 || true)
if [ -n "$REAL_PID" ]; then
  echo $REAL_PID > "$REAL_PID_FILE"
  echo "REAL_PID: $REAL_PID"
else
  echo "⚠️  Could not resolve real host_daemon PID"
fi

echo "PID: $(cat /tmp/itermremote_host.pid 2>/dev/null || echo unknown)"
echo "App: $RELEASE_APP"
echo "Logs: tail -f $LOG_FILE"
