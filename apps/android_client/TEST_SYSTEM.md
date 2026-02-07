# Android Client 测试系统

## 测试架构

```
┌─────────────────────────────────────────┐
│  1. UI 自动测试 (Monkey/Integration)    │
│     - macOS / Android 系统 UI 覆盖       │
│     - 自动点击、滑动、输入                │
│     - 截图对比验证                       │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  2. App 编排测试 (回环)                  │
│     - Host + Client 本地连接             │
│     - WebSocket 消息验证                 │
│     - 状态机转换测试                     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  3. Block 单元测试 (复用)                │
│     - packages/itermremote_blocks       │
│     - 独立功能验证                       │
│     - Mock 数据驱动                      │
└─────────────────────────────────────────┘
```

## 1. UI 自动测试

### Flutter Integration Test

```dart
// test_driver/app_test.dart
import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('Android Client UI', () {
    late FlutterDriver driver;

    setUpAll(() async {
      driver = await FlutterDriver.connect();
    });

    tearDownAll(() async {
      await driver.close();
    });

    test('navigate through all pages', () async {
      // Connect Page
      await driver.waitFor(find.text('Connect to Host'));
      
      // Navigate to Control
      await driver.tap(find.text('Control'));
      await driver.waitFor(find.text('Streaming'));
      
      // Navigate to Shortcuts
      await driver.tap(find.text('Shortcuts'));
      await driver.waitFor(find.text('Quick Switch'));
      
      // Navigate to Settings
      await driver.tap(find.text('Settings'));
      await driver.waitFor(find.text('Settings'));
    });

    test('floating shortcut button', () async {
      await driver.tap(find.text('Control'));
      
      // Tap floating button
      await driver.tap(find.byType('FloatingShortcutButton'));
      
      // Verify toolbar expands
      await driver.waitFor(find.text('Desktop'));
      await driver.waitFor(find.text('Target'));
    });
  });
}
```

### Monkey Test (Android)

```bash
# scripts/test/monkey_test.sh
#!/bin/bash

# Android Monkey 测试
adb shell monkey \
  -p com.itermremote.android_client \
  --throttle 100 \
  --pct-touch 40 \
  --pct-motion 30 \
  --pct-trackball 10 \
  --pct-nav 10 \
  --pct-majornav 5 \
  --pct-appswitch 5 \
  -v -v -v 10000 \
  > /tmp/monkey_test.log 2>&1

# 检查崩溃
if grep -q "CRASH" /tmp/monkey_test.log; then
  echo "❌ Monkey test found crashes"
  exit 1
else
  echo "✅ Monkey test passed"
fi
```

### macOS UI Automation

```bash
# scripts/test/macos_ui_test.sh
#!/bin/bash

# 使用 AppleScript 自动化测试
osascript << APPLESCRIPT
tell application "System Events"
  tell process "android_client"
    # 点击底部导航
    click button "Control"
    delay 1
    
    # 点击悬浮按钮
    click button "FloatingShortcutButton"
    delay 1
    
    # 验证工具栏展开
    if exists button "Desktop" then
      log "✅ Toolbar expanded"
    else
      error "❌ Toolbar not found"
    end if
  end tell
end tell
APPLESCRIPT
```

## 2. App 编排回环测试

### Host + Client 本地连接

```dart
// integration_test/loopback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Loopback Connection Test', () {
    testWidgets('connect to local host', (tester) async {
      // 1. 启动 host_daemon
      final daemon = await Process.start(
        'flutter',
        ['run', '-d', 'macos', '--headless'],
        workingDirectory: '../host_daemon',
      );

      await Future.delayed(Duration(seconds: 3));

      // 2. 启动 client
      await tester.pumpWidget(ITerm2RemoteApp());
      await tester.pumpAndSettle();

      // 3. 连接到本地 host
      await tester.tap(find.text('localhost'));
      await tester.pumpAndSettle();

      // 4. 验证连接成功
      expect(find.text('Connected'), findsOneWidget);

      // 5. 测试 panel 切换
      await tester.tap(find.text('Shortcuts'));
      await tester.tap(find.text('Terminal 2'));
      await tester.pumpAndSettle();

      // 6. 验证切换成功
      expect(find.text('Active'), findsOneWidget);

      // 7. 清理
      daemon.kill();
    });
  });
}
```

### WebSocket 消息验证

```dart
// test/websocket_test.dart
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('WebSocket API', () {
    late WebSocketChannel channel;

    setUp(() {
      channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:8765'),
      );
    });

    tearDown(() {
      channel.sink.close();
    });

    test('get state', () async {
      channel.sink.add(jsonEncode({'cmd': 'get_state'}));
      
      final response = await channel.stream.first;
      final data = jsonDecode(response);
      
      expect(data['connected'], isA<bool>());
      expect(data['panels'], isA<List>());
    });

    test('switch panel', () async {
      channel.sink.add(jsonEncode({
        'cmd': 'switch_panel',
        'panel_id': 'panel-2',
      }));
      
      final response = await channel.stream.first;
      final data = jsonDecode(response);
      
      expect(data['status'], 'ok');
      expect(data['active_panel'], 'panel-2');
    });
  });
}
```

## 3. Block 单元测试

Block 层测试直接复用 `packages/itermremote_blocks/test/`：

```dart
// packages/itermremote_blocks/test/iterm2_block_test.dart
import 'package:test/test.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';

void main() {
  group('ITerm2Block', () {
    late ITerm2Block block;

    setUp(() {
      block = ITerm2Block();
    });

    test('list panels', () async {
      final panels = await block.listPanels();
      expect(panels, isA<List>());
    });

    test('activate panel', () async {
      await block.activatePanel('panel-1');
      final active = await block.getActivePanel();
      expect(active, 'panel-1');
    });
  });
}
```

## 测试运行

### 运行所有测试

```bash
# scripts/test/run_all_tests.sh
#!/bin/bash
set -e

echo "🧪 Running Android Client Tests..."

# 1. Block 单元测试
echo "1️⃣ Block tests..."
cd packages/itermremote_blocks
flutter test
cd -

# 2. App 编排回环测试
echo "2️⃣ Loopback tests..."
cd apps/android_client
flutter test integration_test/loopback_test.dart
cd -

# 3. UI 自动测试
echo "3️⃣ UI tests..."
cd apps/android_client
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart
cd -

# 4. Monkey 测试 (Android only)
if [ "$PLATFORM" = "android" ]; then
  echo "4️⃣ Monkey tests..."
  bash scripts/test/monkey_test.sh
fi

echo "✅ All tests passed!"
```

### CI 集成

```yaml
# .github/workflows/android_client_tests.yml
name: Android Client Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      
      - name: Install dependencies
        run: flutter pub get
      
      - name: Block tests
        run: cd packages/itermremote_blocks && flutter test
      
      - name: Loopback tests
        run: |
          cd apps/android_client
          flutter test integration_test/loopback_test.dart
      
      - name: UI tests
        run: |
          cd apps/android_client
          flutter drive \
            --driver=test_driver/integration_test.dart \
            --target=integration_test/app_test.dart
```

## 测试覆盖率

```bash
# 生成覆盖率报告
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## 测试数据

测试使用 Mock 数据，定义在：

```
apps/android_client/test/fixtures/
├── panels.json          # Panel 列表
├── windows.json         # Window 列表
└── connection_state.json # 连接状态
```
