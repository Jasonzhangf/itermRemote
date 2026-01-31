import 'package:flutter/material.dart';

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
      home: const HomePage(),
    );
  }
}

/// Home page placeholder.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iTerm2 Remote'),
      ),
      body: const Center(
        child: Text('iTerm2 Remote Client'),
      ),
    );
  }
}
