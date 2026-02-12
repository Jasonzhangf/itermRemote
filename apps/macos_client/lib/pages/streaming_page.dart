import 'package:flutter/material.dart';
import '../widgets/streaming/video_renderer.dart';
import '../widgets/streaming/panel_switcher.dart';
import '../widgets/streaming/floating_shortcut_button.dart';
import '../services/connection_service.dart';

class StreamingPage extends StatefulWidget {
  const StreamingPage({super.key, this.hostId, this.hostName, this.hostIp});
  final String? hostId;
  final String? hostName;
  final String? hostIp;

  @override
  State<StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<StreamingPage> {
  HostConnectionState _connectionState = HostConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    ConnectionService.instance.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
    _connectionState = ConnectionService.instance.isConnected
        ? HostConnectionState.connected
        : HostConnectionState.disconnected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(widget.hostName ?? 'Streaming')),
      body: Stack(
        children: [
          Positioned.fill(child: _StreamingView(hostId: widget.hostId, connectionState: _connectionState)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: theme.scaffoldBackgroundColor.withOpacity(0.95),
              child: const PanelSwitcher(),
            ),
          ),
          const Positioned.fill(child: FloatingShortcutButton()),
        ],
      ),
    );
  }
}

class _StreamingView extends StatelessWidget {
  const _StreamingView({this.hostId, required this.connectionState});
  final String? hostId;
  final HostConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = connectionState == HostConnectionState.connected;
    return Stack(
      children: [
        VideoRenderer(hostId: hostId),
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
                Icon(
                  Icons.circle,
                  color: isConnected ? theme.colorScheme.primary : Colors.grey,
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Connected' : 'Disconnected',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
