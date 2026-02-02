#!/bin/bash
# Run bandwidth test app
# Usage: ./run_bandwidth_test.sh

cd "$(dirname "$0")"

echo "Starting bandwidth test app..."
flutter run -d macos lib/bandwidth_test_app.dart
