import 'package:flutter/material.dart';

/// Chat input widget.
///
/// Requirement: allow user to pre-compose then send once.
class ChatInputField extends StatefulWidget {
  final void Function(String text) onSend;

  const ChatInputField({
    super.key,
    required this.onSend,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final TextEditingController _controller = TextEditingController();

  void _send() {
    final text = _controller.text.trimRight();
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _send,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

