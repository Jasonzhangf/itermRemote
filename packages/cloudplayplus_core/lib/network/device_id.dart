import 'package:meta/meta.dart';

/// Stable device identifier used across server + LAN.
///
/// Per requirement:
/// - deviceId = accountId + stableId
///
/// We keep it as a structured type to avoid stringly-typed bugs, but provide a
/// canonical string encoding for storage and transport.
@immutable
class DeviceId {
  final String accountId;
  final String stableId;

  const DeviceId({required this.accountId, required this.stableId});

  /// Canonical string encoding.
  ///
  /// Format: "{accountId}:{stableId}".
  String encode() => '$accountId:$stableId';

  static DeviceId? tryParse(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final idx = t.indexOf(':');
    if (idx <= 0 || idx >= t.length - 1) return null;
    final a = t.substring(0, idx).trim();
    final b = t.substring(idx + 1).trim();
    if (a.isEmpty || b.isEmpty) return null;
    return DeviceId(accountId: a, stableId: b);
  }

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) {
    return other is DeviceId &&
        other.accountId == accountId &&
        other.stableId == stableId;
  }

  @override
  int get hashCode => Object.hash(accountId, stableId);
}

