import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets/desktop_simulator.dart';
import 'pages/main_shell.dart';

/// iTerm2 Remote Android client entry point.
void main() {
  runApp(const ITerm2RemoteApp());
}

class ITerm2RemoteApp extends StatelessWidget {
  const ITerm2RemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    return MaterialApp(
      title: 'iTerm2 Remote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        if (!isDesktop) return child ?? const SizedBox.shrink();
        return DesktopSimulator(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainShell(),
    );
  }
}
