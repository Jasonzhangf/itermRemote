import 'dart:math';

import 'encoding_policy_models.dart';
import 'encoding_policy_profiles.dart';

/// Real-time encoding policy engine.
///
/// This module is intentionally self-contained and unit-testable.
/// It does not call WebRTC APIs directly; it only produces decisions.
class EncodingPolicyEngine {
  final EncodingProfile profile;

  /// Minimum fps bound we try to preserve.
  final int minFps;

  /// Maximum fps bound.
  final int maxFps;

  PolicyState _state = PolicyState.stable;

  // Recovery hysteresis counters.
  int _stableTicks = 0;
  int _congestedTicks = 0;

  EncodingPolicyEngine({
    required this.profile,
    this.minFps = 15,
    this.maxFps = 30,
  });

  PolicyState get state => _state;

  /// Decide encoding parameters based on current context.
  EncodingDecision decide(EncodingContext ctx) {
    final targetFps = ctx.targetFps.clamp(minFps, maxFps);

    // Basic congestion heuristics.
    final isLossy = ctx.packetLossRate >= 0.05;
    final isHighRtt = ctx.rttMs >= 250;
    final isLowBw = ctx.availableBitrateKbps <= _minRequiredBitrateKbps(targetFps);
    final congested = isLossy || isHighRtt || isLowBw;

    if (congested) {
      _congestedTicks++;
      _stableTicks = 0;
      _state = PolicyState.congested;
    } else {
      _stableTicks++;
      _congestedTicks = 0;
      if (_state == PolicyState.congested) {
        _state = PolicyState.recovering;
      } else if (_state == PolicyState.recovering && _stableTicks >= 3) {
        _state = PolicyState.stable;
      }
    }

    // Common decisions for text-heavy capture.
    final contentHint = ctx.textHeavy ? 'text' : 'motion';

    switch (profile.id) {
      case EncodingProfileIds.textLatency:
        return _decideTextLatency(
          ctx: ctx,
          targetFps: targetFps,
          contentHint: contentHint,
        );
      case EncodingProfileIds.textQuality:
        return _decideTextQuality(
          ctx: ctx,
          targetFps: targetFps,
          contentHint: contentHint,
        );
      case EncodingProfileIds.balanced:
      default:
        return _decideBalanced(
          ctx: ctx,
          targetFps: targetFps,
          contentHint: contentHint,
        );
    }
  }

  EncodingDecision _decideTextLatency({
    required EncodingContext ctx,
    required int targetFps,
    required String contentHint,
  }) {
    // Prefer maintain framerate, scale down first.
    final degradationPreference = 'maintain-framerate';
    final scale = _scaleForBandwidth(ctx.availableBitrateKbps, targetFps,
        preferReadability: false);

    final maxBitrate = _capBitrate(ctx.availableBitrateKbps,
        headroomKbps: _state == PolicyState.congested ? 100 : 200);
    final fps = _fpsForState(targetFps, preferFps: true);

    return EncodingDecision(
      contentHint: contentHint,
      degradationPreference: degradationPreference,
      maxBitrateKbps: maxBitrate,
      maxFramerate: fps,
      scaleResolutionDownBy: scale,
    );
  }

  EncodingDecision _decideTextQuality({
    required EncodingContext ctx,
    required int targetFps,
    required String contentHint,
  }) {
    // Prefer keep readability: keep resolution a bit more, drop fps earlier.
    final degradationPreference = 'maintain-resolution';
    final scale = _scaleForBandwidth(ctx.availableBitrateKbps, targetFps,
        preferReadability: true);

    final maxBitrate = _capBitrate(ctx.availableBitrateKbps,
        headroomKbps: _state == PolicyState.congested ? 80 : 150);
    final fps = _fpsForState(targetFps, preferFps: false);

    return EncodingDecision(
      contentHint: contentHint,
      degradationPreference: degradationPreference,
      maxBitrateKbps: maxBitrate,
      maxFramerate: fps,
      scaleResolutionDownBy: scale,
    );
  }

  EncodingDecision _decideBalanced({
    required EncodingContext ctx,
    required int targetFps,
    required String contentHint,
  }) {
    final degradationPreference = 'balanced';
    final scale = _scaleForBandwidth(ctx.availableBitrateKbps, targetFps,
        preferReadability: true);
    final maxBitrate = _capBitrate(ctx.availableBitrateKbps,
        headroomKbps: _state == PolicyState.congested ? 100 : 180);
    final fps = _fpsForState(targetFps, preferFps: true);

    return EncodingDecision(
      contentHint: contentHint,
      degradationPreference: degradationPreference,
      maxBitrateKbps: maxBitrate,
      maxFramerate: fps,
      scaleResolutionDownBy: scale,
    );
  }

  int _minRequiredBitrateKbps(int fps) {
    // For text-heavy terminal capture, usable baseline is relatively low,
    // but below ~150kbps things quickly become unreadable.
    // This is a heuristic threshold to detect congestion.
    return max(150, fps * 8); // e.g. 15fps->120 => 150, 30fps->240
  }

  int _capBitrate(int availableKbps, {required int headroomKbps}) {
    // Keep some headroom to avoid oscillation.
    return max(100, availableKbps - headroomKbps);
  }

  double _scaleForBandwidth(int kbps, int fps, {required bool preferReadability}) {
    // Heuristic mapping:
    // - Higher scale (downscale) when kbps is low.
    // - Prefer readability: downscale less aggressively.
    final baseline = preferReadability ? 350 : 280;
    final k = (baseline * (fps / 30)).round();

    if (kbps >= k * 4) return 1.0;
    if (kbps >= k * 2) return preferReadability ? 1.2 : 1.3;
    if (kbps >= k) return preferReadability ? 1.5 : 1.7;
    return preferReadability ? 2.0 : 2.2;
  }

  int _fpsForState(int targetFps, {required bool preferFps}) {
    if (_state == PolicyState.congested) {
      return preferFps ? max(minFps, min(targetFps, 24)) : min(targetFps, 15);
    }
    if (_state == PolicyState.recovering) {
      return min(targetFps, 24);
    }
    return targetFps;
  }

  // NOTE: SVC (scalabilityMode) is intentionally not used.
  // Rationale: hardware encoders often do not support SVC reliably across
  // platforms; we focus on bitrate/fps/scale + degradationPreference.
}
