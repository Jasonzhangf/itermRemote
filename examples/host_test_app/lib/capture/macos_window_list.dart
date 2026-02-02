import 'package:flutter/services.dart';

class MacOsWindowInfo {
  final String ownerName;
  final int windowNumber;
  final double x;
  final double y;
  final double w;
  final double h;

  const MacOsWindowInfo({
    required this.ownerName,
    required this.windowNumber,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class MacOsWindowList {
  static const MethodChannel _ch = MethodChannel('itermRemote/window_list');

  static Future<List<MacOsWindowInfo>> listWindows() async {
    final any = await _ch.invokeMethod('listWindows');
    if (any is! List) return const [];
    final out = <MacOsWindowInfo>[];
    for (final item in any) {
      if (item is! Map) continue;
     final owner = item['ownerName'];
      final winNum = item['windowNumber'];
      final bounds = item['bounds'];
      if (owner is! String || winNum is! int || bounds is! Map) continue;
      final x = (bounds['X'] ?? bounds['x']);
      final y = (bounds['Y'] ?? bounds['y']);
      final w = (bounds['Width'] ?? bounds['w']);
      final h = (bounds['Height'] ?? bounds['h']);
      if (x is! num || y is! num || w is! num || h is! num) continue;
      out.add(MacOsWindowInfo(
        ownerName: owner,
        windowNumber: winNum,
        x: x.toDouble(),
        y: y.toDouble(),
        w: w.toDouble(),
        h: h.toDouble(),
      ));
    }
    return out;
  }
}
