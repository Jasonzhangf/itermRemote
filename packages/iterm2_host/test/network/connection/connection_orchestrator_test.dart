import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';
import 'package:iterm2_host/network/connection/connection_orchestrator.dart';
import 'package:iterm2_host/network/connection/fake_peer_connection.dart';
import 'package:iterm2_host/network/peer_address_resolver.dart';
import 'package:iterm2_host/network/signaling/fake_signaling_transport.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionOrchestrator', () {
    test('connects via cached ipv6 first and updates book timestamp', () async {
      final deviceId = DeviceId(accountId: 'acc', stableId: 'stable');
      final nowMs = 1700000000000;
      Ipv6AddressBook.nowMsOverride = () => nowMs;
      final book = Ipv6AddressBook.empty().upsertForDevice(
        deviceId: deviceId,
        ipv6: '2001:db8::1',
        port: 5000,
        updatedAtMs: nowMs - 1000,
      );

      final transport = FakeSignalingTransport();
      final resolver = PeerAddressResolver(signaling: transport);
      final peer = FakePeerConnection(
        config: const FakePeerConnectionConfig(
          timeToConnect: Duration(milliseconds: 10),
          failureProbability: 0,
          simulateLatency: false,
        ),
      );
      final orch = ConnectionOrchestrator(
        deviceId: deviceId,
        resolver: resolver,
        book: book,
        peer: peer,
        cfg: const ConnectionOrchestratorConfig(
          maxAttempts: 1,
          perAttemptTimeout: Duration(seconds: 1),
        ),
      );

      await orch.start(nowMs: nowMs);
      expect(orch.state, OrchestratorState.connected);
      expect(orch.lastAttempt!.source, PeerAddressSource.cache);

      final entry = orch.book.pickPreferredForDevice(deviceId);
      expect(entry, isNotNull);
      expect(entry!.updatedAtMs, nowMs);

      Ipv6AddressBook.nowMsOverride = null;
    });

    test('falls back to server hints when no cache exists', () async {
      final deviceId = DeviceId(accountId: 'acc', stableId: 'stable');
      final nowMs = 1700000000000;
      Ipv6AddressBook.nowMsOverride = () => nowMs;

      final transport = FakeSignalingTransport();
      transport.setHints(deviceId, ipv6: '2001:db8::2', port: 6000);
      final resolver = PeerAddressResolver(signaling: transport);
      final peer = FakePeerConnection(
        config: const FakePeerConnectionConfig(
          timeToConnect: Duration(milliseconds: 10),
          failureProbability: 0,
          simulateLatency: false,
        ),
      );

      final orch = ConnectionOrchestrator(
        deviceId: deviceId,
        resolver: resolver,
        book: Ipv6AddressBook.empty(),
        peer: peer,
        cfg: const ConnectionOrchestratorConfig(
          maxAttempts: 2,
          perAttemptTimeout: Duration(seconds: 1),
        ),
      );

      await orch.start(nowMs: nowMs);
      expect(orch.state, OrchestratorState.connected);
      expect(orch.lastAttempt!.source, PeerAddressSource.server);

      final entry = orch.book.pickPreferredForDevice(deviceId);
      expect(entry, isNotNull);
      expect(entry!.ipv6, '2001:db8::2');
      expect(entry.port, 6000);

      Ipv6AddressBook.nowMsOverride = null;
    });

    test('fails after max attempts when peer always fails and no server hints',
        () async {
      final deviceId = DeviceId(accountId: 'acc', stableId: 'stable');

      final transport = FakeSignalingTransport();
      final resolver = PeerAddressResolver(signaling: transport);
      final peer = FakePeerConnection(
        config: const FakePeerConnectionConfig(
          timeToConnect: Duration(milliseconds: 10),
          timeToFail: Duration(milliseconds: 10),
          failureProbability: 1,
          simulateLatency: false,
        ),
      );

      final orch = ConnectionOrchestrator(
        deviceId: deviceId,
        resolver: resolver,
        book: Ipv6AddressBook.empty(),
        peer: peer,
        cfg: const ConnectionOrchestratorConfig(
          maxAttempts: 2,
          perAttemptTimeout: Duration(milliseconds: 200),
        ),
      );

      await orch.start(nowMs: 1);
      expect(orch.state, OrchestratorState.failed);
    });
  });
}
