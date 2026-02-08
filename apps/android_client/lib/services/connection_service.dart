import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class ConnectionService {
  ConnectionService._();
  static final instance = ConnectionService._();

  WebSocketChannel? _channel;
  String? _connectedHostId;
  bool _isConnected = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;
  List<ICEServer> _iceServers = [];
  String _apiBaseUrl = 'http://code.codewhisper.cc';

  final _connectionStateController = StreamController<HostConnectionState>.broadcast();
  final _streamController = StreamController<MediaStream?>.broadcast();
  Stream<HostConnectionState> get connectionState => _connectionStateController.stream;
  Stream<MediaStream?> get remoteStream => _streamController.stream;
  bool get isConnected => _isConnected;
  String? get connectedHostId => _connectedHostId;
  MediaStream? get currentStream => _remoteStream;
  List<ICEServer> get iceServers => _iceServers;

  void setApiBaseUrl(String url) {
    _apiBaseUrl = url;
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
      final uri = Uri.parse('ws://$hostIp:$port');
      _channel = WebSocketChannel.connect(uri);
      _connectionStateController.add(HostConnectionState.connecting);
      _channel!.stream.listen((message) => _onMessage(message), onDone: () => _onDisconnected(), onError: (error) => _onError(error));
      await _startWebRTC();
      _connectedHostId = hostId;
      _isConnected = true;
      _connectionStateController.add(HostConnectionState.connected);
    } catch (e) {
      _connectionStateController.add(HostConnectionState.error);
      rethrow;
    }
  }

  Future<void> _startWebRTC() async {
    print('[WebRTC] Creating peer connection');
    
    final iceServers = await fetchICEServers();
    final pcConfig = <String, dynamic>{
      'iceServers': iceServers.map((s) => s.toJson()).toList(),
    };
    print('[WebRTC] Using ICE servers: ${jsonEncode(pcConfig['ice_servers'])}');
    
    _peerConnection = await createPeerConnection(pcConfig);
    
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print('[WebRTC] onTrack fired! streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _streamController.add(_remoteStream);
        print('[WebRTC] received remote stream - ID: ${_remoteStream!.id}');
      }
    };
    
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      print('[WebRTC] ICE candidate: ${candidate.candidate}');
    };
    
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('[WebRTC] Connection state: $state');
    };
    
    sendCmd('webrtc', 'startLoopback', {'sourceType': 'screen', 'fps': 30, 'bitrateKbps': 2000});
    await Future.delayed(Duration(milliseconds: 500));
    sendCmd('webrtc', 'createOffer', {});
    print('[WebRTC] Requested offer from daemon');
  }

  Future<void> _handleSignaling(Map<String, dynamic> data) async {
    final type = data['type'];
    final sdp = data['sdp'];
    print('[WebRTC] Handling signaling: type=$type');
    if (type == 'offer' && sdp != null) {
      print('[WebRTC] Setting remote description (offer)');
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      print('[WebRTC] Creating answer');
      final answer = await _peerConnection!.createAnswer();
      print('[WebRTC] Setting local description (answer)');
      await _peerConnection!.setLocalDescription(answer);
      print('[WebRTC] Sending answer to daemon');
      sendCmd('webrtc', 'setRemoteDescription', {'type': 'answer', 'sdp': answer.sdp});
    }
  }

  Future<void> disconnect() async {
    print('[WebRTC] Disconnecting');
    await _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    _streamController.add(null);
    await _channel?.sink.close();
    _channel = null;
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
      if (data['type'] == 'ack' && data['success'] == true && data['data'] != null) {
        final ackData = data['data'];
        if (ackData['type'] == 'offer' || ackData['sdp'] != null) {
          _handleSignaling(ackData);
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
