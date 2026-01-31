import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration tests for cross-module settings serialization.
void main() {
  group('StreamSettings Integration', () {
    test('[E1] StreamSettings JSON roundtrip keeps key fields', () {
      final settings = StreamSettings(
        mode: StreamMode.chat,
        captureType: CaptureTargetType.iterm2Panel,
        iterm2SessionId: 'sess-1',
        framerate: 30,
        videoBitrateKbps: 3000,
        cropRect: const {
          'x': 10,
          'y': 20,
          'width': 300,
          'height': 200,
        },
      );

      final json = settings.toJson();
      final decoded = StreamSettings.fromJson(json);

      expect(decoded.mode, StreamMode.chat);
      expect(decoded.captureType, CaptureTargetType.iterm2Panel);
      expect(decoded.iterm2SessionId, 'sess-1');
      expect(decoded.framerate, 30);
      expect(decoded.videoBitrateKbps, 3000);
      expect(decoded.cropRect?['width'], 300);
    });
  });
}
