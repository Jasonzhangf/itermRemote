import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';

void main() {
  group('ITerm2SessionInfo', () {
    test('fromJson parses required fields', () {
      final s = ITerm2SessionInfo.fromJson({
        'id': 'sess-1',
        'title': '1.1.1',
        'detail': 'bash',
        'index': 3,
      });
      expect(s.sessionId, 'sess-1');
      expect(s.title, '1.1.1');
      expect(s.detail, 'bash');
      expect(s.index, 3);
      expect(s.frame, isNull);
      expect(s.windowFrame, isNull);
    });

    test('fromJson parses frame/windowFrame numeric values as doubles', () {
      final s = ITerm2SessionInfo.fromJson({
        'id': 'sess-1',
        'title': '1',
        'detail': 'd',
        'index': 0,
        'frame': {'x': 1, 'y': 2.5, 'w': 3, 'h': 4},
        'windowFrame': {'x': 0, 'y': 0, 'w': 800, 'h': 600},
      });
      expect(s.frame, isNotNull);
      expect(s.frame!['x'], 1.0);
      expect(s.frame!['y'], 2.5);
      expect(s.frame!['w'], 3.0);
      expect(s.frame!['h'], 4.0);
      expect(s.windowFrame!['w'], 800.0);
    });

    test('toJson roundtrips', () {
      final original = ITerm2SessionInfo(
        sessionId: 'sess-9',
        title: 't',
        detail: 'd',
        index: 9,
        frame: const {'x': 1.0, 'y': 2.0, 'w': 3.0, 'h': 4.0},
        windowFrame: const {'x': 0.0, 'y': 0.0, 'w': 10.0, 'h': 20.0},
      );
      final json = original.toJson();
      final restored = ITerm2SessionInfo.fromJson(json);
      expect(restored.sessionId, original.sessionId);
      expect(restored.title, original.title);
      expect(restored.detail, original.detail);
      expect(restored.index, original.index);
      expect(restored.frame, original.frame);
      expect(restored.windowFrame, original.windowFrame);
    });
  });
}

