import 'package:flutter/material.dart';
import '../theme.dart';

class DesktopSimulator extends StatelessWidget {
  const DesktopSimulator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableW = constraints.maxWidth;
              final availableH = constraints.maxHeight;
              // Phone aspect ratio 19.5:9 means height/width = 19.5/9 ≈ 2.16
              final phoneW = (availableW * 0.35).clamp(280.0, 400.0);
              final phoneH = (availableH * 0.85).clamp(phoneW * 2.0, phoneW * 2.2);

             return Row(
               mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (availableW - phoneW > 200)
                    _InfoRail(width: availableW - phoneW - 24),
                  if (availableW - phoneW > 200) const SizedBox(width: 24),
                  _PhoneFrame(width: phoneW, height: phoneH, child: child),
               ],
             );
            },
          ),
        ),
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.width, required this.height, required this.child});

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: AppTheme.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: AppTheme.background,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(width, height),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                    textScaleFactor: 0.9,
                  ),
                  child: child,
                ),
              ),
              Positioned(
                top: 8,
                left: (width / 2) - 40,
                child: Container(
                  width: 80,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRail extends StatelessWidget {
  const _InfoRail({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    if (width < 240) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Android Client Preview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Desktop mock for phone layout\nWebRTC + iTerm2 control surface',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _InfoTag(label: 'Streaming'),
                const SizedBox(width: 8),
                _InfoTag(label: 'Chat'),
                const SizedBox(width: 8),
                _InfoTag(label: 'Panels'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
