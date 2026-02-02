import 'dart:convert';

import 'package:meta/meta.dart';

import 'device_id.dart';

/// IPv6 address cache for peer devices.
///
/// Motivation:
/// - IPv6 discovery may be expensive/unreliable.
/// - Once we learned a device's IPv6, we want to re-use it for direct LAN
///   negotiation without requiring the server every time.
/// - Server connection is used for updates / invalidation.
///
/// This class is pure (no storage). Persist it via the provided codec.
@immutable
class Ipv6AddressRecord {
  final String deviceId;
  final String ipv6;
  final int port;
  final int updatedAtMs;

  const Ipv6AddressRecord({
    required this.deviceId,
    required this.ipv6,
    required this.port,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'ipv6': ipv6,
        'port': port,
        'updatedAtMs': updatedAtMs,
      };

  static Ipv6AddressRecord fromJson(Map<String, dynamic> json) {
    return Ipv6AddressRecord(
      deviceId: (json['deviceId'] ?? '') as String,
      ipv6: (json['ipv6'] ?? '') as String,
      port: (json['port'] ?? 0) as int,
      updatedAtMs: (json['updatedAtMs'] ?? 0) as int,
    );
  }
}

class Ipv6AddressBook {
  final Map<String, Ipv6AddressRecord> _byDeviceId;

  /// Optional override used by tests and simulations to make age checks
  /// deterministic.
  static int Function()? nowMsOverride;

  Ipv6AddressBook._(this._byDeviceId);

  factory Ipv6AddressBook.empty() => Ipv6AddressBook._(<String, Ipv6AddressRecord>{});

  List<Ipv6AddressRecord> get records {
    final list = _byDeviceId.values.toList(growable: false);
    list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  Ipv6AddressRecord? get(String deviceId) => _byDeviceId[deviceId];

  Ipv6AddressRecord? getByDevice(DeviceId deviceId) => get(deviceId.encode());

  Ipv6AddressBook upsert(Ipv6AddressRecord record) {
    final next = Map<String, Ipv6AddressRecord>.from(_byDeviceId);
    next[record.deviceId] = record;
    return Ipv6AddressBook._(next);
  }

  Ipv6AddressBook upsertForDevice({
    required DeviceId deviceId,
    required String ipv6,
    required int port,
    required int updatedAtMs,
  }) {
    return upsert(
      Ipv6AddressRecord(
        deviceId: deviceId.encode(),
        ipv6: ipv6,
        port: port,
        updatedAtMs: updatedAtMs,
      ),
    );
  }

  Ipv6AddressBook remove(String deviceId) {
    final next = Map<String, Ipv6AddressRecord>.from(_byDeviceId);
    next.remove(deviceId);
    return Ipv6AddressBook._(next);
  }

  /// Prefer direct LAN negotiation using cached IPv6.
  ///
  /// Returns null if no usable record exists.
  Ipv6AddressRecord? pickPreferred(String deviceId,
      {int maxAgeMs = 7 * 24 * 3600 * 1000}) {
    final r = _byDeviceId[deviceId];
    if (r == null) return null;
    if (r.ipv6.isEmpty || r.port <= 0) return null;
    final now = (nowMsOverride != null)
        ? nowMsOverride!()
        : DateTime.now().millisecondsSinceEpoch;
    if (r.updatedAtMs <= 0) return null;
    if (now - r.updatedAtMs > maxAgeMs) return null;
    return r;
  }

  Ipv6AddressRecord? pickPreferredForDevice(DeviceId deviceId,
      {int maxAgeMs = 7 * 24 * 3600 * 1000}) {
    return pickPreferred(deviceId.encode(), maxAgeMs: maxAgeMs);
  }

  String encode() {
    final list = _byDeviceId.values
        .map((e) => e.toJson())
        .toList(growable: false);
    return jsonEncode({'records': list});
  }

  static Ipv6AddressBook decode(String s) {
    if (s.trim().isEmpty) return Ipv6AddressBook.empty();
    try {
      final any = jsonDecode(s);
      if (any is! Map) return Ipv6AddressBook.empty();
      final recs = any['records'];
      if (recs is! List) return Ipv6AddressBook.empty();
      final map = <String, Ipv6AddressRecord>{};
      for (final r in recs) {
        if (r is! Map) continue;
        final rr = Ipv6AddressRecord.fromJson(r.map((k, v) => MapEntry(k.toString(), v)));
        if (rr.deviceId.isEmpty) continue;
        map[rr.deviceId] = rr;
      }
      return Ipv6AddressBook._(map);
    } catch (_) {
      return Ipv6AddressBook.empty();
    }
  }
}
