#!/usr/bin/env bash
set -euo pipefail
APP_NAME="android_client"
LOG_FILE="/tmp/${APP_NAME}_console.log"
PID_FILE="/tmp/${APP_NAME}.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/../apps/$APP_NAME"
RELEASE_APP="$APP_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
echo "🛑 Stopping existing $APP_NAME..."
pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 0.5
> "$LOG_FILE" 2>/dev/null || true
echo "🔨 Building release app..."
cd "$APP_DIR"
flutter build macos --release 2>&1 | tee "$LOG_FILE"
if [ ! -d "$RELEASE_APP" ]; then
  echo "❌ Release app not found"
  exit 1
fi
echo "🚀 Starting $APP_NAME..."
open -n --stdout "$LOG_FILE" --stderr "$LOG_FILE" "$RELEASE_APP"
sleep 2
APP_PID=$(pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" | head -1 || true)
if [ -z "$APP_PID" ]; then
  echo "❌ Failed to find app process"
  exit 1
fi
echo "$APP_PID" > "$PID_FILE"
echo "📋 App started with PID: $APP_PID"
echo "⏳ Waiting 8 seconds..."
sleep 8
echo "🔍 Checking logs..."
if ! "$SCRIPT_DIR/check_app_logs.sh" "$LOG_FILE"; then
  echo "❌ Errors in logs"
  exit 1
fi
echo "✅ App started successfully"
