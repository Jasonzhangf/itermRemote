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
    print('Connected to ws://$host:$port');
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
  
  Future<void> status() async {
    final resp = await _send(Command(
      id: '1',
      target: 'orchestrator',
      action: 'getState',
    ));
    if (resp == null) {
      print('Timeout waiting for response');
      return;
    }
    final success = resp['success'] as bool? ?? false;
    if (!success) {
      print('Error: ${resp['error']}');
      return;
    }
    final data = resp['data'] as Map<String, dynamic>?;
    final state = data?['state'] as Map<String, dynamic>?;
    print('Daemon state: ${state?.toString() ?? "{}"}');
  }
  
  Future<void> listWindows() async {
    final resp = await _send(Command(
      id: '2',
      target: 'iterm2',
      action: 'getWindowFrames',
    ));
    if (resp == null) {
      print('Timeout');
      return;
    }
    final success = resp['success'] as bool? ?? false;
    if (!success) {
      print('Error: ${resp['error']}');
      return;
    }
    final data = resp['data'] as Map<String, dynamic>?;
    final windows = data?['windows'] as List<dynamic>?;
    print('Windows (${windows?.length ?? 0}):');
    for (var w in windows ?? []) {
      final num = w['windowNumber'];
      final frame = w['rawWindowFrame'];
      print('  Window #$num: ${frame['x']},${frame['y']} ${frame['w']}x${frame['h']}');
    }
  }
  
  Future<void> switchWindow(int windowNumber) async {
    final sessionsResp = await _send(Command(
      id: '3',
      target: 'iterm2',
      action: 'getSessions',
    ));
    if (sessionsResp == null) {
      print('Timeout getting sessions');
      return;
    }
    final data = sessionsResp['data'] as Map<String, dynamic>?;
    final sessions = data?['sessions'] as List<dynamic>?;
    print('Got ${sessions?.length ?? 0} sessions');
    Map<String, dynamic>? target;
    for (var s in sessions ?? []) {
      if (s is Map<String, dynamic>) {
        if (s['windowNumber'] == windowNumber) {
          target = s;
          break;
        }
      }
    }
    if (target == null) {
      print('Error: No session found for window $windowNumber');
      return;
    }
    final sessionId = target['sessionId'];
    if (sessionId == null) {
      print('Error: Session has no sessionId');
      return;
    }
    print('Activating sessionId: $sessionId');
    final resp = await _send(Command(
      id: '4',
      target: 'iterm2',
      action: 'activateSession',
      payload: {'sessionId': sessionId},
    ));
    if (resp == null) {
      print('Timeout activating');
      return;
    }
    final success = resp['success'] as bool? ?? false;
    print(success ? 'OK' : 'Error: ${resp['error']}');
  }
  
  void close() {
    _sub?.cancel();
    _channel.sink.close();
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: daemon_cli.dart <status|list-windows|switch-window> <windowNumber>');
    exit(1);
  }
  
  final cli = DaemonCli();
  await cli.connect();
  
  try {
    switch (args[0]) {
      case 'status':
        await cli.status();
        break;
      case 'list-windows':
        await cli.listWindows();
        break;
      case 'switch-window':
        if (args.length < 2) {
          print('Need window number');
          exit(1);
        }
        final num = int.tryParse(args[1]);
        if (num == null) {
          print('Invalid window number');
          exit(1);
        }
        await cli.switchWindow(num);
        break;
      default:
        print('Unknown: ${args[0]}');
    }
  } finally {
    cli.close();
  }
}
