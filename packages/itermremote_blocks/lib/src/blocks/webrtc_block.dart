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
  
  // ICE candidate buffering (cloudplayplus_stone approach)
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  
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
   stderr.writeln('[WebRTCBlock] handle START: action=\${cmd.action} id=\${cmd.id} target=\${cmd.target}');
   try {
     final payload = cmd.payload;
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
            message: 'Unknown action: \${cmd.action}',
          );
      }
    } catch (e, stack) {
      stderr.writeln("[WebRTCBlock] ERROR: \$e");
      stderr.writeln("[WebRTCBlock] Stack: \$stack");
      return Ack.fail(
        id: cmd.id,
        code: 'webrtc_error',
        message: e.toString(),
        details: {
          'action': cmd.action,
          'stack': stack.toString(),
        },
      );
    }
  }

  Future<Ack> _startLoopback(Command cmd) async {
    final payload = cmd.payload ?? const <String, Object?>{};

    final sourceTypeAny = payload['sourceType'];
    final sourceType = sourceTypeAny?.toString() ?? 'screen';
    print("[WebRTCBlock] startLoopback called with sourceType=\$sourceType");

    final sourceIdAny = payload['sourceId'];
    final sourceId = sourceIdAny?.toString() ?? '';

    final cropRect = payload['cropRect'] ?? <String, Object?>{};

    final fpsAny = payload['fps'];
    final fps = fpsAny is int ? fpsAny : int.tryParse('\${fpsAny ?? 30}') ?? 30;

    final widthAny = payload['width'];
    final width = widthAny is int ? widthAny : int.tryParse('\${widthAny ?? 1920}') ?? 1920;

    final heightAny = payload['height'];
    final height = heightAny is int ? heightAny : int.tryParse('\${heightAny ?? 1080}') ?? 1080;

   final bitrateAny = payload['bitrateKbps'];
   final bitrateKbps = bitrateAny is int
       ? bitrateAny
       : (bitrateAny != null ? int.tryParse(bitrateAny.toString()) : null) ?? computeHighQualityBitrateKbps(width: width, height: height);
    
    print('[WebRTCBlock] startLoopback params:');
    print('  sourceType=\$sourceType sourceId=\$sourceId');
    print('  fps=\$fps size=\${width}x\$height');
    print('  bitrateKbps=\$bitrateKbps');
    print('  cropRect=\$cropRect');

    // Request display media with proper constraints for high frame rate
    final mediaConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth': width,
          'minHeight': height,
          'maxWidth': width,
          'maxHeight': height,
          'minFrameRate': fps,
          'maxFrameRate': fps,
        },
        'optional': [
          {'googCpuOveruseDetection': true},
        ],
      },
    };

    print("[WebRTCBlock] Requesting display media with constraints: \$mediaConstraints");
    _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    print("[WebRTCBlock] Got stream with \${_localStream?.getVideoTracks().length} video tracks");

    // CRITICAL: Use unified-plan (cloudplayplus_stone approach)
    _pc = await createPeerConnection({
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
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
      
      // cloudplayplus_stone: buffer candidates until remote description is set
      if (!_remoteDescriptionSet) {
        _pendingCandidates.add(candidate);
        print('[WebRTCBlock] Buffered ICE candidate (waiting for remote desc)');
      } else {
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
      }
    };

   final track = _localStream!.getVideoTracks().first;
   _sender = await _pc!.addTrack(track, _localStream!);
   
    // Apply encoding parameters via sender.parameters for max framerate and bitrate
    try {
      final params = _sender!.parameters;
      if (params.encodings != null && params.encodings!.isNotEmpty) {
        for (final encoding in params.encodings!) {
          encoding.maxBitrate = bitrateKbps * 1000;
          encoding.maxFramerate = fps;
          encoding.active = true;
          encoding.scaleResolutionDownBy = 1.0;
        }
      } else {
        params.encodings = <RTCRtpEncoding>[
          RTCRtpEncoding(
            active: true,
            maxBitrate: bitrateKbps * 1000,
            maxFramerate: fps,
            scaleResolutionDownBy: 1.0,
          ),
        ];
      }
      await _sender!.setParameters(params);
    } catch (e) {
      print('[WebRTCBlock] WARNING: setParameters failed: \$e');
    }
    
    // Start frame rate tracking
    _frameCount = 0;
    _fpsStartTime = DateTime.now();
    _actualFps = 0.0;
    
    track.onEnded = () {
      print('[WebRTCBlock] Track ended');
    };
    
    _fpsTimer?.cancel();
    final targetFps = fps;
    final targetFrameInterval = Duration(milliseconds: (1000 / targetFps).round());
    _fpsTimer = Timer.periodic(targetFrameInterval, (_) {
      _frameCount++;
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
      print('[WebRTCBlock] Actual FPS: \${_actualFps.toStringAsFixed(2)}');
    }
  }

  Future<Ack> _stopLoopback(Command? cmd) async {
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
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;

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

  // CRITICAL: Follow cloudplayplus_stone exactly
  // 1. Create offer with OfferToReceiveVideo=true
  RTCSessionDescription sdp = await _pc!.createOffer({
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  });

  // 2. Apply _fixSdp (cloudplayplus_stone approach)
  final fixedSdpStr = _fixSdp(sdp.sdp ?? '');
  sdp.sdp = fixedSdpStr;

  // 3. setLocalDescription with THE SAME fixed SDP
  await _pc!.setLocalDescription(sdp);

  return Ack.ok(
    id: cmd.id,
    data: {
      'type': 'offer',
      'sdp': sdp.sdp,
      'sdpLength': sdp.sdp?.length ?? 0,
    },
  );
}

/// Fix SDP: cloudplayplus_stone approach
/// - Replace profile-level-id=640c1f with 42e032 (H.264 baseline)
/// - NO codec filtering, NO packetization-mode change
String _fixSdp(String sdp) {
  var s = sdp;
  // cloudplayplus_stone: only profile-level-id replacement
  s = s.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032');
  return s;
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
    
    // cloudplayplus_stone: after setRemoteDescription, flush buffered candidates
    _remoteDescriptionSet = true;
    while (_pendingCandidates.isNotEmpty) {
      final candidate = _pendingCandidates.removeAt(0);
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
    }

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
    
    // Apply _fixSdp to answer (cloudplayplus_stone approach)
    final fixedSdp = _fixSdp(answer.sdp ?? '');
    answer.sdp = fixedSdp;
    
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
