import 'package:flutter/material.dart';

import '../widgets/streaming/video_renderer.dart';
import '../widgets/streaming/panel_switcher.dart';
import '../widgets/streaming/floating_shortcut_button.dart';

/// Streaming page - remote control with video + touch interface.
class StreamingPage extends StatefulWidget {
  const StreamingPage({super.key});

  @override
  State<StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<StreamingPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Streaming'),
      ),
      body: Stack(
        children: [
          // Video surface
          Positioned.fill(
            child: _StreamingView(),
          ),
          
          // Panel switcher (top)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: theme.scaffoldBackgroundColor.withOpacity(0.95),
              child: const PanelSwitcher(),
            ),
          ),
          
          // 悬浮快捷键按钮（固定右下角）
          const Positioned.fill(
            child: FloatingShortcutButton(),
          ),
        ],
      ),
    );
  }
}

class _StreamingView extends StatelessWidget {
  const _StreamingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        const VideoRenderer(),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: theme.colorScheme.primary, size: 8),
                const SizedBox(width: 6),
                Text('Connected', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
