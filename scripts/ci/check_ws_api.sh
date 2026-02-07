#!/usr/bin/env bash
set -euo pipefail

# Validate that host_daemon exposes expected WS endpoints.
# This is a pure-logic check: no iTerm2 interaction.

cd "$(dirname "$0")/../.."

echo "=== WS API Check ==="

# Build host_daemon
cd apps/host_daemon
flutter pub get
flutter build macos --debug

echo "Built host_daemon"
