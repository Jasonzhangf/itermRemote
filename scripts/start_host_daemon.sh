#!/bin/bash
# Host Daemon 后台启动脚本
# 用法: ./scripts/start_host_daemon.sh [--port=8766] [--log-file=/tmp/itermremote_host.log]

set -e

# 默认配置
PORT=${ITERMREMOTE_PORT:-8766}
LOG_FILE=${ITERMREMOTE_LOG_FILE:-/tmp/itermremote_host.log}
HEADLESS=${ITERMREMOTE_HEADLESS:-1}

# 解析参数
for arg in "$@"; do
  case $arg in
    --port=*)
      PORT="${arg#*=}"
      shift
      ;;
    --log-file=*)
      LOG_FILE="${arg#*=}"
      shift
      ;;
    *)
      # 未知参数
      ;;
  esac
done

# 检查是否已在运行
PID_FILE="/tmp/itermremote_host.pid"
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if ps -p "$OLD_PID" > /dev/null 2>&1; then
    echo "⚠️  Host daemon already running (PID: $OLD_PID)"
    echo "   To restart, run: kill $OLD_PID && $0"
    exit 1
  else
    echo "🧹 Cleaning up stale PID file"
    rm -f "$PID_FILE"
  fi
fi

# 确保日志目录存在
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

# 启动 daemon
echo "🚀 Starting Host Daemon..."
echo "   Port: $PORT"
echo "   Log:  $LOG_FILE"
echo "   Headless: $HEADLESS"

cd "$(dirname "$0")/.."

if [ "$HEADLESS" = "1" ]; then
  # 后台启动（无窗口）
  cd apps/host_daemon
  flutter run -d macos --debug \
    --dart-define=ITERMREMOTE_HEADLESS=1 \
    --dart-define=ITERMREMOTE_PORT=$PORT \
    2>&1 | tee "$LOG_FILE" &
  PID=$!
else
  # 前台启动（调试用）
  cd apps/host_daemon
  flutter run -d macos --debug \
    --dart-define=ITERMREMOTE_HEADLESS=1 \
    --dart-define=ITERMREMOTE_PORT=$PORT \
    2>&1 | tee "$LOG_FILE" &
  PID=$!
fi

# 保存 PID
echo $PID > "$PID_FILE"

# 等待启动
echo "⏳ Waiting for daemon to start..."
sleep 5

# 检查是否成功
if ps -p "$PID" > /dev/null 2>&1; then
  echo "✅ Host daemon started successfully (PID: $PID)"
  echo "   Logs: tail -f $LOG_FILE"
  echo "   Stop:  kill $PID"
else
  echo "❌ Failed to start host daemon"
  rm -f "$PID_FILE"
  exit 1
fi

# 检查日志是否有错误
if grep -q "Error\|Exception\|Failed" "$LOG_FILE" 2>/dev/null; then
  echo "⚠️  Errors detected in log, check: $LOG_FILE"
fi
