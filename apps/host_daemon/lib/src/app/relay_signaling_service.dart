import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Host-side relay signaling service for NAT traversal
/// Connects to WebSocket relay server and forwards signaling messages to WebRTC block
class RelaySignalingService {
  RelaySignalingService({
    required this.serverHost,
    required this.serverPort,
    required this.token,
    this.reconnectInterval = const Duration(seconds: 5),
  });

  final String serverHost;
  final int serverPort;
  final String token;
  final Duration reconnectInterval;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _disposed = false;
  String? _deviceId;

  // Callbacks for signaling events
  void Function(Map<String, dynamic> payload)? onOfferReceived;
  void Function(Map<String, dynamic> payload)? onAnswerReceived;
  void Function(Map<String, dynamic> payload)? onCandidateReceived;
  void Function()? onConnected;
  void Function()? onDisconnected;

  Future<void> start() async {
    _disposed = false;
    await _connect();
  }

  Future<void> stop() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> _connect() async {
    if (_disposed || _socket != null) return;

    final wsUrl = 'ws://$serverHost:$serverPort/ws/connect?token=$token';
    try {
      print('[RelaySignaling] Connecting to $wsUrl');
      _socket = await WebSocket.connect(wsUrl);
      print('[RelaySignaling] Connected');
      
      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      onConnected?.call();
    } catch (e) {
      print('[RelaySignaling] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    if (data is! String) return;

    try {
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final type = msg['type'];

      if (type == 'proxy') {
        final channel = msg['channel'] as String?;
        final payload = msg['payload'];
        final sourceDeviceId = msg['source_device_id'] as String?;

        print('[RelaySignaling] Received proxy on channel=$channel from=$sourceDeviceId');

        if (channel == 'webrtc-offer' && payload is Map) {
          onOfferReceived?.call(payload.cast<String, dynamic>());
        } else if (channel == 'webrtc-answer' && payload is Map) {
          onAnswerReceived?.call(payload.cast<String, dynamic>());
        } else if (channel == 'webrtc-candidate' && payload is Map) {
          onCandidateReceived?.call(payload.cast<String, dynamic>());
        }
      } else if (type == 'ice_servers') {
        print('[RelaySignaling] Received ICE servers from server');
      } else if (type == 'presence_sync') {
        print('[RelaySignaling] Presence sync: ${msg['online']}');
      }
    } catch (e) {
      print('[RelaySignaling] Failed to parse message: $e');
    }
  }

  void _handleError(Object error) {
    print('[RelaySignaling] Error: $error');
  }

  void _handleDone() {
    print('[RelaySignaling] Disconnected');
    _socket = null;
    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(reconnectInterval, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  /// Send WebRTC offer to target device via relay
  void sendOffer(String sdp, {required String targetDeviceId}) {
    _sendProxy('webrtc-offer', {'sdp': sdp, 'type': 'offer'}, targetDeviceId);
  }

  /// Send WebRTC answer to target device via relay
  void sendAnswer(String sdp, {required String targetDeviceId}) {
    _sendProxy('webrtc-answer', {'sdp': sdp, 'type': 'answer'}, targetDeviceId);
  }

  /// Send ICE candidate to target device via relay
  void sendCandidate(Map<String, dynamic> candidate, {required String targetDeviceId}) {
    _sendProxy('webrtc-candidate', candidate, targetDeviceId);
  }

  void _sendProxy(String channel, Map<String, dynamic> payload, String target) {
    if (_socket == null) {
      print('[RelaySignaling] Not connected, dropping message');
      return;
    }

    final msg = {
      'type': 'proxy',
      'channel': channel,
      'target': target,
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    _socket!.add(jsonEncode(msg));
    print('[RelaySignaling] Sent $channel to $target');
  }

  bool get isConnected => _socket != null;
}
