import 'package:flutter/material.dart';

/// Video rendering placeholder.
///
/// In future phases this will host an RTCVideoRenderer from flutter_webrtc.
class VideoRenderer extends StatelessWidget {
  const VideoRenderer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: const Color(0xFF09090B),
      alignment: Alignment.center,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.2)),
                const SizedBox(height: 16),
                Text(
                  'Video Stream',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Placeholder for WebRTC surface',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
