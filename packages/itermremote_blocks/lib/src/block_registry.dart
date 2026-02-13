import 'package:itermremote_protocol/itermremote_protocol.dart';

import 'block.dart';

class BlockRegistry {
  BlockRegistry();

  final Map<String, Block> _blocks = {};

  Iterable<Block> get all => _blocks.values;

  Block? get(String name) => _blocks[name];

  void register(Block block) {
    final name = block.name;
    if (_blocks.containsKey(name)) {
      throw StateError('Block already registered: $name');
    }
    _blocks[name] = block;
  }

  /// Route a command to the appropriate block.
  Future<Ack> route(Command cmd) async {
    var block = _blocks[cmd.target] ?? _blocks[cmd.target.toLowerCase()];
    print('[BlockRegistry] route: target=\${cmd.target}, available=\${_blocks.keys.toList()}, found=\${block != null}');
    if (block == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'unknown_target',
        message: 'No such block: ${cmd.target}',
        details: {'target': cmd.target},
      );
    }
    try {
      return await block.handle(cmd);
    } catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'block_error',
        message: 'Block threw while handling ${cmd.action}',
        details: {'target': cmd.target, 'action': cmd.action, 'error': e.toString()},
      );
    }
  }

  Map<String, Object?> dumpState() {
    final out = <String, Object?>{};
    for (final b in _blocks.values) {
      out[b.name] = b.state;
    }
    return out;
  }

  Future<void> dispose() async {
    for (final b in _blocks.values) {
      await b.dispose();
    }
    _blocks.clear();
  }
}
