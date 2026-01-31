import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';

void main() {
  group('CaptureTargetType', () {
    test('toJson converts to string', () {
      expect(CaptureTargetType.screen.toJson(), 'screen');
      expect(CaptureTargetType.window.toJson(), 'window');
      expect(CaptureTargetType.iterm2Panel.toJson(), 'iterm2Panel');
    });

    test('fromJson parses string to enum', () {
      expect(CaptureTargetTypeExtension.fromJson('screen'),
          CaptureTargetType.screen);
      expect(CaptureTargetTypeExtension.fromJson('window'),
          CaptureTargetType.window);
      expect(CaptureTargetTypeExtension.fromJson('iterm2Panel'),
          CaptureTargetType.iterm2Panel);
    });

    test('fromJson falls back to screen for unknown values', () {
      expect(CaptureTargetTypeExtension.fromJson('invalid'),
          CaptureTargetType.screen);
      expect(
          CaptureTargetTypeExtension.fromJson(''), CaptureTargetType.screen);
    });
  });
}

