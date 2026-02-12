import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_service.dart';

/// Remote WebSocket service for server-side relay/broadcast.
/// Server only routes messages, does not parse payload.
class RemoteWsService {
  RemoteWsService._();
  static final instance = RemoteWsService._();

  static const String _serverHost = 'code.codewhisper.cc';
  static const int _serverPort = 8081;

  WebSocket? _socket;
  bool _connected = false;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _connected;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> connect() async {
    if (_connected || _socket != null) return;

    final token = AuthService.instance.accessToken;
    if (token == null) {
      throw StateError('Not authenticated');
    }

    final wsUrl = 'ws://$_serverHost:$_serverPort/ws/connect?token=$token';

    try {
      _socket = await WebSocket.connect(wsUrl);
      _connected = true;
      print('[RemoteWS] Connected to $wsUrl');

      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
    } catch (e) {
      print('[RemoteWS] Connection failed: $e');
      _connected = false;
      Future.delayed(const Duration(seconds: 5), connect);
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    _connected = false;
  }

  /// Send a proxy message to server for relay.
  /// [channel]: logical channel (e.g., "webrtc-offer", "ice-candidate")
  /// [payload]: arbitrary JSON-serializable object
  /// [target]: "broadcast" or specific device_id
  void sendProxy({
    required String channel,
    required Map<String, dynamic> payload,
    String target = 'broadcast',
  }) {
    if (!_connected || _socket == null) {
      print('[RemoteWS] Not connected, dropping message');
      return;
    }

    final message = {
      'type': 'proxy',
      'channel': channel,
      'target': target,
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    _socket!.add(jsonEncode(message));
    print('[RemoteWS] Sent proxy message on channel: $channel');
  }

  void _handleMessage(dynamic data) {
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      _messageController.add(json);

      if (json['type'] == 'proxy') {
        print('[RemoteWS] Received proxy from ${json['source_device_id']} on channel ${json['channel']}');
      } else if (json['type'] == 'presence_sync') {
        print('[RemoteWS] Presence sync: ${json['online']}');
      } else if (json['type'] == 'presence_update') {
        print('[RemoteWS] Presence update: ${json['device_id']} is ${json['status']}');
      }
    } catch (e) {
      print('[RemoteWS] Failed to parse message: $e');
    }
  }

  void _handleError(Object error) {
    print('[RemoteWS] Error: $error');
    _connected = false;
  }

  void _handleDone() {
    print('[RemoteWS] Disconnected');
    _connected = false;
    Future.delayed(const Duration(seconds: 5), connect);
  }
}
