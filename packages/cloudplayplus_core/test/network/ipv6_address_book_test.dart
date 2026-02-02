import 'package:test/test.dart';

import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';

void main() {
  group('Ipv6AddressBook', () {
    test('encode/decode roundtrip', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final book = Ipv6AddressBook.empty().upsert(
        Ipv6AddressRecord(
          deviceId: 'd1',
          ipv6: 'fd00::1',
          port: 1234,
          updatedAtMs: now,
        ),
      );

      final encoded = book.encode();
      final decoded = Ipv6AddressBook.decode(encoded);
      final r = decoded.get('d1');
      expect(r, isNotNull);
      expect(r!.ipv6, 'fd00::1');
      expect(r.port, 1234);
    });

    test('pickPreferred returns null when expired', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final deviceId = DeviceId(accountId: 'a', stableId: 's');
      final book = Ipv6AddressBook.empty().upsertForDevice(
        deviceId: deviceId,
        ipv6: 'fd00::1',
        port: 1234,
        updatedAtMs: now - 10 * 24 * 3600 * 1000,
      );
      expect(book.pickPreferred('d1', maxAgeMs: 7 * 24 * 3600 * 1000), isNull);
      expect(book.pickPreferredForDevice(deviceId, maxAgeMs: 7 * 24 * 3600 * 1000), isNull);
    });
  });
}
