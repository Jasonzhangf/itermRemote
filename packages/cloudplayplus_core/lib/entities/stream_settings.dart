import 'capture_target.dart';
import 'stream_mode.dart';

/// Configuration for a stream session.
class StreamSettings {
  final StreamMode mode;
  final CaptureTargetType captureType;

  // iTerm2 panel capture.
  final String? iterm2SessionId;
  final Map<String, double>? cropRect;

  // Video parameters.
  final int framerate;
  final int videoBitrateKbps;

  // Chat mode parameters.
  final int chatBufferSize;

  // TURN parameters.
  final bool useTurn;
  final String? turnServer;
  final String? turnUsername;
  final String? turnPassword;

  const StreamSettings({
    required this.mode,
    required this.captureType,
    this.iterm2SessionId,
    this.cropRect,
    this.framerate = 30,
    this.videoBitrateKbps = 2000,
    this.chatBufferSize = 100000,
    this.useTurn = true,
    this.turnServer,
    this.turnUsername,
    this.turnPassword,
  });

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.toJson(),
      'captureType': captureType.toJson(),
      'iterm2SessionId': iterm2SessionId,
      'cropRect': cropRect,
      'framerate': framerate,
      'videoBitrateKbps': videoBitrateKbps,
      'chatBufferSize': chatBufferSize,
      'useTurn': useTurn,
      'turnServer': turnServer,
      'turnUsername': turnUsername,
      'turnPassword': turnPassword,
    };
  }

  factory StreamSettings.fromJson(Map<String, dynamic> json) {
    return StreamSettings(
      mode: StreamModeExtension.fromJson((json['mode'] as String?) ?? 'video'),
      captureType: CaptureTargetTypeExtension.fromJson(
        (json['captureType'] as String?) ?? 'screen',
      ),
      iterm2SessionId: json['iterm2SessionId'] as String?,
      cropRect: _parseRect(json['cropRect']),
      framerate: (json['framerate'] as int?) ?? 30,
      videoBitrateKbps: (json['videoBitrateKbps'] as int?) ?? 2000,
      chatBufferSize: (json['chatBufferSize'] as int?) ?? 100000,
      useTurn: (json['useTurn'] as bool?) ?? true,
      turnServer: json['turnServer'] as String?,
      turnUsername: json['turnUsername'] as String?,
      turnPassword: json['turnPassword'] as String?,
    );
  }

  static Map<String, double>? _parseRect(dynamic any) {
    if (any is! Map) return null;
    final out = <String, double>{};
    for (final e in any.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (v is num) out[k] = v.toDouble();
    }
    return out.isEmpty ? null : out;
  }

  StreamSettings copyWith({
    StreamMode? mode,
    CaptureTargetType? captureType,
    String? iterm2SessionId,
    Map<String, double>? cropRect,
    int? framerate,
    int? videoBitrateKbps,
    int? chatBufferSize,
    bool? useTurn,
    String? turnServer,
    String? turnUsername,
    String? turnPassword,
  }) {
    return StreamSettings(
      mode: mode ?? this.mode,
      captureType: captureType ?? this.captureType,
      iterm2SessionId: iterm2SessionId ?? this.iterm2SessionId,
      cropRect: cropRect ?? this.cropRect,
      framerate: framerate ?? this.framerate,
      videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
      chatBufferSize: chatBufferSize ?? this.chatBufferSize,
      useTurn: useTurn ?? this.useTurn,
      turnServer: turnServer ?? this.turnServer,
      turnUsername: turnUsername ?? this.turnUsername,
      turnPassword: turnPassword ?? this.turnPassword,
    );
  }
}

