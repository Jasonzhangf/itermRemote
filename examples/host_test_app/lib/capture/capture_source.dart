import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CaptureMode { desktop, window, iterm2Panel }

class CapturableWindow {
  final String id;
  final String title;
  final Uint8List? thumbnail;
  final ThumbnailSize? thumbnailSize;

  const CapturableWindow({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.thumbnailSize,
  });
}

class CapturableScreen {
  final String id;
  final String title;
  final Uint8List? thumbnail;
  final ThumbnailSize? thumbnailSize;

  const CapturableScreen({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.thumbnailSize,
  });
}

class Iterm2PanelItem {
  final String sessionId;
  final String title;
  final String detail;
  final Map<String, double>? cropRectNorm;
  final String? windowSourceId;
  final Uint8List? windowThumbnail;

  const Iterm2PanelItem({
    required this.sessionId,
    required this.title,
    required this.detail,
    required this.cropRectNorm,
    required this.windowSourceId,
    required this.windowThumbnail,
  });
}
