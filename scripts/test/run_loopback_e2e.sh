#!/bin/bash
set -e

echo "=== E2E Loopback Test ==="
echo "Time: $(date)"

# Check daemon running
if ! lsof -nP -iTCP:8766 -sTCP:LISTEN > /dev/null 2>&1; then
  echo "Starting daemon..."
  launchctl start com.itermremote.host-daemon
  sleep 3
fi

# Run protocol smoke test
echo ""
echo "1. Protocol smoke test..."
dart scripts/test_webrtc_smoke.dart || exit 1

# Check logs
echo ""
echo "2. Log check..."
bash scripts/check_app_logs.sh /tmp/itermremote-host-daemon/stdout.log || exit 1

echo ""
echo "=== ALL E2E TESTS PASSED ==="
