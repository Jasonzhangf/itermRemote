#!/bin/bash
# Auto-kill existing instance before launching new one
APP_NAME="itermremote"
BUNDLE_ID="com.example.hostConsole"

# Kill by process name
pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Kill by bundle ID (more reliable)
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true

# Wait for process to terminate
sleep 0.5

# Launch new instance
open "$(dirname "$0")/build/macos/Build/Products/Debug/${APP_NAME}.app"
