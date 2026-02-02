/// Best-effort crop computation for an iTerm2 session (panel) inside its parent
/// window.
///
/// Inputs are the raw `frame` (session) and `windowFrame` values returned by
/// iTerm2's Python API.
///
/// The function evaluates multiple coordinate hypotheses and returns the one
/// with the lowest overflow/clamp penalty.
///
/// Returns `null` when the provided geometry is unusable.
class Iterm2CropComputationResult {
  final Map<String, double> cropRectNorm;
  final String tag;
  final double penalty;
  final int windowMinWidth;
  final int windowMinHeight;

  const Iterm2CropComputationResult({
    required this.cropRectNorm,
    required this.tag,
    required this.penalty,
    required this.windowMinWidth,
    required this.windowMinHeight,
  });
}

Iterm2CropComputationResult? computeIterm2CropRectNorm({
  required double fx,
  required double fy,
  required double fw,
  required double fh,
  required double wx,
  required double wy,
  required double ww,
  required double wh,
}) {
  if (ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0) return null;

  double clamp01(double v) => v.clamp(0.0, 1.0);

  // Bounds in pixels.
  final wPx = fw.clamp(1.0, ww);
  final hPx = fh.clamp(1.0, wh);

  double overflowPenalty({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    if (width <= 1 || height <= 1) return 1e18;
    double p = 0;
    if (left < 0) p += -left;
    if (top < 0) p += -top;
    if (left + width > ww) p += (left + width - ww);
    if (top + height > wh) p += (top + height - wh);
    return p;
  }

  final candidates = <({double left, double top, String tag})>[
    // Doc-based: origin bottom-right, X left, Y up => window - session.
    (left: wx - fx, top: wy - fy, tag: 'doc: wx-fx, wy-fy'),
    // Standard top-left coords: session - window.
    (left: fx - wx, top: fy - wy, tag: 'rel: fx-wx, fy-wy'),
    // Y from bottom.
    (left: fx - wx, top: (wy + wh) - (fy + fh), tag: 'rel: fx-wx, topFromBottom'),
    // X from right edge.
    (left: (wx + ww) - (fx + fw), top: fy - wy, tag: 'alt: leftFromRight, fy-wy'),
    (
      left: (wx + ww) - (fx + fw),
      top: (wy + wh) - (fy + fh),
      tag: 'alt: leftFromRight, topFromBottom'
    ),
    // Some iTerm2 builds appear to return Session.frame already relative to its
    // window.
    (left: fx, top: fy, tag: 'winRel: fx, fy'),
    (left: fx, top: wh - (fy + fh), tag: 'winRel: fx, topFromBottom'),
    (left: ww - (fx + fw), top: fy, tag: 'winRel: leftFromRight, fy'),
    (
      left: ww - (fx + fw),
      top: wh - (fy + fh),
      tag: 'winRel: leftFromRight, topFromBottom'
    ),
  ];

  double bestPenalty = 1e18;
  double bestLeft = wx - fx;
  double bestTop = wy - fy;
  String bestTag = 'doc: wx-fx, wy-fy';

  int priority(String tag) {
    if (tag.startsWith('winRel:')) return 3;
    if (tag.startsWith('rel:')) return 2;
    if (tag.startsWith('alt:')) return 1;
    return 0;
  }

  double scoreCandidate(double left, double top) {
    final overflow = overflowPenalty(
      left: left,
      top: top,
      width: wPx,
      height: hPx,
    );
    final clampedLeft = left.clamp(0.0, ww - wPx);
    final clampedTop = top.clamp(0.0, wh - hPx);
    final clampPenalty = (left - clampedLeft).abs() + (top - clampedTop).abs();
    return overflow + clampPenalty * 2.0;
  }

  const eps = 1e-6;
  for (final c in candidates) {
    final p = scoreCandidate(c.left, c.top);
    if (p < bestPenalty - eps ||
        ((p - bestPenalty).abs() <= eps && priority(c.tag) > priority(bestTag))) {
      bestPenalty = p;
      bestLeft = c.left;
      bestTop = c.top;
      bestTag = c.tag;
    }
  }

  final leftPx = bestLeft.clamp(0.0, ww - wPx);
  final topPx = bestTop.clamp(0.0, wh - hPx);

  final cropRectNorm = <String, double>{
    'x': clamp01(leftPx / ww),
    'y': clamp01(topPx / wh),
    'w': clamp01(wPx / ww),
    'h': clamp01(hPx / wh),
  };

  return Iterm2CropComputationResult(
    cropRectNorm: cropRectNorm,
    tag: bestTag,
    penalty: bestPenalty,
    windowMinWidth: ww.round(),
    windowMinHeight: wh.round(),
  );
}

Iterm2CropComputationResult? computeIterm2CropRectNormBestEffort({
  required double fx,
  required double fy,
  required double fw,
  required double fh,
  required double wx,
  required double wy,
  required double ww,
  required double wh,
  double? rawWx,
  double? rawWy,
  double? rawWw,
  double? rawWh,
}) {
  Iterm2CropComputationResult? best = computeIterm2CropRectNorm(
    fx: fx,
    fy: fy,
    fw: fw,
    fh: fh,
    wx: wx,
    wy: wy,
    ww: ww,
    wh: wh,
  );

  if (rawWw == null || rawWh == null || rawWw <= 0 || rawWh <= 0) return best;

  int touchesBoundary(Map<String, double> r) {
    final x = r['x'] ?? 0.0;
    final y = r['y'] ?? 0.0;
    final w = r['w'] ?? 0.0;
    final h = r['h'] ?? 0.0;
    int t = 0;
    if (x <= 0.0005) t++;
    if (y <= 0.0005) t++;
    if ((x + w) >= 0.9995) t++;
    if ((y + h) >= 0.9995) t++;
    return t;
  }

  double endGapScore(Map<String, double> r) {
    final x = r['x'] ?? 0.0;
    final y = r['y'] ?? 0.0;
    final w = r['w'] ?? 0.0;
    final h = r['h'] ?? 0.0;
    final rightGap = (1.0 - (x + w)).abs();
    final bottomGap = (1.0 - (y + h)).abs();
    return rightGap + bottomGap;
  }

  Iterm2CropComputationResult? pick(
    Iterm2CropComputationResult? a,
    Iterm2CropComputationResult? b,
  ) {
    if (a == null) return b;
    if (b == null) return a;
    const eps = 1e-3;
    if (b.penalty < a.penalty - eps) return b;
    if ((b.penalty - a.penalty).abs() <= eps) {
      final ga = endGapScore(a.cropRectNorm);
      final gb = endGapScore(b.cropRectNorm);
      if (gb < ga - 1e-6) return b;
      if ((gb - ga).abs() <= 1e-6) {
        final ta = touchesBoundary(a.cropRectNorm);
        final tb = touchesBoundary(b.cropRectNorm);
        if (tb < ta) return b;
      }
    }
    return a;
  }

  // Hypothesis: iTerm2 frame/windowFrame already in raw-window coords.
  best = pick(
    best,
    computeIterm2CropRectNorm(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      wx: rawWx ?? wx,
      wy: rawWy ?? wy,
      ww: rawWw,
      wh: rawWh,
    ),
  );

  return best;
}

