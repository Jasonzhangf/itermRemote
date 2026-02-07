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
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _send,
                icon: const Icon(Icons.send, color: Colors.white),
                tooltip: 'Send message',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
