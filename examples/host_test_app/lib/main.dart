import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:itermremote_observability/observability.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:iterm2_host/streaming/stream_host.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

import 'capture/capture_mode_controller.dart';
import 'capture/capture_source.dart';
import 'capture/capture_source_picker.dart' as picker;
import 'capture/iterm2_panel_thumbnail.dart';
import 'verify/iterm2_panel_encoding_matrix_app.dart';

void main() {
  // Default to the deterministic loopback+crop verification app unless the
  // caller explicitly disables it.
  //
  // Rationale: `HostTestApp` is interactive and depends on manual QA; we want
  // a repeatable evidence-producing run (logs + screenshots) by default.
  final useVerifyMatrix =
      (Platform.environment['ITERMREMOTE_RUN_MATRIX'] ?? '1').trim() == '1';
  if (useVerifyMatrix) {
    runApp(const MaterialApp(home: Iterm2PanelEncodingMatrixApp()));
    return;
  }

  // When running in headless mode we still need a Flutter view hierarchy to
  // drive the capture pipeline, but we keep the window effectively invisible.
  if ((Platform.environment['ITERMREMOTE_HEADLESS'] ?? '').trim() == '1') {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MaterialApp(home: HostTestApp()));
    return;
  }
  runApp(const MaterialApp(home: HostTestApp()));
}

/// Test-only bridge so the example app can run without iTerm2 installed.
///
/// We only need stable session metadata for encoding policy tuning.
// Uses scripts/python/* by default.
class RealITerm2Bridge extends ITerm2Bridge {
  RealITerm2Bridge()
    : super(
        sourcesScriptPath: 'scripts/python/iterm2_sources.py',
        activateScriptPath: 'scripts/python/iterm2_activate_and_crop.py',
        sendTextScriptPath: 'scripts/python/iterm2_send_text.py',
        sessionReaderScriptPath: 'scripts/python/iterm2_session_reader.py',
        windowFramesScriptPath: 'scripts/python/iterm2_window_frames.py',
      );
}

class _NoopITerm2Bridge extends ITerm2Bridge {
  _NoopITerm2Bridge() : super();

  @override
  Future<List<ITerm2SessionInfo>> getSessions() async => const [];

  @override
  Future<Map<String, dynamic>> activateSession(String sessionId) async =>
      <String, dynamic>{};

  @override
  Future<bool> sendText(String sessionId, String text) async => false;

  @override
  Future<String> readSessionBuffer(String sessionId, int maxBytes) async => '';
}

class HostTestApp extends StatefulWidget {
  const HostTestApp({super.key});

  @override
  State<HostTestApp> createState() => _HostTestAppState();
}

class _HostTestAppState extends State<HostTestApp> {
  static const String _envHeadless = 'ITERMREMOTE_HEADLESS';
  static const String _envHeadlessDir = 'ITERMREMOTE_HEADLESS_DIR';
  static const String _appName = 'host_test_app';

  RunLogger? _logger;
  bool _allowDesktopSources = false;
  bool _allowDesktopThumbnails = false;

  // Capture mode
  // Default to iTerm2 panel crop mode; the app will auto-pick a panel on start.
  CaptureMode _captureMode = CaptureMode.iterm2Panel;
  // ignore: unused_field
  String? _selectedScreenSourceId;
  // ignore: unused_field
  String? _selectedWindowSourceId;
  // ignore: unused_field
  String? _selectedIterm2SessionId;
  Map<String, double>? _selectedIterm2CropRectNorm;
  String? _selectedIterm2WindowSourceId;
  bool _autoStarted = false;

  // Debug
  Map<String, dynamic>? _lastCaptureSettings;

  // WebRTC
  RTCPeerConnection? _pc1;
  RTCPeerConnection? _pc2;
  RTCRtpSender? _sender;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  final GlobalKey _localBoundaryKey = GlobalKey();
  final GlobalKey _remoteBoundaryKey = GlobalKey();
  MediaStream? _localStream;

  // StreamHost & Policy
  late StreamHost _streamHost;
  bool _streamHostInitialized = false;
  late ITerm2Bridge _bridge;
  late CaptureModeController _capture;
  EncodingProfile _selectedProfile = EncodingProfiles.textLatency;
  EncodingDecision? _currentDecision;

  // Simulation Controls
  double _simBitrateKbps = 2000;
  double _simPacketLoss = 0.0;
  double _simRttMs = 50;
  double _simJitterMs = 5;

  // Real Stats
  Map<String, dynamic> _realStats = {};
  Timer? _monitorTimer;

  @override
  void initState() {
    super.initState();
    _allowDesktopSources = _flagFromEnvOrDefine('ITERMREMOTE_ENABLE_DESKTOP_SOURCES');
    _allowDesktopThumbnails = _flagFromEnvOrDefine('ITERMREMOTE_ENABLE_DESKTOP_THUMBNAILS');
    _initLogger();
    // Widget tests should not attempt to talk to iTerm2 or start timers.
    final isWidgetTest = Platform.environment.containsKey('FLUTTER_TEST');

    _bridge = isWidgetTest ? _NoopITerm2Bridge() : RealITerm2Bridge();
    _capture = CaptureModeController(
      iterm2Bridge: _bridge,
      allowDesktopSources: _allowDesktopSources,
    );
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    if (!isWidgetTest) {
      _initStreamHost();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _autoStartIterm2PanelIfPossible(),
      );
    }
  }

  Future<void> _initLogger() async {
    try {
      _logger = await RunLogger.create(appName: _appName);
      _logger?.log('app_start');
      _logger?.logJson('env', Map<String, dynamic>.from(Platform.environment));
      _logger?.logJson('desktop_sources_flags', {
        'allowDesktopSources': _allowDesktopSources,
        'allowDesktopThumbnails': _allowDesktopThumbnails,
      });
    } catch (_) {
      // best-effort only
    }
  }

  Future<void> _autoStartIterm2PanelIfPossible() async {
    if (_autoStarted) return;
    _autoStarted = true;
    if (!mounted) return;
    if (_captureMode != CaptureMode.iterm2Panel) return;

    try {
      final panels = await _capture.listIterm2Panels();
      if (panels.isEmpty) return;

      // Prefer stable titles when available.
      Iterm2PanelItem picked = panels.first;
      for (final t in const ['1.1.1', '1.1.8']) {
        final m = panels.where((p) => p.title == t).toList();
        if (m.isNotEmpty) {
          picked = m.first;
          break;
        }
      }

      // Activate session to fetch accurate frame + rawWindowFrame.
      final meta = await _bridge.activateSession(picked.sessionId);
      _logger?.logJson(
        'iterm2_activate_meta',
        meta.map((k, v) => MapEntry(k, v)),
      );
      _logger?.writeJson('iterm2_activate_meta', {
        'sessionId': picked.sessionId,
        'meta': meta,
      });
      final f = meta['frame'];
      final wf = meta['windowFrame'];
      final rawWf = meta['rawWindowFrame'];

      if (f is Map && wf is Map) {
        final frame = f.map((k, v) => MapEntry(k.toString(), v));
        final wframe = wf.map((k, v) => MapEntry(k.toString(), v));
        final fx = (frame['x'] as num?)?.toDouble() ?? 0.0;
        final fy = (frame['y'] as num?)?.toDouble() ?? 0.0;
        final fw = (frame['w'] as num?)?.toDouble() ?? 0.0;
        final fh = (frame['h'] as num?)?.toDouble() ?? 0.0;
        final wx = (wframe['x'] as num?)?.toDouble() ?? 0.0;
        final wy = (wframe['y'] as num?)?.toDouble() ?? 0.0;
        final ww = (wframe['w'] as num?)?.toDouble() ?? 0.0;
        final wh = (wframe['h'] as num?)?.toDouble() ?? 0.0;

        // Always prefer the best-effort computation based on pane vs window
        // coordinates. rawWindowFrame is not guaranteed to share the same
        // coordinate space as session.frame (and can cause width/height drift).
        _selectedIterm2CropRectNorm = computeIterm2CropRectNormBestEffort(
          fx: fx,
          fy: fy,
          fw: fw,
          fh: fh,
          wx: wx,
          wy: wy,
          ww: ww,
          wh: wh,
          // Provide raw window frame as a hint for y-offset corrections.
          rawWx: (rawWf is Map ? (rawWf['x'] as num?)?.toDouble() : null),
          rawWy: (rawWf is Map ? (rawWf['y'] as num?)?.toDouble() : null),
          rawWw: (rawWf is Map ? (rawWf['w'] as num?)?.toDouble() : null),
          rawWh: (rawWf is Map ? (rawWf['h'] as num?)?.toDouble() : null),
        )?.cropRectNorm;
      }

      _selectedIterm2SessionId = picked.sessionId;
      final metaCgWindowId = (meta['cgWindowId'] is num)
          ? (meta['cgWindowId'] as num).toInt()
          : null;
      final initialCgWindowId = picked.cgWindowId;
      final effectiveCgWindowId = metaCgWindowId ?? initialCgWindowId;
      _selectedIterm2WindowSourceId = effectiveCgWindowId?.toString();
      _selectedWindowSourceId = effectiveCgWindowId?.toString();

      _logger?.logJson('iterm2_panel_pick', {
        'sessionId': picked.sessionId,
        'title': picked.title,
        'windowSourceId': picked.windowSourceId,
        'cgWindowId': picked.cgWindowId,
        'cgWindowIdFromActivate': metaCgWindowId,
        'cgWindowIdEffective': effectiveCgWindowId,
        'cropRectNorm': picked.cropRectNorm,
      });

      // HEADLESS_NATIVE_CAPTURE_HOOK
      if (_isHeadless) {
        await _headlessNativeCaptureEvidence(sessionId: picked.sessionId);
        exit(0);
      }

      // We already started loopback in _initStreamHost(), and _selectAndCapture
      // will consult the latest selected session/crop when restarting.
      // Avoid double-starting the capture pipeline here.
    } catch (e, st) {
      _logger?.logError(e, st);
    }
  }

  Future<void> _logDesktopWindowSourcesSnapshot(String label) async {
    try {
      // IMPORTANT: On macOS 26.x we've observed hard crashes inside native
      // WebRTC/CoreImage when calling desktopCapturer.getSources (even with
      // thumbnailSize=null). Do NOT call it by default.
      if (!_allowDesktopThumbnails) {
        _logger?.writeJson('desktop_sources_$label', {
          'skipped': true,
          'reason': 'disabled_by_default_due_to_macos26_native_crash',
        });
        return;
      }

      final sources = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: ThumbnailSize(240, 135),
      );
      _logger?.writeJson('desktop_sources_$label', {
        'count': sources.length,
        'sources': sources
            .map(
              (s) => {
                'id': s.id,
                'name': s.name,
                'thumb': {
                  'w': s.thumbnailSize.width,
                  'h': s.thumbnailSize.height,
                  // When thumbnailSize is null this should be 0/empty.
                  'bytes': s.thumbnail?.length ?? 0,
                },
              },
            )
            .toList(growable: false),
      });
    } catch (e, st) {
      _logger?.logError(e, st);
    }
  }

  Future<MediaStream> _getDisplayMediaWithRetry(
    Map<String, dynamic> constraints, {
    required String tag,
  }) async {
    _logger?.writeJson('get_display_media_${tag}_constraints', {
      'tag': tag,
      'constraints': constraints,
    });
    Object? lastErr;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        _logger?.log('getDisplayMedia attempt=$attempt tag=$tag');
        final stream = await navigator.mediaDevices.getDisplayMedia(
          constraints,
        );
        _logger?.log('getDisplayMedia ok tag=$tag');
        return stream;
      } catch (e, st) {
        lastErr = e;
        _logger?.log('getDisplayMedia failed attempt=$attempt tag=$tag err=$e');
        _logger?.log(st.toString());
        // Avoid desktopCapturer.getSources on macOS 26.x (native hard crash).
        await _logDesktopWindowSourcesSnapshot('${tag}_attempt$attempt');
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    throw StateError('getDisplayMedia failed after retries: $lastErr');
  }

  Future<void> _disposeResources() async {
    final pc1 = _pc1;
    final pc2 = _pc2;
    _pc1 = null;
    _pc2 = null;
    _sender = null;
    if (pc1 != null) {
      await pc1.close();
    }
    if (pc2 != null) {
      await pc2.close();
    }
    await _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
  }

  Future<void> _initStreamHost() async {
    _streamHost = StreamHost(iterm2Bridge: _bridge, enableWebRTC: true);
    _streamHostInitialized = true;

    // Keep the UI usable even if iTerm2 scripts are not configured.
    try {
      await _streamHost.initialize(profile: _selectedProfile);
    } catch (e) {
      // ignore: avoid_print
      print('StreamHost init failed: $e');
    }

    // Apply decisions to the loopback sender.
    _streamHost.setDecisionApplier((decision) async {
      setState(() => _currentDecision = decision);
      await _applyDecision(decision);
    });

    await _startLoopbackCall();

    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _updatePolicyAndStats();
    });
  }

  Future<void> _headlessNativeCaptureEvidence({
    required String sessionId,
  }) async {
    // No Flutter UI capture; use macOS screencapture on the iTerm2 CGWindowId.
    try {
      final meta = await _bridge.activateSession(sessionId);
      final cgWid = meta['cgWindowId'];
      final rawWf = meta['rawWindowFrame'];
      final f = meta['frame'];

      if (cgWid is! num || cgWid.toInt() <= 0) return;
      if (rawWf is! Map || f is! Map) return;

      final cgWindowId = cgWid.toInt();
      final rawWy = (rawWf['y'] as num?)?.toDouble() ?? 0.0;
      final frame = f.map((k, v) => MapEntry(k.toString(), v));
      final fx = (frame['x'] as num?)?.toDouble() ?? 0.0;
      final fy = (frame['y'] as num?)?.toDouble() ?? 0.0;
      final fw = (frame['w'] as num?)?.toDouble() ?? 0.0;
      final fh = (frame['h'] as num?)?.toDouble() ?? 0.0;

      final dir = Directory(_headlessOutDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final windowPath = '${dir.path}/iterm2_window_$ts.png';
      final panelPath = '${dir.path}/iterm2_panel_$ts.png';
      final metaPath = '${dir.path}/iterm2_meta_$ts.json';

      // Capture the iTerm2 window.
      final cap = await Process.run('/usr/sbin/screencapture', [
        '-x',
        '-l',
        '$cgWindowId',
        windowPath,
      ]);
      if (cap.exitCode != 0) return;

      // Crop panel region: top = img_h - (y + h) - rawWindowFrame.y
      final pyPath = '/tmp/itermremote_crop_panel.py';
      final py = r'''
import json
from PIL import Image
import sys

window_path, panel_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3]
cgWindowId = int(float(sys.argv[4]))
fx, fy, fw, fh, rawWy = map(float, sys.argv[5:])

img = Image.open(window_path)
img_w, img_h = img.size
left = int(fx)
# Convert from bottom-left-ish to top-left screenshot coords
top = int(img_h - (fy + fh) - rawWy)
right = int(left + fw)
bottom = int(top + fh)

# clamp
left = max(0, min(img_w, left))
right = max(0, min(img_w, right))
top = max(0, min(img_h, top))
bottom = max(0, min(img_h, bottom))

img.crop((left, top, right, bottom)).save(panel_path)

json.dump({
  'cgWindowId': cgWindowId,
  'frame': {'x': fx, 'y': fy, 'w': fw, 'h': fh},
  'rawWy': rawWy,
  'windowImage': {'w': img_w, 'h': img_h},
  'cropBox': [left, top, right, bottom],
}, open(meta_path,'w'))

print('OK', panel_path)
''';
      File(pyPath).writeAsStringSync(py);
      final proc = await Process.run('python3', [
        pyPath,
        windowPath,
        panelPath,
        metaPath,
        '$cgWindowId',
        '$fx',
        '$fy',
        '$fw',
        '$fh',
        '$rawWy',
      ]);
      // ignore: avoid_print
      print(
        'HEADLESS native crop rc=${proc.exitCode} out=${proc.stdout} err=${proc.stderr}',
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _startLoopbackCall() async {
    _logger?.log('loopback_start');
    MediaStream stream;
    try {
      stream = await _selectAndCapture();
    } catch (e, st) {
      _logger?.logError(e, st);
      rethrow;
    }
    _localStream = stream;
    _localRenderer.srcObject = stream;

    // AUTO_HEADLESS_AFTER_STREAM
    if (_isHeadless) {
      // Allow at least one frame to render, then snapshot and exit.
      unawaited(_headlessCaptureEvidence().then((_) => exit(0)));
    }

    try {
      final track = stream.getVideoTracks().first;
      _lastCaptureSettings = track.getSettings();
      _logger?.logJson(
        'capture_settings',
        Map<String, dynamic>.from(_lastCaptureSettings ?? {}),
      );
    } catch (_) {
      _lastCaptureSettings = null;
    }

    // 2-PC loopback
    _pc1 = await createPeerConnection({});
    _pc2 = await createPeerConnection({});

    _pc1!.onIceCandidate = (c) => _pc2!.addCandidate(c);
    _pc2!.onIceCandidate = (c) => _pc1!.addCandidate(c);

    _pc2!.onAddStream = (s) {
      _remoteRenderer.srcObject = s;
    };

    final track = stream.getVideoTracks().first;
    _sender = await _pc1!.addTrack(track, stream);

    final offer = await _pc1!.createOffer();
    await _pc1!.setLocalDescription(offer);
    await _pc2!.setRemoteDescription(offer);

    final answer = await _pc2!.createAnswer();
    await _pc2!.setLocalDescription(answer);
    await _pc1!.setRemoteDescription(answer);

    _logger?.log('loopback_ready');
  }

  Future<void> _updatePolicyAndStats() async {
    if (_sender == null) return;

    final context = EncodingContext(
      rttMs: _simRttMs.toInt(),
      packetLossRate: _simPacketLoss / 100.0,
      availableBitrateKbps: _simBitrateKbps.toInt(),
      jitterMs: _simJitterMs.toInt(),
      targetFps: 30,
    );

    await _streamHost.updateEncodingPolicy(context);

    final stats = await _sender!.getStats();
    final report = <String, dynamic>{};

    for (final s in stats) {
      if (s.type == 'outbound-rtp' && s.values['kind'] == 'video') {
        report['frameHeight'] = s.values['frameHeight'];
        report['frameWidth'] = s.values['frameWidth'];
        report['framesPerSecond'] = s.values['framesPerSecond'];
        report['bytesSent'] = s.values['bytesSent'];
      }
    }

    setState(() {
      _realStats = report;
    });
    _logger?.logJson('webrtc_outbound_stats', report);
  }

  Future<void> _applyDecision(EncodingDecision decision) async {
    if (_sender == null) return;

    final params = _sender!.parameters;
    final encodings = params.encodings;
    if (encodings == null || encodings.isEmpty) {
      params.encodings = [RTCRtpEncoding()];
    }
    final encoding = params.encodings!.first;

    if (decision.maxBitrateKbps != null) {
      encoding.maxBitrate = decision.maxBitrateKbps! * 1000;
    }
    if (decision.maxFramerate != null) {
      encoding.maxFramerate = decision.maxFramerate!;
    }
    if (decision.scaleResolutionDownBy != null) {
      encoding.scaleResolutionDownBy = decision.scaleResolutionDownBy!;
    }

    if (decision.degradationPreference != null) {
      params.degradationPreference = degradationPreferenceforString(
        decision.degradationPreference,
      );
    }

    await _sender!.setParameters(params);
  }

  @override
  void dispose() {
    _logger?.log('app_dispose');
    _monitorTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    if (_streamHostInitialized) {
      _streamHost.dispose();
    }
    _pc1?.close();
    _pc2?.close();
    _localStream?.dispose();
    super.dispose();
  }

  bool get _isHeadless {
    final v = (Platform.environment[_envHeadless] ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  bool _envFlag(String key) {
    final v = (Platform.environment[key] ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  bool _flagFromEnvOrDefine(String key) {
    final v = _readDefineOrEnv(key);
    return v == '1' || v == 'true' || v == 'yes';
  }

  String _readDefineOrEnv(String key) {
    // Prefer `--dart-define` so toggles work even when launched from Finder.
    final defined = switch (key) {
      'ITERMREMOTE_ENABLE_DESKTOP_SOURCES' =>
        const String.fromEnvironment('ITERMREMOTE_ENABLE_DESKTOP_SOURCES'),
      'ITERMREMOTE_ENABLE_DESKTOP_THUMBNAILS' =>
        const String.fromEnvironment('ITERMREMOTE_ENABLE_DESKTOP_THUMBNAILS'),
      _ => ''
    };
    final raw = defined.trim().isNotEmpty
        ? defined.trim()
        : (Platform.environment[key] ?? '').trim();
    return raw.toLowerCase();
  }

  String get _headlessOutDir {
    final d = (Platform.environment[_envHeadlessDir] ?? '').trim();
    return d.isEmpty ? '/tmp/itermremote_headless' : d;
  }

  Future<void> _saveRendererPng({required bool remote}) async {
    try {
      final boundaryKey = remote ? _remoteBoundaryKey : _localBoundaryKey;
      final ctx = boundaryKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;

      final pngBytes = bytes.buffer.asUint8List();
      if (_logger != null) {
        _logger!.writePng(
          remote ? 'remote_preview' : 'local_preview',
          pngBytes,
        );
      }

      final dir = Directory(_headlessOutDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final name = remote ? 'remote' : 'local';
      final f = File('${dir.path}/${name}_$ts.png');
      await f.writeAsBytes(pngBytes);
      // ignore: avoid_print
      print('HEADLESS saved ' + f.path);
    } catch (_) {}
  }

  Future<void> _headlessCaptureEvidence() async {
    // Wait a moment for frames to paint.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _saveRendererPng(remote: false);
    await _saveRendererPng(remote: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isHeadless) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 1280,
          height: 720,
          child: Row(
            children: [
              Expanded(
                child: RepaintBoundary(
                  key: _localBoundaryKey,
                  child: RTCVideoView(_localRenderer),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  key: _remoteBoundaryKey,
                  child: RTCVideoView(_remoteRenderer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('iTerm2 Host Encoding Test')),
      body: Row(
        children: [
          SizedBox(
            width: 350,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCaptureModeToggle(),
                const Divider(),
                _buildProfileSelector(),
                const Divider(),
                _buildSimulationControls(),
                const Divider(),
                _buildDecisionView(),
                const Divider(),
                _buildRealStatsView(),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildPreviewHeader(
                              title: 'Local Capture (Source)',
                              onFocus: () =>
                                  setState(() => _focusRemote = false),
                              focused: !_focusRemote,
                            ),
                            Expanded(
                              flex: _focusRemote ? 1 : 5,
                              child: RepaintBoundary(
                                key: _localBoundaryKey,
                                child: RTCVideoView(_localRenderer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            _buildPreviewHeader(
                              title: 'Encoded & Loopback (Result)',
                              onFocus: () =>
                                  setState(() => _focusRemote = true),
                              focused: _focusRemote,
                            ),
                            Expanded(
                              flex: _focusRemote ? 5 : 1,
                              child: RepaintBoundary(
                                key: _remoteBoundaryKey,
                                child: RTCVideoView(_remoteRenderer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _focusRemote = true;

  Widget _buildPreviewHeader({
    required String title,
    required VoidCallback onFocus,
    required bool focused,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: focused ? Colors.black12 : Colors.transparent,
      child: Row(
        children: [
          Expanded(child: Text(title)),
          TextButton(
            onPressed: onFocus,
            child: Text(focused ? 'Focused' : 'Focus'),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureModeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Capture Mode',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        DropdownButton<CaptureMode>(
          value: _captureMode,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: CaptureMode.desktop,
              child: Text('Desktop (Screen)'),
            ),
            DropdownMenuItem(value: CaptureMode.window, child: Text('Window')),
            DropdownMenuItem(
              value: CaptureMode.iterm2Panel,
              child: Text('iTerm2 Panel (Crop)'),
            ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _captureMode = v);
            _monitorTimer?.cancel();
            await _restartCapture(clearSelection: true);
          },
        ),
        OutlinedButton(
          onPressed: () async {
            _monitorTimer?.cancel();
            await _restartCapture(clearSelection: true);
          },
          child: const Text('Re-select Capture Source'),
        ),
        if (_captureMode == CaptureMode.iterm2Panel &&
            _selectedIterm2SessionId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Selected panel: $_selectedIterm2SessionId',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (_lastCaptureSettings != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Capture settings: ${_lastCaptureSettings!['width']}x${_lastCaptureSettings!['height']} fps=${_lastCaptureSettings!['frameRate']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Future<void> _restartCapture({required bool clearSelection}) async {
    await _pc1?.close();
    await _pc2?.close();
    await _localStream?.dispose();
    _pc1 = null;
    _pc2 = null;
    _localStream = null;
    _sender = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    if (clearSelection) {
      _selectedScreenSourceId = null;
      _selectedWindowSourceId = null;
      _selectedIterm2SessionId = null;
      _selectedIterm2CropRectNorm = null;
      _selectedIterm2WindowSourceId = null;
      _lastCaptureSettings = null;
    }

    await _startLoopbackCall();
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _updatePolicyAndStats();
    });
  }

  Future<MediaStream> _selectAndCapture() async {
    _logger?.logJson('select_and_capture_state', {
      'captureMode': _captureMode.toString(),
      'selectedIterm2SessionId': _selectedIterm2SessionId,
      'selectedIterm2WindowSourceId': _selectedIterm2WindowSourceId,
      'selectedIterm2CropRectNorm': _selectedIterm2CropRectNorm,
      'allowDesktopSources': _allowDesktopSources,
      'allowDesktopThumbnails': _allowDesktopThumbnails,
    });
    switch (_captureMode) {
      case CaptureMode.desktop:
        if (!_allowDesktopSources) {
          throw StateError('desktop sources disabled by env');
        }
        final thumb = ThumbnailSize(240, 135);
        final screens = await _capture.listScreens(thumbnailSize: thumb);
        if (screens.isEmpty) throw StateError('no screens');
        final picked = await picker.CaptureSourcePicker.show(
          context,
          title: 'Select a Screen to Capture',
          items: screens
              .map(
                (s) => picker.PickItem(
                  id: s.id,
                  title: s.title,
                  subtitle: 'screenId=${s.id}',
                  thumbnailBytes: s.thumbnail,
                ),
              )
              .toList(growable: false),
        );
        if (picked == null) {
          throw StateError('no screen selected');
        }
        _selectedScreenSourceId = picked.id;
        final constraints = <String, dynamic>{
          'video': {
            'deviceId': {'exact': picked.id},
            'mandatory': {'frameRate': 30, 'hasCursor': false},
          },
          'audio': false,
        };
        return _getDisplayMediaWithRetry(constraints, tag: 'desktop');

      case CaptureMode.window:
        if (!_allowDesktopSources) {
          throw StateError('window sources disabled by env');
        }
        final thumb = ThumbnailSize(240, 135);
        final windows = await _capture.listWindows();
        if (windows.isEmpty) throw StateError('no windows');
        final picked = await picker.CaptureSourcePicker.show(
          context,
          title: 'Select a Window to Capture',
          items: windows
              .map(
                (w) => picker.PickItem(
                  id: w.id,
                  title: w.title,
                  subtitle: 'windowId=${w.id}',
                  thumbnailBytes: w.thumbnail,
                ),
              )
              .toList(growable: false),
        );
        if (picked == null) {
          throw StateError('no window selected');
        }
        _selectedWindowSourceId = picked.id;
        final constraints = <String, dynamic>{
          'video': {
            'deviceId': {'exact': picked.id},
            'mandatory': {'frameRate': 30, 'hasCursor': false},
          },
          'audio': false,
        };
        return _getDisplayMediaWithRetry(constraints, tag: 'window');

      case CaptureMode.iterm2Panel:
        _logger?.log('select_and_capture_iterm2_panel_enter');
        // Must use real iTerm2 python API.
        final panels = await _capture.listIterm2Panels();
        if (panels.isEmpty) {
          throw StateError('no iTerm2 panels found (is iTerm2 running?)');
        }
        _logger?.log('select_and_capture_iterm2_panel_panels=${panels.length}');
        Iterm2PanelItem? picked;
        if (_selectedIterm2SessionId != null) {
          for (final p in panels) {
            if (p.sessionId == _selectedIterm2SessionId) {
              picked = p;
              break;
            }
          }
          picked ??= panels.first;
          _logger?.log('iterm2_panel_auto_pick');
        } else {
          picked = await showModalBottomSheet<Iterm2PanelItem>(
            context: context,
            isScrollControlled: true,
            builder: (_) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text(
                        'Select iTerm2 Panel',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: panels.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = panels[i];
                          return ListTile(
                            leading: Iterm2PanelThumbnail(
                              thumbnailBytes: p.windowThumbnail,
                              cropRectNorm: p.cropRectNorm,
                            ),
                            title: Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              p.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }
        if (picked == null) {
          throw StateError('no panel selected');
        }

        _logger?.logJson('iterm2_panel_selected', {
          'sessionId': picked.sessionId,
          'title': picked.title,
          'cgWindowId': picked.cgWindowId,
          'windowSourceId': picked.windowSourceId,
          'cropRectNorm': picked.cropRectNorm,
        });

        // Activate session for better correctness (bring to foreground).
        if (!mounted) throw StateError('context not mounted');
        _logger?.log('iterm2_activate_for_capture');
        final meta = await _bridge.activateSession(picked.sessionId);

        // Use cgWindowId from activate (authoritative), fallback to list result.
        final metaCgWindowId = (meta['cgWindowId'] is num)
            ? (meta['cgWindowId'] as num).toInt()
            : null;
        final cgWindowId = metaCgWindowId ?? picked.cgWindowId;
        if (cgWindowId == null || cgWindowId <= 0) {
          throw StateError('missing cgWindowId for panel');
        }
        _selectedIterm2WindowSourceId = cgWindowId.toString();
        _logger?.log('iterm2_capture_cgWindowId=$cgWindowId');

        final f = meta['frame'];
        final wf = meta['windowFrame'];
        final rawWf = meta['rawWindowFrame'];

        _logger?.writeJson('iterm2_activate_meta', {
          'sessionId': picked.sessionId,
          'meta': meta,
        });
        if (f is Map && wf is Map) {
          final frame = f.map((k, v) => MapEntry(k.toString(), v));
          final wframe = wf.map((k, v) => MapEntry(k.toString(), v));
          final fx = (frame['x'] as num?)?.toDouble() ?? 0.0;
          final fy = (frame['y'] as num?)?.toDouble() ?? 0.0;
          final fw = (frame['w'] as num?)?.toDouble() ?? 0.0;
          final fh = (frame['h'] as num?)?.toDouble() ?? 0.0;
          final wx = (wframe['x'] as num?)?.toDouble() ?? 0.0;
          final wy = (wframe['y'] as num?)?.toDouble() ?? 0.0;
          final ww = (wframe['w'] as num?)?.toDouble() ?? 0.0;
          final wh = (wframe['h'] as num?)?.toDouble() ?? 0.0;
          // Use shared best-effort computation. It tries multiple coordinate
          // hypotheses and prefers low-overflow candidates.
          final rawWx = rawWf is Map ? (rawWf['x'] as num?)?.toDouble() : null;
          final rawWy = rawWf is Map ? (rawWf['y'] as num?)?.toDouble() : null;
          final rawWw = rawWf is Map ? (rawWf['w'] as num?)?.toDouble() : null;
          final rawWh = rawWf is Map ? (rawWf['h'] as num?)?.toDouble() : null;
          _selectedIterm2CropRectNorm = computeIterm2CropRectNormBestEffort(
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
          )?.cropRectNorm;
        }
        _selectedIterm2SessionId = picked.sessionId;

        // Single-step UX: user chooses panel only.
        // Prefer DesktopMediaList sourceId when available, otherwise fall back
        // to cgWindowId (SCK path in our patched plugin).
        final sourceId = (picked.windowSourceId != null && picked.windowSourceId!.trim().isNotEmpty)
            ? picked.windowSourceId!
            : cgWindowId.toString();
        _selectedWindowSourceId = sourceId;

        // Fix: allow iTerm2 cropRect to have enough resolution to land on the
        // right panel (especially with split panes). Without this, macOS will
        // often scale down the captured window and the normalized crop will
        // point at the wrong quadrant.
        final minW = (_selectedIterm2CropRectNorm != null)
            ? (1.0 / (_selectedIterm2CropRectNorm!['w'] ?? 1.0) * 576).ceil()
            : 576;
        final minH = (_selectedIterm2CropRectNorm != null)
            ? (1.0 / (_selectedIterm2CropRectNorm!['h'] ?? 1.0) * 768).ceil()
            : 768;

        // IMPORTANT: On macOS, flutter_webrtc's desktop capture expects a
        // DesktopMediaList sourceId (e.g. "window:123"), not a raw cgWindowId.
        // So the primary path must use picked.windowSourceId.
        final cgConstraints = <String, dynamic>{
          'video': {
            'deviceId': {'exact': sourceId},
            'mandatory': {
              'frameRate': 30,
              'hasCursor': false,
              'minWidth': minW,
              'minHeight': minH,
              if (_selectedIterm2CropRectNorm != null)
                'cropRect': _selectedIterm2CropRectNorm,
            },
          },
          'audio': false,
        };
        _logger?.writeJson('iterm2_capture_constraints', {
          'sourceId': sourceId,
          'cgWindowId': cgWindowId,
          'minWidth': minW,
          'minHeight': minH,
          'cropRect': _selectedIterm2CropRectNorm,
          'constraints': cgConstraints,
        });
        _logger?.log('iterm2_get_display_media_begin');
        try {
          return await _getDisplayMediaWithRetry(cgConstraints, tag: 'iterm2_panel');
        } catch (e, st) {
          _logger?.logError(e, st);
        }

        // Fallback: use cgWindowId (when plugin supports it). In our patched
        // plugin this is wired via ScreenCaptureKit.
        if (cgWindowId > 0) {
          final fallbackSourceId = cgWindowId.toString();
          final fallbackConstraints = <String, dynamic>{
            'video': {
              'deviceId': {'exact': fallbackSourceId},
              'mandatory': {
                'frameRate': 30,
                'hasCursor': false,
                'minWidth': minW,
                'minHeight': minH,
                if (_selectedIterm2CropRectNorm != null)
                  'cropRect': _selectedIterm2CropRectNorm,
              },
            },
            'audio': false,
          };
          _logger?.writeJson('iterm2_capture_constraints_fallback', {
            'sourceId': fallbackSourceId,
            'minWidth': minW,
            'minHeight': minH,
            'cropRect': _selectedIterm2CropRectNorm,
            'constraints': fallbackConstraints,
          });
          _logger?.log('iterm2_get_display_media_fallback_begin');
          return _getDisplayMediaWithRetry(
            fallbackConstraints,
            tag: 'iterm2_panel_fallback',
          );
        }

        throw StateError('getDisplayMedia failed and no fallback available');
    }
  }

  Widget _buildProfileSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Encoding Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        DropdownButton<String>(
          value: _selectedProfile.id,
          isExpanded: true,
          items: EncodingProfiles.all.map((p) {
            return DropdownMenuItem(value: p.id, child: Text(p.name));
          }).toList(),
          onChanged: (v) async {
            if (v == null) return;
            final profile = EncodingProfiles.all.firstWhere((p) => p.id == v);
            setState(() => _selectedProfile = profile);

            _monitorTimer?.cancel();
            _streamHost.dispose();
            await _initStreamHost();
          },
        ),
        Text(
          _selectedProfile.description,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSimulationControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Network Simulation (Inputs)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildSlider(
          'Bandwidth (kbps)',
          _simBitrateKbps,
          100,
          4000,
          (v) => _simBitrateKbps = v,
        ),
        _buildSlider(
          'Packet Loss (%)',
          _simPacketLoss,
          0,
          20,
          (v) => _simPacketLoss = v,
        ),
        _buildSlider('RTT (ms)', _simRttMs, 10, 1000, (v) => _simRttMs = v),
        _buildSlider(
          'Jitter (ms)',
          _simJitterMs,
          0,
          100,
          (v) => _simJitterMs = v,
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double val,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(val.toStringAsFixed(0))],
        ),
        Slider(
          value: val,
          min: min,
          max: max,
          divisions: 100,
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ],
    );
  }

  Widget _buildDecisionView() {
    if (_currentDecision == null) return const Text('No decision yet');
    final d = _currentDecision!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Policy Engine Decision',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Text('Max Bitrate: ${d.maxBitrateKbps} kbps'),
        Text('Max FPS: ${d.maxFramerate}'),
        Text('Scale Down: ${d.scaleResolutionDownBy}x'),
        Text('Degradation: ${d.degradationPreference}'),
        Text('Content Hint: ${d.contentHint}'),
      ],
    );
  }

  Widget _buildRealStatsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Real-Time Sender Stats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (_realStats.isEmpty) const Text('Waiting for stats...'),
        for (final entry in _realStats.entries)
          Text('${entry.key}: ${entry.value}'),
      ],
    );
  }
}
