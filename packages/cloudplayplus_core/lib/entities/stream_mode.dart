/// Streaming mode: video (real-time capture) or chat (text buffer).
enum StreamMode {
  video,
  chat,
}

extension StreamModeExtension on StreamMode {
  String toJson() => name;
  static StreamMode fromJson(String value) => StreamMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => StreamMode.video,
      );
}

