import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef JsonMap = Map<String, Object?>;

class Command {
  Command({required this.id, required this.target, required this.action, this.payload});
  final String id;
  final String target;
  final String action;
  final JsonMap? payload;
  
  JsonMap toJson() => {
    'version': 1,
    'type': 'cmd',
    'id': id,
    'target': target,
    'action': action,
    if (payload != null) 'payload': payload,
  };
}

class DaemonCli {
  final String host;
  final int port;
  late final WebSocketChannel _channel;
  int _reqId = 0;
  final _pending = <String, Completer<JsonMap>>{};
  StreamSubscription? _sub;
  
  DaemonCli({this.host='127.0.0.1',this.port=8766});
  
  Future<void> connect() async {
    _channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
    _sub = _channel.stream.listen(
      (raw) {
        if (raw is String) {
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final id = json['id'] as String?;
            if (id != null && _pending.containsKey(id)) {
              _pending.remove(id)!.complete(json);
            }
          } catch (_) {}
        }
      },
      onDone: () {},
      onError: (_) {},
    );
  }
  
  Future<JsonMap?> _send(Command cmd) async {
    final completer = Completer<JsonMap>();
    _pending[cmd.id] = completer;
    _channel.sink.add(jsonEncode(cmd.toJson()));
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _pending.remove(cmd.id);
      return null;
    }
  }
  
  Future<bool> smokeTest() async {
    print('Protocol Smoke Test');
    
    var resp = await _send(Command(id: '${++_reqId}', target: 'iterm2', action: 'getSessions'));
    if (resp == null || !(resp['success'] as bool? ?? false)) {
      print('FAIL: getSessions ${resp?['error']}');
      return false;
    }
    final data = resp['data'] as Map<String, dynamic>?;
    final sessions = data?['sessions'] as List?;
    print('OK: ${sessions?.length ?? 0} sessions');
    if (sessions == null || sessions.isEmpty) return true;
    
    Map<String, dynamic>? first;
    for (var s in sessions) {
      if (s is Map<String, dynamic>) {
        final id = s['sessionId'] ?? s['id'];
        if (id != null && id.toString().isNotEmpty) {
          first = s;
          break;
        }
      }
    }
    if (first == null) {
      print('SKIP: no valid session id');
      return true;
    }
    final sid = first['sessionId'] ?? first['id'];
    
    resp = await _send(Command(
      id: '${++_reqId}',
      target: 'capture',
      action: 'activateAndComputeCrop',
      payload: {'sessionId': sid},
    ));
    if (resp == null || !(resp['success'] as bool? ?? false)) {
      print('FAIL: capture ${resp?['error']}');
      return false;
    }
    print('OK: capture');
    
    resp = await _send(Command(
      id: '${++_reqId}',
      target: 'webrtc',
      action: 'startLoopback',
      payload: {'sourceType': 'window', 'fps': 30, 'bitrateKbps': 1000},
    ));
    if (resp == null || !(resp['success'] as bool? ?? false)) {
      print('FAIL: startLoopback ${resp?['error']}');
      return false;
    }
    print('OK: startLoopback');
    
    resp = await _send(Command(id: '${++_reqId}', target: 'webrtc', action: 'createOffer'));
    if (resp == null || !(resp['success'] as bool? ?? false)) {
      print('FAIL: createOffer ${resp?['error']}');
      return false;
    }
    final offerData = resp['data'] as Map<String, dynamic>?;
    final sdp = offerData?['sdp'];
    if (sdp == null || sdp.toString().isEmpty) {
      print('FAIL: no SDP');
      return false;
    }
    print('OK: offer ${sdp.length} chars');
    
    print('ALL TESTS PASSED');
    return true;
  }
  
  void close() {
    _sub?.cancel();
    _channel.sink.close();
  }
}

void main() async {
  final cli = DaemonCli();
  await cli.connect();
  final ok = await cli.smokeTest();
  cli.close();
  exit(ok ? 0 : 1);
}
