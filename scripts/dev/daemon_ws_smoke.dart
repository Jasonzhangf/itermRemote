import 'dart:async';
import 'dart:io';

import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> main(List<String> args) async {
  final host = Platform.environment['ITERMREMOTE_WS_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['ITERMREMOTE_WS_PORT'] ?? '') ?? 8766;
  final url = Uri.parse('ws://$host:$port');

  stderr.writeln('[smoke] connect $url');
  final ch = WebSocketChannel.connect(url);
  final codec = const EnvelopeJsonCodec();

  final stream = ch.stream.asBroadcastStream();
  final sub = stream.listen((data) {
    stderr.writeln('[smoke] recv: $data');
  });

  Future<Ack> sendCmd(String target, String action, Map<String, Object?> payload) async {
    final id = 'smoke-${DateTime.now().millisecondsSinceEpoch}-${target}-$action';
    final cmd = Command(
      version: itermremoteProtocolVersion,
      id: id,
      target: target,
      action: action,
      payload: payload,
    );
    ch.sink.add(codec.encode(cmd));
    final completer = Completer<Ack>();
    late StreamSubscription s;
    s = stream.listen((data) {
      if (data is! String) return;
      final env = codec.decode(data);
      if (env is Ack && env.id == id) {
        completer.complete(env);
        s.cancel();
      }
    });
    return completer.future.timeout(const Duration(seconds: 3));
  }

  final ack1 = await sendCmd('echo', 'echo', {'hello': 'world'});
  stdout.writeln('echoAck=${ack1.toJson()}');

  final ack2 = await sendCmd('orchestrator', 'getState', const {});
  stdout.writeln('stateAck=${ack2.toJson()}');

  await sub.cancel();
  await ch.sink.close();
}
