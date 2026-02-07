#!/usr/bin/env bash
# Start host_daemon as a background service with keep-alive

set -euo pipefail

APP_PATH="${1:-./apps/host_daemon/build/macos/Build/Products/Release/itermremote.app/Contents/MacOS/itermremote}"
LOG_FILE="${2:-/tmp/host_daemon.log}"
PID_FILE="/tmp/itermremote_daemon.pid"

# Kill existing
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ]; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
fi

# Start daemon with keep-alive wrapper
export ITERMREMOTE_HEADLESS=1
export ITERMREMOTE_WS_PORT=8766

# Use caffeinate to keep process alive on macOS
nohup caffeinate -i "$APP_PATH" > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"

echo "Started host_daemon with PID: $PID"
echo "Log: tail -f $LOG_FILE"
echo "WS endpoint: ws://127.0.0.1:8766"

# Wait for startup
sleep 3

# Check if running
if ps -p $PID > /dev/null 2>&1; then
    if lsof -i :8766 | grep -q "$PID"; then
        echo "✅ Daemon is running and listening on port 8766"
        exit 0
    else
        echo "⚠️ Process running but port 8766 not open"
        exit 1
    fi
else
    echo "❌ Daemon failed to start"
    exit 1
fi
