import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../theme.dart';
import '../../models/connection_model.dart';

/// Bottom status bar showing connection stats and system info.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Left: Connection status
          _StatusIndicator(
            connected: state.activeConnection?.status == ConnectionStatus.connected,
            label: state.activeConnection?.status == ConnectionStatus.connected
                ? 'Connected'
                : 'Disconnected',
          ),
          const VerticalDivider(width: 1, color: AppTheme.divider),
          
          // Middle: Stream stats (only when streaming)
          if (state.isStreaming && state.streamStats != null) ...[
            _StatBadge(
              icon: Icons.speed,
              value: '${state.streamStats!.fps.toStringAsFixed(0)} fps',
            ),
            const VerticalDivider(width: 1, color: AppTheme.divider),
            _StatBadge(
              icon: Icons.data_usage,
              value: '${(state.streamStats!.bitrate / 1000).toStringAsFixed(1)} Mbps',
            ),
            const VerticalDivider(width: 1, color: AppTheme.divider),
            _StatBadge(
              icon: Icons.timelapse,
              value: '${state.streamStats!.latency} ms',
            ),
            const VerticalDivider(width: 1, color: AppTheme.divider),
          ] else ...[
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Ready',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          ],
          
          // Right: Capture mode
          _ModeBadge(mode: state.captureMode),
          const VerticalDivider(width: 1, color: AppTheme.divider),
          
          // Panel count (only in iTerm2 mode)
          if (state.captureMode == CaptureMode.iterm2Panel)
            _Badge(
              label: '${state.panels.length} panels',
              color: AppTheme.accentRed,
            ),
          if (state.captureMode == CaptureMode.iterm2Panel)
            const VerticalDivider(width: 1, color: AppTheme.divider),
          
          // Version
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'v0.1.0',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool connected;
  final String label;

  const _StatusIndicator({
    required this.connected,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? AppTheme.statusSuccess : AppTheme.statusError,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (connected ? AppTheme.statusSuccess : AppTheme.statusError)
                      .withOpacity(0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: connected ? AppTheme.statusSuccess : AppTheme.statusError,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatBadge({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final CaptureMode mode;

  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    
    if (mode == CaptureMode.screen) {
      label = 'Screen';
      color = AppTheme.statusInfo;
    } else if (mode == CaptureMode.window) {
      label = 'Window';
      color = AppTheme.statusWarning;
    } else {
      label = 'iTerm2';
      color = AppTheme.accentRed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
