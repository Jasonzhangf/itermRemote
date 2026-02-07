#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== Full Loopback Validation (host_daemon + host_console) ==="

PORT="${ITERMREMOTE_WS_PORT:-8766}"

# Kill any previous listeners that are clearly ours
# Note: macOS lsof does not accept TCP:PORT in -i. Use -iTCP:PORT.
set +e
lsof -tiTCP:"$PORT" -sTCP:LISTEN | while read -r PID; do
  CMD=$(ps -p "$PID" -o command= | tr '[:upper:]' '[:lower:]' || true)
  if echo "$CMD" | grep -q "itermremote"; then
    echo "killing stale itermremote listener pid=$PID"
    kill -9 "$PID" || true
  fi
done
set -e

echo "Step 1: Start host_daemon (headless)"
cd apps/host_daemon
flutter pub get
ITERMREMOTE_HEADLESS=1 ITERMREMOTE_WS_PORT="$PORT" flutter run -d macos --debug &
DAEMON_PID=$!
cd ../..

echo "daemon pid=$DAEMON_PID"

# Give it time to boot
sleep 6

echo "Step 2: Run host_console in loopback test mode"
cd apps/host_console
flutter pub get
flutter run -d macos --dart-define=TEST_MODE=loopback

# If console exits, stop daemon
kill "$DAEMON_PID" || true
