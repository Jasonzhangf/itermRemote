import 'package:flutter/material.dart';

import '../widgets/streaming/video_renderer.dart';
import '../widgets/streaming/panel_switcher.dart';

/// Streaming page placeholder.
///
/// In Phase-3, this page only shows the intended layout for:
/// - video streaming surface
/// - capture target switching
/// - mode switching between video/chat
class StreamingPage extends StatefulWidget {
  const StreamingPage({super.key});

  @override
  State<StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<StreamingPage> {
  bool _chatMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_chatMode ? 'Chat Mode' : 'Streaming'),
        actions: [
          IconButton(
            tooltip: _chatMode ? 'Switch to video' : 'Switch to chat',
            icon: Icon(_chatMode ? Icons.videocam : Icons.chat_bubble),
            onPressed: () {
              setState(() {
                _chatMode = !_chatMode;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const PanelSwitcher(),
          const Divider(height: 1),
          Expanded(
            child: _chatMode
                ? Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pushNamed('/chat'),
                      child: const Text('Open Chat'),
                    ),
                  )
                : const VideoRenderer(),
          ),
        ],
      ),
    );
  }
}

