import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';

/// Integration tests for ITerm2Bridge.
///
/// Verifies Python script invocation and data flow between Dart and Python.
void main() {
  group('ITerm2Bridge Integration', () {
    late ITerm2Bridge bridge;

    setUpAll(() {
      // Ensure script paths resolve from repository root.
      Directory.current = Directory('../../');
    });

    setUp(() {
      bridge = ITerm2Bridge();
    });

    test('[E2][E3][E4] scripts are available before running integration',
        () async {
      // Ensure mock scripts are available.
      // Also export mock env var for this process: ITerm2Bridge checks
      // Platform.environment to decide which script suffix to use.
      final res = await Process.run(
        'bash',
        ['-lc', 'bash scripts/test/setup_iterm2_mock.sh'],
        environment: {
          ...Platform.environment,
          'ITERMREMOTE_ITERM2_MOCK': '1',
        },
      );
      expect(res.exitCode, 0);
      // Match mock mode used in CI test harness.
      Platform.environment['ITERMREMOTE_ITERM2_MOCK'] = '1';

      final sessions = await bridge.getSessions();
      expect(sessions, isNotEmpty);
      expect(sessions.every((s) => s.sessionId.isNotEmpty), isTrue);
      expect(sessions.every((s) => s.title.isNotEmpty), isTrue);
      expect(sessions.every((s) => s.index >= 0), isTrue);

      final sessionId = sessions.first.sessionId;
      final metadata = await bridge.activateSession(sessionId);
      expect(metadata, isA<Map<String, dynamic>>());
      expect(metadata.containsKey('sessionId'), isTrue);

      final result = await bridge.sendText(sessionId, 'echo hello\n');
      expect(result, isTrue);

      final buffer = await bridge.readSessionBuffer(sessionId, 1024);
      expect(buffer, isA<String>());

      // Invalid session ID should not crash.
      final bad = await bridge.sendText('invalid-session-id', 'test');
      expect(bad, isA<bool>());
    });
  });
}
