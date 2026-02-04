import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_daemon/src/ws_server.dart';

void main() {
  test('WsServer routes cmd to block and returns ack', () async {
    final bus = InMemoryEventBus();
    final registry = BlockRegistry();
    registry.register(EchoBlock());

    final server = WsServer(
      registry: registry,
      bus: bus,
      host: '127.0.0.1',
      port: 0, // ephemeral
    );
    await server.start();

    final actualPort = server.boundPort;
    expect(actualPort, greaterThan(0));

    final ch = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$actualPort'));
    addTearDown(() async {
      await ch.sink.close();
      await server.stop();
      await bus.close();
    });

    const codec = EnvelopeJsonCodec();
    final cmd = Command(
      version: itermremoteProtocolVersion,
      id: '1',
      target: 'echo',
      action: 'echo',
      payload: {'msg': 'hi'},
    );

    ch.sink.add(codec.encode(cmd));

    final first = await ch.stream.first.timeout(const Duration(seconds: 2));
    expect(first, isA<String>());

    final env = codec.decode(first as String);
    expect(env, isA<Ack>());
    final ack = env as Ack;
    expect(ack.id, '1');
    expect(ack.success, isTrue);
    expect(ack.data?['echo'], isNotNull);
  });
}
