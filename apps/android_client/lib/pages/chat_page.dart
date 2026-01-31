import 'package:flutter/material.dart';

import '../widgets/chat/chat_history_view.dart';
import '../widgets/chat/chat_input_field.dart';

/// Chat page placeholder.
///
/// Primary requirement:
/// - user can pre-compose text and send it as a single payload to the host
///   (later: one-shot injection to iTerm2 chat input).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<String> _history = <String>[];

  void _onSend(String text) {
    setState(() {
      _history.add(text);
    });

    // TODO: Send to host via data channel.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ChatHistoryView(messages: _history),
          ),
          const Divider(height: 1),
          ChatInputField(
            onSend: _onSend,
          ),
        ],
      ),
    );
  }
}

