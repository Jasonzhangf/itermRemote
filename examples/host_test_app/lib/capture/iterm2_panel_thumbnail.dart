import 'dart:typed_data';

import 'package:flutter/material.dart';

class Iterm2PanelThumbnail extends StatelessWidget {
  final Uint8List? thumbnailBytes;
  final Map<String, double>? cropRectNorm;

  const Iterm2PanelThumbnail({
    super.key,
    required this.thumbnailBytes,
    required this.cropRectNorm,
  });

  @override
  Widget build(BuildContext context) {
    const w = 92.0;
    const h = 52.0;

    final bytes = thumbnailBytes;
    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: const Icon(Icons.terminal, size: 20, color: Colors.black54),
      );
    }

    final crop = cropRectNorm;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            if (crop != null) CustomPaint(painter: _CropRectPainter(crop)),
          ],
        ),
      ),
    );
  }
}

class _CropRectPainter extends CustomPainter {
  final Map<String, double> crop;

  const _CropRectPainter(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final x = (crop['x'] ?? 0.0).clamp(0.0, 1.0);
    final y = (crop['y'] ?? 0.0).clamp(0.0, 1.0);
    final w = (crop['w'] ?? 0.0).clamp(0.0, 1.0);
    final h = (crop['h'] ?? 0.0).clamp(0.0, 1.0);
    if (w <= 0 || h <= 0) return;

    final rect = Rect.fromLTWH(
      x * size.width,
      y * size.height,
      w * size.width,
      h * size.height,
    );
    final paint = Paint()
      ..color = Colors.redAccent.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, paint);

    final fill = Paint()
      ..color = Colors.redAccent.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fill);
  }

  @override
  bool shouldRepaint(covariant _CropRectPainter oldDelegate) {
    return oldDelegate.crop != crop;
  }
}

