import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import '../iterm2/iterm2_bridge.dart';

/// Streaming host for iTerm2 remote streaming.
///
/// In Phase-2, this is a skeleton with state management and placeholder methods.
/// Future phases will add WebRTC capture, data channel handling, and video streaming.
class StreamHost {
  static RTCPeerConnection? _peerConnection;
  static RTCDataChannel? _dataChannel;
  static MediaStream? _currentStream;
  MediaStreamTrack? _videoSender;

  final ITerm2Bridge iterm2Bridge;
  final ValueNotifier<StreamState> state = ValueNotifier(StreamState.idle);
  final ValueNotifier<List<ITerm2SessionInfo>> sessions =
      ValueNotifier<List<ITerm2SessionInfo>>(const []);

  /// When disabled, WebRTC plugin calls are skipped so unit tests can run on VM.
  final bool enableWebRTC;

  /// Injectable factory to create peer connections (useful for tests).
  final Future<RTCPeerConnection> Function(Map<String, dynamic> configuration)?
      peerConnectionFactory;

  StreamSettings? _currentSettings;

  StreamHost({
    required this.iterm2Bridge,
    this.enableWebRTC = true,
    this.peerConnectionFactory,
  });

  /// Initialize the stream host and load iTerm2 sessions.
  Future<void> initialize() async {
    state.value = StreamState.initializing;
    try {
      await _setupPeerConnection();
      await _refreshSessions();
      state.value = StreamState.ready;
    } catch (e) {
      state.value = StreamState.error;
      throw StreamHostException('Failed to initialize: $e');
    }
  }

  /// Start a streaming session with the given settings.
  Future<void> startStream(StreamSettings settings) async {
    _currentSettings = settings;
    state.value = StreamState.connecting;

    // TODO: Implement actual streaming in future phases.
    // - For video mode: WebRTC capture + video track
    // - For chat mode: data channel only
    // - For iTerm2 panel: crop rect + activate session
    throw UnimplementedError('startStream not yet implemented');
  }

  /// Stop the current streaming session.
  Future<void> stopStream() async {
    state.value = StreamState.stopping;

    // TODO: Stop video track, close peer connection
    _currentStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
    _videoSender = null;
    _currentStream = null;

    state.value = StreamState.idle;
  }

  /// Switch to a different capture target (screen/window/iTerm2 panel).
  Future<void> switchCaptureTarget({
    required CaptureTargetType type,
    String? windowId,
    String? iterm2SessionId,
  }) async {
    // TODO: Implement capture target switching.
    // - For iTerm2: activate session via Python API, compute crop rect
    // - For window: switch desktop source
    throw UnimplementedError('switchCaptureTarget not yet implemented');
  }

  /// Refresh the list of iTerm2 sessions.
  Future<void> refreshSessions() async {
    state.value = StreamState.refreshing;
    try {
      await _refreshSessions();
      state.value = StreamState.ready;
    } catch (e) {
      state.value = StreamState.error;
      rethrow;
    }
  }

  /// Release resources.
  void dispose() {
    _peerConnection?.close();
    _dataChannel?.close();
    _currentStream?.dispose();
    _videoSender = null;
    _peerConnection = null;
    _dataChannel = null;
    _currentStream = null;
    state.dispose();
  }

  Future<void> _setupPeerConnection() async {
    if (!enableWebRTC) {
      return;
    }
    // TODO: Initialize RTCPeerConnection with ICE servers from settings.
    // For now, create a minimal PC for testing.
    final factory = peerConnectionFactory ?? createPeerConnection;
    _peerConnection = await factory({});
  }

  Future<void> _refreshSessions() async {
    final sessionList = await iterm2Bridge.getSessions();
    sessions.value = sessionList;
  }
}

/// Streaming host states.
enum StreamState {
  idle,
  initializing,
  ready,
  refreshing,
  connecting,
  streaming,
  stopping,
  error,
}

/// Exception thrown by StreamHost operations.
class StreamHostException implements Exception {
  final String message;
  StreamHostException(this.message);

  @override
  String toString() => 'StreamHostException: $message';
}
