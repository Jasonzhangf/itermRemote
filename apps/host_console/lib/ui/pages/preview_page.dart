import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../theme.dart';
import '../../models/connection_model.dart';

/// Fullscreen preview page.
/// UI-only: later we will render real WebRTC video here.
class PreviewPage extends StatelessWidget {
  const PreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          state.selectedPanel == null
              ? 'Preview'
              : 'Preview • \${state.selectedPanel!.title}',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Snapshot',
            onPressed: () {},
            icon: const Icon(Icons.camera_alt_outlined, color: AppTheme.textSecondary),
          ),
          IconButton(
            tooltip: 'Fullscreen',
            onPressed: () {},
            icon: const Icon(Icons.fullscreen, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _TopInfoBar(state: state),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PreviewBackgroundPainter(),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Icon(
                              Icons.live_tv,
                              size: 36,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            state.isStreaming
                                ? 'Streaming… (placeholder)'
                                : 'Not streaming',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'This page will host the real WebRTC renderer later',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: _ActionRow(
                        isStreaming: state.isStreaming,
                        onToggle: () => state.setStreaming(!state.isStreaming),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopInfoBar extends StatelessWidget {
  final AppState state;
  const _TopInfoBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final mode = state.captureMode;
    final modeLabel = mode == CaptureMode.screen
        ? 'Screen'
        : (mode == CaptureMode.window ? 'Window' : 'iTerm2 Panel');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _Pill(
            icon: Icons.crop,
            text: modeLabel,
            color: AppTheme.accentRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.selectedPanel == null
                  ? 'No panel selected'
                  : '\${state.selectedPanel!.title} • \${state.selectedPanel!.detail}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          _Pill(
            icon: Icons.speed,
            text: state.streamStats == null
                ? '— fps'
                : '\${state.streamStats!.fps.toStringAsFixed(0)} fps',
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          _Pill(
            icon: Icons.aspect_ratio,
            text: state.streamStats == null
                ? '—×—'
                : '\${state.streamStats!.width}×\${state.streamStats!.height}',
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool isStreaming;
  final VoidCallback onToggle;
  const _ActionRow({required this.isStreaming, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: onToggle,
          icon: Icon(isStreaming ? Icons.stop : Icons.play_arrow, size: 18),
          label: Text(isStreaming ? 'Stop' : 'Start'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('Snapshot'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Pill({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border.withOpacity(0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PreviewBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppTheme.border.withOpacity(0.22)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final accent = Paint()
      ..color = AppTheme.accentRed.withOpacity(0.12)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height * 0.6), accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
