# Architecture

## Overview

iTerm2 Remote Streaming Service consists of three main modules:

1. **cloudplayplus_core** - Shared data models and types
2. **iterm2_host** - macOS host service with iTerm2 Python API bridge
3. **android_client** - Flutter Android client app

## Module Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Android Client (Flutter)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ ConnectPage  │  │StreamingPage │  │  ChatPage    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└───────────────────────────┬─────────────────────────────────┘
                            │ WebRTC / Data Channel
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                    macOS Host (Dart)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ StreamHost   │  │ITerm2Bridge  │  │ Python API   │      │
│  │   (WebRTC)   │◄─┤   (Bridge)   │◄─┤  (Mocked)    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Video Streaming Mode

1. Host captures iTerm2 panel (via screen capture)
2. Encodes to WebRTC video track
3. Client renders via RTCVideoRenderer

### Chat Mode

1. Client composes text in ChatInputField
2. Sends via RTCDataChannel to host
3. Host injects text to iTerm2 session via Python API
4. Host reads session buffer and sends back via data channel

## Core Entities

### StreamSettings
- `mode`: video or chat
- `captureType`: screen, window, or iterm2Panel
- `iterm2SessionId`: target session for iTerm2 panel capture
- `cropRect`: region of interest coordinates
- `framerate`: video fps
- `videoBitrateKbps`: video bitrate
- `turnServer`: optional TURN server configuration

### ITerm2SessionInfo
- `sessionId`: unique identifier
- `title`: session display name
- `detail`: session details (e.g., shell type)
- `index`: session index
- `frame`: current frame bounds
- `windowFrame`: window bounds

## Testing Strategy

- Unit tests for each module (flutter test)
- Integration tests for bridge and settings (test/integration)
- E2E tests via scripts/test/run_e2e.sh
- Mock Python scripts for deterministic testing

## Future Extensions

- Real iTerm2 Python API integration
- WebRTC signaling server
- TURN server support
- Multi-session streaming
- Session history and replay

