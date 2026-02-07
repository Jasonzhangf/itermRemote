import 'package:flutter/material.dart';

/// Chat history view placeholder.
class ChatHistoryView extends StatelessWidget {
  final List<String> messages;

  const ChatHistoryView({
    super.key,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('No messages yet', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                msg,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        );
      },
    );
  }
}
