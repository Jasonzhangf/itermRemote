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
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      child: const Text('Video stream surface (placeholder)'),
    );
  }
}

