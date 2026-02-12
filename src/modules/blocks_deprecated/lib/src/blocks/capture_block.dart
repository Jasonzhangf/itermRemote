import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

class CaptureBlock implements Block {
  CaptureBlock({required ITerm2Bridge iterm2}) : _iterm2 = iterm2;

  final ITerm2Bridge _iterm2;
  late BlockContext _ctx;

  Map<String, Object?> _state = const {
    'ready': false,
  };

  @override
  String get name => 'capture';

  @override
  Map<String, Object?> get state => _state;

  @override
  Future<void> init(BlockContext ctx) async {
    _ctx = ctx;
    _state = const {'ready': true};
    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'ready',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: _state,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _state = const {'ready': false};
  }

  @override
  Future<Ack> handle(Command cmd) async {
    try {
      switch (cmd.action) {
        case 'activateAndComputeCrop':
          return await _activateAndComputeCrop(cmd);
        case 'selectSource':
          return await _selectSource(cmd);
        case 'getState':
          return Ack.ok(id: cmd.id, data: _state);
        default:
          return Ack.fail(
            id: cmd.id,
            code: 'unknown_action',
            message: 'Unknown action: ${cmd.action}',
          );
      }
    } catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'capture_error',
        message: e.toString(),
      );
    }
  }

  Future<Ack> _activateAndComputeCrop(Command cmd) async {
    final sessionId = cmd.payload?['sessionId'];
    if (sessionId is! String || sessionId.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'activateAndComputeCrop requires payload.sessionId',
      );
    }

    final meta = await _iterm2.activateSession(sessionId);
    _state = {
      ..._state,
      'lastActivatedSessionId': sessionId,
      'lastActivateMeta': meta,
    };

    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'activated',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'sessionId': sessionId,
          'meta': meta,
        },
      ),
    );

    return Ack.ok(id: cmd.id, data: {'meta': meta});
  }

  Future<Ack> _selectSource(Command cmd) async {
    final type = cmd.payload?['type'];
    final windowId = cmd.payload?['windowId'];
    final iterm2SessionId = cmd.payload?['iterm2SessionId'];

    if (type is! String || type.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'selectSource requires payload.type (screen/window/iterm2)',
      );
    }

    _state = {
      ..._state,
      'selectedSourceType': type,
      'selectedWindowId': windowId,
      'selectedITerm2SessionId': iterm2SessionId,
    };

    if (type == 'iterm2' &&
        iterm2SessionId is String &&
        iterm2SessionId.isNotEmpty) {
      final meta = await _iterm2.activateSession(iterm2SessionId);
      _state = {
        ..._state,
        'lastActivateMeta': meta,
      };
    }

    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'sourceSelected',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'type': type,
          'windowId': windowId,
          'iterm2SessionId': iterm2SessionId,
        },
      ),
    );

    return Ack.ok(id: cmd.id, data: _state);
  }
}
