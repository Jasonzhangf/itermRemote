import 'package:test/test.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

void main() {
  group('H.264-focused policy behavior', () {
    test('textLatency profile does not set scalabilityMode', () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textLatency);

      const stable = EncodingContext(
        rttMs: 50,
        packetLossRate: 0.0,
        availableBitrateKbps: 2000,
        jitterMs: 5,
        targetFps: 30,
      );

      final decision = engine.decide(stable);
      expect(decision.degradationPreference, 'maintain-framerate');
      expect(decision.contentHint, 'text');
    });

    test('congested state reduces bitrate and scale first, keeps fps', () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textLatency);

      const congested = EncodingContext(
        rttMs: 400,
        packetLossRate: 0.10,
        availableBitrateKbps: 250,
        jitterMs: 30,
        targetFps: 30,
      );

      final decision = engine.decide(congested);
      expect(decision.degradationPreference, 'maintain-framerate');
      expect(decision.maxFramerate, greaterThanOrEqualTo(24));
      expect(decision.scaleResolutionDownBy, greaterThan(1.0));
      expect(decision.maxBitrateKbps, lessThan(200));
    });

    test('textQuality profile prefers maintain-resolution, drops fps earlier', () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textQuality);

      const congested = EncodingContext(
        rttMs: 120,
        packetLossRate: 0.06,
        availableBitrateKbps: 220,
        jitterMs: 20,
        targetFps: 30,
      );

      final decision = engine.decide(congested);
      expect(decision.degradationPreference, 'maintain-resolution');
      expect(decision.maxFramerate, 15);
      expect(decision.scaleResolutionDownBy, greaterThanOrEqualTo(1.5));
    });
  });
}
