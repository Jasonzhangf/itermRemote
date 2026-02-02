import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:test/test.dart';

class _NoopBus implements EventBus {
  @override
  void publish(Event evt) {}
}

class _EchoBlock implements Block {
  _EchoBlock(this._name);

  final String _name;

  @override
  String get name => _name;

  @override
  Future<void> init(BlockContext ctx) async {}

  @override
  Future<void> dispose() async {}

  @override
  Map<String, Object?> get state => {'ready': true};

  @override
  Future<Ack> handle(Command cmd) async {
    if (cmd.action != 'echo') {
      return Ack.fail(id: cmd.id, code: 'unknown_action', message: 'unknown');
    }
    return Ack.ok(id: cmd.id, data: {'payload': cmd.payload});
  }
}

void main() {
  test('route unknown target -> ack error', () async {
    final r = BlockRegistry();
    final ack = await r.route(
      const Command(
        version: itermremoteProtocolVersion,
        id: '1',
        target: 'missing',
        action: 'x',
      ),
    );
    expect(ack.success, false);
    expect(ack.error!.code, 'unknown_target');
  });

  test('route known target -> block handles', () async {
    final r = BlockRegistry();
    final b = _EchoBlock('echo');
    await b.init(BlockContext(bus: _NoopBus()));
    r.register(b);

    final ack = await r.route(
      const Command(
        version: itermremoteProtocolVersion,
        id: '1',
        target: 'echo',
        action: 'echo',
        payload: {'a': 1},
      ),
    );
    expect(ack.success, true);
    expect(ack.data, {'payload': {'a': 1}});
  });
}

