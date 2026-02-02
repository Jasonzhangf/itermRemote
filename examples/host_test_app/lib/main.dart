import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:iterm2_host/streaming/stream_host.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

import 'capture/capture_mode_controller.dart';
import 'capture/capture_source.dart';
import 'capture/capture_source_picker.dart' as picker;
import 'capture/iterm2_panel_thumbnail.dart';

void main() {
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

class HostTestApp extends StatefulWidget {
  const HostTestApp({super.key});

  @override
  State<HostTestApp> createState() => _HostTestAppState();
}

class _HostTestAppState extends State<HostTestApp> {
  static const String _envHeadless = 'ITERMREMOTE_HEADLESS';
  static const String _envHeadlessDir = 'ITERMREMOTE_HEADLESS_DIR';

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
    _bridge = RealITerm2Bridge();
    _capture = CaptureModeController(iterm2Bridge: _bridge);
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    _initStreamHost();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoStartIterm2PanelIfPossible());
  }

  Future<void> _autoStartIterm2PanelIfPossible() async {
    if (_autoStarted) return;
    _autoStarted = true;
    if (!mounted) return;
    if (_captureMode != CaptureMode.iterm2Panel) return;

    try {
      final panels = await _capture.listIterm2Panels(
        thumbnailSize: ThumbnailSize(240, 135),
      );
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

        if (rawWf is Map) {
          final rawWw = (rawWf['w'] as num?)?.toDouble() ?? 1.0;
          final rawWh = (rawWf['h'] as num?)?.toDouble() ?? 1.0;
          _selectedIterm2CropRectNorm = <String, double>{
            'x': fx / rawWw,
            'y': fy / rawWh,
            'w': fw / rawWw,
            'h': fh / rawWh,
          };
        } else {
          _selectedIterm2CropRectNorm = computeIterm2CropRectNormBestEffort(
            fx: fx,
            fy: fy,
            fw: fw,
            fh: fh,
            wx: wx,
            wy: wy,
            ww: ww,
            wh: wh,
          )?.cropRectNorm;
        }
      }

      _selectedIterm2SessionId = picked.sessionId;
      _selectedIterm2WindowSourceId = picked.windowSourceId;
      _selectedWindowSourceId = picked.windowSourceId;

      // HEADLESS_NATIVE_CAPTURE_HOOK
      if (_isHeadless) {
        await _headlessNativeCaptureEvidence(sessionId: picked.sessionId);
        exit(0);
      }


      // Restart loopback with selected panel.
      // Recreate loopback state cleanly.
      await _disposeResources();
      await _startLoopbackCall();
    } catch (_) {
      // Best-effort only.
    }
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
    _streamHost = StreamHost(
      iterm2Bridge: _bridge,
      enableWebRTC: true,
    );

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

  
  Future<void> _headlessNativeCaptureEvidence({required String sessionId}) async {
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
      final cap = await Process.run('/usr/sbin/screencapture', ['-x', '-l', '$cgWindowId', windowPath]);
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
      final proc = await Process.run(
        'python3',
        [pyPath, windowPath, panelPath, metaPath, '$cgWindowId', '$fx', '$fy', '$fw', '$fh', '$rawWy'],
      );
      // ignore: avoid_print
      print('HEADLESS native crop rc=${proc.exitCode} out=${proc.stdout} err=${proc.stderr}');
    } catch (_) {
      // ignore
    }
  }

Future<void> _startLoopbackCall() async {
    final stream = await _selectAndCapture();
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
      params.degradationPreference =
          degradationPreferenceforString(decision.degradationPreference);
    }

    await _sender!.setParameters(params);
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _streamHost.dispose();
    _pc1?.close();
    _pc2?.close();
    _localStream?.dispose();
    super.dispose();
  }


  bool get _isHeadless {
    final v = (Platform.environment[_envHeadless] ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
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

      final dir = Directory(_headlessOutDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final name = remote ? 'remote' : 'local';
      final f = File('${dir.path}/${name}_$ts.png');
      await f.writeAsBytes(bytes.buffer.asUint8List());
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
                              onFocus: () => setState(() => _focusRemote = false),
                              focused: !_focusRemote,
                            ),
                            Expanded(
                              flex: _focusRemote ? 1 : 5,
                              child: RepaintBoundary(key: _localBoundaryKey, child: RTCVideoView(_localRenderer)),
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
                              onFocus: () => setState(() => _focusRemote = true),
                              focused: _focusRemote,
                            ),
                            Expanded(
                              flex: _focusRemote ? 5 : 1,
                              child: RepaintBoundary(key: _remoteBoundaryKey, child: RTCVideoView(_remoteRenderer)),
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
        const Text('Capture Mode', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<CaptureMode>(
          value: _captureMode,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: CaptureMode.desktop, child: Text('Desktop (Screen)')),
            DropdownMenuItem(value: CaptureMode.window, child: Text('Window')),
            DropdownMenuItem(value: CaptureMode.iterm2Panel, child: Text('iTerm2 Panel (Crop)')),
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
        if (_captureMode == CaptureMode.iterm2Panel && _selectedIterm2SessionId != null)
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
    final thumb = ThumbnailSize(240, 135);
    switch (_captureMode) {
      case CaptureMode.desktop:
        final screens = await _capture.listScreens(thumbnailSize: thumb);
        if (screens.isEmpty) throw StateError('no screens');
        final picked = await picker.CaptureSourcePicker.show(
          context,
          title: 'Select a Screen to Capture',
          items: screens
              .map((s) => picker.PickItem(
                    id: s.id,
                    title: s.title,
                    subtitle: 'screenId=${s.id}',
                    thumbnailBytes: s.thumbnail,
                  ))
              .toList(growable: false),
        );
        if (picked == null) {
          throw StateError('no screen selected');
        }
        _selectedScreenSourceId = picked.id;
        final constraints = <String, dynamic>{
          'video': {
            'deviceId': {'exact': picked.id},
            'mandatory': {
              'frameRate': 30,
              'hasCursor': false,
            },
          },
          'audio': false,
        };
        return navigator.mediaDevices.getDisplayMedia(constraints);

      case CaptureMode.window:
        final windows = await _capture.listWindows(thumbnailSize: thumb);
        if (windows.isEmpty) throw StateError('no windows');
        final picked = await picker.CaptureSourcePicker.show(
          context,
          title: 'Select a Window to Capture',
          items: windows
              .map((w) => picker.PickItem(
                    id: w.id,
                    title: w.title,
                    subtitle: 'windowId=${w.id}',
                    thumbnailBytes: w.thumbnail,
                  ))
              .toList(growable: false),
        );
        if (picked == null) {
          throw StateError('no window selected');
        }
        _selectedWindowSourceId = picked.id;
        final constraints = <String, dynamic>{
          'video': {
            'deviceId': {'exact': picked.id},
            'mandatory': {
              'frameRate': 30,
              'hasCursor': false,
            },
          },
          'audio': false,
        };
        return navigator.mediaDevices.getDisplayMedia(constraints);

      case CaptureMode.iterm2Panel:
        // Must use real iTerm2 python API.
        final panels = await _capture.listIterm2Panels(thumbnailSize: thumb);
        if (panels.isEmpty) {
          throw StateError('no iTerm2 panels found (is iTerm2 running?)');
        }
        final picked = await showModalBottomSheet<Iterm2PanelItem>(
          context: context,
          isScrollControlled: true,
          builder: (_) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Select iTerm2 Panel',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
                          title: Text(p.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
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
        if (picked == null) {
          throw StateError('no panel selected');
        }

        // Best-effort: pick an iTerm2 window source automatically based on the
        // panel geometry + desktopCapturer thumbnails.
        final bestWindowSourceId = picked.windowSourceId;
        if (bestWindowSourceId == null || bestWindowSourceId.isEmpty) {
          throw StateError('failed to map panel to a window source');
        }
        _selectedIterm2WindowSourceId = bestWindowSourceId;

        // Activate session for better correctness (bring to foreground).
        if (!mounted) throw StateError('context not mounted');
        final meta = await _bridge.activateSession(picked.sessionId);
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
          // ScreenCaptureKit crops in *captured-frame* coordinates. For direct
          // window capture (mandatory.windowId), the captured frame is in the
          // raw window's pixel space, so normalize using rawWindowFrame.
          if (rawWf is Map) {
            final rawWw = (rawWf['w'] as num?)?.toDouble() ?? 1.0;
            final rawWh = (rawWf['h'] as num?)?.toDouble() ?? 1.0;
            _selectedIterm2CropRectNorm = <String, double>{
              'x': fx / rawWw,
              'y': fy / rawWh,
              'w': fw / rawWw,
              'h': fh / rawWh,
            };
          } else {
            _selectedIterm2CropRectNorm =
                computeIterm2CropRectNormBestEffort(
                      fx: fx,
                      fy: fy,
                      fw: fw,
                      fh: fh,
                      wx: wx,
                      wy: wy,
                      ww: ww,
                      wh: wh,
                    )
                        ?.cropRectNorm;
          }
        }
        _selectedIterm2SessionId = picked.sessionId;

        // Single-step UX: user chooses panel only.
        final sourceId = _selectedIterm2WindowSourceId!;
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

        final constraints = <String, dynamic>{
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
        return navigator.mediaDevices.getDisplayMedia(constraints);
    }
  }

  Widget _buildProfileSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Encoding Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: _selectedProfile.id,
          isExpanded: true,
          items: EncodingProfiles.all.map((p) {
            return DropdownMenuItem(
              value: p.id,
              child: Text(p.name),
            );
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
        Text(_selectedProfile.description,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSimulationControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Network Simulation (Inputs)', style: TextStyle(fontWeight: FontWeight.bold)),
        _buildSlider('Bandwidth (kbps)', _simBitrateKbps, 100, 4000, (v) => _simBitrateKbps = v),
        _buildSlider('Packet Loss (%)', _simPacketLoss, 0, 20, (v) => _simPacketLoss = v),
        _buildSlider('RTT (ms)', _simRttMs, 10, 1000, (v) => _simRttMs = v),
        _buildSlider('Jitter (ms)', _simJitterMs, 0, 100, (v) => _simJitterMs = v),
      ],
    );
  }

  Widget _buildSlider(
      String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(val.toStringAsFixed(0)),
          ],
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
        const Text('Policy Engine Decision', style: TextStyle(fontWeight: FontWeight.bold)),
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
        const Text('Real-Time Sender Stats', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_realStats.isEmpty) const Text('Waiting for stats...'),
        for (final entry in _realStats.entries) Text('${entry.key}: ${entry.value}'),
      ],
    );
  }
}
