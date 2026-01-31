#!/bin/bash
set -e

echo "Running E2E tests..."

bash scripts/test/setup_iterm2_mock.sh

echo "Testing core module..."
pushd packages/cloudplayplus_core >/dev/null
dart pub get
dart test
popd >/dev/null

echo "Testing host module..."
pushd packages/iterm2_host >/dev/null
dart pub get
dart test
popd >/dev/null

echo "Testing android client..."
pushd apps/android_client >/dev/null
flutter pub get
flutter test
popd >/dev/null

echo "All E2E tests passed"

