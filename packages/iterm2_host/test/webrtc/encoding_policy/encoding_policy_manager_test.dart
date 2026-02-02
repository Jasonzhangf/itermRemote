import 'package:test/test.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

void main() {
  group('EncodingPolicyManager', () {
    test('update calls applier and stores lastDecision', () async {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textLatency);
      EncodingDecision? applied;

      final manager = EncodingPolicyManager(
        engine: engine,
        applier: (d) async {
          applied = d;
        },
      );

      final ctx = const EncodingContext(
        rttMs: 80,
        packetLossRate: 0.01,
        availableBitrateKbps: 1200,
        jitterMs: 10,
        targetFps: 30,
      );

      final decision = await manager.update(ctx);
      expect(applied, isNotNull);
      expect(manager.lastDecision, isNotNull);
      expect(manager.lastDecision.toString(), decision.toString());
    });
  });
}
