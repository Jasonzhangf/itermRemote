// ignore_for_file: directives_ordering, directives_after_declarations, duplicate_import, undefined_identifier
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/theme.dart';
import 'logic/app_state.dart';
import 'ui/pages/main_page.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const HostConsoleApp(),
    ),
  );
}

class HostConsoleApp extends StatelessWidget {
  const HostConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTermRemote Console',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainPage(),
    );
  }
}
