#!/bin/bash
set -e

echo "Creating directory structure..."

# Create module directories
mkdir -p packages/cloudplayplus_core/lib/{entities,services,utils}
mkdir -p packages/iterm2_host/lib/{iterm2,streaming,config}
mkdir -p apps/android_client/lib/{pages,widgets,services}

# Create script directories
mkdir -p scripts/ci
mkdir -p scripts/python
mkdir -p scripts/test

# Create test directories
mkdir -p test/unit
mkdir -p test/integration
mkdir -p test/e2e

# Create docs directory
mkdir -p docs

echo "Creating placeholder files..."

# Create library entry points
touch packages/cloudplayplus_core/lib/cloudplayplus_core.dart
touch packages/iterm2_host/lib/main.dart
touch apps/android_client/lib/main.dart

echo "Creating pubspec.yaml files..."

# Core package pubspec
cat > packages/cloudplayplus_core/pubspec.yaml << 'EOF'
name: cloudplayplus_core
version: 0.1.0
description: Shared core library for iTerm2 remote streaming
publish_to: none

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  test: ^1.26.0
  mockito: ^5.4.4
  build_runner: ^2.4.0
EOF

# Host package pubspec
cat > packages/iterm2_host/pubspec.yaml << 'EOF'
name: iterm2_host
version: 0.1.0
description: macOS host service for iTerm2 remote streaming
publish_to: none

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  cloudplayplus_core:
    path: ../cloudplayplus_core
  flutter:
    sdk: flutter

dev_dependencies:
  test: ^1.26.0
  mockito: ^5.4.4
EOF

# Android client pubspec
cat > apps/android_client/pubspec.yaml << 'EOF'
name: android_client
version: 0.1.0
description: Android client for iTerm2 remote streaming
publish_to: none

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.3.0'

dependencies:
  cloudplayplus_core:
    path: ../../packages/cloudplayplus_core
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
EOF

echo "Creating test placeholders..."

mkdir -p packages/cloudplayplus_core/test
mkdir -p packages/iterm2_host/test
mkdir -p apps/android_client/test

touch packages/cloudplayplus_core/test/core_test.dart
touch packages/iterm2_host/test/host_test.dart
touch apps/android_client/test/client_test.dart

echo "Creating .gitignore..."

cat > .gitignore << 'EOF'
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
coverage/
*.log
.DS_Store
EOF

echo "Creating CI directory placeholder..."

mkdir -p scripts/ci
touch scripts/ci/.gitkeep

echo "✅ Skeleton structure created successfully"

