import 'dart:async';
import 'dart:io';

import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

class WsServer {
  WsServer({
    required this.registry,
    required InMemoryEventBus bus,
    required this.host,
    required this.port,
  }) : _bus = bus;

  final BlockRegistry registry;
  final InMemoryEventBus _bus;
  final String host;
  final int port;

  final _codec = const EnvelopeJsonCodec();
  HttpServer? _server;

  final Set<_WsClient> _clients = {};

  Future<void> start() async {
    // Best-effort preflight: clear stale listeners from previous runs.
    // Ignore failures to avoid killing unrelated processes.
    try {
      await _killOwnPortOccupiers(port);
    } catch (_) {}
    final handler = Pipeline().addMiddleware(logRequests()).addHandler(
      webSocketHandler(_handleWs),
    );

    try {
      _server = await shelf_io.serve(handler, host, port);
      final actualPort = _server!.port;
      // ignore: avoid_print
      print('[host_daemon] WS server listening on http://$host:$actualPort');
      await _selfCheckTcp();
    } on SocketException catch (e) {
      // ignore: avoid_print
      print('[host_daemon] WS bind failed: $e');
      // If the port is already in use, we only kill a listener that is clearly
      // ours (host_daemon/itermremote). We never kill random node processes.
      if (e.osError?.errorCode != 48 /*EADDRINUSE*/) {
        rethrow;
      }

      final killed = await _killOwnPortOccupiers(port);
      // ignore: avoid_print
      print('[host_daemon] killOwnPortOccupiers=$killed');
      if (!killed) {
        rethrow;
      }

      _server = await shelf_io.serve(handler, host, port);
      final actualPort = _server!.port;
      // ignore: avoid_print
      print('[host_daemon] WS server listening on http://$host:$actualPort (after kill)');
      await _selfCheckTcp();
    }

    _bus.stream.listen((evt) {
      for (final c in _clients) {
        if (c.isSubscribed(evt.source)) {
          c.send(evt);
        }
      }
    });
  }

  Future<void> _selfCheckTcp() async {
    // Sanity check: if we can't connect to our own listener, crash early.
    try {
      final actualPort = _server?.port ?? port;
      final socket = await Socket.connect(host, actualPort, timeout: const Duration(seconds: 1));
      socket.destroy();
    } catch (e) {
      // ignore: avoid_print
      print('[host_daemon] FATAL: WS listener self-check failed: $e');
      rethrow;
    }
  }

  Future<bool> _killOwnPortOccupiers(int port) async {
    try {
      // Use lsof -t to get PIDs, then verify the command belongs to us.
      final res = await Process.run(
        '/usr/sbin/lsof',
        ['-t', '-nP', '-i', 'TCP:$port', '-sTCP:LISTEN'],
      );
      if (res.exitCode != 0) return false;

      final targets = <int>{};
      final raw = (res.stdout as String).trim();
      if (raw.isEmpty) return false;
      final selfPid = pid;
      final pids = raw.split(RegExp(r'\s+')).map(int.tryParse);

      for (final otherPid in pids) {
        if (otherPid == null) continue;
        if (selfPid != null && otherPid == selfPid) {
          continue;
        }
        final ps = await Process.run(
          '/bin/ps',
          ['-p', '$otherPid', '-o', 'command='],
        );
        if (ps.exitCode != 0) continue;
        final cmd = (ps.stdout as String).toLowerCase();
        if (cmd.contains('itermremote.app/contents/macos/itermremote') ||
            cmd.contains('host_daemon') ||
            cmd.contains('itermremote')) {
          targets.add(otherPid);
        }
      }

      if (targets.isEmpty) return false;

      // ignore: avoid_print
      print('[host_daemon] killing port $port targets: ${targets.toList()}');
      for (final p in targets) {
        try {
          Process.killPid(p, ProcessSignal.sigterm);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (final p in targets) {
        try {
          Process.killPid(p, ProcessSignal.sigkill);
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleWs(webSocket) {
    final client = _WsClient(webSocket, codec: _codec);
    _clients.add(client);

    client.onClosed.then((_) {
      _clients.remove(client);
    });

    client.incoming.listen((env) async {
      if (env is! Command) return;

      if (env.target == 'orchestrator' && env.action == 'subscribe') {
        final sources = (env.payload?['sources'] as List?)?.whereType<String>().toSet();
        if (sources == null) {
          client.send(
            Ack.fail(
              id: env.id,
              code: 'invalid_payload',
              message: 'subscribe requires payload.sources: string[]',
            ),
          );
          return;
        }
        client.setSubscriptions(sources);
        client.send(Ack.ok(id: env.id, data: {'sources': sources.toList()}));
        return;
      }

      if (env.target == 'orchestrator' && env.action == 'getState') {
        client.send(Ack.ok(id: env.id, data: {'state': registry.dumpState()}));
        return;
      }

      final ack = await registry.route(env);
      client.send(ack);
    });
  }
}

class _WsClient {
  _WsClient(this._ws, {required EnvelopeJsonCodec codec}) : _codec = codec {
    _ws.stream.listen(
      (data) {
        if (data is String) {
          try {
            _incomingController.add(_codec.decode(data));
          } catch (e) {
            _ws.sink.add(
              _codec.encode(
                Ack.fail(
                  id: 'unknown',
                  code: 'decode_error',
                  message: e.toString(),
                ),
              ),
            );
          }
        }
      },
      onDone: () {
        _incomingController.close();
        _closed.complete();
      },
      onError: (_) {
        _incomingController.close();
        _closed.complete();
      },
    );
  }

  final dynamic _ws;
  final EnvelopeJsonCodec _codec;
  final _incomingController = StreamController<Envelope>.broadcast();
  final _closed = Completer<void>();

  Set<String> _subscriptions = const {};

  Stream<Envelope> get incoming => _incomingController.stream;
  Future<void> get onClosed => _closed.future;

  bool isSubscribed(String source) => _subscriptions.contains(source);

  void setSubscriptions(Set<String> sources) {
    _subscriptions = sources;
  }

  void send(Envelope env) {
    _ws.sink.add(_codec.encode(env));
  }
}
