#!/bin/bash
# Host Daemon 停止脚本

PID_FILE="/tmp/itermremote_host.pid"
REAL_PID_FILE="/tmp/itermremote_host_real.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "⚠️  No PID file found. Attempting cleanup by process name."
  pkill -9 -f "host_daemon.app/Contents/MacOS/host_daemon" 2>/dev/null || true
  pkill -9 -f "itermremote.app/Contents/MacOS/itermremote" 2>/dev/null || true
  exit 0
fi

PID=$(cat "$PID_FILE")
REAL_PID=""
if [ -f "$REAL_PID_FILE" ]; then
  REAL_PID=$(cat "$REAL_PID_FILE")
fi

if [ -n "$REAL_PID" ] && ps -p "$REAL_PID" > /dev/null 2>&1; then
  PID=$REAL_PID
fi

if ps -p "$PID" > /dev/null 2>&1; then
  echo "🛑 Stopping Host Daemon (PID: $PID)..."
  kill "$PID"
  sleep 2

  # 强制杀死如果还在运行
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "⚠️  Process still running, forcing kill..."
    kill -9 "$PID"
  fi

  rm -f "$PID_FILE" "$REAL_PID_FILE"
  echo "✅ Host daemon stopped"
else
  echo "⚠️  Process $PID not running (cleaning up)"
  rm -f "$PID_FILE" "$REAL_PID_FILE"
fi

# Ensure no orphan process remains
pkill -9 -f "host_daemon.app/Contents/MacOS/host_daemon" 2>/dev/null || true
pkill -9 -f "itermremote.app/Contents/MacOS/itermremote" 2>/dev/null || true
