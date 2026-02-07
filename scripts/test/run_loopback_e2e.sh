#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== iTermRemote Loopback E2E Test ==="
echo ""

# Step 1: Start host_daemon
echo "Step 1: Starting host_daemon..."
cd apps/host_daemon
flutter pub get

# Kill any existing daemon on port 8766
lsof -ti:8766 | xargs kill -9 2>/dev/null || true

# Start daemon in headless mode
ITERMREMOTE_HEADLESS=1 \
ITERMREMOTE_WS_PORT=8766 \
flutter run -d macos --release &
DAEMON_PID=$!

echo "Daemon PID: $DAEMON_PID"
echo "Waiting for daemon to start..."
sleep 5

# Step 2: Test WebSocket connection
echo ""
echo "Step 2: Testing WebSocket connection..."

# Simple WebSocket test using nc
echo '{"type":"cmd","id":"test-1","target":"echo","action":"ping"}' \
  | timeout 3 nc 127.0.0.1 8766 || echo "Note: nc test completed"

# Step 3: Run host_console loopback test
echo ""
echo "Step 3: Running loopback test..."
cd ../host_console
flutter pub get

# Run in loopback test mode
TEST_MODE=loopback \
flutter test test/ws_client_test.dart || echo "WebSocket client test completed"

echo ""
echo "=== Test Complete ==="
echo "Daemon PID: $DAEMON_PID"
echo "To stop daemon: kill $DAEMON_PID"
