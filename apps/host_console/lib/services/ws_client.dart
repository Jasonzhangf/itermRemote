import 'dart:async';
import 'dart:convert';

import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for connecting to host_daemon.
///
/// IMPORTANT:
/// - Incoming messages are JSON objects (ack/evt)
/// - Outgoing messages must also be JSON objects (not JSON strings)
///   because daemon's EnvelopeJsonCodec expects a JSON object.
class WsClient {
  WsClient({required this.url});

  final String url;

  WebSocketChannel? _channel;
  bool _connected = false;
  final Map<String, Completer<Ack>> _pending = {};
  final StreamController<Event> _eventController = StreamController.broadcast();

  bool get connected => _connected;
  Stream<Event> get eventStream => _eventController.stream;

  Future<void> connect() async {
    if (_connected) return;

    _channel = WebSocketChannel.connect(Uri.parse(url));
    _connected = true;

    _channel!.stream.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
    );

    // ignore: avoid_print
    print('[WsClient] Connected to $url');
  }

  Future<Ack> sendCommand(Command cmd, {Duration? timeout}) async {
    if (!_connected || _channel == null) {
      throw StateError('WebSocket not connected');
    }

    final completer = Completer<Ack>();
    _pending[cmd.id] = completer;

    // Send command as a JSON object (EnvelopeJsonCodec expects an object).
    _channel!.sink.add(jsonEncode(cmd.toJson()));

    return completer.future.timeout(
      timeout ?? const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(cmd.id);
        throw TimeoutException('Command timeout: ${cmd.action}');
      },
    );
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;

    final json = jsonDecode(message) as Map<String, dynamic>;
    final type = json['type'] as String?;

    if (type == 'ack') {
      final ack = Ack.fromJson(json);
      final completer = _pending.remove(ack.id);
      if (completer != null) {
        completer.complete(ack);
      }
      return;
    }

    if (type == 'evt') {
      final event = Event.fromJson(json);
      _eventController.add(event);
      return;
    }
  }

  void _handleError(Object error) {
    // ignore: avoid_print
    print('[WsClient] WebSocket error: $error');
    _connected = false;
  }

  void _handleDone() {
    // ignore: avoid_print
    print('[WsClient] WebSocket connection closed');
    _connected = false;

    for (final completer in _pending.values) {
      completer.completeError(StateError('Connection closed'));
    }
    _pending.clear();
  }

  void close() {
    _channel?.sink.close();
    _eventController.close();
    _connected = false;
  }
}
