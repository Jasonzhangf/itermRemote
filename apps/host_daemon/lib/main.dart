import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app/daemon_orchestrator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure the daemon can find Python scripts when launched from /Applications.
  const repoRoot = '/Users/fanzhang/Documents/github/itermRemote';
  final stateDirPath = Platform.environment['ITERMREMOTE_STATE_DIR'];

  final orchestrator = DaemonOrchestrator(
    repoRoot: repoRoot,
    stateDirPath: stateDirPath,
  );

  await orchestrator.initialize();

  runApp(const DaemonApp());
}

class DaemonApp extends StatelessWidget {
  const DaemonApp({super.key});

  @override
  Widget build(BuildContext context) {
    // In headless mode we keep the window effectively invisible and non-interactive.
    // We still need a Flutter view hierarchy for plugins that require a running
    // Flutter engine.
    final headless =
        (Platform.environment['ITERMREMOTE_HEADLESS'] ?? '').trim() == '1';
    if (headless) {
      return const MaterialApp(home: SizedBox.shrink());
    }

    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('iTermRemote Daemon'))),
    );
  }
}
