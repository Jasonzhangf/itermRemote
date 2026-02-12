import 'package:test/test.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

void main() {
  group('EchoBlock', () {
    test('name is "echo"', () {
      final block = EchoBlock();
      expect(block.name, 'echo');
    });

    test('onCommand echoes payload', () async {
      final block = EchoBlock();
      final bus = InMemoryEventBus();
      final ctx = BlockContext(bus: bus);
      await block.init(ctx);

      final cmd = Command(
        version: 1,
        id: '1',
        target: 'echo',
        action: 'echo',
        payload: {'msg': 'hello'},
      );
      final ack = await block.handle(cmd);

      expect(ack.success, isTrue);
      expect((ack.data?['echo'] as Map)['msg'], 'hello');

      await block.dispose();
    });

    test('dispose completes', () async {
      final block = EchoBlock();
      final bus = InMemoryEventBus();
      final ctx = BlockContext(bus: bus);
      await block.init(ctx);
      await block.dispose();
    });
  });
}
