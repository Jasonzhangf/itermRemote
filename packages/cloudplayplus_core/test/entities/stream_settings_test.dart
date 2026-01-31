import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';

void main() {
  group('StreamSettings', () {
    test('serializes and deserializes correctly', () {
      final s = StreamSettings(
        mode: StreamMode.video,
        captureType: CaptureTargetType.iterm2Panel,
        iterm2SessionId: 'sess-123',
        cropRect: const {'x': 0.1, 'y': 0.2, 'w': 0.3, 'h': 0.4},
        framerate: 60,
        videoBitrateKbps: 3500,
        chatBufferSize: 200000,
        useTurn: true,
        turnServer: 'turn:example.com:3478',
        turnUsername: 'u',
        turnPassword: 'p',
      );

      final json = s.toJson();
      final restored = StreamSettings.fromJson(json);

      expect(restored.mode, StreamMode.video);
      expect(restored.captureType, CaptureTargetType.iterm2Panel);
      expect(restored.iterm2SessionId, 'sess-123');
      expect(restored.cropRect, s.cropRect);
      expect(restored.framerate, 60);
      expect(restored.videoBitrateKbps, 3500);
      expect(restored.chatBufferSize, 200000);
      expect(restored.useTurn, isTrue);
      expect(restored.turnServer, 'turn:example.com:3478');
      expect(restored.turnUsername, 'u');
      expect(restored.turnPassword, 'p');
    });

    test('uses defaults when fields missing', () {
      final s = StreamSettings.fromJson({});
      expect(s.mode, StreamMode.video);
      expect(s.captureType, CaptureTargetType.screen);
      expect(s.framerate, 30);
      expect(s.videoBitrateKbps, 2000);
      expect(s.chatBufferSize, 100000);
      expect(s.useTurn, isTrue);
      expect(s.turnServer, isNull);
    });

    test('parses cropRect numeric values as doubles', () {
      final s = StreamSettings.fromJson({
        'mode': 'video',
        'captureType': 'iterm2Panel',
        'cropRect': {'x': 1, 'y': 2.5, 'w': 3, 'h': 4},
      });
      expect(s.cropRect, isNotNull);
      expect(s.cropRect!['x'], 1.0);
      expect(s.cropRect!['y'], 2.5);
      expect(s.cropRect!['w'], 3.0);
      expect(s.cropRect!['h'], 4.0);
    });

    test('copyWith merges fields', () {
      final s = StreamSettings(
        mode: StreamMode.video,
        captureType: CaptureTargetType.screen,
        framerate: 30,
        videoBitrateKbps: 2000,
      );

      final updated = s.copyWith(
        mode: StreamMode.chat,
        chatBufferSize: 123,
        useTurn: false,
      );

      expect(updated.mode, StreamMode.chat);
      expect(updated.captureType, CaptureTargetType.screen);
      expect(updated.chatBufferSize, 123);
      expect(updated.useTurn, isFalse);
      expect(updated.framerate, 30);
      expect(updated.videoBitrateKbps, 2000);
    });
  });
}

