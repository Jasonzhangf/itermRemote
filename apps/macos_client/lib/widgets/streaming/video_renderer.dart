import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/connection_service.dart';
import 'gesture_controller.dart';

class VideoRenderer extends StatefulWidget {
  const VideoRenderer({super.key, this.hostId});
  final String? hostId;

  @override
  State<VideoRenderer> createState() => _VideoRendererState();
}

class _VideoRendererState extends State<VideoRenderer> with GestureControllerMixin {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final GlobalKey _containerKey = GlobalKey();
  bool _initialized = false;
  bool _hasStream = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    _initialized = true;
    ConnectionService.instance.remoteStream.listen((stream) {
      if (mounted && stream != null) {
        setState(() {
          _renderer.srcObject = stream;
          _hasStream = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  RenderBox? get _renderBox {
    final context = _containerKey.currentContext;
    if (context == null) return null;
    return context.findRenderObject() as RenderBox?;
  }

  @override
  void onSingleTap(double xPercent, double yPercent) {
    debugPrint('Single tap at (\$xPercent, \$yPercent)');
  }

  @override
  void onDoubleTap(double xPercent, double yPercent) {
    debugPrint('Double tap at (\$xPercent, \$yPercent)');
  }

  @override
  void onPanStart(double xPercent, double yPercent) {
    debugPrint('Pan start at (\$xPercent, \$yPercent)');
  }

  @override
  void onPanUpdate(double deltaX, double deltaY) {
    debugPrint('Pan update: (\$deltaX, \$deltaY)');
  }

  @override
  void onPanEnd() {
    debugPrint('Pan end');
  }

  @override
  void onTwoFingerScroll(double deltaX, double deltaY) {
    debugPrint('Two-finger scroll: (\$deltaX, \$deltaY)');
  }

  @override
  void onPinchZoom(double scaleChange) {
    final newScale = (videoScale * scaleChange).clamp(1.0, 5.0);
    setTransform(newScale, videoOffset);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || !_hasStream) {
      return Container(
        color: const Color(0xFF09090B),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text('Waiting for stream...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            key: _containerKey,
            onPointerDown: (event) => handlePointerDown(event, _renderBox),
            onPointerMove: (event) => handlePointerMove(event, _renderBox),
            onPointerUp: (event) => handlePointerUp(event, _renderBox),
            child: Transform(
              transform: Matrix4.identity()
                ..translate(videoOffset.dx, videoOffset.dy)
                ..scale(videoScale),
              alignment: Alignment.center,
              child: RTCVideoView(
                _renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: _FpsOverlay(),
        ),
      ],
    );
  }
}

class _FpsOverlay extends StatefulWidget {
  @override
  State<_FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<_FpsOverlay> {
  int _fps = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: 500), (_) {
      setState(() => _fps = ConnectionService.instance.currentFps);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'FPS: \$_fps',
        style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
