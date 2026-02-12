#!/bin/bash
# 同时启动 host_daemon 和 macOS client
# host_daemon 作为后台服务监听 8766
# macOS client 只用于设置/配置，通过 WebRTC 连接 daemon

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_APP="$REPO_ROOT/apps/host_daemon/build/macos/Build/Products/Release/itermremote.app"
CLIENT_APP="$REPO_ROOT/apps/macos_client/build/macos/Build/Products/Debug/macos_client.app"
DAEMON_LOG="/tmp/itermremote_daemon.log"
CLIENT_LOG="/tmp/itermremote_client.log"

echo "=== 启动 Host + Client 组合 ==="

# 1. 清理旧进程
echo "[1/4] 清理旧进程..."
pkill -9 -f "itermremote.app/Contents/MacOS/itermremote" 2>/dev/null || true
pkill -9 -f "macos_client.app/Contents/MacOS/macos_client" 2>/dev/null || true
sleep 1

# 2. 构建 daemon (如果需要)
if [ ! -d "$DAEMON_APP" ] || [ -n "$(find "$REPO_ROOT/packages/itermremote_blocks" -newer "$DAEMON_APP" 2>/dev/null)" ]; then
    echo "[2/4] 构建 host_daemon..."
    cd "$REPO_ROOT/apps/host_daemon"
    flutter build macos --release 2>&1 | tee "$DAEMON_LOG"
else
    echo "[2/4] host_daemon 已是最新"
fi

# 3. 构建 client (如果需要)
if [ ! -d "$CLIENT_APP" ] || [ -n "$(find "$REPO_ROOT/apps/macos_client" -newer "$CLIENT_APP" 2>/dev/null)" ]; then
    echo "[3/4] 构建 macOS client..."
    cd "$REPO_ROOT/apps/macos_client"
    flutter build macos --debug 2>&1 | tee "$CLIENT_LOG"
else
    echo "[3/4] macOS client 已是最新"
fi

# 4. 启动 daemon (后台模式)
echo "[4/4] 启动服务..."
rm -f "$DAEMON_LOG" "$CLIENT_LOG"

# 启动 daemon
DAEMON_BIN="$DAEMON_APP/Contents/MacOS/itermremote"
nohup env \
    ITERMREMOTE_HEADLESS=1 \
    ITERMREMOTE_WS_PORT=8766 \
    ITERMREMOTE_REPO_ROOT="$REPO_ROOT" \
    "$DAEMON_BIN" >> "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!
echo "  Daemon PID: $DAEMON_PID"
echo $DAEMON_PID > /tmp/itermremote_daemon.pid

# 等待 daemon 启动
for i in $(seq 1 30); do
    if lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
        echo "  ✓ Daemon 就绪 (端口 8766)"
        break
    fi
    sleep 1
done

# 启动 client
CLIENT_BIN="$CLIENT_APP/Contents/MacOS/macos_client"
"$CLIENT_BIN" >> "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!
echo "  Client PID: $CLIENT_PID"
echo $CLIENT_PID > /tmp/itermremote_client.pid

echo ""
echo "=== 启动完成 ==="
echo "Daemon:  ws://127.0.0.1:8766 (日志: tail -f $DAEMON_LOG)"
echo "Client:  ws://127.0.0.1:9999 (日志: tail -f $CLIENT_LOG)"
echo ""
echo "按 Ctrl+C 停止，或运行: bash scripts/stop_host_and_client.sh"

# 保持脚本运行（以便 Ctrl+C 能同时杀掉两个进程）
trap 'echo ""; echo "停止中..."; kill $DAEMON_PID $CLIENT_PID 2>/dev/null; exit 0' INT TERM
wait
