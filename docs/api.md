# API (Draft)

This document describes the planned API surface between Android client and macOS host.

## Transport

- WebRTC PeerConnection for media (video) and data channel (chat + control).
- Signaling is out-of-scope in Phase 4 and will be added later.

## Messages

All control and chat messages should be JSON objects encoded as UTF-8 text over a WebRTC data channel.

### Start Stream

```json
{
  "type": "startStream",
  "settings": {
    "mode": "video",
    "captureType": "iterm2Panel",
    "iterm2SessionId": "sess-1",
    "cropRect": {"x": 0, "y": 0, "width": 800, "height": 600},
    "framerate": 30,
    "videoBitrateKbps": 2000,
    "useTurn": true,
    "turnServer": "turn:example.com:3478",
    "turnUsername": "u",
    "turnPassword": "p"
  }
}
```

### Stop Stream

```json
{ "type": "stopStream" }
```

### Switch Capture Target

```json
{ "type": "switchCaptureTarget", "captureType": "window", "windowId": "..." }
```

### Send Chat Text (One-shot)

```json
{ "type": "sendChat", "sessionId": "sess-1", "text": "hello\nworld" }
```

### Read Chat Buffer

```json
{ "type": "readBuffer", "sessionId": "sess-1", "maxBytes": 100000 }
```

### Host Replies

```json
{ "type": "ok" }
```

```json
{ "type": "buffer", "sessionId": "sess-1", "text": "..." }
```

```json
{ "type": "error", "message": "..." }
```

