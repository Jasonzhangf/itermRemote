import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:host_console/services/ws_client.dart';

void main() {
  test('WsClient sendCommand receives Ack', () async {
    late final HttpServer server;

    final handler = webSocketHandler((webSocket) {
      webSocket.stream.listen((msg) {
        final jsonMap = jsonDecode(msg as String) as Map<String, dynamic>;
        final cmd = Command.fromJson(jsonMap);
        final ack = Ack.ok(id: cmd.id, data: {'ok': true});
        webSocket.sink.add(jsonEncode(ack.toJson()));
      });
    });

    server = await shelf_io.serve(
      handler,
      '127.0.0.1',
      0,
    );

    final url = 'ws://127.0.0.1:${server.port}';
    final client = WsClient(url: url);
    await client.connect();

    final cmd = Command(
      version: itermremoteProtocolVersion,
      id: 'test-1',
      target: 'echo',
      action: 'ping',
    );

    final ack = await client.sendCommand(cmd);
    expect(ack.success, isTrue);
    expect(ack.data?['ok'], isTrue);

    client.close();
    await server.close(force: true);
  });
}
