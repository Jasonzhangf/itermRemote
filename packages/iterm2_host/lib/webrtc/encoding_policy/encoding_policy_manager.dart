import 'encoding_policy_engine.dart';
import 'encoding_policy_models.dart';

typedef EncodingDecisionApplier = Future<void> Function(EncodingDecision decision);

/// Manages periodic encoding policy decisions and applies them.
///
/// This class is WebRTC-agnostic and can be wired to RTCRtpSender
/// by providing an applier implementation at runtime.
class EncodingPolicyManager {
  final EncodingPolicyEngine engine;
  final EncodingDecisionApplier applier;

  EncodingDecision? _lastDecision;

  EncodingPolicyManager({
    required this.engine,
    required this.applier,
  });

  EncodingDecision? get lastDecision => _lastDecision;

  /// Update policy decision based on the latest context.
  Future<EncodingDecision> update(EncodingContext context) async {
    final decision = engine.decide(context);
    _lastDecision = decision;
    await applier(decision);
    return decision;
  }
}
