import 'dart:async';
import 'dart:io';

import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

class ITerm2Block implements Block {
  ITerm2Block({required ITerm2Bridge bridge}) : _bridge = bridge;

  final ITerm2Bridge _bridge;
  late BlockContext _ctx;

  Map<String, Object?> _state = const {
    'ready': false,
  };

  @override
  String get name => 'iterm2';

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
        case 'getSessions':
          return await _getSessions(cmd);
        case 'activateSession':
          return await _activateSession(cmd);
        case 'sendText':
          return await _sendText(cmd);
        case 'readSessionBuffer':
          return await _readSessionBuffer(cmd);
        case 'getWindowFrames':
          return await _getWindowFrames(cmd);
        default:
          return Ack.fail(
            id: cmd.id,
            code: 'unknown_action',
            message: 'Unknown action: ${cmd.action}',
          );
      }
    } on TimeoutException catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'timeout',
        message: e.message ?? 'Timed out while handling ${cmd.action}',
      );
    } catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'iterm2_error',
        message: e.toString(),
      );
    }
  }

  Future<Ack> _getSessions(Command cmd) async {
    final sessions = await _withTimeout(_bridge.getSessions());
    return Ack.ok(
      id: cmd.id,
      data: {
        'sessions': sessions.map((s) => s.toJson()).toList(),
      },
    );
  }

  Future<Ack> _activateSession(Command cmd) async {
    final sessionId = cmd.payload?['sessionId'];
    if (sessionId is! String || sessionId.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'activateSession requires payload.sessionId',
      );
    }
    final meta = await _withTimeout(_bridge.activateSession(sessionId));
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

  Future<Ack> _sendText(Command cmd) async {
    final sessionId = cmd.payload?['sessionId'];
    final text = cmd.payload?['text'];
    if (sessionId is! String || sessionId.trim().isEmpty || text is! String) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'sendText requires payload.sessionId and payload.text',
      );
    }
    final ok = await _withTimeout(_bridge.sendText(sessionId, text));
    return Ack.ok(id: cmd.id, data: {'ok': ok});
  }

  Future<Ack> _readSessionBuffer(Command cmd) async {
    final sessionId = cmd.payload?['sessionId'];
    final maxBytes = cmd.payload?['maxBytes'];
    if (sessionId is! String || sessionId.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'readSessionBuffer requires payload.sessionId',
      );
    }
    final mb = (maxBytes is num) ? maxBytes.toInt() : 65536;
    final text = await _withTimeout(_bridge.readSessionBuffer(sessionId, mb));
    return Ack.ok(id: cmd.id, data: {'text': text});
  }

  Future<Ack> _getWindowFrames(Command cmd) async {
    final frames = await _withTimeout(_bridge.getWindowFrames());
    return Ack.ok(id: cmd.id, data: {'windows': frames});
  }

  Future<T> _withTimeout<T>(Future<T> future) {
    final timeoutMs = int.tryParse(
            Platform.environment['ITERMREMOTE_BLOCK_TIMEOUT_MS'] ?? '') ??
        6000;
    return future.timeout(Duration(milliseconds: timeoutMs));
  }
}
