import 'package:test/test.dart';
import 'package:iterm2_host/webrtc/encoding_policy/encoding_policy.dart';

void main() {
  group('EncodingPolicyEngine', () {
    test('text_latency profile prefers maintain-framerate and scales down', () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textLatency);

      final stable = engine.decide(
        const EncodingContext(
          rttMs: 50,
          packetLossRate: 0.0,
          availableBitrateKbps: 2000,
          jitterMs: 5,
          targetFps: 30,
        ),
      );
      expect(stable.degradationPreference, 'maintain-framerate');
      expect(stable.maxFramerate, 30);
      expect(stable.scaleResolutionDownBy, 1.0);
      expect(stable.contentHint, 'text');

      final congested = engine.decide(
        const EncodingContext(
          rttMs: 400,
          packetLossRate: 0.10,
          availableBitrateKbps: 200,
          jitterMs: 30,
          targetFps: 30,
        ),
      );

      expect(engine.state, PolicyState.congested);
      expect(congested.maxFramerate, lessThanOrEqualTo(24));
      expect(congested.scaleResolutionDownBy, greaterThan(1.0));
    });

    test('text_quality profile prefers maintain-resolution and drops fps earlier',
        () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.textQuality);

      final congested = engine.decide(
        const EncodingContext(
          rttMs: 120,
          packetLossRate: 0.06,
          availableBitrateKbps: 220,
          jitterMs: 20,
          targetFps: 30,
        ),
      );

      expect(congested.degradationPreference, 'maintain-resolution');
      expect(congested.maxFramerate, 15);
      expect(congested.scaleResolutionDownBy, greaterThanOrEqualTo(1.5));
    });

    test('engine transitions congested -> recovering -> stable with hysteresis',
        () {
      final engine = EncodingPolicyEngine(profile: EncodingProfiles.balanced);

      // Force congestion.
      engine.decide(
        const EncodingContext(
          rttMs: 300,
          packetLossRate: 0.0,
          availableBitrateKbps: 180,
          jitterMs: 10,
          targetFps: 30,
        ),
      );
      expect(engine.state, PolicyState.congested);

      // Recovering after first stable tick.
      engine.decide(
        const EncodingContext(
          rttMs: 50,
          packetLossRate: 0.0,
          availableBitrateKbps: 2000,
          jitterMs: 5,
          targetFps: 30,
        ),
      );
      expect(engine.state, PolicyState.recovering);

      // After 3 stable ticks, become stable.
      engine.decide(
        const EncodingContext(
          rttMs: 50,
          packetLossRate: 0.0,
          availableBitrateKbps: 2000,
          jitterMs: 5,
          targetFps: 30,
        ),
      );
      engine.decide(
        const EncodingContext(
          rttMs: 50,
          packetLossRate: 0.0,
          availableBitrateKbps: 2000,
          jitterMs: 5,
          targetFps: 30,
        ),
      );
      expect(engine.state, PolicyState.stable);
    });

    test('EncodingDecision conversions produce expected keys', () {
      const decision = EncodingDecision(
        maxBitrateKbps: 500,
        maxFramerate: 20,
        scaleResolutionDownBy: 1.5,
        degradationPreference: 'maintain-framerate',
      );

      final enc = decision.toRtpEncodingParams();
      expect(enc['maxBitrate'], 500000);
      expect(enc['maxFramerate'], 20);
      expect(enc['scaleResolutionDownBy'], 1.5);

      final sender = decision.toRtpSenderParams();
      expect(sender['degradationPreference'], 'maintain-framerate');
    });
  });
}
