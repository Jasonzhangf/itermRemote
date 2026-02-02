import 'package:iterm2_host/config/host_config.dart';
import 'package:test/test.dart';

void main() {
  group('HostConfig', () {
    test('encode/decode roundtrip keeps key fields', () {
      final cfg = HostConfig(
        accountId: 'acc1',
        stableId: 's1',
        signalingServerUrl: 'wss://example.com/ws',
        turn: const TurnConfig(uri: 'turn:turn.example.com', username: 'u', credential: 'p'),
        networkPriority: const [
          NetworkEndpointType.ipv6,
          NetworkEndpointType.turn,
        ],
        logLevel: 'debug',
        enableSimulation: false,
      );

      final encoded = cfg.encode();
      final decoded = HostConfig.decode(encoded);

      expect(decoded.accountId, 'acc1');
      expect(decoded.stableId, 's1');
      expect(decoded.signalingServerUrl, 'wss://example.com/ws');
      expect(decoded.turn, isNotNull);
      expect(decoded.turn!.uri, 'turn:turn.example.com');
      expect(decoded.networkPriority, [NetworkEndpointType.ipv6, NetworkEndpointType.turn]);
      expect(decoded.logLevel, 'debug');
      expect(decoded.enableSimulation, false);
    });

    test('fromJson falls back to default priority when missing', () {
      final decoded = HostConfig.fromJson({
        'version': 1,
        'accountId': 'acc',
        'stableId': 'stable',
        'signalingServerUrl': '',
      });
      expect(decoded.networkPriority.isNotEmpty, true);
      expect(decoded.networkPriority.first, NetworkEndpointType.ipv6);
    });
  });
}

