import 'package:flutter/material.dart';

import 'pages/connect_page.dart';
import 'pages/streaming_page.dart';
import 'pages/chat_page.dart';

/// iTerm2 Remote Android client entry point.
void main() {
  runApp(const ITerm2RemoteApp());
}

class ITerm2RemoteApp extends StatelessWidget {
  const ITerm2RemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTerm2 Remote',
      theme: ThemeData.dark(),
      routes: {
        '/': (_) => const ConnectPage(),
        '/streaming': (_) => const StreamingPage(),
        '/chat': (_) => const ChatPage(),
      },
      initialRoute: '/',
    );
  }
}
