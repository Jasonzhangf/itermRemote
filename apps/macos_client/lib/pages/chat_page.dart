import 'package:flutter/material.dart';
import '../widgets/chat/chat_history_view.dart';
import '../widgets/chat/chat_input_field.dart';
import '../services/connection_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<String> _history = <String>[];

  void _onSend(String text) {
    setState(() => _history.add(text));
    if (ConnectionService.instance.isConnected) {
      ConnectionService.instance.sendCmd('chat_input', 'send', {'text': text});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(child: ChatHistoryView(messages: _history)),
          const Divider(height: 1),
          ChatInputField(onSend: _onSend),
        ],
      ),
    );
  }
}
