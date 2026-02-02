#!/bin/bash
set -euo pipefail

PORT="${1:-8766}"
WS_URL="ws://127.0.0.1:${PORT}"
LOG_DIR="/tmp/itermremote-host-daemon"
DAEMON_BIN="/Users/fanzhang/Documents/github/itermRemote/apps/host_daemon/build/macos/Build/Products/Debug/itermremote.app/Contents/MacOS/itermremote"

mkdir -p "$LOG_DIR"

echo "[E2E] Kill existing itermremote (repo build only)"
pkill -f "${DAEMON_BIN}" 2>/dev/null || true

echo "[E2E] Stop launchd daemon (avoid port conflict)"
launchctl bootout "gui/$(id -u)/itermremote.host-daemon" 2>/dev/null || true

echo "[E2E] Kill any leftover itermremote listener on :$PORT"
for pid in $(/usr/sbin/lsof -t -nP -i "TCP:$PORT" -sTCP:LISTEN 2>/dev/null || true); do
  cmd=$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)
  if echo "$cmd" | grep -qi "itermremote.app/Contents/MacOS/itermremote"; then
    kill -9 "$pid" 2>/dev/null || true
  fi
done

echo "[E2E] Start daemon headless on port $PORT"
ITERMREMOTE_HEADLESS=1 ITERMREMOTE_WS_PORT="$PORT" ITERMREMOTE_STATE_DIR="$LOG_DIR" \
  "$DAEMON_BIN" >"$LOG_DIR/stdout.log" 2>"$LOG_DIR/stderr.log" &
DAEMON_PID=$!
echo "$DAEMON_PID" > "$LOG_DIR/pid"

# Deterministic readiness: wait until we can TCP-connect to the port.
python3 - <<PY
import socket, time, sys
port=int("$PORT")
for i in range(40):
  s=socket.socket()
  s.settimeout(0.2)
  try:
    s.connect(("127.0.0.1", port))
    s.close()
    print("[E2E] TCP ready")
    sys.exit(0)
  except Exception:
    s.close()
    time.sleep(0.25)
print("[E2E] TCP NOT ready")
sys.exit(2)
PY

echo "[E2E] Run WS verification"
dart run scripts/test/verify_daemon_iterm2_crop.dart "$WS_URL"

echo "[E2E] Stop daemon"
kill "$DAEMON_PID" 2>/dev/null || true
sleep 1

echo "[E2E] Restart launchd daemon"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/itermremote.host-daemon.plist" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/itermremote.host-daemon" 2>/dev/null || true

echo "[E2E] OK. Logs: $LOG_DIR"
