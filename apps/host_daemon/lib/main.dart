import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'src/ws_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final stateDir = Directory(
    Platform.environment['ITERMREMOTE_STATE_DIR'] ??
        '${Directory.systemTemp.path}/itermremote-host-daemon',
  );
  if (!stateDir.existsSync()) {
    stateDir.createSync(recursive: true);
  }
  // ignore: avoid_print
  print('[host_daemon] stateDir: ${stateDir.path}');
  final crashLog = File('${stateDir.path}/crash.log');
  final heartbeat = File('${stateDir.path}/heartbeat');
  final pidFile = File('${stateDir.path}/pid');
  try {
    pidFile.writeAsStringSync('$pid\n');
  } catch (_) {
    // State dir might be restricted in some environments; keep running.
  }

  FlutterError.onError = (details) {
    try {
      crashLog.writeAsStringSync(
        '[FlutterError] ${DateTime.now().toIso8601String()}\n'
        '${details.exceptionAsString()}\n'
        '${details.stack ?? ''}\n\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    // Early log to verify daemon entry before any async work.
    // ignore: avoid_print
    print('[host_daemon] runZonedGuarded entry');
    // Best-effort: if a stale daemon is still running, terminate it.
    // ignore: discarded_futures
    _killStaleDaemon(pidFile);

    Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        heartbeat.writeAsStringSync(DateTime.now().toIso8601String());
      } catch (_) {}
    });

    final bus = InMemoryEventBus();
    final registry = BlockRegistry();

    final ctx = BlockContext(bus: bus);

    // Register core blocks.
    final echoBlock = EchoBlock();
    registry.register(echoBlock);

    // Ensure the daemon can find Python scripts when launched from /Applications.
    const repoRoot = '/Users/fanzhang/Documents/github/itermRemote';
    final bridge = ITerm2Bridge(repoRoot: repoRoot);
    final iterm2 = ITerm2Block(bridge: bridge);
    registry.register(iterm2);

    final capture = CaptureBlock(iterm2: bridge);
    registry.register(capture);

    // Initialize blocks.
    for (final b in registry.all) {
      // ignore: discarded_futures
      b.init(ctx);
    }
    // ignore: avoid_print
    print('[host_daemon] blocks initialized');

    final host = '127.0.0.1';
    final envPortStr = Platform.environment['ITERMREMOTE_WS_PORT'];
    final envPort = int.tryParse(envPortStr ?? '');
    final port = envPort ?? 8766;
    // ignore: avoid_print
    print('[host_daemon] ws port env=$envPortStr');
    final wsServer = WsServer(
      registry: registry,
      bus: bus,
      host: host,
      port: port,
    );

    // ignore: avoid_print
    print('[host_daemon] starting WS server on $host:$port');
    await wsServer.start();
    // ignore: avoid_print
    print('[host_daemon] WS server started');

    // Run local network prompt best-effort in background after startup.
    // ignore: discarded_futures
    _triggerLocalNetworkPrompt();

    runApp(const DaemonApp());
  }, (error, stack) {
    // ignore: avoid_print
    print('[host_daemon] FATAL: $error\n$stack');
    try {
      crashLog.writeAsStringSync(
        '[ZonedError] ${DateTime.now().toIso8601String()}\n'
        '$error\n$stack\n\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[host_daemon] crash log write failed: $e');
    }
  });
}

Future<void> _killStaleDaemon(File pidFile) async {
  try {
    if (!pidFile.existsSync()) return;
    final text = pidFile.readAsStringSync().trim();
    final oldPid = int.tryParse(text);
    if (oldPid == null || oldPid == pid) return;
    final ps = await Process.run('ps', ['-p', '$oldPid', '-o', 'command='])
        .timeout(const Duration(milliseconds: 500));
    if (ps.exitCode != 0) return;
    final cmd = (ps.stdout as String).toLowerCase();
    if (!cmd.contains('itermremote') && !cmd.contains('host_daemon')) return;
    // ignore: avoid_print
    print('[host_daemon] killing stale daemon pid=$oldPid');
    try {
      Process.killPid(oldPid, ProcessSignal.sigterm);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 200));
    try {
      Process.killPid(oldPid, ProcessSignal.sigkill);
    } catch (_) {}
  } catch (_) {}
}

Future<void> _triggerLocalNetworkPrompt() async {
  try {
    // Ensure this is best-effort and only runs once per boot/session.
    final stateDir = Directory('/tmp/itermremote-host-daemon');
    if (!stateDir.existsSync()) {
      stateDir.createSync(recursive: true);
    }
    final marker = File('${stateDir.path}/local_network_prompt_triggered');
    if (marker.existsSync()) {
      return;
    }

    // ignore: avoid_print
    print('[host_daemon] local network prompt attempt');
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    if (ifaces.isEmpty) return;

    final addrs = ifaces.expand((i) => i.addresses).where(
          (a) => a.type == InternetAddressType.IPv4 && !a.isLoopback,
        );
    if (addrs.isEmpty) return;

    // Deterministic trigger: attempt a quick TCP connect to a "neighbor" IP in
    // the same /24. This is much more likely to prompt Local Network access
    // than loopback-only traffic.
    final local = addrs.first;
    final parts = local.address.split('.');
    if (parts.length == 4) {
      final neighbor = '${parts[0]}.${parts[1]}.${parts[2]}.1';
      try {
        final s = await Socket.connect(neighbor, 9,
            timeout: const Duration(milliseconds: 200));
        s.destroy();
      } catch (_) {}
    }

    // UDP broadcast/multicast triggers Local Network prompt on macOS.
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final payload = utf8.encode('itermremote-local-network');
    socket.send(payload, InternetAddress('224.0.0.251'), 5353); // mDNS
    socket.send(payload, InternetAddress('255.255.255.255'), 9); // discard
    socket.close();

    // Also try a quick TCP connect to the first LAN IP (will fail fast but triggers prompt).
    final addr = addrs.first;
    try {
      final s = await Socket.connect(addr.address, 9,
          timeout: const Duration(milliseconds: 200));
      s.destroy();
    } catch (_) {}

    // Mark as attempted to avoid repeated prompts/spam.
    try {
      marker.writeAsStringSync(DateTime.now().toIso8601String());
    } catch (_) {}
  } catch (_) {
    // Ignore; prompt may still appear on first real WS access.
  }
}

class DaemonApp extends StatelessWidget {
  const DaemonApp({super.key});

  @override
  Widget build(BuildContext context) {
    // In headless mode we keep the window effectively invisible and non-interactive.
    // We still need a Flutter view hierarchy for plugins that require a running
    // Flutter engine.
    final headless = (Platform.environment['ITERMREMOTE_HEADLESS'] ?? '').trim() == '1';
    if (headless) {
      return const MaterialApp(
        home: SizedBox.shrink(),
      );
    }

    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('iTermRemote Daemon')),
      ),
    );
  }
}
