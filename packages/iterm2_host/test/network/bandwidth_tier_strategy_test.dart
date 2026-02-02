import 'package:test/test.dart';
import 'package:iterm2_host/network/bandwidth_tier_strategy.dart';

void main() {
  group('BandwidthTierStrategy', () {
    test('basic tier mapping matches thresholds', () {
      const cfg = BandwidthTierConfig();
      final now = 1000;

      BandwidthTierDecision d(int bwe) {
        return decideBandwidthTier(
          previous: const BandwidthTierState.initial(),
          input: BandwidthTierInput(
            bweKbps: bwe,
            lossFraction: 0,
            rttMs: 50,
            freezeDelta: 0,
            width: cfg.baseWidth,
            height: cfg.baseHeight,
          ),
          cfg: cfg,
          nowMs: now,
        );
      }

      expect(d(0).fpsTier, 15); // unknown -> hold initial
      expect(d(100).fpsTier, 15); // still hold initial (needs step down hold)
      expect(d(249).fpsTier, 15);
      expect(d(250).fpsTier, 15);
      expect(d(499).fpsTier, 15);
      expect(d(500).fpsTier, 15);
      expect(d(999).fpsTier, 15);
      expect(d(1000).fpsTier, 15);
    });

    test('step up requires stable duration and healthy signals', () {
      const cfg = BandwidthTierConfig(stepUpStableDuration: Duration(seconds: 1));
      var state = const BandwidthTierState.initial();

      // Provide BWE that qualifies for step up from 15 -> 30
      final input = BandwidthTierInput(
        bweKbps: 600,
        lossFraction: 0,
        rttMs: 50,
        freezeDelta: 0,
        width: cfg.baseWidth,
        height: cfg.baseHeight,
      );

      final d0 = decideBandwidthTier(previous: state, input: input, cfg: cfg, nowMs: 0);
      state = d0.state;
      expect(d0.fpsTier, 15);

      final d1 = decideBandwidthTier(previous: state, input: input, cfg: cfg, nowMs: 1000);
      expect(d1.fpsTier, 30);
      expect(d1.targetBitrateKbps, greaterThanOrEqualTo(250));
    });

    test('congested reduces effective bandwidth', () {
      const cfg = BandwidthTierConfig(congestedBandwidthFactor: 0.8);
      final input = BandwidthTierInput(
        bweKbps: 1000,
        lossFraction: 0.05,
        rttMs: 500,
        freezeDelta: 1,
        width: cfg.baseWidth,
        height: cfg.baseHeight,
      );

      final d = decideBandwidthTier(
        previous: const BandwidthTierState.initial(),
        input: input,
        cfg: cfg,
        nowMs: 0,
      );
      expect(d.effectiveBandwidthKbps, 800);
    });
  });
}

