import 'dart:math';

import 'package:cloudplayplus_core/network/device_id.dart';

import 'signaling_transport.dart';

/// In-memory fake signaling transport for local simulation.
class FakeSignalingTransport implements SignalingTransport {
  final Map<String, PeerAddressHints> _hintsByDeviceId;
  final Random _rng;
  bool failFetch = false;

  FakeSignalingTransport({
    Map<String, PeerAddressHints>? initial,
    Random? rng,
  })  : _hintsByDeviceId = Map<String, PeerAddressHints>.from(initial ?? const {}),
        _rng = rng ?? Random(1);

  void setHints(DeviceId deviceId, {required String ipv6, required int port}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _hintsByDeviceId[deviceId.encode()] = PeerAddressHints(
      ipv6: ipv6,
      port: port,
      fetchedAtMs: now,
    );
  }

  @override
  Future<PeerAddressHints> fetchPeerAddressHints({required DeviceId deviceId}) async {
    if (failFetch) {
      throw StateError('fake signaling fetch failed');
    }
    // Simulate jitter.
    await Future<void>.delayed(Duration(milliseconds: 20 + _rng.nextInt(30)));
    return _hintsByDeviceId[deviceId.encode()] ??
        PeerAddressHints(ipv6: null, port: null, fetchedAtMs: DateTime.now().millisecondsSinceEpoch);
  }
}

