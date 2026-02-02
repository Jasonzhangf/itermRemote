import 'package:meta/meta.dart';

/// Recovery policy for signaling/server connectivity.
///
/// Goals:
/// - Avoid reconnect spam (throttle).
/// - Use backoff schedule on repeated failures.
/// - Prefer local cached IPv6 direct negotiation when applicable.
/// - Stop recovery once the session is healthy.
///
/// Reference implementation inspiration:
/// - cloudplayplus_stone/lib/services/app_lifecycle_reconnect_service.dart

enum RecoveryTrigger {
  appResumed,
  transportDisconnected,
  negotiationFailed,
}

enum SessionHealth {
  healthy,
  unhealthy,
  unknown,
}

enum TransportState {
  connected,
  connecting,
  disconnected,
}

@immutable
class RecoveryConfig {
  /// Avoid reconnect spam on quick app switches.
  final int minKickIntervalMs;

  /// Consider recovery only when backgrounded long enough.
  final int minBackgroundForKickMs;

  /// Backoff schedule after failed attempts. Required by spec: 5s -> 9s -> 26s.
  final List<int> backoffSeconds;

  /// Time budget per attempt to wait for transport readiness.
  final Duration perAttemptReadyGrace;

  /// Time budget per attempt to wait for session health after restart.
  final Duration perAttemptSessionGrace;

  const RecoveryConfig({
    this.minKickIntervalMs = 1800,
    this.minBackgroundForKickMs = 8000,
    this.backoffSeconds = const <int>[5, 9, 26],
    this.perAttemptReadyGrace = const Duration(seconds: 4),
    this.perAttemptSessionGrace = const Duration(seconds: 5),
  });
}

@immutable
class RecoveryState {
  final int flowToken;
  final bool flowActive;
  final int attempt;
  final int lastKickAtMs;
  final int lastPausedAtMs;

  const RecoveryState({
    required this.flowToken,
    required this.flowActive,
    required this.attempt,
    required this.lastKickAtMs,
    required this.lastPausedAtMs,
  });

  const RecoveryState.initial()
      : flowToken = 0,
        flowActive = false,
        attempt = 0,
        lastKickAtMs = 0,
        lastPausedAtMs = 0;

  RecoveryState copyWith({
    int? flowToken,
    bool? flowActive,
    int? attempt,
    int? lastKickAtMs,
    int? lastPausedAtMs,
  }) {
    return RecoveryState(
      flowToken: flowToken ?? this.flowToken,
      flowActive: flowActive ?? this.flowActive,
      attempt: attempt ?? this.attempt,
      lastKickAtMs: lastKickAtMs ?? this.lastKickAtMs,
      lastPausedAtMs: lastPausedAtMs ?? this.lastPausedAtMs,
    );
  }
}

enum RecoveryActionType {
  none,
  reconnectTransport,
  restartSession,
  tryDirectIpv6,
  scheduleRetry,
  stop,
}

@immutable
class RecoveryAction {
  final RecoveryActionType type;
  final Duration? delay;
  final String reason;
  final RecoveryState nextState;

  const RecoveryAction({
    required this.type,
    required this.reason,
    required this.nextState,
    this.delay,
  });
}

class ServerRecoveryPolicy {
  /// Decide what to do when app resumes / transport disconnects / negotiation fails.
  ///
  /// This function is deterministic and side-effect free.
  static RecoveryAction onTrigger({
    required RecoveryState previous,
    required RecoveryTrigger trigger,
    required int nowMs,
    required TransportState transport,
    required SessionHealth sessionHealth,
    required bool hasCachedIpv6,
    RecoveryConfig cfg = const RecoveryConfig(),
  }) {
    // If session is healthy, stop any active flow.
    if (sessionHealth == SessionHealth.healthy) {
      return RecoveryAction(
        type: RecoveryActionType.stop,
        reason: 'session-healthy',
        nextState: previous.copyWith(flowActive: false),
      );
    }

    // Trigger gating for app resume.
    if (trigger == RecoveryTrigger.appResumed) {
      final pausedForMs = previous.lastPausedAtMs > 0
          ? (nowMs - previous.lastPausedAtMs)
          : 0;
      if (pausedForMs < cfg.minBackgroundForKickMs) {
        return RecoveryAction(
          type: RecoveryActionType.none,
          reason: 'resume-too-short',
          nextState: previous,
        );
      }
    }

    // Throttle kicks.
    if (nowMs - previous.lastKickAtMs < cfg.minKickIntervalMs) {
      return RecoveryAction(
        type: RecoveryActionType.none,
        reason: 'throttled',
        nextState: previous,
      );
    }

    // Start or continue a recovery flow.
    final token = previous.flowToken + 1;
    var state = previous.copyWith(
      flowActive: true,
      flowToken: token,
      attempt: previous.attempt + 1,
      lastKickAtMs: nowMs,
    );

    // First attempt: prefer direct IPv6 negotiation when cache exists.
    if (state.attempt == 1 && hasCachedIpv6) {
      return RecoveryAction(
        type: RecoveryActionType.tryDirectIpv6,
        reason: 'prefer-cached-ipv6',
        nextState: state,
      );
    }

    // If transport is disconnected, reconnect it first.
    if (transport == TransportState.disconnected) {
      return RecoveryAction(
        type: RecoveryActionType.reconnectTransport,
        reason: 'transport-disconnected',
        nextState: state,
      );
    }

    // If transport is ready but session unhealthy, restart session.
    if (transport == TransportState.connected &&
        sessionHealth == SessionHealth.unhealthy) {
      return RecoveryAction(
        type: RecoveryActionType.restartSession,
        reason: 'session-unhealthy',
        nextState: state,
      );
    }

    // Otherwise schedule retry with backoff.
    final backoffIdx = (state.attempt - 1).clamp(0, cfg.backoffSeconds.length - 1);
    final delay = Duration(seconds: cfg.backoffSeconds[backoffIdx]);
    return RecoveryAction(
      type: RecoveryActionType.scheduleRetry,
      delay: delay,
      reason: 'backoff',
      nextState: state,
    );
  }

  /// Record app pause timestamp.
  static RecoveryState onPaused({required RecoveryState previous, required int nowMs}) {
    return previous.copyWith(lastPausedAtMs: nowMs, flowActive: false);
  }
}
