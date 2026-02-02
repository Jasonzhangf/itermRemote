import 'dart:convert';

import 'package:meta/meta.dart';

/// Persisted configuration for the Host service.
///
/// This lives in the host (desktop) machine and is intentionally kept
/// independent from Flutter UI so it can be unit-tested on the Dart VM.
@immutable
class HostConfig {
  static const int currentVersion = 1;

  final int version;
  final String accountId;
  final String stableId;

  /// Signaling server URL (wss/https).
  final String signalingServerUrl;

  /// TURN server configuration.
  final TurnConfig? turn;

  /// Network preference order.
  final List<NetworkEndpointType> networkPriority;

  /// Log level: trace/debug/info/warn/error.
  final String logLevel;

  /// Feature flags.
  final bool enableSimulation;

  const HostConfig({
    this.version = currentVersion,
    required this.accountId,
    required this.stableId,
    required this.signalingServerUrl,
    this.turn,
    this.networkPriority = const <NetworkEndpointType>[
      NetworkEndpointType.ipv6,
      NetworkEndpointType.tailscale,
      NetworkEndpointType.lanIpv4,
      NetworkEndpointType.turn,
    ],
    this.logLevel = 'info',
    this.enableSimulation = true,
  });

  HostConfig copyWith({
    int? version,
    String? accountId,
    String? stableId,
    String? signalingServerUrl,
    TurnConfig? turn,
    List<NetworkEndpointType>? networkPriority,
    String? logLevel,
    bool? enableSimulation,
  }) {
    return HostConfig(
      version: version ?? this.version,
      accountId: accountId ?? this.accountId,
      stableId: stableId ?? this.stableId,
      signalingServerUrl: signalingServerUrl ?? this.signalingServerUrl,
      turn: turn ?? this.turn,
      networkPriority: networkPriority ?? this.networkPriority,
      logLevel: logLevel ?? this.logLevel,
      enableSimulation: enableSimulation ?? this.enableSimulation,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'accountId': accountId,
        'stableId': stableId,
        'signalingServerUrl': signalingServerUrl,
        'turn': turn?.toJson(),
        'networkPriority': networkPriority.map((e) => e.id).toList(growable: false),
        'logLevel': logLevel,
        'enableSimulation': enableSimulation,
      };

  String encode() => jsonEncode(toJson());

  static HostConfig decode(String s) {
    if (s.trim().isEmpty) {
      return HostConfig(
        accountId: 'acc',
        stableId: 'stable',
        signalingServerUrl: '',
      );
    }
    final any = jsonDecode(s);
    if (any is! Map) {
      throw const FormatException('invalid host config json');
    }
    return fromJson(any.map((k, v) => MapEntry(k.toString(), v)));
  }

  static HostConfig fromJson(Map<String, dynamic> json) {
    final v = (json['version'] ?? currentVersion) as int;
    // v1 migration is trivial; keep hook for future versions.
    final accountId = (json['accountId'] ?? '') as String;
    final stableId = (json['stableId'] ?? '') as String;
    final signalingServerUrl = (json['signalingServerUrl'] ?? '') as String;
    final turnAny = json['turn'];
    TurnConfig? turn;
    if (turnAny is Map) {
      turn = TurnConfig.fromJson(turnAny.map((k, v) => MapEntry(k.toString(), v)));
    }
    final priAny = json['networkPriority'];
    final pri = <NetworkEndpointType>[];
    if (priAny is List) {
      for (final e in priAny) {
        if (e is String) {
          final parsed = NetworkEndpointType.tryParse(e);
          if (parsed != null) pri.add(parsed);
        }
      }
    }
    final logLevel = (json['logLevel'] ?? 'info') as String;
    final enableSimulation = (json['enableSimulation'] ?? true) as bool;

    return HostConfig(
      version: v,
      accountId: accountId,
      stableId: stableId,
      signalingServerUrl: signalingServerUrl,
      turn: turn,
      networkPriority: pri.isEmpty
          ? const <NetworkEndpointType>[
              NetworkEndpointType.ipv6,
              NetworkEndpointType.tailscale,
              NetworkEndpointType.lanIpv4,
              NetworkEndpointType.turn,
            ]
          : pri,
      logLevel: logLevel,
      enableSimulation: enableSimulation,
    );
  }
}

@immutable
class TurnConfig {
  final String uri;
  final String username;
  final String credential;

  const TurnConfig({
    required this.uri,
    required this.username,
    required this.credential,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'username': username,
        'credential': credential,
      };

  static TurnConfig fromJson(Map<String, dynamic> json) {
    return TurnConfig(
      uri: (json['uri'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      credential: (json['credential'] ?? '') as String,
    );
  }
}

enum NetworkEndpointType {
  ipv6('ipv6'),
  tailscale('tailscale'),
  lanIpv4('lan_ipv4'),
  turn('turn');

  final String id;
  const NetworkEndpointType(this.id);

  static NetworkEndpointType? tryParse(String s) {
    for (final v in NetworkEndpointType.values) {
      if (v.id == s) return v;
    }
    return null;
  }
}

