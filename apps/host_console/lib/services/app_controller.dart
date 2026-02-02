import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';
import 'package:flutter/foundation.dart';
import 'package:iterm2_host/config/host_config.dart';
import 'package:iterm2_host/config/host_config_store.dart';
import 'package:iterm2_host/network/connection/connection_orchestrator.dart';
import 'package:iterm2_host/network/connection/fake_peer_connection.dart';
import 'package:iterm2_host/network/peer_address_resolver.dart';
import 'package:iterm2_host/network/recovery/server_recovery_policy.dart';
import 'package:iterm2_host/network/signaling/fake_signaling_transport.dart';

enum HostRunState { stopped, starting, connected, failed }

class AppController extends ChangeNotifier {
  final HostConfigStore store;

  HostConfig? _config;
  HostRunState _runState = HostRunState.stopped;

  ConnectionOrchestrator? _orchestrator;
  FakeSignalingTransport? _fakeSignaling;
  Ipv6AddressBook _book = Ipv6AddressBook.empty();

  String? _lastStatus;

  final List<String> _eventLog = <String>[];

  List<String> get eventLog => List<String>.unmodifiable(_eventLog);

  AppController({required this.store});

  HostConfig? get config => _config;
  HostRunState get runState => _runState;
  Ipv6AddressBook get addressBook => _book;
  String get lastStatus => _lastStatus ?? '';
  ConnectionAttempt? get lastAttempt => _orchestrator?.lastAttempt;

  Future<void> load() async {
    _config = await store.load();
    notifyListeners();
  }

  Future<void> save(HostConfig cfg) async {
    await store.save(cfg);
    _config = cfg;
    notifyListeners();
  }

  String get deviceIdString {
    final c = _config;
    if (c == null) return '';
    return DeviceId(accountId: c.accountId, stableId: c.stableId).encode();
  }

  Future<void> startSimulation() async {
    final c = _config;
    if (c == null) {
      await load();
    }
    final cfg = _config;
    if (cfg == null) return;

    _runState = HostRunState.starting;
    _lastStatus = 'starting';
    notifyListeners();

    final deviceId = DeviceId(accountId: cfg.accountId, stableId: cfg.stableId);

    _fakeSignaling = FakeSignalingTransport();
    // Default hint for simulation, can be edited later in UI.
    _fakeSignaling!.setHints(deviceId, ipv6: '2001:db8::2', port: 6000);
    final resolver = PeerAddressResolver(signaling: _fakeSignaling!);

    final peer = FakePeerConnection(
      config: const FakePeerConnectionConfig(
        timeToConnect: Duration(milliseconds: 100),
        failureProbability: 0.0,
        simulateLatency: true,
      ),
    );

    _orchestrator = ConnectionOrchestrator(
      deviceId: deviceId,
      resolver: resolver,
      book: _book,
      peer: peer,
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _orchestrator!.start(nowMs: nowMs);
    _book = _orchestrator!.book;

    _eventLog
      ..clear()
      ..addAll(_orchestrator!.events.map((e) => '[${e.type.name}] ${e.message}'));

    if (_orchestrator!.state == OrchestratorState.connected) {
      _runState = HostRunState.connected;
      _lastStatus = 'connected';
    } else {
      _runState = HostRunState.failed;
      _lastStatus = 'failed';
    }

    notifyListeners();
  }

  Future<void> triggerNegotiationFailed() async {
    final orch = _orchestrator;
    if (orch == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final action = await orch.onTrigger(
      trigger: RecoveryTrigger.negotiationFailed,
      nowMs: nowMs,
      transport: TransportState.connected,
      sessionHealth: SessionHealth.unhealthy,
    );
    _book = orch.book;
    _eventLog
      ..clear()
      ..addAll(orch.events.map((e) => '[${e.type.name}] ${e.message}'))
      ..add('[ui] trigger negotiationFailed -> ${action.type.name}');

    notifyListeners();
  }

  Future<void> stop() async {
    _orchestrator?.stop();
    _orchestrator?.dispose();
    _orchestrator = null;
    _fakeSignaling = null;
    _runState = HostRunState.stopped;
    _lastStatus = 'stopped';
    notifyListeners();
  }
}
