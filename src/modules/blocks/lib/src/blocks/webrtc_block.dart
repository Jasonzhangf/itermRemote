import 'dart:async';

import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

/// WebRTC block for loopback testing.
/// This block provides a minimal loopback implementation for testing
/// video encoding and cropping without requiring a remote client.
class WebRTCBlock implements Block {
  WebRTCBlock();

  late BlockContext _ctx;

  Map<String, Object?> _state = const {
    'ready': false,
    'loopbackActive': false,
  };

  @override
  String get name => 'webrtc';

  @override
  Map<String, Object?> get state => _state;

  @override
  Future<void> init(BlockContext ctx) async {
    _ctx = ctx;
    _state = const {'ready': true, 'loopbackActive': false};
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
    _state = const {'ready': false, 'loopbackActive': false};
  }

  @override
  Future<Ack> handle(Command cmd) async {
    try {
      switch (cmd.action) {
        case 'startLoopback':
          return await _startLoopback(cmd);
        case 'stopLoopback':
          return await _stopLoopback(cmd);
        case 'getLoopbackStats':
          return await _getLoopbackStats(cmd);
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
        code: 'webrtc_error',
        message: e.toString(),
      );
    }
  }

  Future<Ack> _startLoopback(Command cmd) async {
    final sourceType = cmd.payload?['sourceType'];
    final sourceId = cmd.payload?['sourceId'];
    final cropRect = cmd.payload?['cropRect'];

    if (sourceType is! String || sourceType.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'startLoopback requires payload.sourceType',
      );
    }

    _state = {
      ..._state,
      'loopbackActive': true,
      'loopbackSourceType': sourceType,
      'loopbackSourceId': sourceId,
      'loopbackCropRect': cropRect,
      'loopbackStartTime': DateTime.now().millisecondsSinceEpoch,
    };

    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'loopbackStarted',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'sourceType': sourceType,
          'sourceId': sourceId,
          'cropRect': cropRect,
        },
      ),
    );

    return Ack.ok(id: cmd.id, data: _state);
  }

  Future<Ack> _stopLoopback(Command cmd) async {
    _state = {
      ..._state,
      'loopbackActive': false,
      'loopbackStopTime': DateTime.now().millisecondsSinceEpoch,
    };

    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'loopbackStopped',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: _state,
      ),
    );

    return Ack.ok(id: cmd.id, data: _state);
  }

  Future<Ack> _getLoopbackStats(Command cmd) async {
    final stats = {
      'active': _state['loopbackActive'],
      'sourceType': _state['loopbackSourceType'],
      'sourceId': _state['loopbackSourceId'],
      'cropRect': _state['loopbackCropRect'],
      'startTime': _state['loopbackStartTime'],
      'stopTime': _state['loopbackStopTime'],
    };

    return Ack.ok(id: cmd.id, data: {'stats': stats});
  }
}
