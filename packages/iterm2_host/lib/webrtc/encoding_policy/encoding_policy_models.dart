/// Input context for encoding policy decision.
class EncodingContext {
  /// Current round-trip time in milliseconds.
  final int rttMs;

  /// Packet loss rate (0.0 to 1.0).
  final double packetLossRate;

  /// Estimated available bandwidth in kbps.
  final int availableBitrateKbps;

  /// Network jitter in milliseconds.
  final int jitterMs;

  /// Current target fps from application.
  final int targetFps;

  /// Whether content is text-heavy (affects contentHint).
  final bool textHeavy;

  const EncodingContext({
    required this.rttMs,
    required this.packetLossRate,
    required this.availableBitrateKbps,
    required this.jitterMs,
    required this.targetFps,
    this.textHeavy = true,
  });

  @override
  String toString() {
    return 'EncodingContext(rtt=${rttMs}ms, loss=${(packetLossRate * 100).toInt()}%, bw=${availableBitrateKbps}kbps, jitter=${jitterMs}ms, targetFps=$targetFps)';
  }
}

/// Encoding decision output to apply to RTCRtpSender.
class EncodingDecision {
  /// Maximum bitrate in kbps.
  final int? maxBitrateKbps;

  /// Maximum framerate.
  final int? maxFramerate;

  /// Scale resolution down by factor (>1 reduces resolution).
  final double? scaleResolutionDownBy;

  /// Degradation preference: 'maintain-framerate', 'maintain-resolution', 'balanced'.
  final String? degradationPreference;

  /// SVC scalability mode: 'L1T1', 'L1T2', 'L1T3', etc.
  final String? scalabilityMode;

  /// Content hint: 'text', 'detail', 'motion', 'speech', 'music', 'film'.
  final String? contentHint;

  const EncodingDecision({
    this.maxBitrateKbps,
    this.maxFramerate,
    this.scaleResolutionDownBy,
    this.degradationPreference,
    this.scalabilityMode,
    this.contentHint,
  });

  /// Convert to RTCRtpParameters encoding modifications.
  Map<String, dynamic> toRtpEncodingParams() {
    return {
      if (maxBitrateKbps != null) 'maxBitrate': maxBitrateKbps! * 1000,
      if (maxFramerate != null) 'maxFramerate': maxFramerate!,
      if (scaleResolutionDownBy != null) 'scaleResolutionDownBy': scaleResolutionDownBy!,
      if (scalabilityMode != null) 'scalabilityMode': scalabilityMode!,
    };
  }

  /// Convert to RTCRtpParameters sender-level modifications.
  Map<String, dynamic> toRtpSenderParams() {
    return {
      if (degradationPreference != null) 'degradationPreference': degradationPreference!,
    };
  }

  @override
  String toString() {
    return 'EncodingDecision(maxBitrate=$maxBitrateKbps, maxFps=$maxFramerate, scale=$scaleResolutionDownBy, degrad=$degradationPreference, svc=$scalabilityMode, hint=$contentHint)';
  }
}

/// Policy state for recovery hysteresis.
enum PolicyState {
  stable,
  congested,
  recovering,
}

/// Base profile for encoding policies.
class EncodingProfile {
  final String id;
  final String name;
  final String description;

  const EncodingProfile({
    required this.id,
    required this.name,
    required this.description,
  });
}
