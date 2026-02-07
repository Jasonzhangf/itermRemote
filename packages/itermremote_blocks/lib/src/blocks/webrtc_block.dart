import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

/// WebRTC block for loopback testing.
/// This block provides a minimal loopback implementation for testing
/// video encoding and cropping without requiring a remote client.
class WebRTCBlock implements Block {
  WebRTCBlock();

  late BlockContext _ctx;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCRtpSender? _sender;

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
    await _stopLoopback(null);
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
        case 'createOffer':
          return await _createOffer(cmd);
        case 'setRemoteDescription':
          return await _setRemoteDescription(cmd);
        case 'createAnswer':
          return await _createAnswer(cmd);
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
    final fps = cmd.payload?['fps'] ?? 30;
    final bitrateKbps = cmd.payload?['bitrateKbps'] ?? 1000;

    if (sourceType is! String || sourceType.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'startLoopback requires payload.sourceType',
      );
    }

    // Setup constraints. For desktop capture, flutter_webrtc expects the
    // screen/window source in the video constraints on desktop.
    final videoConstraints = <String, dynamic>{
      'mandatory': {
        'frameRate': fps,
      },
      'optional': {},
      if (cropRect != null) 'cropRect': cropRect,
    };

    if (sourceType == 'desktop' || sourceType == 'screen' || sourceType == 'window') {
      videoConstraints['mandatory']['chromeMediaSource'] = 'desktop';
      if (sourceId != null) {
        videoConstraints['mandatory']['chromeMediaSourceId'] = sourceId;
      }
    } else if (sourceId != null) {
      videoConstraints['deviceId'] = {'exact': sourceId};
    }

    final constraints = <String, dynamic>{
      'audio': false,
      'video': videoConstraints,
    };

    // For desktop/screen/window capture, use getDisplayMedia instead of getUserMedia.
    // getUserMedia is for camera/microphone; getDisplayMedia is for screen capture.
    if (sourceType == 'desktop' || sourceType == 'screen' || sourceType == 'window') {
      _localStream = await navigator.mediaDevices.getDisplayMedia(constraints);
    } else {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    }

    // Create peer connection
    _pc = await createPeerConnection({
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    // Add track
    final track = _localStream!.getVideoTracks().first;
    _sender = await _pc!.addTrack(track, _localStream!);
    _state = {
      ..._state,
      'loopbackActive': true,
      'loopbackSourceType': sourceType,
      'loopbackSourceId': sourceId,
      'loopbackCropRect': cropRect,
      'loopbackStartTime': DateTime.now().millisecondsSinceEpoch,
      'loopbackFps': fps,
      'loopbackBitrateKbps': bitrateKbps,
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
          'fps': fps,
          'bitrateKbps': bitrateKbps,
        },
      ),
    );

    return Ack.ok(id: cmd.id, data: _state);
  }

  Future<Ack> _stopLoopback(Command? cmd) async {
    if (_localStream != null) {
      await _localStream!.dispose();
      _localStream = null;
    }
    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }
    _sender = null;

    _state = {
      ..._state,
      'loopbackActive': false,
      'loopbackStopTime': DateTime.now().millisecondsSinceEpoch,
    };

    if (cmd != null) {
      _ctx.bus.publish(
        Event(
          version: itermremoteProtocolVersion,
          source: name,
          event: 'loopbackStopped',
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: _state,
        ),
      );
    }

    return Ack.ok(id: cmd?.id ?? '', data: _state);
  }

  Future<Ack> _createOffer(Command cmd) async {
    if (_pc == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_ready',
        message: 'PeerConnection not initialized',
      );
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    return Ack.ok(
      id: cmd.id,
      data: {
        'type': 'offer',
        'sdp': offer.sdp,
      },
    );
  }

  Future<Ack> _setRemoteDescription(Command cmd) async {
    if (_pc == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_ready',
        message: 'PeerConnection not initialized',
      );
    }

    final type = cmd.payload?['type'];
    final sdp = cmd.payload?['sdp'];

    if (type is! String || sdp is! String) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'setRemoteDescription requires type and sdp',
      );
    }

    final description = RTCSessionDescription(sdp, type);
    await _pc!.setRemoteDescription(description);

    return Ack.ok(id: cmd.id, data: {'success': true});
  }

  Future<Ack> _createAnswer(Command cmd) async {
    if (_pc == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_ready',
        message: 'PeerConnection not initialized',
      );
    }

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    return Ack.ok(
      id: cmd.id,
      data: {
        'type': 'answer',
        'sdp': answer.sdp,
      },
    );
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
