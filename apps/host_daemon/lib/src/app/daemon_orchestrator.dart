/// Daemon orchestrator: coordinates block initialization and lifecycle.
/// This is the "app" layer that wires together system modules.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ip_reporter.dart';
import 'relay_signaling_service.dart';
import 'package:flutter/material.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:daemon_ws/ws_server.dart';

import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_blocks/src/blocks/verify_block.dart';
import 'package:itermremote_blocks/src/blocks/webrtc_block.dart';
import 'package:itermremote_blocks/src/blocks/capture_source_block.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

/// Orchestrates the daemon startup sequence and block wiring.
class DaemonOrchestrator {
  DaemonOrchestrator({
    required this.repoRoot,
    String? stateDirPath,
    int? wsPort,
  }) : stateDir = Directory(
         stateDirPath ?? '${Directory.systemTemp.path}/itermremote-host-daemon',
       ) {
    _wsPort = wsPort;
  }

  final String repoRoot;
  final Directory stateDir;
  int? _wsPort;

  late final InMemoryEventBus bus;
  late final BlockRegistry registry;
  late final WsServer wsServer;
  IpReporter? _ipReporter;
  RelaySignalingService? _relayService;
  WebRTCBlock? _webrtcBlock;
  String? _relayTargetDeviceId;

  late final File _logFile;

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $msg';
    // ignore: avoid_print
    print(line);
    // Also write to file for automation (sync for reliability)
    try {
      _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      // If file write fails, at least print went to stdout
      print('[orchestrator] Failed to write log: $e');
    }
  }

  Future<void> initialize() async {
    if (!stateDir.existsSync()) {
      stateDir.createSync(recursive: true);
    }
    // Use absolute path and ensure parent directory exists
    final logPath = '${stateDir.absolute.path}/daemon.log';
    _logFile = File(logPath);
    // Ensure parent directory exists
    if (!_logFile.parent.existsSync()) {
      _logFile.parent.createSync(recursive: true);
    }
    // Ensure log file exists for writes
    if (!_logFile.existsSync()) {
      _logFile.createSync(recursive: true);
    }
    _log('[orchestrator] stateDir: ${stateDir.path}');
    _log('[orchestrator] Log file: ${_logFile.path}');
    _log('[orchestrator] Log file exists: ${_logFile.existsSync()}');

    final crashLog = File('${stateDir.path}/crash.log');
    final heartbeat = File('${stateDir.path}/heartbeat');
    final pidFile = File('${stateDir.path}/pid');
    try {
      pidFile.writeAsStringSync('$pid\n');
    } catch (_) {}

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

    await _killStaleDaemon(pidFile);

    Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        heartbeat.writeAsStringSync(DateTime.now().toIso8601String());
      } catch (_) {}
    });

    bus = InMemoryEventBus();
    registry = BlockRegistry();
    final ctx = BlockContext(bus: bus);

    final echoBlock = EchoBlock();
    registry.register(echoBlock);

    final bridge = ITerm2Bridge(repoRoot: repoRoot);
    final iterm2 = ITerm2Block(bridge: bridge);
    registry.register(iterm2);

    final capture = CaptureBlock(iterm2: bridge);
    registry.register(capture);

    final webrtc = WebRTCBlock();
    registry.register(webrtc);
    _webrtcBlock = webrtc;
    // Print WebRTCBlock address for debugging
    print('[orchestrator] WebRTCBlock instance: ${webrtc.hashCode}');

    final captureSource = CaptureSourceBlock();
    registry.register(captureSource);

    final verify = VerifyBlock();
    verify.setDependencies(iterm2Bridge: bridge);
    registry.register(verify);

    for (final b in registry.all) {
      _log('[orchestrator] init block: ${b.name} (${b.runtimeType})');
      await b.init(ctx);
    }
    _log('[orchestrator] blocks initialized');

    final host = '::';  // Listen on both IPv4 and IPv6
    final envPortStr = Platform.environment['ITERMREMOTE_WS_PORT'];
    final envPort = int.tryParse(envPortStr ?? '');
    final port = envPort ?? _wsPort ?? 8766;
    _log('[orchestrator] ws port env=$envPortStr');

    wsServer = WsServer(registry: registry, bus: bus, host: host, port: port);

    _log('[orchestrator] starting WS server on $host:$port');
    await wsServer.start();
    _log('[orchestrator] WS server started');

    // Start IP reporter if token available (from env or temp file)
    var token = Platform.environment['ITERMREMOTE_TOKEN'];
    _log('[orchestrator] env token: ${token == null ? 'null' : (token.isEmpty ? 'empty' : 'length=${token.length}')}');
    if (token == null || token.isEmpty) {
      // Try reading from temp file (for launchd/app launch via open command)
      final tokenFile = File('/tmp/itermremote_test_token.txt');
      if (tokenFile.existsSync()) {
        try {
          token = tokenFile.readAsStringSync().trim();
          if (token.isNotEmpty) {
            _log('[orchestrator] Token loaded from file (length=${token.length})');
          } else {
            _log('[orchestrator] Token file empty');
          }
        } catch (e) {
          _log('[orchestrator] Failed to read token file: $e');
        }
      } else {
        _log('[orchestrator] Token file not found at /tmp/itermremote_test_token.txt');
      }
    } else {
      _log('[orchestrator] Token from environment (length=${token.length})');
    }
    if (token != null && token.isNotEmpty) {
      _log('[orchestrator] Starting relay services with token length=${token.length}');
      // Add immediate test connection to verify relay reachable
      try {
        final testWs = await WebSocket.connect('ws://code.codewhisper.cc:8081/ws/connect?token=$token');
        testWs.close();
        _log('[orchestrator] Relay test connection successful');
        // Write marker file to indicate relay connectivity
        final marker = File('/tmp/itermremote_relay_connected');
        marker.writeAsStringSync('connected at ${DateTime.now().toIso8601String()}');
      } catch (e) {
        _log('[orchestrator] Relay test connection failed: $e');
        // Optionally write failure marker
        final marker = File('/tmp/itermremote_relay_failed');
        marker.writeAsStringSync('failed at ${DateTime.now().toIso8601String()}: $e');
      }
      _ipReporter = IpReporter(
        serverHost: 'code.codewhisper.cc',
        serverPort: 8081,
        token: token,
      );
      await _ipReporter!.start();
      _log('[orchestrator] IP reporter started');

      // Start relay signaling service for NAT traversal
      _relayService = RelaySignalingService(
        serverHost: 'code.codewhisper.cc',
        serverPort: 8081,
        token: token,
      );

      // Wire relay callbacks to WebRTC block
      _setupRelayCallbacks(ctx);

      // Start relay service in background to avoid blocking
      unawaited(_startRelayService());
    } else {
      _log('[orchestrator] No token, relay services disabled');
    }

    _triggerLocalNetworkPrompt();
  }

  void _setupRelayCallbacks(BlockContext ctx) {
    if (_relayService == null || _webrtcBlock == null) return;

    _relayService!.onOfferReceived = (payload) async {
      final sourceDeviceId = payload['source_device_id'] as String?;
      if (sourceDeviceId != null) {
        _relayTargetDeviceId = sourceDeviceId;
      }
      _log('[orchestrator] Relay: received offer, starting loopback first');
      // Ensure WebRTC is started with a local stream before accepting remote offer
      if (_webrtcBlock != null) {
        final startCmd = Command(
          version: 1,
          id: 'relay-start-loopback',
          target: 'webrtc',
          action: 'startLoopback',
          payload: {'sourceType': 'screen', 'fps': 30, 'bitrateKbps': 2000},
        );
        await _webrtcBlock!.handle(startCmd);
        await Future.delayed(const Duration(milliseconds: 500));
      }
      _log('[orchestrator] Relay: received offer');
      // Forward to WebRTC block
      final cmd = Command(
        version: 1,
        id: 'relay-offer-${DateTime.now().millisecondsSinceEpoch}',
        target: 'webrtc',
        action: 'setRemoteDescription',
        payload: payload,
      );
      await _webrtcBlock!.handle(cmd);
    };

    _relayService!.onAnswerReceived = (payload) async {
      _log('[orchestrator] Relay: received answer');
      final cmd = Command(
        version: 1,
        id: 'relay-answer-${DateTime.now().millisecondsSinceEpoch}',
        target: 'webrtc',
        action: 'setRemoteDescription',
        payload: payload,
      );
      await _webrtcBlock!.handle(cmd);
    };

    _relayService!.onCandidateReceived = (payload) async {
      _log('[orchestrator] Relay: received candidate');
      final cmd = Command(
        version: 1,
        id: 'relay-candidate-${DateTime.now().millisecondsSinceEpoch}',
        target: 'webrtc',
        action: 'addIceCandidate',
        payload: payload,
      );
      await _webrtcBlock!.handle(cmd);
    };

    // Listen to WebRTC events and forward via relay
    bus.stream.where((e) => e.source == 'webrtc').listen((event) {
      if (_relayService?.isConnected != true) return;

      if (event.event == 'iceCandidate' && event.payload != null) {
        final payload = event.payload as Map<String, dynamic>?;
        if (payload != null) {
          final target = _relayTargetDeviceId ?? 'broadcast';
          _relayService!.sendCandidate(payload, targetDeviceId: target);
        }
      } else if (event.event == 'loopbackStarted') {
        // When WebRTC starts, we're ready to receive connections
        _log('[orchestrator] WebRTC ready for relay connections');
      }
    });
  }

  Future<void> _killStaleDaemon(File pidFile) async {
    try {
      if (!pidFile.existsSync()) return;
      final text = pidFile.readAsStringSync().trim();
      final oldPid = int.tryParse(text);
      if (oldPid == null || oldPid == pid) return;
      final ps = await Process.run('ps', [
        '-p',
        '$oldPid',
        '-o',
        'command=',
      ]).timeout(const Duration(milliseconds: 500));
      if (ps.exitCode != 0) return;
      final cmd = (ps.stdout as String).toLowerCase();
      if (!cmd.contains('itermremote') && !cmd.contains('host_daemon')) return;
      _log('[orchestrator] killing stale daemon pid=$oldPid');
      try {
        Process.killPid(oldPid, ProcessSignal.sigterm);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        Process.killPid(oldPid, ProcessSignal.sigkill);
      } catch (_) {}
    } catch (_) {}
  }

  void _triggerLocalNetworkPrompt() {
    // ignore: discarded_futures
    _triggerLocalNetworkPromptImpl();
  }

  Future<void> _triggerLocalNetworkPromptImpl() async {
    try {
      final stateDir = Directory('/tmp/itermremote-host-daemon');
      if (!stateDir.existsSync()) {
        stateDir.createSync(recursive: true);
      }
      final marker = File('${stateDir.path}/local_network_prompt_triggered');
      if (marker.existsSync()) {
        return;
      }

      _log('[orchestrator] local network prompt attempt');
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      if (ifaces.isEmpty) return;

      final addrs = ifaces
          .expand((i) => i.addresses)
          .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback);
      if (addrs.isEmpty) return;

      final local = addrs.first;
      final parts = local.address.split('.');
      if (parts.length == 4) {
        final neighbor = '${parts[0]}.${parts[1]}.${parts[2]}.1';
        try {
          final s = await Socket.connect(
            neighbor,
            9,
            timeout: const Duration(milliseconds: 200),
          );
          s.destroy();
        } catch (_) {}
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final payload = utf8.encode('itermremote-local-network');
      socket.send(payload, InternetAddress('224.0.0.251'), 5353);
      socket.send(payload, InternetAddress('255.255.255.255'), 9);
      socket.close();

      final addr = addrs.first;
      try {
        final s = await Socket.connect(
          addr.address,
          9,
          timeout: const Duration(milliseconds: 200),
        );
        s.destroy();
      } catch (_) {}

      try {
        marker.writeAsStringSync(DateTime.now().toIso8601String());
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _ipReporter?.stop();
    await _relayService?.stop();
    await wsServer.stop();
    await registry.dispose();
    _ipReporter = null;
    _relayService = null;
  }

  Future<void> _startRelayService() async {
    try {
      await _relayService?.start();
      _log('[orchestrator] Relay signaling service started');
    } catch (e) {
      _log('[orchestrator] Relay service start failed: $e');
    }
  }
}
