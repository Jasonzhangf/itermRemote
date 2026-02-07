import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app/daemon_orchestrator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const repoRoot = '/Users/fanzhang/Documents/github/itermRemote';
  final env = Map<String, String>.from(Platform.environment);
  env['ITERMREMOTE_REPO_ROOT'] = repoRoot;
  env['ITERMREMOTE_PY_TIMEOUT_MS'] = env['ITERMREMOTE_PY_TIMEOUT_MS'] ?? '10000';
  final stateDirPath = Platform.environment['ITERMREMOTE_STATE_DIR'];

  final orchestrator = DaemonOrchestrator(
    repoRoot: repoRoot,
    stateDirPath: stateDirPath,
  );

  await orchestrator.initialize();

  // Keep the process alive in headless mode
  final headless = (Platform.environment['ITERMREMOTE_HEADLESS'] ?? '').trim() == '1' ||
                   const String.fromEnvironment('ITERMREMOTE_HEADLESS') == '1';
  if (headless) {
    // Keep the Dart VM alive
    Timer.periodic(const Duration(seconds: 1), (_) {
      // Heartbeat to keep process alive
    });
  }

  runApp(const DaemonApp());
}

class DaemonApp extends StatelessWidget {
  const DaemonApp({super.key});

  @override
  Widget build(BuildContext context) {
    final headlessEnv = (Platform.environment['ITERMREMOTE_HEADLESS'] ?? '').trim() == '1';
    final headlessDefine = const String.fromEnvironment('ITERMREMOTE_HEADLESS') == '1';
    final headless = headlessEnv || headlessDefine;
    if (headless) {
      return const MaterialApp(home: SizedBox.shrink());
    }

    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('iTermRemote Daemon'))),
    );
  }
}
