/// WebSocket message handler for daemon
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class MessageHandler {
  final Map<WebSocket, RTCPeerConnection> _peerConnections = {};
  final Map<WebSocket, MediaStream> _localStreams = {};
  int _frameCount = 0;
  Timer? _statsTimer;

  Future<void> handleMessage(String message, WebSocket ws) async {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;
      
      print('[WS] Received message type: $type');
      
      switch (type) {
        case 'echo':
          await _handleEcho(data, ws);
        case 'webrtc':
          await _handleWebRTC(data['data'], ws);
        case 'startLoopback':
          await _startLoopback(ws, data['data'] ?? {});
        case 'stopLoopback':
          await _stopLoopback(ws);
        case 'setRemoteDescription':
          await _setRemoteDescription(ws, data['data'] ?? {});
        case 'getSources':
          await _handleGetSources(ws);
        case 'captureFrame':
          await _handleCaptureFrame(data['data'], ws);
        default:
          _sendError(ws, 'Unknown message type: $type', id: data['id']);
      }
    } catch (e, stack) {
      print('[WS] Error handling message: $e');
      print('[WS] Stack: $stack');
      _sendError(ws, 'Invalid message format: $e');
    }
  }

  Future<void> _handleEcho(dynamic data, WebSocket ws) async {
    final payload = data['data'] ?? {};
    _sendResponse(ws, 'echo', {'echo': payload});
  }

  Future<void> _handleWebRTC(dynamic data, WebSocket ws) async {
    final action = data['action'] as String?;
    final payload = data['data'] ?? {};
    
    print('[WebRTC] Received action: $action');

    switch (action) {
      case 'startLoopback':
        await _startLoopback(ws, payload);
      case 'stopLoopback':
        await _stopLoopback(ws);
      case 'setRemoteDescription':
        await _setRemoteDescription(ws, payload);
      default:
        print('[WebRTC] Unknown action: $action');
        _sendError(ws, 'Unknown webrtc action: $action', id: data['id']);
    }
  }

  Future<void> _startLoopback(WebSocket ws, Map<String, dynamic> payload) async {
    try {
      print('[WebRTC] Starting loopback...');
      
      // Get display media (screen capture)
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'minFrameRate': '30',
          }
        },
        'audio': false
      });
      
      _localStreams[ws] = stream;
      print('[WebRTC] Got display media stream with ${stream.getVideoTracks().length} video tracks');

      // Create peer connection
      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ]
      });
      
      _peerConnections[ws] = pc;
      
      // Add tracks
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
        print('[WebRTC] Added track: ${track.kind} - ${track.id}');
      }
      
      // Set up frame counter
      _frameCount = 0;
      _startStatsTimer(ws);
      
      // Handle ICE candidates
      pc.onIceCandidate = (candidate) {
        if (candidate != null) {
          _sendMessage(ws, 'iceCandidate', {
            'candidate': candidate.toMap(),
          });
        }
      };
      
      // Create offer
      final offer = await pc.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': true,
        }
      });
      
      await pc.setLocalDescription(offer);
      
      print('[WebRTC] Created offer, sending to client');
      
      // Send offer to client
      _sendMessage(ws, 'startLoopback', {
        'success': true,
        'offer': {'type': offer.type, 'sdp': offer.sdp}
      });
      
      // Also send as 'offer' for compatibility
      _sendMessage(ws, 'offer', {
        'offer': {'type': offer.type, 'sdp': offer.sdp}
      });
      
    } catch (e, stack) {
      print('[WebRTC] Error starting loopback: $e');
      print('[WebRTC] Stack: $stack');
      _sendMessage(ws, 'startLoopback', {'success': false, 'error': e.toString()});
    }
  }

  Future<void> _setRemoteDescription(WebSocket ws, Map<String, dynamic> data) async {
    try {
      final pc = _peerConnections[ws];
      if (pc == null) {
        _sendError(ws, 'No peer connection found');
        return;
      }
      
      final answer = RTCSessionDescription(
        data['sdp'] as String? ?? '',
        data['type'] as String? ?? 'answer'
      );
      
      await pc.setRemoteDescription(answer);
      print('[WebRTC] Remote description set');
      
      _sendResponse(ws, 'setRemoteDescription', {'success': true});
      
      // Start simulating frame delivery
      _startFrameSimulation(ws);
      
    } catch (e) {
      print('[WebRTC] Error setting remote description: $e');
      _sendResponse(ws, 'setRemoteDescription', {'success': false, 'error': e.toString()});
    }
  }

  void _startFrameSimulation(WebSocket ws) {
    // Simulate video frames being generated
    Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      if (_peerConnections[ws] == null) {
        timer.cancel();
        return;
      }
      
      _frameCount++;
      if (_frameCount % 30 == 0) {
        print('[WebRTC] Generated $_frameCount frames');
      }
      
      // Send frame notification
      _sendMessage(ws, 'videoFrame', {
        'frameNumber': _frameCount,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _startStatsTimer(WebSocket ws) {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_peerConnections[ws] == null) {
        timer.cancel();
        return;
      }
      
      _sendMessage(ws, 'stats', {
        'frames': _frameCount,
        'fps': 30,
      });
    });
  }

  Future<void> _stopLoopback(WebSocket ws) async {
    try {
      _statsTimer?.cancel();
      
      final pc = _peerConnections.remove(ws);
      if (pc != null) {
        await pc.close();
      }
      
      final stream = _localStreams.remove(ws);
      if (stream != null) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
      }
      
      print('[WebRTC] Loopback stopped');
      _sendResponse(ws, 'stopLoopback', {'success': true});
      
    } catch (e) {
      print('[WebRTC] Error stopping loopback: $e');
      _sendResponse(ws, 'stopLoopback', {'success': false, 'error': e.toString()});
    }
  }

  Future<void> _handleGetSources(WebSocket ws) async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final sources = devices
          .where((d) => d.kind == 'videoinput')
          .map((d) => {'id': d.deviceId, 'name': d.label})
          .toList();
      
      _sendResponse(ws, 'getSources', {'sources': sources});
    } catch (e) {
      _sendError(ws, 'Failed to get sources: $e');
    }
  }

  Future<void> _handleCaptureFrame(Map<String, dynamic> data, WebSocket ws) async {
    // Placeholder for frame capture
    _sendResponse(ws, 'captureFrame', {'success': true});
  }

  void _sendMessage(WebSocket ws, String type, dynamic data) {
    try {
      final message = jsonEncode({
        'type': type,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      ws.add(message);
    } catch (e) {
      print('[WS] Error sending message: $e');
    }
  }

  void _sendResponse(WebSocket ws, String type, dynamic data, {String? id}) {
    try {
      final message = jsonEncode({
        'version': 1,
        'type': type,
        'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'success': true,
        'data': data,
      });
      ws.add(message);
    } catch (e) {
      print('[WS] Error sending response: $e');
    }
  }

  void _sendError(WebSocket ws, String error, {String? id}) {
    try {
      final message = jsonEncode({
        'version': 1,
        'type': 'error',
        'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'success': false,
        'error': {
          'code': 'error',
          'message': error,
          'details': null,
        },
      });
      ws.add(message);
    } catch (e) {
      print('[WS] Error sending error: $e');
    }
  }

  void dispose(WebSocket ws) {
    _stopLoopback(ws);
    _peerConnections.remove(ws);
    _localStreams.remove(ws);
  }
}
