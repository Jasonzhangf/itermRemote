/// Connection model - immutable data class
class ConnectionModel {
  final String id;
  final String name;
  final String host;
  final int port;
  final ConnectionStatus status;
  final ConnectionType type;
  final DateTime? lastConnected;
  final String? errorMessage;

  const ConnectionModel({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8765,
    this.status = ConnectionStatus.disconnected,
    this.type = ConnectionType.host,
    this.lastConnected,
    this.errorMessage,
  });

  ConnectionModel copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    ConnectionStatus? status,
    ConnectionType? type,
    DateTime? lastConnected,
    String? errorMessage,
  }) {
    return ConnectionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      status: status ?? this.status,
      type: type ?? this.type,
      lastConnected: lastConnected ?? this.lastConnected,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum ConnectionType {
  host,      // Host daemon
  direct,    // Direct WebRTC
}

/// Capture mode for streaming
enum CaptureMode {
  screen,      // Full screen
  window,      // Specific window
  iterm2Panel, // iTerm2 panel crop
}

/// Panel info from iTerm2
class PanelInfo {
  final String id;
  final String title;
  final String detail;
  final int index;
  final Rect frame;
  final bool isActive;

  const PanelInfo({
    required this.id,
    required this.title,
    required this.detail,
    required this.index,
    required this.frame,
    this.isActive = false,
  });
}

class Rect {
  final double x, y, width, height;
  const Rect(this.x, this.y, this.width, this.height);
}
