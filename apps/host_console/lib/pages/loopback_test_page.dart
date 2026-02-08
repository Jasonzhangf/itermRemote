import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../services/ws_client.dart';

/// Loopback test page: connects to daemon and runs WebRTC loopback test.
///
/// Flow:
/// 1. Connect to daemon WebSocket
/// 2. List iTerm2 sessions
/// 3. Select a session
/// 4. Start WebRTC loopback (daemon handles capture + encoding)
/// 5. Receive video track and display
class LoopbackTestPage extends StatefulWidget {
  const LoopbackTestPage({super.key});

  @override
  State<LoopbackTestPage> createState() => _LoopbackTestPageState();
}

class _LoopbackTestPageState extends State<LoopbackTestPage> {
  WsClient? _wsClient;
  bool _connected = false;
  List<Map<String, dynamic>> _sessions = [];
  String? _selectedSessionId;
  bool _isLoading = false;
  String? _error;

  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _connectToDaemon();
  }

  @override
  void dispose() {
    _pc?.close();
    _remoteRenderer.dispose();
    _wsClient?.close();
    super.dispose();
  }

  Future<void> _connectToDaemon() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = 'ws://127.0.0.1:8766';
      _wsClient = WsClient(url: url);
      await _wsClient!.connect();

      setState(() {
        _connected = true;
        _isLoading = false;
      });

      // Auto-load sessions
      await _loadSessions();
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSessions() async {
    if (_wsClient == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ack = await _wsClient!.sendCommand(
        Command(
          version: itermremoteProtocolVersion,
          id: _generateId(),
          target: 'iterm2',
          action: 'listSessions',
        ),
      );

      if (ack.success && ack.data != null) {
        final list = ack.data!['sessions'] as List?;
        if (list != null) {
          setState(() {
            _sessions = list.map((e) => e as Map<String, dynamic>).toList();
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = ack.error?.message ?? 'Failed to list sessions';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load sessions: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startLoopback() async {
    if (_wsClient == null || _selectedSessionId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Step 1: ask daemon CaptureBlock to activate panel and return crop meta
      final activateAck = await _wsClient!.sendCommand(
        Command(
          version: itermremoteProtocolVersion,
          id: _generateId(),
          target: 'capture',
          action: 'activateAndComputeCrop',
          payload: {'sessionId': _selectedSessionId},
        ),
      );

      if (!activateAck.success) {
        setState(() {
          _error = 'Failed to activate/crop: ${activateAck.error?.message}';
          _isLoading = false;
        });
        return;
      }

      final meta = activateAck.data?['meta'] as Map?;
      if (meta == null) {
        setState(() {
          _error = 'activateAndComputeCrop did not return meta';
          _isLoading = false;
        });
        return;
      }

      final cgWindowId = meta['cgWindowId'];
      final cropMeta = {
        'cgWindowId': cgWindowId,
        'frame': meta['frame'],
        'rawWindowFrame': meta['rawWindowFrame'],
        'windowFrame': meta['windowFrame'],
      };

      // Compute normalized crop rect in captured frame coordinates
      // (same math as VerifyBlock cropping)
      final f = (cropMeta['frame'] as Map?) ?? const {};
      final wf = (cropMeta['rawWindowFrame'] as Map?) ?? const {};
      final fx = (f['x'] as num?)?.toDouble() ?? 0.0;
      final fy = (f['y'] as num?)?.toDouble() ?? 0.0;
      final fw = (f['w'] as num?)?.toDouble() ?? 0.0;
      final fh = (f['h'] as num?)?.toDouble() ?? 0.0;
      final ww = (wf['w'] as num?)?.toDouble() ?? 1.0;
      final wh = (wf['h'] as num?)?.toDouble() ?? 1.0;
      final cropRect = {
        'x': (fx / ww).clamp(0.0, 1.0),
        'y': (fy / wh).clamp(0.0, 1.0),
        'w': (fw / ww).clamp(0.0, 1.0),
        'h': (fh / wh).clamp(0.0, 1.0),
      };

      // Step 2: start loopback capture in daemon
      final loopAck = await _wsClient!.sendCommand(
        Command(
          version: itermremoteProtocolVersion,
          id: _generateId(),
          target: 'webrtc',
          action: 'startLoopback',
          payload: {
            'sourceType': 'window',
            'sourceId': cgWindowId?.toString(),
            'cropRect': cropRect,
            'fps': 30,
            'bitrateKbps': 1000,
          },
        ),
      );

      if (!loopAck.success) {
        setState(() {
          _error = 'Failed to start daemon loopback: ${loopAck.error?.message}';
          _isLoading = false;
        });
        return;
      }

      // Step 3: connect signaling (daemon is offerer)
      final offerAck = await _wsClient!.sendCommand(
        Command(
          version: itermremoteProtocolVersion,
          id: _generateId(),
          target: 'webrtc',
          action: 'createOffer',
        ),
      );
      final offerSdp = offerAck.data?['sdp'];
      if (!offerAck.success || offerSdp is! String || offerSdp.isEmpty) {
        setState(() {
          _error = 'Failed to get offer from daemon';
          _isLoading = false;
        });
        return;
      }

      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };

      _pc = await createPeerConnection(config);
      _pc!.onTrack = (event) {
        if (event.track.kind == 'video') {
          _remoteRenderer.srcObject = event.streams[0];
          setState(() {});
        }
      };

      await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      final setAnswerAck = await _wsClient!.sendCommand(
        Command(
          version: itermremoteProtocolVersion,
          id: _generateId(),
          target: 'webrtc',
          action: 'setRemoteDescription',
          payload: {'type': 'answer', 'sdp': answer.sdp},
        ),
      );
      if (!setAnswerAck.success) {
        setState(() {
          _error = 'Failed to send answer to daemon: ${setAnswerAck.error?.message}';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loopback started for session: $_selectedSessionId'),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to start loopback: $e';
        _isLoading = false;
      });
    }
  }

  String _generateId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Loopback Test'),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSessions,
              tooltip: 'Refresh Sessions',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _connectToDaemon,
              child: const Text('Retry Connection'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_connected) {
      return const Center(child: Text('Connecting to daemon...'));
    }

    return Row(
      children: [
        // Left panel: Session list
        SizedBox(
          width: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'iTerm2 Sessions (${_sessions.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final sessionId = session['sessionId'] as String;
                    final title = session['title'] as String;
                    final isSelected = sessionId == _selectedSessionId;

                    return ListTile(
                      title: Text(title),
                      subtitle: Text(sessionId, style: const TextStyle(fontSize: 10)),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedSessionId = sessionId;
                        });
                      },
                    );
                  },
                ),
              ),
              if (_selectedSessionId != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    onPressed: _startLoopback,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Loopback'),
                  ),
                ),
            ],
          ),
        ),

        // Right panel: Video preview
        Expanded(
          child: Container(
            color: Colors.black,
            child: _pc == null
                ? const Center(
                    child: Text(
                      'Select a session and start loopback',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : RTCVideoView(_remoteRenderer),
          ),
        ),
      ],
    );
  }
}
