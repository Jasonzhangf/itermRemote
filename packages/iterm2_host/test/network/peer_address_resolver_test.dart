import 'package:test/test.dart';

import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';
import 'package:iterm2_host/network/peer_address_resolver.dart';
import 'package:iterm2_host/network/signaling/fake_signaling_transport.dart';

void main() {
  group('PeerAddressResolver', () {
    test('uses cache first when available', () async {
      final deviceId = DeviceId(accountId: 'a', stableId: 's');
      final now = DateTime.now().millisecondsSinceEpoch;
      final book = Ipv6AddressBook.empty().upsertForDevice(
        deviceId: deviceId,
        ipv6: 'fd00::1',
        port: 5555,
        updatedAtMs: now,
      );

      final signaling = FakeSignalingTransport();
      signaling.setHints(deviceId, ipv6: 'fd00::2', port: 6666);

      final resolver = PeerAddressResolver(signaling: signaling);
      final r = await resolver.resolve(
        deviceId: deviceId,
        book: book,
        directAttemptFailed: false,
      );
      expect(r.source, PeerAddressSource.cache);
      expect(r.ipv6, 'fd00::1');
      expect(r.port, 5555);
    });

    test('fetches server hints when cache missing', () async {
      final deviceId = DeviceId(accountId: 'a', stableId: 's');
      final book = Ipv6AddressBook.empty();
      final signaling = FakeSignalingTransport();
      signaling.setHints(deviceId, ipv6: 'fd00::2', port: 6666);

      final resolver = PeerAddressResolver(signaling: signaling);
      final r = await resolver.resolve(
        deviceId: deviceId,
        book: book,
        directAttemptFailed: false,
      );
      expect(r.source, PeerAddressSource.server);
      expect(r.ipv6, 'fd00::2');
      expect(r.port, 6666);
      expect(r.updatedBook.getByDevice(deviceId)!.ipv6, 'fd00::2');
    });

    test('fetches server hints after direct attempt failed', () async {
      final deviceId = DeviceId(accountId: 'a', stableId: 's');
      final now = DateTime.now().millisecondsSinceEpoch;
      final book = Ipv6AddressBook.empty().upsertForDevice(
        deviceId: deviceId,
        ipv6: 'fd00::bad',
        port: 5555,
        updatedAtMs: now,
      );
      final signaling = FakeSignalingTransport();
      signaling.setHints(deviceId, ipv6: 'fd00::good', port: 6666);

      final resolver = PeerAddressResolver(signaling: signaling);
      final r = await resolver.resolve(
        deviceId: deviceId,
        book: book,
        directAttemptFailed: true,
      );
      expect(r.source, PeerAddressSource.server);
      expect(r.ipv6, 'fd00::good');
    });
  });
}

