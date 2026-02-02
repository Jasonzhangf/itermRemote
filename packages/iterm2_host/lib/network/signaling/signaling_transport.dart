import 'package:cloudplayplus_core/network/device_id.dart';

/// Abstract transport used by the host to fetch peer addressing hints.
///
/// We intentionally keep this at the "address hints" level so it can be
/// simulated locally and unit-tested without WebRTC.
abstract class SignalingTransport {
  Future<PeerAddressHints> fetchPeerAddressHints({required DeviceId deviceId});
}

class PeerAddressHints {
  final String? ipv6;
  final int? port;
  final int fetchedAtMs;

  const PeerAddressHints({
    required this.ipv6,
    required this.port,
    required this.fetchedAtMs,
  });

  bool get hasIpv6 => (ipv6 != null && ipv6!.isNotEmpty && (port ?? 0) > 0);
}

