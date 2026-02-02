import 'package:test/test.dart';

import 'package:cloudplayplus_core/network/device_id.dart';

void main() {
  group('DeviceId', () {
    test('encode/parse roundtrip', () {
      const id = DeviceId(accountId: 'acc', stableId: 'stable');
      final s = id.encode();
      final parsed = DeviceId.tryParse(s);
      expect(parsed, isNotNull);
      expect(parsed, id);
    });

    test('tryParse rejects invalid', () {
      expect(DeviceId.tryParse(''), isNull);
      expect(DeviceId.tryParse('a'), isNull);
      expect(DeviceId.tryParse(':'), isNull);
      expect(DeviceId.tryParse('a:'), isNull);
      expect(DeviceId.tryParse(':b'), isNull);
    });
  });
}

