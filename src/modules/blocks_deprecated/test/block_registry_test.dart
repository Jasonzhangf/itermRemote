import 'package:test/test.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';

void main() {
  group('BlockRegistry', () {
    test('register and get by name', () {
      final registry = BlockRegistry();
      final echo = EchoBlock();
      registry.register(echo);

      expect(registry.get('echo'), echo);
      expect(registry.all.length, 1);
    });

    test('get returns null for unknown block', () {
      final registry = BlockRegistry();
      expect(registry.get('unknown'), isNull);
    });

    test('all returns registered blocks', () {
      final registry = BlockRegistry();
      final echo = EchoBlock();
      registry.register(echo);

      expect(registry.all.length, 1);
      expect(registry.all.first, echo);
    });
  });
}
