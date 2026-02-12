import 'dart:async';
import 'dart:convert';
import 'auth_service.dart';
import 'remote_ws_service.dart';

/// WebRTC signaling service using server relay
class SignalingService {
  SignalingService._();
  static final SignalingService instance = SignalingService._();

  bool _isConnecting = false;
  String? _targetDeviceId;
  
  Function(String, dynamic)? onSignalingMessage;

  Future<void> connectToDevice(String deviceId) async {
    if (_isConnecting) {
      throw StateError('Already connecting');
    }
    
    _isConnecting = true;
    _targetDeviceId = deviceId;

    // Ensure remote WS is connected
    if (!RemoteWsService.instance.isConnected) {
      await RemoteWsService.instance.connect();
    }

    // Send connection request via relay
    RemoteWsService.instance.sendProxy(
      channel: 'webrtc-connect-request',
      payload: {
        'target_device': deviceId,
        'action': 'request_connection',
      },
      target: deviceId,
    );

    // Listen for signaling messages
    RemoteWsService.instance.messageStream.listen(_handleSignalingMessage);
  }

  void _handleSignalingMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'proxy') return;
    
    final channel = msg['channel'] as String?;
    final payload = msg['payload'];
    
    if (channel?.startsWith('webrtc-') ?? false) {
      onSignalingMessage?.call(channel!, payload);
    }
  }

  void sendOffer(String sdp) {
    if (_targetDeviceId == null) return;
    
    RemoteWsService.instance.sendProxy(
      channel: 'webrtc-offer',
      payload: {'sdp': sdp},
      target: _targetDeviceId!,
    );
  }

  void sendAnswer(String sdp) {
    if (_targetDeviceId == null) return;
    
    RemoteWsService.instance.sendProxy(
      channel: 'webrtc-answer',
      payload: {'sdp': sdp},
      target: _targetDeviceId!,
    );
  }

  void sendCandidate(Map<String, dynamic> candidate) {
    if (_targetDeviceId == null) return;
    
    RemoteWsService.instance.sendProxy(
      channel: 'webrtc-candidate',
      payload: candidate,
      target: _targetDeviceId!,
    );
  }

  void disconnect() {
    _isConnecting = false;
    _targetDeviceId = null;
  }
}
