import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_blocks/src/blocks/verify_block.dart';
import 'package:itermremote_blocks/src/blocks/webrtc_block.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:daemon_ws/ws_server.dart';

void main(List<String> args) async {
  final repoRoot = Platform.environment['ITERMREMOTE_REPO_ROOT'] ?? '/Users/fanzhang/Documents/github/itermRemote';
  int port = 8766;
  
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[i + 1]) ?? 8766;
    }
  }

  final stateDir = Directory('${Directory.systemTemp.path}/itermremote-host-daemon');
  if (!stateDir.existsSync()) {
    stateDir.createSync(recursive: true);
  }

  print('[daemon] Starting server on port $port');

  final bus = InMemoryEventBus();
  final registry = BlockRegistry();
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

  final verify = VerifyBlock();
  verify.setDependencies(iterm2Bridge: bridge);
  registry.register(verify);

  for (final b in registry.all) {
    print('[daemon] init block: ${b.name}');
    await b.init(ctx);
  }
  print('[daemon] blocks initialized');

  final wsServer = WsServer(
    registry: registry, 
    bus: bus, 
    host: '0.0.0.0', 
    port: port,
  );

  await wsServer.start();
  print('[daemon] WebSocket server started on 0.0.0.0:$port');

  // Keep process alive
  await Completer<void>().future;
}
