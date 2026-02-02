import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';

void main() {
  group('computeIterm2CropRectNormBestEffort', () {
    test('returns normalized crop within 0..1', () {
      final r = computeIterm2CropRectNormBestEffort(
        fx: 400,
        fy: 0,
        fw: 400,
        fh: 300,
        wx: 0,
        wy: 0,
        ww: 800,
        wh: 600,
      );
      expect(r, isNotNull);
      final crop = r!.cropRectNorm;
      for (final k in ['x', 'y', 'w', 'h']) {
        expect(crop[k], isNotNull);
        expect(crop[k]!, inInclusiveRange(0.0, 1.0));
      }
      expect(crop['w']!, closeTo(0.5, 1e-6));
      expect(crop['h']!, closeTo(0.5, 1e-6));
    });
  });
}

