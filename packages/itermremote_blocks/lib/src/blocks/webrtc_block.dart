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
   stderr.writeln('[WebRTCBlock] handle START: action=${cmd.action} id=${cmd.id} target=${cmd.target}');
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
      stderr.writeln("[WebRTCBlock] ERROR: \${e.runtimeType}: \$e");
      stderr.writeln("[WebRTCBlock] Stack: \$stack");
      return Ack.fail(
        id: cmd.id,
        code: 'webrtc_error',
        message: e.toString(),
        details: {
          'action': cmd.action,
          'errorType': e.runtimeType.toString(),
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

    final cropRectRaw = payload['cropRect'];
    final cropRect = (cropRectRaw is Map<String, dynamic>) ? cropRectRaw : <String, dynamic>{};

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

    // Normalize cropRect values to ensure all keys have valid doubles
    final normalizedCropRect = <String, dynamic>{};
    if (cropRect.isNotEmpty) {
      for (final entry in cropRect.entries) {
        final v = entry.value;
        if (v is num) {
          normalizedCropRect[entry.key] = v.toDouble();
        }
      }
    }

    print('[WebRTCBlock] startLoopback params:');
    print('  sourceType=$sourceType sourceId=$sourceId');
    print('  fps=$fps size=${width}x$height');
    print('  bitrateKbps=$bitrateKbps');
    print('  cropRect=$normalizedCropRect');

    // Build media constraints with sourceId and cropRect support
    final mediaConstraints = <String, dynamic>{
      'audio': false,
      'video': <String, dynamic>{},
    };

    final videoConstraints = mediaConstraints['video'] as Map<String, dynamic>;

    // Build optional list
    final optionalConstraints = <Map<String, dynamic>>[];

    videoConstraints['mandatory'] = {
      'minWidth': width,
      'minHeight': height,
      'maxWidth': width,
      'maxHeight': height,
      'minFrameRate': fps,
      'maxFrameRate': fps,
    };

    // NOTE: deviceId constraint causes "type 'Null' is not a subtype of type 'String'" error
    // on macOS flutter_webrtc. For window capture, we use cropRect on full screen capture
    // and skip deviceId entirely.

    optionalConstraints.add({'googCpuOveruseDetection': true});
    videoConstraints['optional'] = optionalConstraints;

    print("[WebRTCBlock] Requesting display media with constraints: $mediaConstraints");
    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      print("[WebRTCBlock] Got stream with ${stream.getVideoTracks().length} video tracks");

      if (stream.getVideoTracks().isEmpty) {
        print("[WebRTCBlock] ERROR: no video tracks returned");
        return Ack.fail(
          id: cmd.id,
          code: 'no_video_track',
          message: 'getDisplayMedia returned no video tracks',
        );
      }

      _localStream = stream;
      // Log track settings for debugging
      final track = stream.getVideoTracks().first;
      final settings = await track.getSettings();
      print("[WebRTCBlock] Track settings: $settings");
    } catch (e, stack) {
      print('[WebRTCBlock] getDisplayMedia failed: $e');
      print('[WebRTCBlock] Stack: $stack');
      print('[WebRTCBlock] Constraints that failed: $mediaConstraints');
      return Ack.fail(
        id: cmd.id,
        code: 'get_display_media_failed',
        message: 'Failed to get display media: $e',
        details: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'sourceType': sourceType,
          'sourceId': sourceId,
          'constraints': mediaConstraints.toString(),
        },
      );
    }

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

    // Add track to peer connection
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
      print('[WebRTCBlock] WARNING: setParameters failed: $e');
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
      'loopbackCropRect': normalizedCropRect.isNotEmpty ? normalizedCropRect : cropRect,
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

  // 2. Apply _fixSdp (profile-level-id replacement) AND _fixSdpBitrate (bitrate injection)
  final fixedSdpStr = _fixSdp(sdp.sdp ?? '');
  final bitrate = (_state['loopbackBitrateKbps'] as int? ?? 2000).clamp(250, 20000);
  final fixedSdpWithBitrate = _fixSdpBitrate(fixedSdpStr, bitrate);
  sdp.sdp = fixedSdpWithBitrate;

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
/// - Fix setup attribute for answer SDP (loopback mode)
/// - Ensure proper a=setup value (active/passive/actpass)
/// - NO codec filtering, NO packetization-mode change
String _fixSdp(String sdp, {bool isAnswer = false}) {
  var s = sdp;
  // cloudplayplus_stone: only profile-level-id replacement (use word boundaries to avoid partial matches)
  // Replace all variants of 640c1f/640c33 with 42e032 (H.264 baseline)
  s = s.replaceAll(RegExp(r'profile-level-id=640c[0-9a-f]{2}\b'), 'profile-level-id=42e032');

  // For loopback answer: fix setup attribute
  // Ensure answer SDP has proper a=setup value
  if (isAnswer) {
    // Check current setup value and replace if invalid
    final setupMatch = RegExp(r'a=setup:(\w+)').firstMatch(s);
    if (setupMatch == null) {
      // No setup attribute found, add active setup after fingerprint line
      s = s.replaceAllMapped(
        RegExp(r'(a=fingerprint:[^\r\n]+[\r\n]+)'),
        (match) => '${match.group(1)}a=setup:active\r\n',
      );
      // If fingerprint not found, try adding after ice-options
      if (!s.contains('a=setup:active')) {
        s = s.replaceAllMapped(
          RegExp(r'(a=ice-options:[^\r\n]+[\r\n]+)'),
          (match) => '${match.group(1)}a=setup:active\r\n',
        );
      }
    } else {
      final setupValue = setupMatch.group(1)!;
      // Replace actpass with active for answer
      if (setupValue == 'actpass') {
        s = s.replaceAll('a=setup:actpass', 'a=setup:active');
      }
    }
  }

  return s;
}

/// Fix SDP bitrate: inject b=AS and x-google bitrate fields
/// - Add b=AS after c=IN line in video section
/// - Inject x-google-max/min/start-bitrate into a=fmtp lines
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
        details: {'type': type?.runtimeType.toString(), 'sdp': sdp?.runtimeType.toString()},
      );
    }

    final description = RTCSessionDescription(sdp, type);
    try {
      await _pc!.setRemoteDescription(description);
    } catch (e, stack) {
      print('[WebRTCBlock] setRemoteDescription failed: ${e.runtimeType}: $e');
      return Ack.fail(
        id: cmd.id,
        code: 'set_remote_desc_failed',
        message: 'setRemoteDescription failed: $e',
        details: {
          'sdpLength': sdp.length,
          'type': type,
          'errorType': e.runtimeType.toString(),
          'stack': stack.toString(),
        },
      );
    }

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
    final sdpMLineIndexRaw = cmd.payload?['sdpMLineIndex'];

    // Robust validation for candidate
    if (candidate is! String || candidate.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'addIceCandidate requires non-empty candidate string',
        details: {'candidateType': candidate.runtimeType.toString()},
      );
    }

    // Robust parsing for sdpMLineIndex (handle int/double/string/null)
    int? sdpMLineIndex;
    if (sdpMLineIndexRaw is int) {
      sdpMLineIndex = sdpMLineIndexRaw;
    } else if (sdpMLineIndexRaw is double) {
      sdpMLineIndex = sdpMLineIndexRaw.toInt();
    } else if (sdpMLineIndexRaw is String) {
      sdpMLineIndex = int.tryParse(sdpMLineIndexRaw);
    }

    try {
      await _pc!.addCandidate(
        RTCIceCandidate(
          candidate,
          sdpMid is String ? sdpMid : null,
          sdpMLineIndex,
        ),
      );
      return Ack.ok(id: cmd.id, data: {'success': true});
    } catch (e, stack) {
      print('[WebRTCBlock] addCandidate failed: $e');
      return Ack.fail(
        id: cmd.id,
        code: 'add_ice_failed',
        message: 'Failed to add ICE candidate: $e',
        details: {
          'candidateLength': candidate.length,
          'sdpMid': sdpMid,
          'sdpMLineIndex': sdpMLineIndex,
          'error': e.toString(),
        },
      );
    }
  }

  Future<Ack> _createAnswer(Command cmd) async {
    if (_pc == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_ready',
        message: 'PeerConnection not initialized',
      );
    }

    try {
      final answer = await _pc!.createAnswer();

      // Validate answer SDP
      if (answer.sdp == null || answer.sdp!.isEmpty) {
        return Ack.fail(
          id: cmd.id,
          code: 'create_answer_failed',
          message: 'createAnswer returned null or empty SDP. Remote description may not be set.',
          details: {
            'hasRemoteDescription': _remoteDescriptionSet,
            'sdpType': answer.type,
          },
        );
      }

      // Apply _fixSdp to answer (cloudplayplus_stone approach)
      final fixedSdp = _fixSdp(answer.sdp!, isAnswer: true);
      answer.sdp = fixedSdp;

      await _pc!.setLocalDescription(answer);

      return Ack.ok(
        id: cmd.id,
        data: {
          'type': 'answer',
          'sdp': answer.sdp,
        },
      );
    } catch (e, stack) {
      print('[WebRTCBlock] createAnswer failed: ${e.runtimeType}: $e');
      return Ack.fail(
        id: cmd.id,
        code: 'create_answer_failed',
        message: 'createAnswer failed: $e',
        details: {
          'errorType': e.runtimeType.toString(),
          'hasRemoteDescription': _remoteDescriptionSet,
          'stack': stack.toString(),
        },
      );
    }
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
