import 'dart:async';

import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';

import 'capture_source.dart';
import 'macos_window_list.dart';

/// Load capturable sources (screen/window/iTerm2 panel) using real system APIs.
///
/// This lives in the example app because it uses flutter_webrtc desktop APIs.
class CaptureModeController {
  final ITerm2Bridge iterm2Bridge;

  CaptureModeController({required this.iterm2Bridge});

  Future<List<CapturableScreen>> listScreens({
    ThumbnailSize? thumbnailSize,
  }) async {
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Screen],
      thumbnailSize: thumbnailSize,
    );
    return sources
        .map((s) => CapturableScreen(
              id: s.id,
              title: s.name,
              thumbnail: s.thumbnail,
              thumbnailSize: thumbnailSize,
            ))
        .toList(growable: false);
  }

  bool _isItermSource(DesktopCapturerSource s) {
    final an = (s.appName ?? '').toLowerCase();
    final aid = (s.appId ?? '').toLowerCase();
    final name = s.name.toLowerCase();
    return an.contains('iterm') || aid.contains('iterm') || name.contains('iterm');
  }

  bool _isSelfSource(DesktopCapturerSource s) {
    final an = (s.appName ?? '').toLowerCase();
    final aid = (s.appId ?? '').toLowerCase();
    final name = s.name.toLowerCase();
    return an.contains('host_test_app') ||
        aid.contains('host_test_app') ||
        name.contains('host_test_app');
  }

  Future<List<CapturableWindow>> listWindows({
    ThumbnailSize? thumbnailSize,
  }) async {
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Window],
      thumbnailSize: thumbnailSize,
    );
    return sources
        .map((s) => CapturableWindow(
              id: s.id,
              title: s.name,
              thumbnail: s.thumbnail,
              thumbnailSize: thumbnailSize,
            ))
        .toList(growable: false);
  }

  /// iTerm2 panels need: (1) panel list from python API, (2) a window capture
  /// source to crop from.
  Future<List<Iterm2PanelItem>> listIterm2Panels({
    required ThumbnailSize thumbnailSize,
  }) async {
    final panels = await iterm2Bridge.getSessions();

    // Also list windows with thumbnails, used to render panel previews.
    final windows = await desktopCapturer.getSources(
      types: [SourceType.Window],
      thumbnailSize: thumbnailSize,
    );

    // Use iTerm2 window_number to deterministically pick the correct window:
    // - fetch the real iTerm2 window frame via python
    // - match by nearest desktop window bounds via a small macOS helper
    final winNumberToDesktopSourceId = <int, String>{};
    for (final p in panels) {
      final n = p.windowNumber;
      if (n == null || n <= 0) continue;
      if (winNumberToDesktopSourceId.containsKey(n)) continue;
      try {
        final id = await _resolveDesktopWindowForItermWindowNumber(n, windows);
        if (id != null) winNumberToDesktopSourceId[n] = id;
      } catch (_) {
        // ignore, fall back to null
      }
    }

    final items = <Iterm2PanelItem>[];
    for (final p in panels) {
      final crop = _computeCropRectNormFromSession(p);
      final bestWindowId = (p.windowNumber != null)
          ? winNumberToDesktopSourceId[p.windowNumber!]
          : null;
      final bestWindow = (bestWindowId == null)
          ? null
          : windows.where((w) => w.id == bestWindowId).cast<DesktopCapturerSource?>().first;
      // Prefer the stable CGWindowID for SCK-direct capture.
      // Use cgWindowId if available; otherwise fall back to resolved window source.
      String stableWindowSourceId;
      if (p.cgWindowId != null && p.cgWindowId! > 0) {
        stableWindowSourceId = '${p.cgWindowId}';
      } else if (bestWindowId != null) {
        stableWindowSourceId = bestWindowId;
      } else {
        // Last resort: use windowNumber if available.
        stableWindowSourceId = (p.windowNumber != null && p.windowNumber! > 0)
            ? '${p.windowNumber}'
            : '';
      }

      items.add(Iterm2PanelItem(
        sessionId: p.sessionId,
        title: p.title,
        detail: p.detail,
        cropRectNorm: crop,
        windowSourceId: stableWindowSourceId.isNotEmpty ? stableWindowSourceId : null,
        windowThumbnail: bestWindow?.thumbnail,
      ));
    }

    return items;
  }

  /// Public helper for app-level selection flows.
  ///
  /// Given an iTerm2 `windowNumber`, attempt to resolve the corresponding
  /// flutter_webrtc DesktopCapturerSource.id.
  Future<String?> resolveDesktopWindowForItermWindowNumber(
    int windowNumber,
    List<DesktopCapturerSource> windows,
  ) {
    return _resolveDesktopWindowForItermWindowNumber(windowNumber, windows);
  }

  Map<String, double>? _computeCropRectNormFromSession(ITerm2SessionInfo s) {
    final f = s.frame;
    final wf = s.windowFrame;
    if (f == null || wf == null) return null;

    final fx = f['x'] ?? 0.0;
    final fy = f['y'] ?? 0.0;
    final fw = f['w'] ?? 0.0;
    final fh = f['h'] ?? 0.0;

    final wx = wf['x'] ?? 0.0;
    final wy = wf['y'] ?? 0.0;
    final ww = wf['w'] ?? 0.0;
    final wh = wf['h'] ?? 0.0;

    final r = computeIterm2CropRectNormBestEffort(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      wx: wx,
      wy: wy,
      ww: ww,
      wh: wh,
    );
    return r?.cropRectNorm;
  }

  Future<String?> _resolveDesktopWindowForItermWindowNumber(
    int windowNumber,
    List<DesktopCapturerSource> windows,
  ) async {
    final frames = await iterm2Bridge.getWindowFrames();
    Map<String, dynamic>? target;
    for (final w in frames) {
      final n = w['windowNumber'];
      if (n is num && n.toInt() == windowNumber) {
        target = w;
        break;
      }
    }
    if (target == null) return null;
    final raw = target['rawWindowFrame'];
    if (raw is! Map) return null;
    final rx = (raw['x'] as num?)?.toDouble();
    final ry = (raw['y'] as num?)?.toDouble();
    final rw = (raw['w'] as num?)?.toDouble();
    final rh = (raw['h'] as num?)?.toDouble();
    if (rx == null || ry == null || rw == null || rh == null) return null;

    // With the cloudplayplus_stone fork of flutter_webrtc, the desktop capturer
    // surfaces the native windowId (best-effort) which is matchable.
    for (final s in windows) {
      final wid = s.windowId;
      if (wid != null && wid == windowNumber && _isItermSource(s)) {
        return s.id;
      }
    }

    // Strong fallback: prefer any window source that is clearly iTerm2.
    // This avoids selecting the wrong app when windowId mapping is unreliable.
    for (final s in windows) {
      if (_isItermSource(s)) return s.id;
    }

   // Get macOS window list from native API and match iTerm2 window frame.
    List<MacOsWindowInfo> macWindows;
    try {
      macWindows = await MacOsWindowList.listWindows();
    } catch (_) {
      macWindows = const [];
    }
    final candidates = macWindows
        .where((w) => w.ownerName.toLowerCase().contains('iterm'))
        .toList(growable: false);

    if (candidates.isEmpty) return null;

    double score(MacOsWindowInfo w) {
      // iTerm2 coordinates are bottom-left; CGWindow bounds are top-left.
      // We match primarily by size to avoid coordinate system mismatch.
      final sizeScore = (w.w - rw).abs() + (w.h - rh).abs();
      return sizeScore;
    }

    MacOsWindowInfo best = candidates.first;
    double bestScore = score(best);
    for (final c in candidates.skip(1)) {
      final s = score(c);
      if (s < bestScore) {
        bestScore = s;
        best = c;
      }
    }

    // Map to flutter_webrtc DesktopCapturerSource by closest size.
    // NOTE: This is a weak heuristic because thumbnail sizes are not the real
    // window sizes. Prefer appName/appId and windowId match whenever possible.
    DesktopCapturerSource? bestSource;
    double bestSourceScore = double.infinity;
    for (final s in windows) {
      if (_isSelfSource(s)) continue;
      final ts = s.thumbnailSize;
      final sw = ts.width.toDouble();
      final sh = ts.height.toDouble();
      // Thumbnail is a scaled representation; use aspect ratio match only.
      final arPenalty = ((sw / sh) - (best.w / best.h)).abs() * 1000.0;
      final namePenalty = s.name.toLowerCase().contains('iterm') ? 0.0 : 5000.0;
      final total = arPenalty + namePenalty;
      if (total < bestSourceScore) {
        bestSourceScore = total;
        bestSource = s;
      }
    }

    return bestSource?.id;
  }
}
