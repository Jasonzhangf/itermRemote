import 'dart:math';

import 'package:meta/meta.dart';

/// Tiered adaptive encoding policy for iTerm2 panel streaming.
///
/// This module is intentionally pure (no WebRTC dependencies) so it can be
/// unit-tested and reused on both host/controller when needed.
///
/// Reference strategy: packages/iterm2_host/README.md (User Notes section).

/// 带宽分级规则（基于 README 中的策略基线）：
/// - B < 250kbps → 5fps
/// - 250 ≤ B < 500kbps → 15fps
/// - 500 ≤ B < 1000kbps → 30fps
/// - B ≥ 1000kbps → 60fps
///
/// 升档/降档条件：
/// - 升档（保守）：需要连续 5s 满足
///   - B >= nextTierThreshold
///   - 且 loss < 1% 且 rtt < 300ms 且 freezeΔ == 0
/// - 降档（快速）：连续 1.5s 满足任一
///   - B < currentTierThreshold * 0.85
///   - 或 loss > 3% 或 freezeΔ > 0
/// - 每次只允许跨 1 个档位
///
/// 码率策略：
/// - R_base(fpsTier) = R15 * fpsTier / 15
/// - R_cap = B * 0.85（headroom，可调 0.8~0.9）
/// - fpsTier < 60：R_video = min(R_base(fpsTier), R_cap)
/// - fpsTier == 60：R_video = min(R_cap, 1000 + qualityBoost(B))
/// - qualityBoost(B) = clamp((B - 1000) * 0.5, 0, 1500)
/// - 下限：R_video >= 30 kbps

@immutable
class BandwidthTierConfig {
  /// 基础分辨率（窗口模式 / iTerm panel 裁切后）
  final int baseWidth;
  final int baseHeight;

  /// 15fps 基准码率（kbps）@ 576×768
  final int baseBitrate15FpsKbps;

  /// 带宽阈值（kbps）
  final int t1Kbps; // < t1 → 5fps
  final int t2Kbps; // < t2 → 15fps
  final int t3Kbps; // < t3 → 30fps
  // B >= t3 → 60fps

  /// 码率封顶的 headroom（协议/重传/音频/突发预留）
  final double headroom; // 默认 0.85，可调 0.8~0.9

  /// 链路拥塞时带宽有效值降权因子
  final double congestedBandwidthFactor; // 默认 0.8

  /// 升档需要稳定的持续时间（毫秒）
  final Duration stepUpStableDuration;

  /// 降档需要稳定的持续时间（毫秒）
  final Duration stepDownStableDuration;

  /// 降档带宽比例阈值
  final double stepDownBandwidthRatio; // 默认 0.85

  /// 升档最大丢包率（0.01 = 1%）
  final double stepUpMaxLossFraction;

  /// 升档最大 RTT（毫秒）
  final double stepUpMaxRttMs;

  /// 升档要求无冻结帧
  final int stepUpRequireFreezeDelta;

  /// 降档最小丢包率（0.03 = 3%）
  final double stepDownMinLossFraction;

  /// 视频码率下限（避免极端低码率把编码器搞崩）
  final int minVideoBitrateKbps;

  /// 60fps 下的质量提升上限（kbps）
  final int maxQualityBoostKbps;

  const BandwidthTierConfig({
    this.baseWidth = 576,
    this.baseHeight = 768,
    this.baseBitrate15FpsKbps = 250,
    this.t1Kbps = 250,
    this.t2Kbps = 500,
    this.t3Kbps = 1000,
    this.headroom = 0.85,
    this.congestedBandwidthFactor = 0.8,
    this.stepUpStableDuration = const Duration(seconds: 5),
    this.stepDownStableDuration = const Duration(milliseconds: 1500),
    this.stepDownBandwidthRatio = 0.85,
    this.stepUpMaxLossFraction = 0.01,
    this.stepUpMaxRttMs = 300,
    this.stepUpRequireFreezeDelta = 0,
    this.stepDownMinLossFraction = 0.03,
    this.minVideoBitrateKbps = 30,
    this.maxQualityBoostKbps = 1500,
  });
}

/// 带宽分级状态
@immutable
class BandwidthTierState {
  final int fpsTier;
  final int lastTierChangeAtMs;
  final int stableUpSinceMs;
  final int stableDownSinceMs;

  const BandwidthTierState({
    required this.fpsTier,
    required this.lastTierChangeAtMs,
    required this.stableUpSinceMs,
    required this.stableDownSinceMs,
  });

  const BandwidthTierState.initial()
      : fpsTier = 15,
        lastTierChangeAtMs = 0,
        stableUpSinceMs = -1,
        stableDownSinceMs = -1;

  BandwidthTierState copyWith({
    int? fpsTier,
    int? lastTierChangeAtMs,
    int? stableUpSinceMs,
    int? stableDownSinceMs,
  }) {
    return BandwidthTierState(
      fpsTier: fpsTier ?? this.fpsTier,
      lastTierChangeAtMs: lastTierChangeAtMs ?? this.lastTierChangeAtMs,
      stableUpSinceMs: stableUpSinceMs ?? this.stableUpSinceMs,
      stableDownSinceMs: stableDownSinceMs ?? this.stableDownSinceMs,
    );
  }
}

/// 带宽分级输入
@immutable
class BandwidthTierInput {
  /// 带宽估计（kbps），理想情况下来自 WebRTC BWE
  final int bweKbps;

  /// 接收端网络健康状况
  final double lossFraction; // 0.0 ~ 1.0
  final double rttMs;
  final int freezeDelta;

  /// 渲染分辨率（解码后）
  final int width;
  final int height;

  const BandwidthTierInput({
    required this.bweKbps,
    required this.lossFraction,
    required this.rttMs,
    required this.freezeDelta,
    required this.width,
    required this.height,
  });
}

/// 带宽分级决策
@immutable
class BandwidthTierDecision {
  final BandwidthTierState state;
  final int fpsTier;
  final int targetBitrateKbps;
  final int effectiveBandwidthKbps;
  final String reason;

  const BandwidthTierDecision({
    required this.state,
    required this.fpsTier,
    required this.targetBitrateKbps,
    required this.effectiveBandwidthKbps,
    required this.reason,
  });

  @override
  String toString() =>
      'BandwidthTierDecision(fpsTier=$fpsTier, bitrate=$targetBitrateKbps kbps, '
      'effectiveB=$effectiveBandwidthKbps kbps, reason=$reason)';
}

/// 根据带宽计算 fps 档位
int _tierFromBandwidthKbps(int b, BandwidthTierConfig cfg) {
  if (b < cfg.t1Kbps) return 5;
  if (b < cfg.t2Kbps) return 15;
  if (b < cfg.t3Kbps) return 30;
  return 60;
}

/// 当前档位升档所需的最小带宽
int _upperThresholdForTier(int tier, BandwidthTierConfig cfg) {
  if (tier <= 5) return cfg.t1Kbps; // 5 -> 15
  if (tier <= 15) return cfg.t2Kbps; // 15 -> 30
  if (tier <= 30) return cfg.t3Kbps; // 30 -> 60
  return cfg.t3Kbps;
}

/// 当前档位保持所需的最小带宽
int _lowerThresholdForTier(int tier, BandwidthTierConfig cfg) {
  if (tier <= 5) return 0;
  if (tier <= 15) return cfg.t1Kbps;
  if (tier <= 30) return cfg.t2Kbps;
  return cfg.t3Kbps;
}

/// 下一档位（升档）
int _stepUpTier(int tier) {
  if (tier < 15) return 15;
  if (tier < 30) return 30;
  if (tier < 60) return 60;
  return tier;
}

/// 上一档位（降档）
int _stepDownTier(int tier) {
  if (tier > 30) return 30;
  if (tier > 15) return 15;
  if (tier > 5) return 5;
  return tier;
}

/// 按面积比例缩放基准码率
///
/// 对于非 576×768 的分辨率，基准码率按面积比例计算：
/// R_base = R_ref * (W*H) / (576*768)
int _scaledR15Kbps({
  required int width,
  required int height,
  required BandwidthTierConfig cfg,
}) {
  final w = max(1, width);
  final h = max(1, height);
  final baseArea = max(1, cfg.baseWidth * cfg.baseHeight);
  final area = w * h;
  final scaled = (cfg.baseBitrate15FpsKbps * area / baseArea).round();
  return scaled.clamp(80, 5000);
}

/// 计算视频码率
///
/// - fpsTier < 60：min(R_base, R_cap)
/// - fpsTier == 60：允许带宽越高画质越好，码率上限为 t3Kbps + qualityBoost
/// - 下限：minVideoBitrateKbps
int _computeVideoBitrateKbps({
  required int fpsTier,
  required int effectiveBandwidthKbps,
  required int width,
  required int height,
  required BandwidthTierConfig cfg,
}) {
  final b = max(0, effectiveBandwidthKbps);
  // 未知 BWE → 不做限制（优先使用档位基准）
  final cap = (b <= 0)
      ? 200000
      : (b * cfg.headroom).floor().clamp(cfg.minVideoBitrateKbps, 200000);

  final r15 = _scaledR15Kbps(width: width, height: height, cfg: cfg);
  final base =
      (r15 * fpsTier / 15).round().clamp(cfg.minVideoBitrateKbps, 200000);

  if (fpsTier < 60) {
    return min(base, cap).clamp(cfg.minVideoBitrateKbps, 200000);
  }

  // 60fps：带宽越高画质越好
  final boost =
      ((b - cfg.t3Kbps) * 0.5).round().clamp(0, cfg.maxQualityBoostKbps);
  final target60 = (cfg.t3Kbps + boost).clamp(cfg.t3Kbps, 200000);
  return min(target60, cap).clamp(cfg.minVideoBitrateKbps, 200000);
}

/// 判断链路是否拥塞
bool _isCongested(BandwidthTierInput inb, BandwidthTierConfig cfg) {
  return (inb.lossFraction > 0.02) ||
      (inb.rttMs > 450) ||
      (inb.freezeDelta > 0);
}

/// 判断是否满足升档条件
bool _canStepUp(BandwidthTierInput inb, BandwidthTierConfig cfg) {
  return (inb.lossFraction < cfg.stepUpMaxLossFraction) &&
      (inb.rttMs > 0 ? inb.rttMs < cfg.stepUpMaxRttMs : true) &&
      (inb.freezeDelta <= cfg.stepUpRequireFreezeDelta);
}

/// 决定下一个 fps 档位 + 码率
///
/// 输入：带宽估计（BWE）+ 网络健康状况
/// 输出：fps 档位 + 目标码率 + 有效带宽
BandwidthTierDecision decideBandwidthTier({
  required BandwidthTierState previous,
  required BandwidthTierInput input,
  BandwidthTierConfig cfg = const BandwidthTierConfig(),
  required int nowMs,
}) {
  final congested = _isCongested(input, cfg);
  final bwe = max(0, input.bweKbps);
  final effectiveB =
      congested ? (bwe * cfg.congestedBandwidthFactor).floor() : bwe;
  int tier = previous.fpsTier;

  int stableUpSince = previous.stableUpSinceMs;
  int stableDownSince = previous.stableDownSinceMs;

  final nextUpTier = _stepUpTier(tier);
  final nextDownTier = _stepDownTier(tier);

  final nextUpThreshold = _upperThresholdForTier(tier, cfg);
  final currLowerThreshold = _lowerThresholdForTier(tier, cfg);

  // 降档快速路径：带宽远低于当前阈值，或明显的丢包/冻结
  final wantDownByBandwidth = (effectiveB > 0) &&
      (effectiveB < (currLowerThreshold * cfg.stepDownBandwidthRatio));
  final wantDownByLoss = input.lossFraction >= cfg.stepDownMinLossFraction;
  final wantDownByFreeze = input.freezeDelta > 0;
  final wantDown =
      (wantDownByBandwidth || wantDownByLoss || wantDownByFreeze) &&
          (nextDownTier != tier);

  // 升档：带宽支持更高档位且网络健康
  final wantUp = (effectiveB >= nextUpThreshold) &&
      (nextUpTier != tier) &&
      _canStepUp(input, cfg);

  if (wantUp) {
    stableDownSince = -1;
    stableUpSince = stableUpSince < 0 ? nowMs : stableUpSince;
    final heldMs = nowMs - stableUpSince;
    if (heldMs >= cfg.stepUpStableDuration.inMilliseconds) {
      final old = tier;
      tier = nextUpTier;
      stableUpSince = -1;
      stableDownSince = -1;
      final bitrate = _computeVideoBitrateKbps(
        fpsTier: tier,
        effectiveBandwidthKbps: effectiveB,
        width: input.width,
        height: input.height,
        cfg: cfg,
      );
      return BandwidthTierDecision(
        state: previous.copyWith(
          fpsTier: tier,
          lastTierChangeAtMs: nowMs,
          stableUpSinceMs: stableUpSince,
          stableDownSinceMs: stableDownSince,
        ),
        fpsTier: tier,
        targetBitrateKbps: bitrate,
        effectiveBandwidthKbps: effectiveB,
        reason: 'tier-up $old->$tier B=$effectiveB congested=$congested',
      );
    }
  } else {
    stableUpSince = -1;
  }

  if (wantDown) {
    stableUpSince = -1;
    stableDownSince = stableDownSince < 0 ? nowMs : stableDownSince;
    final heldMs = nowMs - stableDownSince;
    if (heldMs >= cfg.stepDownStableDuration.inMilliseconds) {
      final old = tier;
      tier = nextDownTier;
      stableDownSince = -1;
      stableUpSince = -1;
      final bitrate = _computeVideoBitrateKbps(
        fpsTier: tier,
        effectiveBandwidthKbps: effectiveB,
        width: input.width,
        height: input.height,
        cfg: cfg,
      );
      return BandwidthTierDecision(
        state: previous.copyWith(
          fpsTier: tier,
          lastTierChangeAtMs: nowMs,
          stableUpSinceMs: stableUpSince,
          stableDownSinceMs: stableDownSince,
        ),
        fpsTier: tier,
        targetBitrateKbps: bitrate,
        effectiveBandwidthKbps: effectiveB,
        reason:
            'tier-down $old->$tier B=$effectiveB loss=${(input.lossFraction * 100).toStringAsFixed(2)}% '
            'freezeΔ=${input.freezeDelta}',
      );
    }
  } else {
    stableDownSince = -1;
  }

  // 无档位变化；仍根据有效 B 计算当前档位的码率
  final bitrate = _computeVideoBitrateKbps(
    fpsTier: tier,
    effectiveBandwidthKbps: effectiveB,
    width: input.width,
    height: input.height,
    cfg: cfg,
  );

  return BandwidthTierDecision(
    state: previous.copyWith(
      fpsTier: tier,
      stableUpSinceMs: stableUpSince,
      stableDownSinceMs: stableDownSince,
    ),
    fpsTier: tier,
    targetBitrateKbps: bitrate,
    effectiveBandwidthKbps: effectiveB,
    reason: 'tier-hold $tier B=$effectiveB congested=$congested',
  );
}
