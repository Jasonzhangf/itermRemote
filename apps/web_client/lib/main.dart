import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

void main() {
  html.document.title = 'iTermRemote Web Client';
  final root = html.DivElement()..id = 'app';
  html.document.body!.append(root);

  final logBox = html.PreElement()
    ..id = 'log'
    ..style.height = '200px'
    ..style.overflowY = 'scroll'
    ..style.backgroundColor = '#111'
    ..style.color = '#0f0'
    ..style.padding = '8px';

  final status = html.DivElement()..text = 'Status: idle';
  final connectBtn = html.ButtonElement()..text = 'Connect Loopback';
  final disconnectBtn = html.ButtonElement()
    ..text = 'Disconnect'
    ..disabled = true;
  final video = html.VideoElement()
    ..autoplay = true
    ..playsInline = true
    ..style.width = '100%'
    ..style.backgroundColor = '#000';

  root..append(status)..append(connectBtn)..append(disconnectBtn)..append(video)..append(logBox);

  WebSocketClient? client;

  void log(String msg) {
    logBox.text += '${DateTime.now().toIso8601String()} $msg\n';
    logBox.scrollTop = logBox.scrollHeight;
  }

  connectBtn.onClick.listen((_) async {
    if (client != null) return;
    status.text = 'Status: connecting';
    connectBtn.disabled = true;
    disconnectBtn.disabled = false;
    log('Connecting to ws://127.0.0.1:8766');
    client = WebSocketClient(
      onLog: log,
      onStatus: (s) => status.text = 'Status: $s',
      onStream: (stream) {
        video.srcObject = stream;
      },
    );
    await client!.connect();
  });

  disconnectBtn.onClick.listen((_) {
    client?.dispose();
    client = null;
    status.text = 'Status: idle';
    connectBtn.disabled = false;
    disconnectBtn.disabled = true;
  });
}

class WebSocketClient {
  WebSocketClient({required this.onLog, required this.onStatus, required this.onStream});

  final void Function(String message) onLog;
  final void Function(String status) onStatus;
  final void Function(html.MediaStream stream) onStream;

  html.WebSocket? _socket;
  html.RtcPeerConnection? _peer;
  final _pendingMessages = StreamController<String>.broadcast();

  Future<void> connect() async {
    _socket = html.WebSocket('ws://127.0.0.1:8766');
    _socket!.onOpen.listen((_) {
      onLog('WebSocket open');
      onStatus('ws_connected');
      _setupPeer();
    });
    _socket!.onMessage.listen((event) {
      onLog('WS <= ${event.data}');
      _pendingMessages.add(event.data as String);
      _handleMessage(event.data as String);
    });
    _socket!.onClose.listen((_) {
      onLog('WebSocket closed');
      onStatus('ws_closed');
    });
    _socket!.onError.listen((_) {
      onLog('WebSocket error');
      onStatus('ws_error');
    });
  }

  Future<void> _setupPeer() async {
    _peer = html.RtcPeerConnection({
      'iceServers': [],
    });

    _peer!.onTrack.listen((event) {
      if (event.streams.isNotEmpty) {
        onLog('Got remote stream');
        onStream(event.streams.first);
      }
    });

    _peer!.onIceCandidate.listen((event) {
      if (event.candidate != null) {
        _send({'type': 'ice', 'candidate': event.candidate!.candidate, 'sdpMid': event.candidate!.sdpMid, 'sdpMLineIndex': event.candidate!.sdpMLineIndex});
      }
    });

    final offer = await _peer!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peer!.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp});
  }

  void _handleMessage(String message) async {
    final data = jsonDecode(message) as Map<String, dynamic>;
    switch (data['type']) {
      case 'answer':
        final desc = html.RtcSessionDescription(data['sdp'] as String, 'answer');
        await _peer?.setRemoteDescription(desc);
        break;
      case 'ice':
        final candidate = html.RtcIceCandidate(data['candidate'] as String, data['sdpMid'] as String?, data['sdpMLineIndex'] as int?);
        await _peer?.addIceCandidate(candidate);
        break;
      default:
        onLog('Unhandled message: $data');
    }
  }

  void _send(Map<String, dynamic> payload) {
    final msg = jsonEncode(payload);
    onLog('WS => $msg');
    _socket?.send(msg);
  }

  void dispose() {
    _peer?.close();
    _socket?.close();
    _pendingMessages.close();
  }
}
