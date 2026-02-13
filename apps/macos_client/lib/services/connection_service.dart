import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'remote_ws_service.dart';

class ConnectionService {
  ConnectionService._();
  static final instance = ConnectionService._();

  WebSocketChannel? _channel;
  StreamSubscription<Map<String, dynamic>>? _relaySub;
  bool _relayMode = false;
  String? _relayTargetDeviceId;
  String? _connectedHostId;
  bool _isConnected = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;
  int _frameCount = 0;
  int _lastFrameCount = 0;
  int _currentFps = 0;
  bool _hasStream = false;
  Timer? _frameTimer;
  List<ICEServer> _iceServers = [];
  String _apiBaseUrl = 'http://code.codewhisper.cc';
  String? _preferredSessionId;

  final Map<String, Completer<Map<String, dynamic>>> _pendingAcks = {};
  
  // ICE candidate buffering (cloudplayplus_stone approach)
  final List<RTCIceCandidate> _pendingCandidates = [];

  final _connectionStateController = StreamController<HostConnectionState>.broadcast();
  final _streamController = StreamController<MediaStream?>.broadcast();
  Stream<HostConnectionState> get connectionState => _connectionStateController.stream;
  Stream<MediaStream?> get remoteStream => _streamController.stream;
  bool get isConnected => _isConnected;
  String? get connectedHostId => _connectedHostId;
  MediaStream? get currentStream => _remoteStream;
  int get frameCount => _frameCount;
  int get currentFps => _currentFps;
  bool get hasStream => _hasStream;
  List<ICEServer> get iceServers => _iceServers;

  void setApiBaseUrl(String url) {
    _apiBaseUrl = url;
  }

  void setPreferredSessionId(String? sessionId) {
    _preferredSessionId = sessionId;
  }

  Future<List<ICEServer>> fetchICEServers() async {
    try {
      final response = await http.get(Uri.parse('$_apiBaseUrl/api/v1/ice/servers'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> servers = data['ice_servers'] ?? [];
        _iceServers = servers.map((s) => ICEServer.fromJson(s)).toList();
        print('[ICE] Fetched ${_iceServers.length} ICE servers');
        return _iceServers;
      }
    } catch (e) {
      print('[ICE] Failed to fetch ICE servers: $e');
    }
    _iceServers = [ICEServer(urls: ['stun:stun.l.google.com:19302'])];
    return _iceServers;
  }

  Future<ICEServer?> measureRTTAndSelectBest() async {
    if (_iceServers.isEmpty) {
      await fetchICEServers();
    }
    if (_iceServers.isEmpty) return null;

    ICEServer? bestServer;
    int bestRTT = 999999;

    for (final server in _iceServers) {
      final rtt = await _measureRTT(server);
      print('[ICE] Server ${server.urls.first} RTT: ${rtt}ms');
      if (rtt < bestRTT) {
        bestRTT = rtt;
        bestServer = server;
      }
    }
    print('[ICE] Best server: ${bestServer?.urls.first} (RTT: ${bestRTT}ms)');
    return bestServer;
  }

  Future<int> _measureRTT(ICEServer server) async {
    final url = server.urls.first;
    if (!url.startsWith('turn:') && !url.startsWith('turns:')) {
      return 0;
    }
    final uri = Uri.parse(url.replaceFirst('turn:', 'tcp://').replaceFirst('turns:', 'tls://'));
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(uri.host, uri.port > 0 ? uri.port : 3478, timeout: const Duration(seconds: 3));
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      stopwatch.stop();
      return 999999;
    }
  }

  Future<List<Map<String, String>>> discoverHosts() async {
    final hosts = <Map<String, String>>[];
    final localIp = await _getLocalIp();
    if (localIp == null) return [{'id': 'localhost', 'name': 'localhost', 'ip': '127.0.0.1'}];
    final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
    for (var i = 1; i <= 10; i++) {
      final testIp = '$subnet.$i';
      if (await _checkHost(testIp)) hosts.add({'id': 'host-$testIp', 'name': testIp, 'ip': testIp});
    }
    if (hosts.isEmpty) hosts.add({'id': 'localhost', 'name': 'localhost', 'ip': '127.0.0.1'});
    return hosts;
  }

  Future<String?> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _checkHost(String ip, {int port = 8766}) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true;
    } catch (_) { return false; }
  }

  Future<void> connect({required String hostId, required String hostIp, int port = 8766}) async {
    if (_isConnected) await disconnect();
    try {
      var resolvedHostIp = hostIp;
      if (Platform.isAndroid) {
        final isEmulator = hostIp.contains('127.0.0.1') || 
                         hostIp.contains('localhost') ||
                         hostIp == '10.0.2.2';
        if (isEmulator) {
          resolvedHostIp = '10.0.2.2';
          print('[WS] Android emulator: using 10.0.2.2 for host');
        } else {
          resolvedHostIp = hostIp;
          print('[WS] Android real device: using $resolvedHostIp:$port');
        }
      } else {
        print('[WS] Connecting to $resolvedHostIp:$port (original: $hostIp)');
      }
      final uri;
      if (resolvedHostIp.contains(':')) {
        uri = Uri.parse('ws://[$resolvedHostIp]:$port');
      } else {
        uri = Uri.parse('ws://$resolvedHostIp:$port');
      }
      _channel = WebSocketChannel.connect(uri);
      _connectionStateController.add(HostConnectionState.connecting);
      _channel!.stream.listen((message) => _onMessage(message), onDone: () => _onDisconnected(), onError: (error) => _onError(error));
      sendCmd('orchestrator', 'subscribe', {'sources': ['webrtc']});
      await _startWebRTC();
      _connectedHostId = hostId;
      _isConnected = true;
      _connectionStateController.add(HostConnectionState.connected);
    } catch (e) {
      _connectionStateController.add(HostConnectionState.error);
      rethrow;
    }
  }

  Future<void> connectViaRelay({required String hostDeviceId}) async {
    if (_isConnected) {
      await disconnect();
    }

    _relayMode = true;
    _relayTargetDeviceId = hostDeviceId;
    _connectionStateController.add(HostConnectionState.connecting);

    if (!RemoteWsService.instance.isConnected) {
      await RemoteWsService.instance.connect();
    }

    _relaySub?.cancel();
    _relaySub = RemoteWsService.instance.messageStream.listen(_onRelayMessage);

    await _startWebRTC();
    _connectedHostId = hostDeviceId;
    _isConnected = true;
    _connectionStateController.add(HostConnectionState.connected);
    print('[Relay] Connected in relay mode, target=$hostDeviceId');
  }

  Future<void> _startWebRTC() async {
    print('[WebRTC] Creating peer connection');
    
    final iceServers = await fetchICEServers();
    final pcConfig = <String, dynamic>{
      'iceServers': iceServers.map((s) => s.toJson()).toList(),
      'sdpSemantics': 'unified-plan',  // cloudplayplus_stone uses unified-plan
    };
    print('[WebRTC] Using ICE servers: ${jsonEncode(pcConfig['ice_servers'])}');
    
    _peerConnection = await createPeerConnection(pcConfig);
    
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print('[WebRTC] onTrack fired! streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _streamController.add(_remoteStream);
        print('[WebRTC] received remote stream - ID: ${_remoteStream!.id}');
        _startFrameCounting();
      }
    };
    
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }

      if (_relayMode && _relayTargetDeviceId != null) {
        RemoteWsService.instance.sendProxy(
          channel: 'webrtc-candidate',
          target: _relayTargetDeviceId!,
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
        print('[Relay] Sent local ICE candidate via relay');
      } else {
        // cloudplayplus_stone: buffer candidates until remote description is set
        _pendingCandidates.add(candidate);
        print('[WebRTC] Buffered local ICE candidate');
      }
    };
    
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('[WebRTC] Connection state: $state');
    };
    
    if (_relayMode) {
      final offer = await _peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      });
      final fixedSdp = _fixSdp(offer.sdp ?? '');
      offer.sdp = fixedSdp;
      await _peerConnection!.setLocalDescription(offer);

      if (_relayTargetDeviceId != null) {
        RemoteWsService.instance.sendProxy(
          channel: 'webrtc-offer',
          target: _relayTargetDeviceId!,
          payload: {
            'type': 'offer',
            'sdp': offer.sdp,
          },
        );
        print('[Relay] Sent offer via relay');
      }
      return;
    }

    final capturePayload = await _prepareIterm2Capture();
    print('[Capture] iterm2 payload: $capturePayload');
    if (capturePayload != null) {
      sendCmd('webrtc', 'startLoopback', capturePayload);
    } else {
      sendCmd('webrtc', 'startLoopback', {'sourceType': 'screen', 'fps': 30, 'bitrateKbps': 2000});
    }
    await Future.delayed(Duration(milliseconds: 500));
    sendCmd('webrtc', 'createOffer', {});
    print('[WebRTC] Requested offer from daemon');
  }

  Future<void> _onRelayMessage(Map<String, dynamic> msg) async {
    if (msg['type'] != 'proxy') return;
    final channel = msg['channel'] as String?;
    final payload = msg['payload'];
    if (payload is! Map || _peerConnection == null) return;
    final p = payload.cast<String, dynamic>();

    if (channel == 'webrtc-answer') {
      final sdp = p['sdp'] as String?;
      if (sdp != null) {
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        print('[Relay] Applied remote answer');
      }
    } else if (channel == 'webrtc-offer') {
      final sdp = p['sdp'] as String?;
      if (sdp != null) {
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        final answer = await _peerConnection!.createAnswer({
          'mandatory': {
            'OfferToReceiveAudio': false,
            'OfferToReceiveVideo': false,
          },
          'optional': [],
        });
        answer.sdp = _fixSdp(answer.sdp ?? '');
        await _peerConnection!.setLocalDescription(answer);
        if (_relayTargetDeviceId != null) {
          RemoteWsService.instance.sendProxy(
            channel: 'webrtc-answer',
            target: _relayTargetDeviceId!,
            payload: {
              'type': 'answer',
              'sdp': answer.sdp,
            },
          );
        }
        print('[Relay] Replied with answer');
      }
    } else if (channel == 'webrtc-candidate') {
      await _handleRemoteCandidate(p);
    }
  }

  void _notifyStateChange() {
    _connectionStateController.add(_isConnected ? HostConnectionState.connected : HostConnectionState.connecting);
  }

  void _startFrameCounting() {
    _frameTimer?.cancel();
    _frameCount = 0;
    _lastFrameCount = 0;
    _currentFps = 0;
    print('[WebRTC] Starting frame counting timer');
    _frameTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final stats = await _peerConnection?.getStats();
        if (stats == null) {
          print('[WebRTC] Stats is null');
          return;
        }
        print('[WebRTC] Stats count: ${stats.length}');

        num? framesDecoded;
        num? framesReceived;
        num? framesPerSecond;

        for (final report in stats) {
          final values = report.values;
          final reportType = report.type;
          final kind = values['kind'];
          print('[WebRTC] Stats report type=$reportType kind=$kind keys=${values.keys.toList()}');

          if (reportType == 'inbound-rtp' && kind == 'video') {
            final decoded = values['framesDecoded'];
            final received = values['framesReceived'];
            final fps = values['framesPerSecond'];

            if (decoded is num) framesDecoded = decoded;
            if (received is num) {
              framesReceived = received;
              if (received > 0 && !_hasStream) {
                _hasStream = true;
                _notifyStateChange();
              }
            }
            if (fps is num && fps > 0) {
              framesPerSecond = fps;
              _currentFps = fps.round();
            }
          }
        }

        final currentFrames = (framesDecoded ?? framesReceived ?? _frameCount).toInt();
        final delta = currentFrames - _lastFrameCount;

        _frameCount = currentFrames;
        _currentFps = framesPerSecond?.round() ?? (delta >= 0 ? delta : 0);
        _lastFrameCount = currentFrames;

        print('[WebRTC] FPS updated: fps=$_currentFps total=$_frameCount decoded=$framesDecoded received=$framesReceived fpsField=$framesPerSecond');
      } catch (e) {
        print('[WebRTC] Frame count error: $e');
      }
    });
  }

  Future<void> _handleSignaling(Map<String, dynamic> data) async {
    final type = data['type'];
    final sdp = data['sdp'];
    print('[WebRTC] Handling signaling: type=$type');
    if (type == 'offer' && sdp != null) {
      print('[WebRTC] Setting remote description (offer)');
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      
      // cloudplayplus_stone: after setRemoteDescription, flush buffered candidates
      print('[WebRTC] Flushing ${_pendingCandidates.length} buffered local candidates');
      while (_pendingCandidates.isNotEmpty) {
        final candidate = _pendingCandidates.removeAt(0);
        sendCmd('webrtc', 'addIceCandidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
      
      print('[WebRTC] Creating answer');
      // cloudplayplus_stone: OfferToReceiveVideo=false in answer
      final answer = await _peerConnection!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
      
      // cloudplayplus_stone: apply _fixSdp to answer
      final fixedSdp = _fixSdp(answer.sdp ?? '');
      answer.sdp = fixedSdp;
      print('[WebRTC] Fixed answer SDP (profile-level-id)');
      
      print('[WebRTC] Setting local description (answer)');
      await _peerConnection!.setLocalDescription(answer);
      print('[WebRTC] Sending answer to daemon');
      sendCmd('webrtc', 'setRemoteDescription', {'type': 'answer', 'sdp': answer.sdp});
    }
  }
  
  /// Fix SDP: cloudplayplus_stone approach
  String _fixSdp(String sdp) {
    var s = sdp;
    s = s.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032');
    return s;
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    final candidate = payload['candidate'];
    final sdpMid = payload['sdpMid'];
    final sdpMLineIndex = payload['sdpMLineIndex'];
    if (candidate == null || _peerConnection == null) return;
    try {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(candidate as String, sdpMid as String?, sdpMLineIndex as int?),
      );
      print('[WebRTC] Added remote ICE candidate');
    } catch (e) {
      print('[WebRTC] Failed to add remote candidate: $e');
    }
  }

  Future<Map<String, dynamic>> _sendCommandAwait(String target, String action, Map<String, dynamic>? payload, {Duration timeout = const Duration(seconds: 5)}) async {
    final id = 'cmd-${DateTime.now().millisecondsSinceEpoch}-$target-$action';
    final cmd = {'version': 1, 'type': 'cmd', 'id': id, 'target': target, 'action': action};
    if (payload != null) {
      cmd['payload'] = payload;
    }
    final completer = Completer<Map<String, dynamic>>();
    _pendingAcks[id] = completer;
    _channel?.sink.add(jsonEncode(cmd));
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingAcks.remove(id);
      return {'success': false, 'error': 'timeout'};
    });
  }

  Map<String, dynamic>? _buildIterm2CropRect(Map<String, dynamic> meta) {
    final f = (meta['layoutFrame'] as Map?) ?? const {};
    final wf = (meta['layoutWindowFrame'] as Map?) ?? const {};
    final fx = (f['x'] as num?)?.toDouble() ?? 0.0;
    final fy = (f['y'] as num?)?.toDouble() ?? 0.0;
    final fw = (f['w'] as num?)?.toDouble() ?? 0.0;
    final fh = (f['h'] as num?)?.toDouble() ?? 0.0;
    final ww = (wf['w'] as num?)?.toDouble() ?? 1.0;
    final wh = (wf['h'] as num?)?.toDouble() ?? 1.0;
    if (ww <= 0 || wh <= 0) return null;
    return {
      'x': (fx / ww).clamp(0.0, 1.0),
      'y': (fy / wh).clamp(0.0, 1.0),
      'w': (fw / ww).clamp(0.0, 1.0),
      'h': (fh / wh).clamp(0.0, 1.0),
    };
  }

  Future<Map<String, dynamic>?> _prepareIterm2Capture() async {
    print('[Capture] Starting iterm2 capture...');
    final sessionsAck = await _sendCommandAwait('iterm2', 'getSessions', {});
    final sessionsCount = ((sessionsAck['data'] as Map?)?['sessions'] as List?)?.length ?? 0;
    print('[Capture] getSessions: success=${sessionsAck['success']}, count=$sessionsCount');
    if (sessionsAck['success'] != true) return null;
    final data = sessionsAck['data'] as Map<String, dynamic>? ?? {};
    final sessions = (data['sessions'] as List?) ?? [];
    if (sessions.isEmpty) return null;

    Map<String, dynamic>? picked;
    if (_preferredSessionId != null) {
      for (final s in sessions) {
        if (s is Map && s['id'] == _preferredSessionId) {
          picked = s.cast<String, dynamic>();
          break;
        }
      }
    }
    if (picked == null) {
      for (final s in sessions) {
        if (s is Map && s['cgWindowId'] != null) {
          picked = s.cast<String, dynamic>();
          break;
        }
      }
    }
    picked ??= sessions.first is Map ? (sessions.first as Map).cast<String, dynamic>() : null;
    if (picked == null) return null;

    final sessionId = picked['id'] as String?;
    if (sessionId == null) return null;
    final activateAck = await _sendCommandAwait('iterm2', 'activateSession', {'sessionId': sessionId});
    print('[Capture] activateSession: success=${activateAck['success']}');
    if (activateAck['success'] != true) return null;

    final meta = (activateAck['data'] as Map?)?['meta'] as Map<String, dynamic>? ?? {};
    final cropRect = _buildIterm2CropRect(meta);
    final cgWindowId = meta['cgWindowId'] ?? picked['cgWindowId'];
    if (cgWindowId == null) return null;

    final layoutFrame = (meta['layoutFrame'] as Map?) ?? const {};
    final width = (layoutFrame['w'] as num?)?.toInt() ?? 1920;
    final height = (layoutFrame['h'] as num?)?.toInt() ?? 1080;

    print('[Capture] Returning capture payload: sourceId=$cgWindowId, cropRect=$cropRect');
    return {
      'sourceType': 'window',
      'sourceId': cgWindowId.toString(),
      if (cropRect != null) 'cropRect': cropRect,
      'fps': 30,
      'width': width,
      'height': height,
      'bitrateKbps': 2000,
    };
  }

  Future<void> disconnect() async {
    print('[WebRTC] Disconnecting');
    await _peerConnection?.close();
    _frameTimer?.cancel();
    _peerConnection = null;
    _remoteStream = null;
    _streamController.add(null);
    await _channel?.sink.close();
    _channel = null;
    await _relaySub?.cancel();
    _relaySub = null;
    _relayMode = false;
    _relayTargetDeviceId = null;
    _connectedHostId = null;
    _isConnected = false;
    _connectionStateController.add(HostConnectionState.disconnected);
  }

  void sendCmd(String target, String action, Map<String, dynamic> payload) {
    final cmd = {'version': 1, 'type': 'cmd', 'id': 'cmd-${DateTime.now().millisecondsSinceEpoch}', 'target': target, 'action': action, 'payload': payload};
    final cmdStr = jsonEncode(cmd);
    print('[WS] Sending: ${cmdStr.substring(0, cmdStr.length > 100 ? 100 : cmdStr.length)}...');
    _channel?.sink.add(cmdStr);
  }

  void _onMessage(dynamic message) {
    print('[WS] Received: ${message.toString().substring(0, message.toString().length > 100 ? 100 : message.toString().length)}...');
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'ack') {
        final id = data['id'];
        if (id is String && _pendingAcks.containsKey(id)) {
          _pendingAcks.remove(id)?.complete(data);
        }
        if (data['success'] == true && data['data'] != null) {
          final ackData = data['data'];
          if (ackData['type'] == 'offer' || ackData['sdp'] != null) {
            _handleSignaling(ackData);
          }
        }
      } else if (data['type'] == 'evt') {
        final source = data['source'];
        final event = data['event'];
        final payload = data['payload'];
        if (source == 'webrtc' && event == 'iceCandidate' && payload is Map) {
          _handleRemoteCandidate(payload.cast<String, dynamic>());
        }
      }
    } catch (e) {
      print('[WS] Parse error: $e');
    }
  }

  void _onDisconnected() {
    print('[WS] Disconnected');
    _isConnected = false;
    _connectedHostId = null;
    _connectionStateController.add(HostConnectionState.disconnected);
  }

  void _onError(dynamic error) {
    print('[WS] Error: $error');
    _connectionStateController.add(HostConnectionState.error);
  }

  void dispose() {
    _channel?.sink.close();
    _connectionStateController.close();
    _streamController.close();
  }
}

enum HostConnectionState { disconnected, connecting, connected, error }

class ICEServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  ICEServer({
    required this.urls,
    this.username,
    this.credential,
  });

  factory ICEServer.fromJson(Map<String, dynamic> json) {
    final urls = json['urls'];
    return ICEServer(
      urls: urls is List ? List<String>.from(urls) : [urls.toString()],
      username: json['username'],
      credential: json['credential'],
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'urls': urls};
    if (username != null) json['username'] = username;
    if (credential != null) json['credential'] = credential;
    return json;
  }
}
