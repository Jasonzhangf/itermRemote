import 'dart:io';

import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('ITerm2Bridge (mock scripts)', () {
    late ITerm2Bridge bridge;

    // Note: CI sets ITERMREMOTE_ITERM2_MOCK=1 before running tests.

    setUp(() {
      bridge = ITerm2Bridge();
    });

    test('getSessions returns a list', () async {
      final sessions = await bridge.getSessions();
      expect(sessions.length, 2);
      expect(sessions[0].sessionId, 'session-1');
      expect(sessions[1].sessionId, 'session-2');
    });

    test('activateSession returns metadata', () async {
      final meta = await bridge.activateSession('session-1');
      expect(meta['sessionId'], 'session-1');
      // windowId should be present and numeric, but its exact value is not
      // important for most logic (crop uses frames). Keep the assertion loose
      // to avoid CI flakes when mock scripts change.
      expect(meta['windowId'], isA<num>());
      expect(meta['frame'], isNotNull);
      expect(meta['windowFrame'], isNotNull);
    });

    test('sendText returns ok', () async {
      final ok = await bridge.sendText('session-1', 'echo hello');
      expect(ok, isTrue);
    });

    test('readSessionBuffer returns decoded text', () async {
      final text = await bridge.readSessionBuffer('session-1', 100000);
      expect(text, contains('Mock session buffer'));
      expect(text, contains('session-1'));
    });
  });
}
