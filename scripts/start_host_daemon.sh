#!/bin/bash
# Host Daemon start script with log checking

set -e

PORT=${ITERMREMOTE_WS_PORT:-8766}
LOG_FILE=${ITERMREMOTE_LOG_FILE:-/tmp/itermremote_host.log}
ITERMREMOTE_REPO_ROOT=${ITERMREMOTE_REPO_ROOT:-$(pwd)}

for arg in "$@"; do
  case $arg in
    --port=*) PORT="${arg#*=}" ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
  esac
done

# Kill existing daemon
bash scripts/stop_host_daemon.sh 2>/dev/null || true

rm -f "$LOG_FILE"
mkdir -p "$(dirname "$LOG_FILE")"

echo "Starting Host Daemon..."
echo "Port: $PORT"
echo "Log: $LOG_FILE"

cd apps/host_daemon
flutter run -d macos --debug \
  --dart-define=ITERMREMOTE_WS_PORT=$PORT \
  --dart-define=ITERMREMOTE_REPO_ROOT=$ITERMREMOTE_REPO_ROOT \
  2>&1 | tee "$LOG_FILE" &
PID=$!
cd ../..

echo $PID > /tmp/itermremote_host.pid

# Wait for WS server
for i in $(seq 1 30); do
  if grep -q "WS server listening" "$LOG_FILE" 2>/dev/null; then
    echo "✅ Daemon started (WS ready)"
    break
  fi
  if ! ps -p $PID > /dev/null 2>&1; then
    echo "❌ Daemon crashed"
    exit 1
  fi
  sleep 1
done

# Check logs for errors
if [ -f scripts/check_app_logs.sh ]; then
  bash scripts/check_app_logs.sh "$LOG_FILE" || exit 1
else
  echo "⚠️ check_app_logs.sh not found"
fi

echo "PID: $PID"
echo "Logs: tail -f $LOG_FILE"
