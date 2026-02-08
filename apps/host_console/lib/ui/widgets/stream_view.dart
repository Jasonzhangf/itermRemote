import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../theme.dart';
import '../../models/connection_model.dart';
import '../pages/preview_page.dart';

/// Center stream view - shows the remote desktop/window/panel stream.
/// This is currently a static placeholder (UI only). Real rendering will be
/// wired up via WS + WebRTC later.
class StreamView extends StatelessWidget {
  const StreamView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stream header - responsive layout (no overflow)
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildModeChip(state.captureMode),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _buildStreamTitle(state),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildPrimaryButton(
                          icon: state.isStreaming ? Icons.stop : Icons.play_arrow,
                          label: state.isStreaming ? 'Stop' : 'Start',
                          onTap: () => state.setStreaming(!state.isStreaming),
                        ),
                        const SizedBox(width: 8),
                        _buildSecondaryButton(
                          icon: Icons.camera_alt_outlined,
                          label: 'Snapshot',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  _buildModeChip(state.captureMode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _buildStreamTitle(state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _buildPrimaryButton(
                    icon: state.isStreaming ? Icons.stop : Icons.play_arrow,
                    label: state.isStreaming ? 'Stop' : 'Start',
                    onTap: () => state.setStreaming(!state.isStreaming),
                  ),
                  const SizedBox(width: 8),
                  _buildSecondaryButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Snapshot',
                    onTap: () {},
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Main preview surface
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Subtle pattern background
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(),
                    ),
                  ),

                  // Placeholder content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(
                            Icons.desktop_windows_outlined,
                            size: 32,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Preview Surface',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          state.isStreaming
                              ? 'Streaming… (UI placeholder)'
                              : 'Select a source and start streaming',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Fake overlay controls
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _buildInfoPill(
                      icon: Icons.speed,
                      label: state.streamStats == null
                          ? '— fps'
                          : '${state.streamStats!.fps.toStringAsFixed(0)} fps',
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _buildInfoPill(
                      icon: Icons.aspect_ratio,
                      label: state.streamStats == null
                          ? '—×—'
                          : '${state.streamStats!.width}×${state.streamStats!.height}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildStreamTitle(AppState state) {
    final mode = state.captureMode;
    if (mode == CaptureMode.screen) {
      return 'Screen Capture';
    } else if (mode == CaptureMode.window) {
      return 'Window Capture';
    } else {
      // CaptureMode.iterm2Panel
      return state.selectedPanel == null
          ? 'iTerm2 Panel (not selected)'
          : 'iTerm2 Panel • ${state.selectedPanel!.title} • ${state.selectedPanel!.detail}';
    }
  }

  Widget _buildModeChip(CaptureMode mode) {
    String label;
    IconData icon;
    if (mode == CaptureMode.screen) {
      label = 'SCREEN';
      icon = Icons.crop_free;
    } else if (mode == CaptureMode.window) {
      label = 'WINDOW';
      icon = Icons.window_outlined;
    } else {
      label = 'ITERM2 PANEL';
      icon = Icons.grid_view;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accentRedLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.accentRedLight,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border.withOpacity(0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.border.withOpacity(0.25)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
