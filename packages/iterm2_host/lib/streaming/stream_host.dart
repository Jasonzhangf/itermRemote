import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
// WebRTC integration is intentionally omitted from the core host package
// to keep it Dart VM testable. UI/examples own actual WebRTC wiring.

import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import '../iterm2/iterm2_bridge.dart';
import '../utils/value_notifier.dart';
import '../webrtc/encoding_policy/encoding_policy.dart';

/// Streaming host for iTerm2 remote streaming.
///
/// In Phase-2, this is a skeleton with state management and placeholder methods.
/// Future phases will add WebRTC capture, data channel handling, and video streaming.
class StreamHost {
  // WebRTC fields intentionally omitted in core package.

  final ITerm2Bridge iterm2Bridge;
  final ValueNotifier<StreamState> state = ValueNotifier(StreamState.idle);
  final ValueNotifier<List<ITerm2SessionInfo>> sessions =
      ValueNotifier<List<ITerm2SessionInfo>>(const []);

  /// When disabled, WebRTC plugin calls are skipped so unit tests can run on VM.
  final bool enableWebRTC;

  // Reserved for future: WebRTC factory injection.

  StreamSettings? _currentSettings;

  late EncodingPolicyManager encodingPolicyManager;

  StreamHost({
    required this.iterm2Bridge,
    this.enableWebRTC = true,
    EncodingProfile? initialProfile,
  }) {
    encodingPolicyManager = EncodingPolicyManager(
      engine: EncodingPolicyEngine(
          profile: initialProfile ?? EncodingProfiles.textLatency),
      applier: (_) async {
        // No-op in Phase-2/3. Future phases will apply to RTCRtpSender.
      },
    );
  }

  /// Initialize the stream host and load iTerm2 sessions.
  Future<void> initialize({EncodingProfile? profile}) async {
    state.value = StreamState.initializing;
    try {
      if (profile != null) {
        encodingPolicyManager = EncodingPolicyManager(
          engine: EncodingPolicyEngine(profile: profile),
          applier: encodingPolicyManager.applier,
        );
      }
      await _setupPeerConnection();
      await _refreshSessions();
      state.value = StreamState.ready;
    } catch (e) {
      state.value = StreamState.error;
      throw StreamHostException('Failed to initialize: $e');
    }
  }

  /// Set a custom decision applier (for testing or advanced use cases).
  void setDecisionApplier(EncodingDecisionApplier applier) {
    encodingPolicyManager = EncodingPolicyManager(
      engine: encodingPolicyManager.engine,
      applier: applier,
    );
  }

  /// Update encoding parameters based on latest network stats.
  ///
  /// In Phase-2/3 this only computes and stores the decision.
  Future<EncodingDecision> updateEncodingPolicy(EncodingContext context) {
    return encodingPolicyManager.update(context);
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
    state.dispose();
  }

  Future<void> _setupPeerConnection() async {
    if (!enableWebRTC) {
      return;
    }
    // TODO: Initialize RTCPeerConnection in UI layer.
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
