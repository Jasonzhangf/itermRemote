import 'dart:async';

import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';

import '../peer_address_resolver.dart';
import '../recovery/server_recovery_policy.dart';
import 'fake_peer_connection.dart';

enum OrchestratorState {
  idle,
  resolving,
  connecting,
  connected,
  waitingRetry,
  stopped,
  failed,
}

enum OrchestratorEventType {
  start,
  resolve,
  attempt,
  connected,
  failed,
  recoveryAction,
  scheduleRetry,
  stopped,
}

class OrchestratorEvent {
  final OrchestratorEventType type;
  final int atMs;
  final String message;
  final ConnectionAttempt? attempt;
  final RecoveryActionType? recoveryAction;
  final Duration? delay;

  const OrchestratorEvent({
    required this.type,
    required this.atMs,
    required this.message,
    this.attempt,
    this.recoveryAction,
    this.delay,
  });
}

class ConnectionAttempt {
  final String ipv6;
  final int port;
  final PeerAddressSource source;

  const ConnectionAttempt({
    required this.ipv6,
    required this.port,
    required this.source,
  });
}

class ConnectionOrchestratorConfig {
  /// Max number of sequential endpoint attempts (cache + server) per connect.
  final int maxAttempts;

  /// Budget for a single connection attempt.
  final Duration perAttemptTimeout;

  const ConnectionOrchestratorConfig({
    this.maxAttempts = 3,
    this.perAttemptTimeout = const Duration(seconds: 4),
  });
}

/// Local-simulation-first connection orchestrator.
///
/// - Direct-first using cached IPv6.
/// - Falls back to server hints.
/// - Integrates [ServerRecoveryPolicy] for retries/backoff.
/// - Pure logic + timeouts; WebRTC is represented by [FakePeerConnection].
class ConnectionOrchestrator {
  final DeviceId deviceId;
  final PeerAddressResolver resolver;
  final FakePeerConnection peer;
  final ConnectionOrchestratorConfig cfg;
  final RecoveryConfig recoveryCfg;

  OrchestratorState _state = OrchestratorState.idle;
  RecoveryState _recovery = const RecoveryState.initial();
  Ipv6AddressBook _book;

  bool _directAttemptFailed = false;
  Timer? _retryTimer;

  ConnectionAttempt? _lastAttempt;
  final List<OrchestratorEvent> _events = <OrchestratorEvent>[];

  List<OrchestratorEvent> get events => List<OrchestratorEvent>.unmodifiable(_events);

  ConnectionOrchestrator({
    required this.deviceId,
    required this.resolver,
    required Ipv6AddressBook book,
    FakePeerConnection? peer,
    this.cfg = const ConnectionOrchestratorConfig(),
    this.recoveryCfg = const RecoveryConfig(),
  })  : peer = peer ?? FakePeerConnection(),
        _book = book;

  OrchestratorState get state => _state;
  Ipv6AddressBook get book => _book;
  RecoveryState get recoveryState => _recovery;
  ConnectionAttempt? get lastAttempt => _lastAttempt;

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> start({required int nowMs}) async {
    if (_state != OrchestratorState.idle && _state != OrchestratorState.stopped) {
      throw StateError('orchestrator already started');
    }
    _directAttemptFailed = false;
    _events.clear();
    _events.add(OrchestratorEvent(
      type: OrchestratorEventType.start,
      atMs: nowMs,
      message: 'start',
    ));
    _setState(OrchestratorState.resolving);
    await _connectOnce(nowMs: nowMs);
  }

  void stop() {
    _retryTimer?.cancel();
    _retryTimer = null;
    peer.disconnect();
    _events.add(OrchestratorEvent(
      type: OrchestratorEventType.stopped,
      atMs: DateTime.now().millisecondsSinceEpoch,
      message: 'stopped',
    ));
    _setState(OrchestratorState.stopped);
  }

  /// Signal app pause. Updates recovery state.
  void onPaused({required int nowMs}) {
    _recovery = ServerRecoveryPolicy.onPaused(previous: _recovery, nowMs: nowMs);
  }

  /// Trigger recovery based on runtime signals.
  Future<RecoveryAction> onTrigger({
    required RecoveryTrigger trigger,
    required int nowMs,
    required TransportState transport,
    required SessionHealth sessionHealth,
  }) async {
    final hasCached = _book.pickPreferredForDevice(deviceId) != null;
    final action = ServerRecoveryPolicy.onTrigger(
      previous: _recovery,
      trigger: trigger,
      nowMs: nowMs,
      transport: transport,
      sessionHealth: sessionHealth,
      hasCachedIpv6: hasCached,
      cfg: recoveryCfg,
    );
    _recovery = action.nextState;

    _events.add(OrchestratorEvent(
      type: OrchestratorEventType.recoveryAction,
      atMs: nowMs,
      message: action.reason,
      recoveryAction: action.type,
      delay: action.delay,
    ));

    switch (action.type) {
      case RecoveryActionType.none:
      case RecoveryActionType.stop:
        return action;
      case RecoveryActionType.tryDirectIpv6:
        _directAttemptFailed = false;
        await _connectOnce(nowMs: nowMs);
        return action;
      case RecoveryActionType.reconnectTransport:
      case RecoveryActionType.restartSession:
        // In this local orchestrator, transport/session operations are simulated
        // by re-running resolution + connect.
        await _connectOnce(nowMs: nowMs);
        return action;
      case RecoveryActionType.scheduleRetry:
        final delay = action.delay ?? const Duration(seconds: 5);
        _scheduleRetry(delay: delay, nowMs: nowMs);
        return action;
    }
  }

  void _scheduleRetry({required Duration delay, required int nowMs}) {
    _retryTimer?.cancel();
    _setState(OrchestratorState.waitingRetry);
    _events.add(OrchestratorEvent(
      type: OrchestratorEventType.scheduleRetry,
      atMs: nowMs,
      message: 'retry in ${delay.inMilliseconds}ms',
      delay: delay,
    ));
    _retryTimer = Timer(delay, () {
      // Fire and forget; tests can await via polling state.
      unawaited(_connectOnce(nowMs: nowMs + delay.inMilliseconds));
    });
  }

  Future<void> _connectOnce({required int nowMs}) async {
    var attempts = 0;
    while (attempts < cfg.maxAttempts) {
      attempts++;

      _setState(OrchestratorState.resolving);
      _events.add(OrchestratorEvent(
        type: OrchestratorEventType.resolve,
        atMs: nowMs,
        message: 'resolve (attempt $attempts)',
      ));
      final resolved = await resolver.resolve(
        deviceId: deviceId,
        book: _book,
        directAttemptFailed: _directAttemptFailed,
      );
      _book = resolved.updatedBook;

      if (!resolved.hasAddress) {
        _directAttemptFailed = true;
        break;
      }

      _lastAttempt = ConnectionAttempt(
        ipv6: resolved.ipv6!,
        port: resolved.port!,
        source: resolved.source,
      );

      _events.add(OrchestratorEvent(
        type: OrchestratorEventType.attempt,
        atMs: nowMs,
        message: 'connect ${_lastAttempt!.ipv6}:${_lastAttempt!.port} via ${_lastAttempt!.source.name}',
        attempt: _lastAttempt,
      ));

      _setState(OrchestratorState.connecting);
      peer.reset();
      try {
        await peer
            .connect(ipv6: resolved.ipv6!, port: resolved.port!)
            .timeout(cfg.perAttemptTimeout);
      } on TimeoutException {
        _directAttemptFailed = true;
        continue;
      } catch (_) {
        _directAttemptFailed = true;
        continue;
      }

      if (peer.isConnected) {
        // Persist successful IPv6 into book.
        _book = _book.upsertForDevice(
          deviceId: deviceId,
          ipv6: resolved.ipv6!,
          port: resolved.port!,
          updatedAtMs: nowMs,
        );
        _setState(OrchestratorState.connected);
        _events.add(OrchestratorEvent(
          type: OrchestratorEventType.connected,
          atMs: nowMs,
          message: 'connected',
          attempt: _lastAttempt,
        ));
        return;
      }

      _directAttemptFailed = true;
    }

    _setState(OrchestratorState.failed);
    _events.add(OrchestratorEvent(
      type: OrchestratorEventType.failed,
      atMs: nowMs,
      message: 'failed',
      attempt: _lastAttempt,
    ));
  }

  void _setState(OrchestratorState s) {
    _state = s;
  }
}
