#!/usr/bin/env bash
# Standard way to run host_console with log capture and mandatory error checking
# AGENTS.md Rule: Any error in logs = MUST FIX before continuing

set -euo pipefail

APP_NAME="itermremote"
LOG_FILE="/tmp/${APP_NAME}_console.log"
PID_FILE="/tmp/${APP_NAME}.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kill existing instance (mandatory single instance)
echo "🛑 Stopping existing $APP_NAME..."
pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 0.5

# Clear old logs
> "$LOG_FILE" 2>/dev/null || true

echo "🚀 Starting $APP_NAME..."
cd "$SCRIPT_DIR/../apps/host_console"

# Run with log capture
flutter run -d macos --debug 2>&1 | tee "$LOG_FILE" &
PID=$!
echo $PID > "$PID_FILE"

echo ""
echo "📋 App started with PID: $PID"
echo "📄 Logs: tail -f $LOG_FILE"
echo ""
echo "⏳ Waiting 8 seconds for startup..."
sleep 8

echo ""
echo "🔍 Checking for startup errors (AGENTS.md mandatory)..."
if ! "$SCRIPT_DIR/check_app_logs.sh" "$LOG_FILE"; then
  echo ""
  echo "❌ STARTUP FAILED - Errors detected in logs"
  echo "💡 Fix the errors above, then re-run this script"
  echo "💡 Full log: tail -100 $LOG_FILE"
  
  # Kill the app since it has errors
  pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
  exit 1
fi

echo ""
echo "✅ App started successfully with NO ERRORS"
echo "📄 Monitor logs: tail -f $LOG_FILE"
