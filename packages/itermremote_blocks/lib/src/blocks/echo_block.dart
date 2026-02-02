import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';
/// Simple echo block for testing and initial daemon skeleton.
/// Returns the payload as-is for the 'echo' action.
class EchoBlock implements Block {
  EchoBlock() : _name = 'echo';

  @override
  final String _name;

  @override
  String get name => _name;

  @override
  Map<String, Object?> get state => {'ready': true};

  @override
  Future<void> init(BlockContext ctx) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<Ack> handle(Command cmd) async {
    if (cmd.action == 'echo') {
      return Ack.ok(id: cmd.id, data: {'echo': cmd.payload});
    }
    return Ack.fail(
      id: cmd.id,
      code: 'unknown_action',
      message: 'Unknown action: ${cmd.action}',
    );
  }
}
