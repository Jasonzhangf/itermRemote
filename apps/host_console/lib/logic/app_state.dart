import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/connection_model.dart';
import '../services/ws_client.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

/// Global application state with real WebSocket connection to daemon
class AppState extends ChangeNotifier {
  // Connection
  final List<ConnectionModel> connections = [];
  ConnectionModel? activeConnection;
  
  // WebSocket client
  WsClient? _wsClient;
  bool _isConnected = false;
  String? _errorMessage;
  
  // Stream state
  bool isStreaming = false;
  CaptureMode captureMode = CaptureMode.iterm2Panel;
  
  // iTerm2 panels (now from real daemon)
  final List<PanelInfo> panels = [];
  PanelInfo? selectedPanel;
  bool _isLoadingPanels = false;
  
  // Stats
  StreamStats? streamStats;
  
  // Getters
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  bool get isLoadingPanels => _isLoadingPanels;
  WsClient? get wsClient => _wsClient;

  AppState() {
    // Add local daemon connection
    connections.add(const ConnectionModel(
      id: 'local-daemon',
      name: 'Local Daemon',
      host: 'localhost',
      port: 8766,
      status: ConnectionStatus.disconnected,
      type: ConnectionType.host,
    ));
    activeConnection = connections.first;
  }

  /// Connect to the daemon via WebSocket
  Future<void> connect() async {
    if (_isConnected) return;
    
    final conn = activeConnection;
    if (conn == null) return;
    
    try {
      _errorMessage = null;
      notifyListeners();
      
      final url = 'ws://${conn.host}:${conn.port}';
      _wsClient = WsClient(url: url);
      await _wsClient!.connect();
      
      // Subscribe to events
      _wsClient!.eventStream.listen(_handleEvent);
      
      _isConnected = true;
      _updateConnectionStatus(ConnectionStatus.connected);
      
      // Fetch panels after connection
      await refreshPanels();
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _isConnected = false;
      _updateConnectionStatus(ConnectionStatus.error);
      notifyListeners();
    }
  }

  /// Disconnect from daemon
  Future<void> disconnect() async {
    _wsClient?.close();
    _wsClient = null;
    _isConnected = false;
    _updateConnectionStatus(ConnectionStatus.disconnected);
    panels.clear();
    notifyListeners();
  }

  /// Refresh panels from daemon via ITerm2Block
  Future<void> refreshPanels() async {
    if (!_isConnected || _wsClient == null) return;
    
    _isLoadingPanels = true;
    notifyListeners();
    
    try {
      final cmd = Command(
        version: 1,
        id: 'get-sessions-${DateTime.now().millisecondsSinceEpoch}',
        target: 'iterm2',
        action: 'getSessions',
      );
      
      final ack = await _wsClient!.sendCommand(cmd);
      
      if (ack.success) {
        final sessions = ack.data?['sessions'] as List<dynamic>?;
        if (sessions != null) {
          panels.clear();
          for (var i = 0; i < sessions.length; i++) {
            final s = sessions[i] as Map<String, dynamic>;
            panels.add(PanelInfo(
              id: s['id'] ?? 'panel-$i',
              title: s['name'] ?? 'Panel $i',
              detail: '${s['profileName'] ?? ''} · ${s['command'] ?? ''}',
              index: i,
              frame: const Rect(0, 0, 0, 0), // Will be populated via getCropMeta
              isActive: s['isActive'] ?? false,
            ));
          }
        }
      } else {
        _errorMessage = 'Failed to get panels: ${ack.error?.message ?? 'unknown error'}';
      }
    } catch (e) {
      _errorMessage = 'Error refreshing panels: $e';
    } finally {
      _isLoadingPanels = false;
      notifyListeners();
    }
  }

  /// Activate a panel via ITerm2Block
  Future<void> activatePanel(PanelInfo panel) async {
    if (!_isConnected || _wsClient == null) return;
    
    try {
      final cmd = Command(
        version: 1,
        id: 'activate-${DateTime.now().millisecondsSinceEpoch}',
        target: 'iterm2',
        action: 'activateSession',
        payload: {'sessionId': panel.id},
      );
      
      final ack = await _wsClient!.sendCommand(cmd);
      
      if (ack.success) {
        selectedPanel = panel;
        // Update active status
        for (var i = 0; i < panels.length; i++) {
          final p = panels[i];
          panels[i] = PanelInfo(
            id: p.id,
            title: p.title,
            detail: p.detail,
            index: p.index,
            frame: p.frame,
            isActive: p.id == panel.id,
          );
        }
        notifyListeners();
      } else {
        _errorMessage = 'Failed to activate panel: ${ack.error?.message ?? 'unknown error'}';
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Error activating panel: $e';
      notifyListeners();
    }
  }

  void _handleEvent(Event event) {
    // Handle daemon events (e.g., panel changes, stream updates)
    if (event.event == 'activated') {
      // Refresh panels when a session is activated elsewhere
      refreshPanels();
    }
  }

  void _updateConnectionStatus(ConnectionStatus status) {
    if (activeConnection != null) {
      final idx = connections.indexWhere((c) => c.id == activeConnection!.id);
      if (idx >= 0) {
        connections[idx] = ConnectionModel(
          id: activeConnection!.id,
          name: activeConnection!.name,
          host: activeConnection!.host,
          port: activeConnection!.port,
          status: status,
          type: activeConnection!.type,
        );
        activeConnection = connections[idx];
      }
    }
  }

  void setActiveConnection(ConnectionModel? conn) {
    activeConnection = conn;
    notifyListeners();
  }

  void setCaptureMode(CaptureMode mode) {
    captureMode = mode;
    notifyListeners();
  }

  void setSelectedPanel(PanelInfo? panel) {
    selectedPanel = panel;
    notifyListeners();
  }

  void setStreaming(bool streaming) {
    isStreaming = streaming;
    notifyListeners();
  }

  void updateStats(StreamStats stats) {
    streamStats = stats;
    notifyListeners();
  }
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsClient?.close();
    super.dispose();
  }
}

class StreamStats {
  final double fps;
  final int bitrate;
  final int width;
  final int height;
  final int latency;

  const StreamStats({
    required this.fps,
    required this.bitrate,
    required this.width,
    required this.height,
    required this.latency,
  });
}
