#!/bin/bash
# 停止 run_host_and_client.sh 启动的 host_daemon + macOS client

set -euo pipefail

echo "=== 停止 Host + Client ==="

if [ -f /tmp/itermremote_client.pid ]; then
  CLIENT_PID="$(cat /tmp/itermremote_client.pid || true)"
  if [ -n "${CLIENT_PID:-}" ] && ps -p "$CLIENT_PID" >/dev/null 2>&1; then
    kill "$CLIENT_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$CLIENT_PID" 2>/dev/null || true
    echo "✓ 已停止 client PID=$CLIENT_PID"
  fi
fi

if [ -f /tmp/itermremote_daemon.pid ]; then
  DAEMON_PID="$(cat /tmp/itermremote_daemon.pid || true)"
  if [ -n "${DAEMON_PID:-}" ] && ps -p "$DAEMON_PID" >/dev/null 2>&1; then
    kill "$DAEMON_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$DAEMON_PID" 2>/dev/null || true
    echo "✓ 已停止 daemon PID=$DAEMON_PID"
  fi
fi

# 兜底清理
pkill -9 -f "macos_client.app/Contents/MacOS/macos_client" 2>/dev/null || true
pkill -9 -f "itermremote.app/Contents/MacOS/itermremote" 2>/dev/null || true

rm -f /tmp/itermremote_client.pid /tmp/itermremote_daemon.pid

echo "✓ 清理完成"
