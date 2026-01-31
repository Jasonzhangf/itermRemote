import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';

void main() {
  group('StreamMode', () {
    test('toJson converts to string', () {
      expect(StreamMode.video.toJson(), 'video');
      expect(StreamMode.chat.toJson(), 'chat');
    });

    test('fromJson parses string to enum', () {
      expect(StreamModeExtension.fromJson('video'), StreamMode.video);
      expect(StreamModeExtension.fromJson('chat'), StreamMode.chat);
    });

    test('fromJson falls back to video for unknown values', () {
      expect(StreamModeExtension.fromJson('invalid'), StreamMode.video);
      expect(StreamModeExtension.fromJson(''), StreamMode.video);
    });
  });
}

