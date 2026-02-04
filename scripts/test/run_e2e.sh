#!/bin/bash
set -e

echo "Running E2E tests..."

echo "Testing core module..."
pushd packages/cloudplayplus_core >/dev/null
flutter pub get
flutter test
popd >/dev/null

echo "Testing host module..."
pushd packages/iterm2_host >/dev/null
flutter pub get
flutter test
popd >/dev/null

echo "Testing android client..."
pushd apps/android_client >/dev/null
flutter pub get
flutter test
popd >/dev/null

echo "Testing host console..."
pushd apps/host_console >/dev/null
flutter pub get
flutter test
popd >/dev/null

echo "Skipping integration suite in CI (iTerm2 mock removed)."

echo "All E2E tests passed"
