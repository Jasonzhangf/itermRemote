import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudplayplus_core/iterm2/iterm2_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';

void main() {
  runApp(const MaterialApp(home: Iterm2PanelEncodingMatrixApp()));
}

class Iterm2PanelEncodingMatrixApp extends StatefulWidget {
  const Iterm2PanelEncodingMatrixApp({super.key});

  @override
  State<Iterm2PanelEncodingMatrixApp> createState() =>
      _Iterm2PanelEncodingMatrixAppState();
}

class _Iterm2PanelEncodingMatrixAppState
    extends State<Iterm2PanelEncodingMatrixApp> {
  final ITerm2Bridge _bridge = ITerm2Bridge();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final GlobalKey _remotePreviewKey = GlobalKey();

  RTCPeerConnection? _pc1;
  RTCPeerConnection? _pc2;
  RTCRtpSender? _sender;
  MediaStream? _localStream;

  final List<String> _logs = <String>[];
  Map<String, double>? _lastCropRectNorm;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_localRenderer.initialize());
    unawaited(_remoteRenderer.initialize());
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _log(String s) {
    // ignore: avoid_print
    print('[matrix] $s');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, s);
    });
  }

  Future<void> _run() async {
    if (!Platform.isMacOS) {
      _log('skip: only supported on macOS');
      exitCode = 0;
      exit(exitCode);
    }

    final title = (Platform.environment['ITERM2_PANEL_TITLE'] ?? '1.1.1')
        .trim();
    final fpsList = _parseIntList(
      Platform.environment['FPS_LIST'] ?? '60,30,15',
    );
    final bitrateList = _parseIntList(
      Platform.environment['BITRATE_KBPS_LIST'] ?? '2000,1000,500,250',
    );
    final outDirPath =
        (Platform.environment['ITERMREMOTE_MATRIX_OUT_DIR'] ??
                'build/verify_matrix')
            .trim();

    final outDir = Directory(outDirPath);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final runDir = Directory('${outDir.path}/$ts');
      runDir.createSync(recursive: true);

    _log('panel title=$title fps=$fpsList bitrate=$bitrateList out=$runDir');

    try {
      final session = await _findSessionByTitle(title);
      if (session == null) {
        _log('FAIL: session not found for title=$title');
        exitCode = 2;
        exit(exitCode);
      }

      final meta = await _bridge.activateSession(session.sessionId);
      final cropRect = _computeCropRectFromMeta(meta);
      _lastCropRectNorm = cropRect;
      final sourceId = await _resolveWindowSourceId(meta);

      // Ask the SCK capturer to dump its first captured frame for evidence.
      // This avoids screencapture's coordinate quirks.
      final firstFramePath = '${runDir.path}/window_capture.png';

      await _captureWindowOverlay(meta, cropRect, runDir);

      if (sourceId == null) {
        _log(
          'FAIL: could not resolve iTerm2 window sourceId via DesktopCapturer. '
          'This usually means flutter_webrtc cannot enumerate window sources '
          '(permission or plugin crash).',
        );
      }

      if (sourceId == null || sourceId.isEmpty) {
        _log('FAIL: could not resolve window source id');
        exitCode = 2;
        exit(exitCode);
      }

      _log('using sourceId=$sourceId crop=$cropRect');

      final constraints = <String, dynamic>{
        'audio': false,
        'video': {
          'deviceId': {'exact': sourceId},
          'mandatory': {
            'frameRate': 60,
            'minWidth': (meta['frame']['w'] as num).toInt(),
            'minHeight': (meta['frame']['h'] as num).toInt(),
            'hasCursor': false,
            'itermremoteFirstFramePath': firstFramePath,
            if (cropRect != null) 'cropRect': cropRect,
          },
        },
      };

      _localStream = await navigator.mediaDevices.getDisplayMedia(constraints);
      _localRenderer.srcObject = _localStream;

      await _setupLoopback();
      await _waitForInboundFrames(minFrames: 10);

      final results = <Map<String, dynamic>>[];
      for (final fps in fpsList) {
        for (final bitrate in bitrateList) {
          final res = await _runCase(
            fps: fps,
            bitrateKbps: bitrate,
            outDir: runDir,
          );
          results.add(res);
        }
      }

      final summaryPath = '${runDir.path}/matrix_summary.json';
      File(summaryPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'panelTitle': title,
          'windowOverlay': '${runDir.path}/window_with_crop.png',
          'windowCapture': '${runDir.path}/window_capture.png',
          'fpsList': fpsList,
          'bitrateKbpsList': bitrateList,
          'results': results,
        }),
      );

      _log('OK: matrix finished -> $summaryPath');
      _done = true;
      exitCode = 0;
      exit(exitCode);
    } catch (e, st) {
      _log('ERROR: $e');
      _log(st.toString());
      exitCode = 3;
      exit(exitCode);
    } finally {
      await _cleanup();
    }
  }

  Future<void> _setupLoopback() async {
    _pc1 = await createPeerConnection({});
    _pc2 = await createPeerConnection({});

    _pc1!.onIceCandidate = (c) => _pc2!.addCandidate(c);
    _pc2!.onIceCandidate = (c) => _pc1!.addCandidate(c);

    _pc2!.onAddStream = (s) {
      _remoteRenderer.srcObject = s;
    };

    final track = _localStream!.getVideoTracks().first;
    _sender = await _pc1!.addTrack(track, _localStream!);

    final offer = await _pc1!.createOffer();
    await _pc1!.setLocalDescription(offer);
    await _pc2!.setRemoteDescription(offer);

    final answer = await _pc2!.createAnswer();
    await _pc2!.setLocalDescription(answer);
    await _pc1!.setRemoteDescription(answer);
  }

  Future<Map<String, dynamic>> _runCase({
    required int fps,
    required int bitrateKbps,
    required Directory outDir,
  }) async {
    _log('CASE fps=$fps bitrate=$bitrateKbps');

    final params = _sender!.parameters;
    if (params.encodings == null || params.encodings!.isEmpty) {
      params.encodings = [RTCRtpEncoding()];
    }
    final encoding = params.encodings!.first;
    encoding.maxBitrate = bitrateKbps * 1000;
    encoding.maxFramerate = fps;
    encoding.scaleResolutionDownBy = 1.0;
    await _sender!.setParameters(params);

    await Future<void>.delayed(const Duration(seconds: 2));
    await _waitForInboundFrames(minFrames: 8);

    final outbound = await _getOutboundStats();
    final inbound = await _getInboundStats();

    final tag = 'fps${fps}_kbps${bitrateKbps}';
    final previewPath = await _screenshotRemotePreviewTo(
      outDir,
      tag,
      _lastCropRectNorm,
    );

    final record = <String, dynamic>{
      'fps': fps,
      'bitrateKbps': bitrateKbps,
      'preview': previewPath,
      'track': '',
      'outbound': outbound,
      'inbound': inbound,
    };

    final jsonPath = '${outDir.path}/$tag.json';
    File(
      jsonPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));

    _log('CASE done: $jsonPath');
    return record;
  }

  Future<void> _waitForInboundFrames({required int minFrames}) async {
    final pc = _pc2!;
    final endAt = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(endAt)) {
      final stats = await pc.getStats();
      for (final r in stats) {
        if (r.type != 'inbound-rtp') continue;
        final v = Map<String, dynamic>.from(r.values);
        if (v['kind'] != 'video' && v['mediaType'] != 'video') continue;
        final frames = (v['framesDecoded'] is num)
            ? (v['framesDecoded'] as num).toInt()
            : 0;
        if (frames >= minFrames) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<Map<String, dynamic>> _getOutboundStats() async {
    final stats = await _sender!.getStats();
    for (final s in stats) {
      if (s.type == 'outbound-rtp' && s.values['kind'] == 'video') {
        return Map<String, dynamic>.from(s.values);
      }
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _getInboundStats() async {
    final stats = await _pc2!.getStats();
    for (final s in stats) {
      if (s.type == 'inbound-rtp' && s.values['kind'] == 'video') {
        return Map<String, dynamic>.from(s.values);
      }
    }
    return <String, dynamic>{};
  }

  Future<String> _screenshotRemotePreviewTo(
    Directory outDir,
    String tag,
    Map<String, double>? cropRectNorm,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final boundary =
        _remotePreviewKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return '';
    
    final decodedW = _remoteRenderer.videoWidth;
    final decodedH = _remoteRenderer.videoHeight;

    // Make the saved preview match the decoded video resolution.
    // boundary.toImage() captures the widget size (which may be constrained by layout),
    // so we need to adjust pixelRatio to scale it up to decoded frame size.
    if (decodedW == 0 || decodedH == 0) {
      _log('skip screenshot: decoder not ready');
      return '';
    }
    
    // Get the actual widget size in physical pixels
    final box = boundary.paintBounds;
    final widgetPhysicalW = box.width * ui.window.devicePixelRatio;
    final widgetPhysicalH = box.height * ui.window.devicePixelRatio;
    
    if (widgetPhysicalW == 0 || widgetPhysicalH == 0) {
      _log('skip screenshot: widget size zero');
      return '';
    }
    
    // Calculate pixelRatio to scale widget to decoded frame size
    final pixelRatioW = decodedW / widgetPhysicalW;
    final pixelRatioH = decodedH / widgetPhysicalH;
    
    // Use the larger ratio to ensure the output covers the full frame
    // (this may cause slight stretching if aspect ratios differ)
    final pixelRatio = pixelRatioW > pixelRatioH ? pixelRatioW : pixelRatioH;
    
    _log('screenshot: decoded=${decodedW}x${decodedH} widgetPhysical=${widgetPhysicalW.toInt()}x${widgetPhysicalH.toInt()} pixelRatio=${pixelRatio.toStringAsFixed(3)}');

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    
    _log('screenshot: captured image size=${image.width}x${image.height}');

    // Resize the captured image to match decoded frame size exactly.
    // boundary.toImage() output size is driven by widget layout; we want
    // deterministic evidence aligned with the real decoded frame size.
    ui.Image finalSourceImage = image;
    if (image.width != decodedW || image.height != decodedH) {
      final recorder2 = ui.PictureRecorder();
      final canvas2 = Canvas(recorder2);
      canvas2.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, decodedW.toDouble(), decodedH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture2 = recorder2.endRecording();
      finalSourceImage = await picture2.toImage(decodedW, decodedH);
      _log('screenshot: resized to ${decodedW}x${decodedH}');
    }

    // Draw red border around cropped content
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(finalSourceImage, Offset.zero, Paint());
    final paint = Paint()
      ..color = const Color(0xFFFF0000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        finalSourceImage.width.toDouble(),
        finalSourceImage.height.toDouble(),
      ),
      paint,
    );
    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(
      finalSourceImage.width,
      finalSourceImage.height,
    );

    final bytes = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return '';
    final path = '${outDir.path}/preview_$tag.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    return path;
  }

  Future<_Session?> _findSessionByTitle(String title) async {
    final sessions = await _bridge.getSessions();
    for (final s in sessions) {
      if (s.title == title) {
        return _Session(sessionId: s.sessionId, title: s.title);
      }
    }
    return null;
  }

  Future<String?> _resolveWindowSourceId(Map<String, dynamic> meta) async {
    // Use cgWindowId from iTerm2 API for exact window match
    final wantCgWindowId = meta['cgWindowId'];

    final sources = await desktopCapturer.getSources(
      types: [SourceType.Window],
      thumbnailSize: ThumbnailSize(1, 1),
    );

    if (wantCgWindowId != null) {
      final want = wantCgWindowId.toString();
      for (final s in sources) {
        if (s.id == want) return s.id;
      }
    }

    for (final s in sources) {
      final name = s.name.toLowerCase();
      if (name.contains('iterm')) return s.id;
    }

    return null;
  }

  Map<String, double>? _computeCropRectFromMeta(Map<String, dynamic> meta) {
    final f = meta['frame'];
    final wf = meta['windowFrame'];
    final rawWf = meta['rawWindowFrame'];
    if (f is! Map || wf is! Map) return null;

    final fx = _toDouble(f['x']);
    final fy = _toDouble(f['y']);
    final fw = _toDouble(f['w']);
    final fh = _toDouble(f['h']);
    // NOTE: scripts/python/iterm2_sources.py currently sets windowFrame == rawWindowFrame.
    // Treat windowFrame as the window's absolute origin (not content origin).
    final wx = _toDouble(wf['x']);
    final wy = _toDouble(wf['y']);
    final ww = _toDouble(wf['w']);
    final wh = _toDouble(wf['h']);

    final rawWx = rawWf is Map ? _toDouble(rawWf['x']) : null;
    final rawWy = rawWf is Map ? _toDouble(rawWf['y']) : null;
    final rawWw = rawWf is Map ? _toDouble(rawWf['w']) : null;
    final rawWh = rawWf is Map ? _toDouble(rawWf['h']) : null;

    // Hard rule: compute crop in the *captured image* coordinate system.
    // We capture the window using Quartz (screencapture -l), which returns a
    // bitmap in pixel units (raw).
    // So, if rawWindowFrame is available, convert pane/window coords into that
    // raw coordinate space by using a scale derived from raw vs window sizes.
    // This keeps the math deterministic across different window sizes.

    Map<String, double>? crop;
    if (rawWw != null && rawWh != null && rawWw > 0 && rawWh > 0) {
      // If windowFrame == rawWindowFrame (absolute window coords), the pane frame
      // is already in the same coordinate space as the captured image.
      final leftPx = fx;
      final topPx = fy;
      final wPx = fw;
      final hPx = fh;

      double clamp01(double v) => v.clamp(0.0, 1.0);
      final x = clamp01(leftPx / rawWw);
      final y = clamp01(topPx / rawWh);
      final wNorm = clamp01(wPx / rawWw);
      final hNorm = clamp01(hPx / rawWh);
      crop = {
        'x': x,
        'y': y,
        'w': wNorm,
        'h': hNorm,
      };
      _log('crop direct raw: crop=$crop');
    } else {
      // Fallback: use best-effort heuristics when raw window bounds are missing.
      final best = computeIterm2CropRectNormBestEffort(
        fx: fx,
        fy: fy,
        fw: fw,
        fh: fh,
        wx: wx,
        wy: wy,
        ww: ww,
        wh: wh,
        rawWx: rawWx,
        rawWy: rawWy,
        rawWw: rawWw,
        rawWh: rawWh,
      );
      if (best != null) {
        _log('crop best tag=${best.tag} penalty=${best.penalty.toStringAsFixed(3)}');
      }
      crop = best?.cropRectNorm;
    }

    return crop;
  }

  Future<void> _captureWindowOverlay(
    Map<String, dynamic> meta,
    Map<String, double>? cropRectNorm,
    Directory runDir,
  ) async {
    try {
      final cgWindowId = meta['cgWindowId'];
      if (cgWindowId is! num || cgWindowId.toInt() <= 0) {
        _log('skip window overlay: missing cgWindowId');
        return;
      }
      if (cropRectNorm == null) {
        _log('skip window overlay: missing cropRect');
        return;
      }

      final windowPath = '${runDir.path}/window_capture.png';
      final overlayPath = '${runDir.path}/window_with_crop.png';
      // IMPORTANT: The most reliable evidence is the actual captured frame
      // from ScreenCaptureKit / flutter-webrtc. screencapture -l has different
      // sizing rules (shadows/titlebar) and breaks coordinate consistency.
      //
      // For now, keep window_capture.png optional. The overlay still works with
      // a fallback capture, but dn2.2 will replace this with SCK first-frame.
      if (!File(windowPath).existsSync()) {
        final cap = await Process.run('/usr/sbin/screencapture', [
          '-x',
          '-l',
          '${cgWindowId.toInt()}',
          windowPath,
        ]);
        if (cap.exitCode != 0) {
          _log('window capture failed: ${cap.stderr}');
          return;
        }
      }

      final pyPath = '/tmp/itermremote_draw_crop.py';
      // Read actual image size first, then compute scaled crop box
      const py = r"""
import json
import sys

try:
    from PIL import Image, ImageDraw
except Exception as e:
    print('PIL not available:', e)
    sys.exit(2)

window_path, overlay_path, crop_json = sys.argv[1], sys.argv[2], sys.argv[3]
crop = json.loads(crop_json)

img = Image.open(window_path)
w, h = img.size

# Crop is in layoutWindowFrame coordinate space (3836x1977)
# Image is screencapture output (different size, e.g., 3908x2114)
# We need to scale the crop to the actual image size
lww = float(crop.get('lww', 3836.0))
lwh = float(crop.get('lwh', 1977.0))
fx = float(crop.get('x', 0.0))
fy = float(crop.get('y', 0.0))
fw = float(crop.get('w', 0.0))
fh = float(crop.get('h', 0.0))

scale_x = w / lww
scale_y = h / lwh

left = int(round(fx * scale_x))
top = int(round(fy * scale_y))
right = int(round((fx + fw) * scale_x))
bottom = int(round((fy + fh) * scale_y))

# Clamp to image bounds
left = max(0, min(left, w - 1))
top = max(0, min(top, h - 1))
right = max(left + 1, min(right, w))
bottom = max(top + 1, min(bottom, h))

draw = ImageDraw.Draw(img)
for i in range(4):
    draw.rectangle([left - i, top - i, right + i, bottom + i], outline=(255, 0, 0))

img.save(overlay_path)
print(f'OK {overlay_path} box=({left},{top})-({right},{bottom}) scale=({scale_x:.3f},{scale_y:.3f})')
""";
      // NOTE: For overlay, use layoutFrame which has real absolute pixel positions.
      final lf = meta['layoutFrame'];
      final lwf = meta['layoutWindowFrame'];
      Map<String, double> overlayCrop = {};
      if (lf is Map && lwf is Map) {
        final fx = _toDouble(lf['x']);
        final fy = _toDouble(lf['y']);
        final fw = _toDouble(lf['w']);
        final fh = _toDouble(lf['h']);
        final lww = _toDouble(lwf['w']);
        final lwh = _toDouble(lwf['h']);
        if (lww > 0 && lwh > 0) {
          // CRITICAL: iTerm2 Frame uses bottom-left origin (0,0), but images use top-left.
          // We need to flip y coordinate: y_top_left = windowHeight - y_bottom_left - height
          final yTopLeft = lwh - fy - fh;
          
          // Pass absolute pixel coordinates in layoutWindowFrame space + dimensions
          overlayCrop = {
            'lww': lww,
            'lwh': lwh,
            'x': fx,
            'y': yTopLeft,
            'w': fw,
            'h': fh,
          };
          _log('overlay crop: iTerm2 bottom-left(${fx},${fy}) -> image top-left(${fx},${yTopLeft}) size(${fw}x${fh})');
        } else {
          overlayCrop = cropRectNorm;
        }
      } else {
        overlayCrop = cropRectNorm;
      }

     File(pyPath).writeAsStringSync(py);
      final cropJsonStr = jsonEncode(overlayCrop);
      _log('overlay crop JSON: $cropJsonStr');
      final proc = await Process.run('python3', [
        pyPath,
        windowPath,
        overlayPath,
        cropJsonStr,
      ]);
      if (proc.exitCode != 0) {
        _log('window overlay failed: ${proc.stderr}');
      } else {
        _log('window overlay saved: $overlayPath, stdout: ${proc.stdout}');
      }
    } catch (e) {
      _log('window overlay error: $e');
    }
  }

  double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  List<int> _parseIntList(String raw) {
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .where((v) => v > 0)
        .toList(growable: false);
  }

  Future<void> _cleanup() async {
    try {
      final s = _localStream;
      if (s != null) {
        for (final t in s.getTracks()) {
          t.stop();
        }
        await s.dispose();
      }
    } catch (_) {}

    try {
      await _sender?.replaceTrack(null);
    } catch (_) {}

    try {
      await _pc1?.close();
      await _pc2?.close();
    } catch (_) {}

    _localStream = null;
    _pc1 = null;
    _pc2 = null;
    _sender = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Scaffold(body: Center(child: Text('Done')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('iTerm2 Panel Encoding Matrix')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(child: RTCVideoView(_localRenderer)),
                Expanded(
                  child: RepaintBoundary(
                    key: _remotePreviewKey,
                    child: RTCVideoView(_remoteRenderer),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _logs.length,
              itemBuilder: (context, i) =>
                  Text(_logs[i], style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Session {
  final String sessionId;
  final String title;

  const _Session({required this.sessionId, required this.title});
}
