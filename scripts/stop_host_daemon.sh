#!/bin/bash
# Host Daemon 停止脚本

PID_FILE="/tmp/itermremote_host.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "⚠️  No PID file found. Daemon may not be running."
  exit 1
fi

PID=$(cat "$PID_FILE")

if ps -p "$PID" > /dev/null 2>&1; then
  echo "🛑 Stopping Host Daemon (PID: $PID)..."
  kill "$PID"
  sleep 2
  
  # 强制杀死如果还在运行
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "⚠️  Process still running, forcing kill..."
    kill -9 "$PID"
  fi
  
  rm -f "$PID_FILE"
  echo "✅ Host daemon stopped"
else
  echo "⚠️  Process $PID not running (cleaning up)"
  rm -f "$PID_FILE"
fi
