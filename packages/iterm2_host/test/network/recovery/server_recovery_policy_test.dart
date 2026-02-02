import 'package:test/test.dart';
import 'package:iterm2_host/network/recovery/server_recovery_policy.dart';

void main() {
  group('ServerRecoveryPolicy', () {
    test('stop when session becomes healthy', () {
      final a = ServerRecoveryPolicy.onTrigger(
        previous: const RecoveryState.initial(),
        trigger: RecoveryTrigger.transportDisconnected,
        nowMs: 10000,
        transport: TransportState.disconnected,
        sessionHealth: SessionHealth.healthy,
        hasCachedIpv6: true,
      );
      expect(a.type, RecoveryActionType.stop);
    });

    test('prefer cached IPv6 on first attempt', () {
      final a = ServerRecoveryPolicy.onTrigger(
        previous: const RecoveryState.initial(),
        trigger: RecoveryTrigger.transportDisconnected,
        nowMs: 10000,
        transport: TransportState.disconnected,
        sessionHealth: SessionHealth.unhealthy,
        hasCachedIpv6: true,
      );
      expect(a.type, RecoveryActionType.tryDirectIpv6);
      expect(a.nextState.attempt, 1);
    });

    test('reconnect transport when disconnected and no cached IPv6', () {
      final a = ServerRecoveryPolicy.onTrigger(
        previous: const RecoveryState.initial(),
        trigger: RecoveryTrigger.transportDisconnected,
        nowMs: 10000,
        transport: TransportState.disconnected,
        sessionHealth: SessionHealth.unhealthy,
        hasCachedIpv6: false,
      );
      expect(a.type, RecoveryActionType.reconnectTransport);
    });

    test('restart session when transport connected but session unhealthy', () {
      final a = ServerRecoveryPolicy.onTrigger(
        previous: const RecoveryState.initial(),
        trigger: RecoveryTrigger.negotiationFailed,
        nowMs: 10000,
        transport: TransportState.connected,
        sessionHealth: SessionHealth.unhealthy,
        hasCachedIpv6: false,
      );
      expect(a.type, RecoveryActionType.restartSession);
    });

    test('throttle repeated kicks', () {
      final prev = const RecoveryState.initial().copyWith(lastKickAtMs: 10000);
      final a = ServerRecoveryPolicy.onTrigger(
        previous: prev,
        trigger: RecoveryTrigger.transportDisconnected,
        nowMs: 10100,
        transport: TransportState.disconnected,
        sessionHealth: SessionHealth.unhealthy,
        hasCachedIpv6: false,
        cfg: const RecoveryConfig(minKickIntervalMs: 500),
      );
      expect(a.type, RecoveryActionType.none);
      expect(a.reason, 'throttled');
    });

    test('app resume is gated by background duration', () {
      final paused = ServerRecoveryPolicy.onPaused(
        previous: const RecoveryState.initial(),
        nowMs: 0,
      );
      final a = ServerRecoveryPolicy.onTrigger(
        previous: paused,
        trigger: RecoveryTrigger.appResumed,
        nowMs: 1000,
        transport: TransportState.disconnected,
        sessionHealth: SessionHealth.unhealthy,
        hasCachedIpv6: false,
        cfg: const RecoveryConfig(minBackgroundForKickMs: 8000),
      );
      expect(a.type, RecoveryActionType.none);
      expect(a.reason, 'resume-too-short');
    });

    test('backoff schedule caps at last entry', () {
      var state = const RecoveryState.initial().copyWith(attempt: 10);
      final a = ServerRecoveryPolicy.onTrigger(
        previous: state.copyWith(lastKickAtMs: 0),
        trigger: RecoveryTrigger.negotiationFailed,
        nowMs: 10000,
        transport: TransportState.connecting,
        sessionHealth: SessionHealth.unknown,
        hasCachedIpv6: false,
        cfg: const RecoveryConfig(backoffSeconds: [5, 9, 26]),
      );
      expect(a.type, RecoveryActionType.scheduleRetry);
      expect(a.delay, const Duration(seconds: 26));
    });
  });
}

