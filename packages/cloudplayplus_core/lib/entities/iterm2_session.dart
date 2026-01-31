/// Information about an iTerm2 session (panel).
class ITerm2SessionInfo {
  final String sessionId;
  final String title;
  final String detail;
  final int index;
  final Map<String, double>? frame;
  final Map<String, double>? windowFrame;

  const ITerm2SessionInfo({
    required this.sessionId,
    required this.title,
    required this.detail,
    required this.index,
    this.frame,
    this.windowFrame,
  });

  factory ITerm2SessionInfo.fromJson(Map<String, dynamic> json) {
    return ITerm2SessionInfo(
      sessionId: json['id'] as String,
      title: json['title'] as String,
      detail: json['detail'] as String,
      index: json['index'] as int,
      frame: _parseRect(json['frame']),
      windowFrame: _parseRect(json['windowFrame']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': sessionId,
      'title': title,
      'detail': detail,
      'index': index,
      if (frame != null) 'frame': frame,
      if (windowFrame != null) 'windowFrame': windowFrame,
    };
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
}

