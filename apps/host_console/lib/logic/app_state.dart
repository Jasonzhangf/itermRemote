import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:itermremote_protocol/itermremote_protocol.dart";
import "../models/connection_model.dart";
import "../services/ws_client.dart";
import "../services/daemon_manager.dart";
import "../services/device_service.dart";
import "dart:async";

/// Global application state with real WebSocket + WebRTC connection to daemon
class AppState extends ChangeNotifier {
  // Connection
  final List<ConnectionModel> connections = [];
  ConnectionModel? activeConnection;

  WsClient? _wsClient;
  bool _isConnected = false;
  String _lastStatus = "disconnected";

  // Device status reporting
  Timer? _statusReportTimer;

  // iTerm2 panels (now from real daemon)
  List<PanelInfo> panels = [];

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;
  String? _capturePreviewPath;
  MediaStream? _capturePreviewStream;
  bool _isStreaming = false;
  CaptureMode _captureMode = CaptureMode.screen;
  PanelInfo? _selectedPanel;
  StreamStats? _streamStats;

  // UI state
  bool _isLoadingPanels = false;
  String? _errorMessage;

  bool get isConnected => _isConnected;
  String get lastStatus => _lastStatus;
  WsClient? get wsClient => _wsClient;
  bool get isStreaming => _isStreaming;
  CaptureMode get captureMode => _captureMode;
  PanelInfo? get selectedPanel => _selectedPanel;
  StreamStats? get streamStats => _streamStats;
  MediaStream? get remoteStream => _remoteStream;
  String? get capturePreviewPath => _capturePreviewPath;
  MediaStream? get capturePreviewStream => _capturePreviewStream;
  bool get isLoadingPanels => _isLoadingPanels;
  String? get errorMessage => _errorMessage;

  AppState() {
    connections.add(const ConnectionModel(
      id: "local-daemon",
      name: "Local Daemon",
      host: "127.0.0.1",
      port: 8766,
      status: ConnectionStatus.disconnected,
      type: ConnectionType.host,
    ));
    activeConnection = connections.first;
  }

  /// Resolve local IP for daemon connection (IPv6 -> Tailscale -> LAN IPv4)
  Future<String> _resolveLocalConnectIp() async {
    try {
      final interfaces = await NetworkInterface.list(includeLinkLocal: false, includeLoopback: false);

      final ipv6 = <String>[];
      final ipv4Ts = <String>[];
      final ipv4Lan = <String>[];

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final address = addr.address;
          if (addr.type == InternetAddressType.IPv6) {
            ipv6.add(address);
          } else if (addr.type == InternetAddressType.IPv4) {
            if (interface.name.contains('tailscale') ||
                interface.name.contains('ts0') ||
                address.startsWith('100.')) {
              ipv4Ts.add(address);
            } else {
              ipv4Lan.add(address);
            }
          }
        }
      }

      if (ipv6.isNotEmpty) return ipv6.first;
      if (ipv4Ts.isNotEmpty) return ipv4Ts.first;
      if (ipv4Lan.isNotEmpty) return ipv4Lan.first;
    } catch (_) {}

    return "127.0.0.1";
  }

  /// Connect to the daemon via WebSocket + WebRTC
  Future<void> connect() async {
    if (_isConnected) return;

    final conn = activeConnection;
    if (conn == null) return;

    _updateConnectionStatus(ConnectionStatus.connecting, "connecting");

    try {
      // Ensure daemon is healthy before attempting WS connection
      final daemonHealthy = await DaemonManager().ensureHealthy();
      if (!daemonHealthy) {
        _lastStatus = "daemon not healthy";
        _errorMessage = "daemon not healthy";
        _updateConnectionStatus(ConnectionStatus.error, "daemon not healthy");
        notifyListeners();
        return;
      }

      final ip = await _resolveLocalConnectIp();
      final url = "ws://$ip:${conn.port}";
      _wsClient = WsClient(url: url);
      await _wsClient!.connect();

      _isConnected = true;
      _lastStatus = "connected";
      _updateConnectionStatus(ConnectionStatus.connected, "connected");

      await _startStatusReporting();
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _lastStatus = "failed: $e";
      _errorMessage = e.toString();
      _updateConnectionStatus(ConnectionStatus.error, "error");
      notifyListeners();
    }
  }

  Future<void> _createPeerConnection() async {
    print("[WebRTC] Creating peer connection");
    _peerConnection = await createPeerConnection({
      "iceServers": [{"urls": "stun:stun.l.google.com:19302"}],
    });

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print("[WebRTC] onTrack fired! streams=${event.streams.length}");
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        print("[WebRTC] received remote stream - ID: ${_remoteStream!.id}");
        _streamStats ??= const StreamStats(fps: 30, width: 0, height: 0, bitrate: 0, latency: 0);
        notifyListeners();
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      print("[WebRTC] ICE candidate: ${candidate.candidate}");
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print("[WebRTC] Connection state: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _isStreaming = false;
        notifyListeners();
      }
    };
  }

  Future<Ack?> _sendCommand(String target, String action, Map<String, dynamic> payload) async {
    if (_wsClient == null) return null;
    final cmd = Command(
      version: itermremoteProtocolVersion,
      id: "cmd-${DateTime.now().millisecondsSinceEpoch}",
      action: action,
      target: target,
      payload: payload,
    );
    return await _wsClient!.sendCommand(cmd);
  }

  Future<void> _handleSignaling(Map<String, dynamic> data) async {
    final type = data["type"];
    final sdp = data["sdp"];
    print("[WebRTC] Handling signaling: type=$type");
    if (type == "offer" && sdp != null) {
      print("[WebRTC] Setting remote description (offer)");
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
      print("[WebRTC] Creating answer");
      final answer = await _peerConnection!.createAnswer();
      print("[WebRTC] Setting local description (answer)");
      await _peerConnection!.setLocalDescription(answer);
      print("[WebRTC] Sending answer to daemon");
      await _sendCommand("webrtc", "setRemoteDescription", {
        "type": "answer",
        "sdp": answer.sdp,
      });
      _isStreaming = true;
      notifyListeners();
    }
  }

  Future<void> loadCapturePreview() async {
    if (_wsClient == null) return;
    final evidenceDir = '/tmp/itermremote-preview';
    final cropMetaAck = await _sendCommand('capture', 'activateAndComputeCrop', {
      'sessionId': _selectedPanel?.id ?? '',
    });
    final meta = cropMetaAck?.data?['meta'];
    if (meta == null) return;

    final previewAck = await _sendCommand('verify', 'captureEvidence', {
      'evidenceDir': evidenceDir,
      'cropMeta': meta,
      'sessionId': _selectedPanel?.id ?? '',
    });
    final evidencePath = previewAck?.data?['evidencePath'] as String?;
    if (evidencePath == null) return;
    _capturePreviewPath = evidencePath;
    notifyListeners();
  }

  void _updateConnectionStatus(ConnectionStatus status, String message) {
    final conn = activeConnection;
    if (conn == null) return;

    final index = connections.indexOf(conn);
    connections[index] = conn.copyWith(
      status: status,
      errorMessage: message,
      lastConnected: status == ConnectionStatus.connected
          ? DateTime.now()
          : conn.lastConnected,
    );
    activeConnection = connections[index];
  }

  void setStreaming(bool streaming) {
    if (streaming && !_isStreaming) {
      if (_capturePreviewPath == null) {
        _errorMessage = "capture preview required before streaming";
        notifyListeners();
        return;
      }
      _startStreaming();
    } else if (!streaming && _isStreaming) {
      _isStreaming = false;
      _remoteStream = null;
      notifyListeners();
    }
  }

  Future<void> _startStreaming() async {
    if (_wsClient == null) {
      await connect();
    }
    if (_wsClient == null) return;

    if (_peerConnection == null) {
      await _createPeerConnection();
    }

    // Start loopback on daemon (encoded stream) after preview success
    await _sendCommand("webrtc", "startLoopback", {
      "sourceType": "screen",
      "fps": 30,
      "bitrateKbps": 2000,
    });

    // Request offer
    final offerAck = await _sendCommand("webrtc", "createOffer", {});
    if (offerAck?.data != null) {
      final data = offerAck!.data!;
      final type = data['type'];
      final sdp = data['sdp'];
      if (type is String && sdp is String) {
        await _handleSignaling({"type": type, "sdp": sdp});
      }
    }
  }

  void setCaptureMode(CaptureMode mode) {
    _captureMode = mode;
    _selectedPanel = null;
    _isStreaming = false;
    _remoteStream = null;
    _capturePreviewPath = null;
    notifyListeners();
  }

  void selectPanel(PanelInfo panel) {
    _selectedPanel = panel;
    _captureMode = CaptureMode.iterm2Panel;
    _isStreaming = false;
    _remoteStream = null;
    _capturePreviewPath = null;
    notifyListeners();
  }

  Future<void> refreshPanels() async {
    if (_wsClient == null) return;
    _isLoadingPanels = true;
    notifyListeners();
    final ack = await _sendCommand("iterm2", "getSessions", {});
    if (ack?.data != null) {
      final sessions = ack!.data!['sessions'] as List? ?? [];
      panels = _mapSessionsToPanels(sessions);
    }
    _isLoadingPanels = false;
    notifyListeners();
  }

  List<PanelInfo> _mapSessionsToPanels(List sessions) {
    final result = <PanelInfo>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i] as Map;
      final id = s['sessionId'] ?? s['id'] ?? 'session-$i';
      final title = s['title'] ?? 'Session';
      final detail = s['connectionId'] ?? '';
      final frame = s['frame'] as Map? ?? {};
      result.add(PanelInfo(
        id: id.toString(),
        title: title.toString(),
        detail: detail.toString(),
        index: i,
        frame: Rect(
          (frame['x'] ?? 0).toDouble(),
          (frame['y'] ?? 0).toDouble(),
          (frame['w'] ?? frame['width'] ?? 0).toDouble(),
          (frame['h'] ?? frame['height'] ?? 0).toDouble(),
        ),
      ));
    }
    return result;
  }

  Future<void> activatePanel(PanelInfo panel) async {
    if (_wsClient == null) return;
    await _sendCommand("iterm2", "activateSession", {"sessionId": panel.id});
    await _refreshCapturePreview();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void disconnect() {
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    _capturePreviewPath = null;
    _wsClient?.close();
    _wsClient = null;
    _isConnected = false;
    _lastStatus = "disconnected";
    _isStreaming = false;
    _updateConnectionStatus(ConnectionStatus.disconnected, "disconnected");
    _stopStatusReporting();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStatusReporting();
    _peerConnection?.close();
    _wsClient?.close();
    super.dispose();
  }

  Future<void> _startStatusReporting() async {
    await DeviceService.instance.reportDeviceStatus(isOnline: true);
    _statusReportTimer?.cancel();
    _statusReportTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => DeviceService.instance.reportDeviceStatus(isOnline: true),
    );
  }

  Future<void> _refreshCapturePreview() async {
    if (_wsClient == null) return;
    final evidenceDir = '/tmp/itermremote-preview';
    final sessionId = _selectedPanel?.id;
    if (sessionId == null || sessionId.isEmpty) return;

    final activateAck = await _sendCommand('capture', 'activateAndComputeCrop', {
      'sessionId': sessionId,
    });
    final meta = activateAck?.data?['meta'];
    if (meta == null) return;

    final captureAck = await _sendCommand('verify', 'captureEvidence', {
      'evidenceDir': evidenceDir,
      'sessionId': sessionId,
      'cropMeta': meta,
    });
    final croppedPng = captureAck?.data?['croppedPng'] as String?;
    if (croppedPng == null) return;
    _capturePreviewPath = croppedPng;
    notifyListeners();
  }

  void _stopStatusReporting() {
    DeviceService.instance.reportDeviceStatus(isOnline: false);
    _statusReportTimer?.cancel();
    _statusReportTimer = null;
  }
}
