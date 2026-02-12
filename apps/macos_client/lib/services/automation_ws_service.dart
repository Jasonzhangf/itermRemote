import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Automation WebSocket Service
/// Exposes app state and controls for external automation testing
class AutomationWsService {
  AutomationWsService._();
  static final instance = AutomationWsService._();

  bool _isRunning = false;
  int _port = 9999;
  
  HttpServer? _server;
  final _clients = <WebSocketChannel>[];
  Timer? _stateBroadcastTimer;
  
  // State callbacks for automation
  Map<String, dynamic> Function()? getStateCallback;
  Future<dynamic> Function(String action, Map<String, dynamic> params)? executeActionCallback;
  
  bool get isRunning => _isRunning;
  
  Future<void> start({int port = 9999}) async {
    if (_isRunning) return;
    _port = port;
    
    try {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } catch (_) {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      }
      _isRunning = true;
      print('[AutomationWS] Started on ws://127.0.0.1:$port');
      
      // Start state broadcast
      _stateBroadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final state = getStateCallback?.call() ?? {'status': 'unknown'};
        broadcastState(state);
      });
      
      await for (var request in _server!) {
        if (request.uri.path == '/ws' || request.uri.path == '/' || request.uri.path.isEmpty) {
          var socket = await WebSocketTransformer.upgrade(request);
          var channel = IOWebSocketChannel(socket);
          _clients.add(channel);
          _handleClient(channel);
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      }
    } catch (e) {
      print('[AutomationWS] Error: $e');
      _isRunning = false;
    }
  }
  
  void _handleClient(WebSocketChannel channel) {
    channel.stream.listen(
      (data) => _handleMessage(data, channel),
      onDone: () => _clients.remove(channel),
      onError: (e) {
        print('[AutomationWS] Client error: $e');
        _clients.remove(channel);
      },
    );
  }
  
  Future<void> _handleMessage(dynamic data, WebSocketChannel sender) async {
    try {
      final msg = jsonDecode(data);
      final action = msg['action'] as String?;
      final params = msg['params'] as Map<String, dynamic>? ?? {};
      final requestId = msg['requestId'] as String? ?? 'unknown';
      
      dynamic result;
      
      switch (action) {
        case 'getState':
          result = getStateCallback?.call() ?? {'status': 'unknown'};
          break;
          
        case 'execute':
          final cmd = params['command'] as String?;
          if (cmd != null && executeActionCallback != null) {
            result = await executeActionCallback!(cmd, params);
          } else {
            result = {'error': 'No command or callback'};
          }
          break;
          
        default:
          result = {'error': 'Unknown action: $action'};
      }
      
      sender.sink.add(jsonEncode({
        'type': 'response',
        'requestId': requestId,
        'result': result,
      }));
    } catch (e) {
      sender.sink.add(jsonEncode({
        'type': 'error',
        'error': e.toString(),
      }));
    }
  }
  
  void broadcastState(Map<String, dynamic> state) {
    if (_clients.isEmpty) return;
    final msg = jsonEncode({
      'type': 'state',
      'data': state,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    for (var client in _clients.toList()) {
      try {
        client.sink.add(msg);
      } catch (e) {
        _clients.remove(client);
      }
    }
  }
  
  Future<void> stop() async {
    _isRunning = false;
    _stateBroadcastTimer?.cancel();
    for (var client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    print('[AutomationWS] Stopped');
  }
}
