import 'package:cloudplayplus_core/network/device_id.dart';
import 'package:cloudplayplus_core/network/ipv6_address_book.dart';

import 'signaling/signaling_transport.dart';

/// Resolve peer address with "direct-first" strategy.
///
/// Rules:
/// 1) Prefer cached IPv6 in [Ipv6AddressBook].
/// 2) If cache miss or direct attempt fails, fetch hints from server (transport)
///    and update cache.
///
/// This module is pure except for calling the provided [SignalingTransport].
class PeerAddressResolver {
  final SignalingTransport signaling;

  PeerAddressResolver({required this.signaling});

  /// Resolve best address to try.
  ///
  /// Returns a tuple-like result: address + updated book.
  Future<ResolvedPeerAddress> resolve({
    required DeviceId deviceId,
    required Ipv6AddressBook book,
    required bool directAttemptFailed,
  }) async {
    // If we haven't failed yet, try cache first.
    if (!directAttemptFailed) {
      final cached = book.pickPreferredForDevice(deviceId);
      if (cached != null) {
        return ResolvedPeerAddress(
          ipv6: cached.ipv6,
          port: cached.port,
          updatedBook: book,
          source: PeerAddressSource.cache,
        );
      }
    }

    // Otherwise fetch from server transport.
    final hints = await signaling.fetchPeerAddressHints(deviceId: deviceId);
    if (!hints.hasIpv6) {
      return ResolvedPeerAddress(
        ipv6: null,
        port: null,
        updatedBook: book,
        source: PeerAddressSource.none,
      );
    }

    final updated = book.upsertForDevice(
      deviceId: deviceId,
      ipv6: hints.ipv6!,
      port: hints.port!,
      updatedAtMs: hints.fetchedAtMs,
    );

    return ResolvedPeerAddress(
      ipv6: hints.ipv6,
      port: hints.port,
      updatedBook: updated,
      source: PeerAddressSource.server,
    );
  }
}

enum PeerAddressSource { cache, server, none }

class ResolvedPeerAddress {
  final String? ipv6;
  final int? port;
  final Ipv6AddressBook updatedBook;
  final PeerAddressSource source;

  const ResolvedPeerAddress({
    required this.ipv6,
    required this.port,
    required this.updatedBook,
    required this.source,
  });

  bool get hasAddress => ipv6 != null && ipv6!.isNotEmpty && (port ?? 0) > 0;
}

