import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : 'ws://127.0.0.1:8766';
  final ws = await _connectWithRetry(url);

  final responses = StreamController<Map<String, Object?>>.broadcast();
  ws.listen((msg) {
    if (msg is! String) return;
    try {
      final decoded = jsonDecode(msg);
      if (decoded is! Map) return;
      responses.add(decoded.cast<String, Object?>());
    } catch (_) {}
  });

  Future<Map<String, Object?>> sendCmd({
    required String id,
    required String target,
    required String action,
    Map<String, Object?>? payload,
  }) async {
    final cmd = <String, Object?>{
      'version': 1,
      'type': 'cmd',
      'id': id,
      'target': target,
      'action': action,
      if (payload != null) 'payload': payload,
    };
    ws.add(jsonEncode(cmd));

    try {
      return await responses.stream.firstWhere(
        (m) => m['type'] == 'ack' && m['id'] == id,
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw TimeoutException('Timeout waiting ack for $id');
    }
  }

  try {
    stdout.writeln('START url=$url');
    final pingId = 'ping-${DateTime.now().millisecondsSinceEpoch}';
    final pingAck = await sendCmd(
      id: pingId,
      target: 'echo',
      action: 'echo',
      payload: {'ping': true},
    );
    stdout.writeln('ACK_PING=$pingAck');
    if (pingAck['success'] != true) {
      stderr.writeln('ping failed: $pingAck');
      exit(1);
    }

    final id1 = 'list-${DateTime.now().millisecondsSinceEpoch}';
    final ack1 = await sendCmd(id: id1, target: 'iterm2', action: 'getSessions');
    stdout.writeln('ACK_LIST=$ack1');

    if (ack1['success'] != true) {
      stderr.writeln('list failed: $ack1');
      exit(2);
    }

    final data1 = (ack1['data'] as Map?)?.cast<String, Object?>();
    final sessions = (data1?['sessions'] as List?)?.whereType<Map>().toList() ?? const [];
    stdout.writeln('SESSIONS_COUNT=${sessions.length}');

    if (sessions.isEmpty) {
      stderr.writeln('no sessions');
      exit(3);
    }

    final first = sessions.first.cast<String, Object?>();
    final sessionId = (first['sessionId'] ?? first['id'] ?? '').toString();
    stdout.writeln('PICK_SESSION=$sessionId');

    final id2 = 'act-${DateTime.now().millisecondsSinceEpoch}';
    final ack2 = await sendCmd(
      id: id2,
      target: 'iterm2',
      action: 'activateSession',
      payload: {'sessionId': sessionId},
    );
    stdout.writeln('ACK_ACTIVATE=$ack2');

    if (ack2['success'] != true) {
      stderr.writeln('activate failed: $ack2');
      exit(4);
    }

    final id3 = 'crop-${DateTime.now().millisecondsSinceEpoch}';
    final ack3 = await sendCmd(
      id: id3,
      target: 'capture',
      action: 'activateAndComputeCrop',
      payload: {'sessionId': sessionId},
    );
    stdout.writeln('ACK_CROP=$ack3');

    if (ack3['success'] != true) {
      stderr.writeln('computeCrop failed: $ack3');
      exit(5);
    }

    await ws.close();
    await responses.close();
  } catch (e, st) {
    stderr.writeln('Error: $e\n$st');
    await ws.close();
    await responses.close();
    exit(1);
  }
}

Future<WebSocket> _connectWithRetry(String url) async {
  const maxAttempts = 20;
  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await WebSocket.connect(url);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  throw SocketException('Failed to connect to $url after $maxAttempts attempts');
}
