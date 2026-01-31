/// Capture target type for streaming.
enum CaptureTargetType {
  screen,
  window,
  iterm2Panel,
}

extension CaptureTargetTypeExtension on CaptureTargetType {
  String toJson() => name;
  static CaptureTargetType fromJson(String value) =>
      CaptureTargetType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => CaptureTargetType.screen,
      );
}

