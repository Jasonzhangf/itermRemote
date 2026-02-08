#!/usr/bin/env bash
# Stop android_client release app

set -euo pipefail

APP_NAME="android_client"
PID_FILE="/tmp/${APP_NAME}.pid"

echo "🛑 Stopping $APP_NAME..."

# Kill by process name
pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true

# Clean up PID file
rm -f "$PID_FILE"

sleep 0.5

# Verify stopped
if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" > /dev/null 2>&1; then
  echo "⚠️ Process still running, forcing kill..."
  pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
  sleep 1
fi

echo "✅ $APP_NAME stopped"

