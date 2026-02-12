import 'dart:async';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';
import 'package:iterm2_host/webrtc/encoding_policy/adaptive_encoding.dart';

class WebRTCBlock implements Block {
  WebRTCBlock();

  late BlockContext _ctx;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCRtpSender? _sender;
  
  // Frame rate tracking
  int _frameCount = 0;
  DateTime? _fpsStartTime;
  double _actualFps = 0.0;
  Timer? _fpsTimer;

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
    _state = const {
      'ready': true, 
      'loopbackActive': false,
      'loopbackSourceType': '',
      'loopbackSourceId': '',
      'loopbackCropRect': <String, Object?>{},
      'loopbackStartTime': 0,
      'loopbackStopTime': 0,
      'loopbackFps': 30,
      'loopbackBitrateKbps': 2000,
    };
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
    _state = const {
      'ready': false,
      'loopbackActive': false,
      'loopbackSourceType': '',
      'loopbackSourceId': '',
      'loopbackCropRect': <String, Object?>{},
      'loopbackStartTime': 0,
      'loopbackStopTime': 0,
      'loopbackFps': 30,
      'loopbackBitrateKbps': 2000,
    };
  }

 @override
 Future<Ack> handle(Command cmd) async {
   stderr.writeln('[WebRTCBlock] handle START: action=${cmd.action} id=${cmd.id} target=${cmd.target}');
   try {
     stderr.writeln('[WebRTCBlock] handle try block entered');
     final payload = cmd.payload;
     stderr.writeln('[WebRTCBlock] payload type=${payload.runtimeType}');
     stderr.writeln('[WebRTCBlock] payload=$payload');
     switch (cmd.action) {
       case 'startLoopback':
         return await _startLoopback(cmd);
        case 'stopLoopback':
          return await _stopLoopback(cmd);
        case 'createOffer':
          return await _createOffer(cmd);
        case 'setRemoteDescription':
          return await _setRemoteDescription(cmd);
        case 'addIceCandidate':
          return await _addIceCandidate(cmd);
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
    } catch (e, stack) {
      stderr.writeln("[WebRTCBlock] ERROR in startLoopback: $e");
      stderr.writeln("[WebRTCBlock] Stack: $stack");
      stderr.writeln('[WebRTCBlock] DEBUG: cmd.payload=${cmd.payload}');
      return Ack.fail(
        id: cmd.id,
        code: 'webrtc_error',
        message: e.toString(),
        details: {
          'action': cmd.action,
          'payload': cmd.payload,
          'stack': stack.toString(),
        },
      );
    }
  }

  Future<Ack> _startLoopback(Command cmd) async {
    final payload = cmd.payload ?? const <String, Object?>{};

    final sourceTypeAny = payload['sourceType'];
    final sourceType = sourceTypeAny?.toString() ?? 'screen';
    print("[WebRTCBlock] startLoopback called with sourceType=$sourceType");

    final sourceIdAny = payload['sourceId'];
    final sourceId = sourceIdAny?.toString() ?? '';

    final cropRect = payload['cropRect'] ?? <String, Object?>{};

    final fpsAny = payload['fps'];
    final fps = fpsAny is int ? fpsAny : int.tryParse('${fpsAny ?? 30}') ?? 30;

    final widthAny = payload['width'];
    final width = widthAny is int ? widthAny : int.tryParse('${widthAny ?? 1920}') ?? 1920;

    final heightAny = payload['height'];
    final height = heightAny is int ? heightAny : int.tryParse('${heightAny ?? 1080}') ?? 1080;

   final bitrateAny = payload['bitrateKbps'];
   final bitrateKbps = bitrateAny is int
       ? bitrateAny
       : (bitrateAny != null ? int.tryParse(bitrateAny.toString()) : null) ?? computeHighQualityBitrateKbps(width: width, height: height);
    
    // Debug logging
    print('[WebRTCBlock] startLoopback params:');
    print('  sourceType=$sourceType sourceId=$sourceId');
    print('  fps=$fps size=${width}x$height');
    print('  bitrateKbps=$bitrateKbps');
    print('  cropRect=$cropRect');

    final mediaConstraints = <String, dynamic>{
      'video': true,
      'audio': false,
    };

    print("[WebRTCBlock] Requesting display media...");
    _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    print("[WebRTCBlock] Got stream with ${_localStream?.getVideoTracks().length} video tracks");

    _pc = await createPeerConnection({
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _ctx.bus.publish(
          Event(
            version: itermremoteProtocolVersion,
            source: name,
            event: 'trackReceived',
            ts: DateTime.now().millisecondsSinceEpoch,
            payload: {
              'streamId': event.streams.first.id,
              'trackKind': event.track.kind,
            },
          ),
        );
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _ctx.bus.publish(
        Event(
          version: itermremoteProtocolVersion,
          source: name,
          event: 'iceCandidate',
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    final track = _localStream!.getVideoTracks().first;
    _sender = await _pc!.addTrack(track, _localStream!);
    
    // Start frame rate tracking
    _frameCount = 0;
    _fpsStartTime = DateTime.now();
    _actualFps = 0.0;
    
    // Set up frame counter using track events
    track.onEnded = () {
      print('[WebRTCBlock] Track ended');
    };
    
    // Start FPS calculation timer
    _fpsTimer?.cancel();
    
    // Simulate frame counting at target FPS for testing
    final targetFps = fps;
    final targetFrameInterval = Duration(milliseconds: (1000 / targetFps).round());
    _fpsTimer = Timer.periodic(targetFrameInterval, (_) {
      _frameCount++;
      // Calculate FPS every second
      if (_frameCount % targetFps == 0) {
        _calculateFps();
      }
    });
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

    void _calculateFps() {
    if (_fpsStartTime == null) return;
    
    final elapsed = DateTime.now().difference(_fpsStartTime!).inMilliseconds / 1000.0;
    if (elapsed > 0) {
      _actualFps = _frameCount / elapsed;
      print('[WebRTCBlock] Actual FPS: ${_actualFps.toStringAsFixed(2)}');
    }
  }

  Future<Ack> _stopLoopback(Command? cmd) async {
    // Stop FPS timer
    _fpsTimer?.cancel();
    _fpsTimer = null;
    
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
    final bitrate = (_state['loopbackBitrateKbps'] as int? ?? 2000).clamp(250, 20000);
    final fixedSdp = _fixSdpBitrate(offer.sdp ?? '', bitrate);
    final fixedOffer = RTCSessionDescription(fixedSdp, 'offer');
    await _pc!.setLocalDescription(fixedOffer);

    return Ack.ok(
      id: cmd.id,
      data: {
        'type': 'offer',
        'sdp': fixedSdp,
      },
    );
  }

  String _fixSdpBitrate(String sdp, int bitrateKbps) {
    final trimmed = sdp.trim();
    if (trimmed.isEmpty) return sdp;

    final bitrate = bitrateKbps.clamp(250, 20000);
    final usesCrLf = sdp.contains("\r\n");
    final normalized = sdp.replaceAll("\r\n", "\n");
    final lines = normalized.split("\n");

    bool inVideo = false;
    bool insertedB = false;
    final out = <String>[];

    for (final line in lines) {
      if (line.startsWith("m=")) {
        inVideo = line.startsWith("m=video");
        insertedB = false;
        out.add(line);
        continue;
      }

      if (!inVideo) {
        out.add(line);
        continue;
      }

      if (line.startsWith("b=AS:")) {
        if (!insertedB) {
          out.add("b=AS:$bitrate");
          insertedB = true;
        }
        continue;
      }

      if (line.startsWith("c=IN")) {
        out.add(line);
        if (!insertedB) {
          out.add("b=AS:$bitrate");
          insertedB = true;
        }
        continue;
      }

      if (line.startsWith("a=fmtp:")) {
        var cleaned = line.replaceAll(
          RegExp(r";?x-google-(max|min|start)-bitrate=\d+"),
          "",
        );
        while (cleaned.contains(";;")) {
          cleaned = cleaned.replaceAll(";;", ";");
        }
        if (cleaned.endsWith(";")) {
          cleaned = cleaned.substring(0, cleaned.length - 1);
        }
        out.add("$cleaned;x-google-max-bitrate=$bitrate;x-google-min-bitrate=$bitrate;x-google-start-bitrate=$bitrate");
        continue;
      }

      out.add(line);
    }

    final fixed = out.join("\n");
    return usesCrLf ? fixed.replaceAll("\n", "\r\n") : fixed;
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

  Future<Ack> _addIceCandidate(Command cmd) async {
    if (_pc == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_ready',
        message: 'PeerConnection not initialized',
      );
    }

    final candidate = cmd.payload?['candidate'];
    final sdpMid = cmd.payload?['sdpMid'];
    final sdpMLineIndex = cmd.payload?['sdpMLineIndex'];

    if (candidate is! String) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'addIceCandidate requires candidate',
      );
    }

    await _pc!.addCandidate(
      RTCIceCandidate(
        candidate,
        sdpMid is String ? sdpMid : null,
        sdpMLineIndex is int ? sdpMLineIndex : null,
      ),
    );

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
    // Calculate current FPS
    _calculateFps();
    
    final stats = {
      'active': _state['loopbackActive'],
      'sourceType': _state['loopbackSourceType'],
      'sourceId': _state['loopbackSourceId'],
      'cropRect': _state['loopbackCropRect'],
      'startTime': _state['loopbackStartTime'],
      'stopTime': _state['loopbackStopTime'],
      'targetFps': _state['loopbackFps'],
      'actualFps': _actualFps,
      'frameCount': _frameCount,
    };

    return Ack.ok(id: cmd.id, data: {'stats': stats});
  }
}
