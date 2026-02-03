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
  final bool _allowDesktopSources;

  CaptureModeController({
    required this.iterm2Bridge,
    bool allowDesktopSources = false,
  }) : _allowDesktopSources = allowDesktopSources;

  Future<List<CapturableScreen>> listScreens({
    ThumbnailSize? thumbnailSize,
  }) async {
    if (!_allowDesktopSources) {
      return const [];
    }
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Screen],
      thumbnailSize: thumbnailSize,
    );
    return sources
        .map(
          (s) => CapturableScreen(
            id: s.id,
            title: s.name,
            thumbnail: s.thumbnail,
            thumbnailSize: thumbnailSize,
          ),
        )
        .toList(growable: false);
  }

  bool _isItermSource(DesktopCapturerSource s) {
    final name = s.name.toLowerCase();
    return name.contains('iterm');
  }

  bool _isSelfSource(DesktopCapturerSource s) {
    final name = s.name.toLowerCase();
    return name.contains('host_test_app');
  }

  Future<List<CapturableWindow>> listWindows({
    ThumbnailSize? thumbnailSize,
  }) async {
    if (!_allowDesktopSources) {
      return const [];
    }
    final sources = await desktopCapturer.getSources(
      types: [SourceType.Window],
      thumbnailSize: thumbnailSize,
    );
    return sources
        .map(
          (s) => CapturableWindow(
            id: s.id,
            title: s.name,
            thumbnail: s.thumbnail,
            thumbnailSize: thumbnailSize,
          ),
        )
        .toList(growable: false);
  }

  /// iTerm2 panels need: (1) panel list from python API, (2) a window capture
  /// source to crop from.
  Future<List<Iterm2PanelItem>> listIterm2Panels({
    ThumbnailSize? thumbnailSize,
  }) async {
    final panels = await iterm2Bridge.getSessions();

    // Labels must reflect spatial order, not enumeration order.
    // We'll sort by (top, left) in the iTerm2 coordinate system.
    // iTerm2 frames are in points. If frame is missing, fall back to layoutFrame.
    int cmp(ITerm2SessionInfo a, ITerm2SessionInfo b) {
      final af = a.frame ?? a.layoutFrame;
      final bf = b.frame ?? b.layoutFrame;
      final ay = af?['y'] ?? 0.0;
      final ax = af?['x'] ?? 0.0;
      final by = bf?['y'] ?? 0.0;
      final bx = bf?['x'] ?? 0.0;
      // Smaller y is higher/top in most iTerm2 frames.
      if ((ay - by).abs() > 1e-3) return ay.compareTo(by);
      if ((ax - bx).abs() > 1e-3) return ax.compareTo(bx);
      return a.index.compareTo(b.index);
    }

    final sortedPanels = panels.toList(growable: false)..sort(cmp);
    final titleBySession = <String, String>{};
    for (int i = 0; i < sortedPanels.length; i++) {
      titleBySession[sortedPanels[i].sessionId] = 'P${i + 1}';
    }

    List<DesktopCapturerSource> windows = const [];
    Map<int, String> winNumberToDesktopSourceId = const {};
    if (_allowDesktopSources) {
      // Also list windows with thumbnails, used to render panel previews.
      windows = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: thumbnailSize,
      );

      // Use iTerm2 window_number to deterministically pick the correct window:
      // - fetch the real iTerm2 window frame via python
      // - match by nearest desktop window bounds via a small macOS helper
      winNumberToDesktopSourceId = <int, String>{};
      for (final p in panels) {
        final n = p.windowNumber;
        if (n == null || n <= 0) continue;
        if (winNumberToDesktopSourceId.containsKey(n)) continue;
        try {
          final id = await _resolveDesktopWindowForItermWindowNumber(
            n,
            windows,
          );
          if (id != null) winNumberToDesktopSourceId[n] = id;
        } catch (_) {
          // ignore, fall back to null
        }
      }
    }

    final items = <Iterm2PanelItem>[];
    for (final p in panels) {
      final crop = _computeCropRectNormFromSession(p);
      final bestWindowId = (_allowDesktopSources && p.windowNumber != null)
          ? winNumberToDesktopSourceId[p.windowNumber!]
          : null;
      final bestWindow = (bestWindowId == null)
          ? null
          : windows
                .where((w) => w.id == bestWindowId)
                .cast<DesktopCapturerSource?>()
                .first;
      String? stableWindowSourceId;
      if (_allowDesktopSources) {
        if (bestWindowId != null && bestWindowId.isNotEmpty) {
          stableWindowSourceId = bestWindowId;
        } else {
          for (final w in windows) {
            if (_isItermSource(w)) {
              stableWindowSourceId = w.id;
              break;
            }
          }
        }
      }

      items.add(
        Iterm2PanelItem(
          sessionId: p.sessionId,
          title: titleBySession[p.sessionId] ?? p.title,
          detail: p.detail,
          cgWindowId: p.cgWindowId,
          cropRectNorm: crop,
          windowSourceId: stableWindowSourceId,
          windowThumbnail: bestWindow?.thumbnail,
        ),
      );
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
    // Prefer real frame; fall back to layoutFrame when iTerm2 API lacks it.
    final f = s.frame ?? s.layoutFrame;
    if (f == null) return null;

    final fx = f['x'] ?? 0.0;
    final fy = f['y'] ?? 0.0;
    final fw = f['w'] ?? 0.0;
    final fh = f['h'] ?? 0.0;

    Map<String, double>? r = _computeCropFromFrames(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      // For correctness, we always try to compute in the windowFrame space.
      // rawWindowFrame is only used as a *hint* for coordinate mismatch.
      wf: s.windowFrame ?? s.layoutWindowFrame ?? s.rawWindowFrame,
      rawWf: s.rawWindowFrame,
    );

    if (_cropLooksInvalid(r)) {
      r = _computeCropFromFrames(
        fx: fx,
        fy: fy,
        fw: fw,
        fh: fh,
        wf: s.layoutWindowFrame,
        rawWf: s.rawWindowFrame,
        // Avoid using layoutFrame here because it can represent an inferred
        // tiling that does not match real split ratios.
        layout: null,
      );
    }

    return r;
  }

  Map<String, double>? _computeCropFromFrames({
    required double fx,
    required double fy,
    required double fw,
    required double fh,
    required Map<String, double>? wf,
    required Map<String, double>? rawWf,
    Map<String, double>? layout,
  }) {
    if (wf == null) return null;
    final wx = wf['x'] ?? 0.0;
    final wy = wf['y'] ?? 0.0;
    final ww = wf['w'] ?? 0.0;
    final wh = wf['h'] ?? 0.0;
    if (ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0) return null;

    final r = computeIterm2CropRectNormBestEffort(
      fx: layout?['x'] ?? fx,
      fy: layout?['y'] ?? fy,
      fw: layout?['w'] ?? fw,
      fh: layout?['h'] ?? fh,
      wx: wx,
      wy: wy,
      ww: ww,
      wh: wh,
      rawWx: rawWf?['x'],
      rawWy: rawWf?['y'],
      rawWw: rawWf?['w'],
      rawWh: rawWf?['h'],
    );
    return r?.cropRectNorm;
  }

  bool _cropLooksInvalid(Map<String, double>? r) {
    if (r == null) return true;
    final x = r['x'] ?? 0.0;
    final y = r['y'] ?? 0.0;
    final w = r['w'] ?? 0.0;
    final h = r['h'] ?? 0.0;
    if (w <= 0.001 || h <= 0.001) return true;
    if (w > 1.001 || h > 1.001) return true;
    if (x < -0.01 || y < -0.01) return true;
    if (x + w > 1.01 || y + h > 1.01) return true;
    return false;
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
