# cloudplayplus_core

## Module Overview

Shared core library for iTerm2 remote streaming. Contains models, protocol definitions, and utilities reused by host and client.

## Architecture

```
Dart/Flutter module with lib/.
Contains domain/entities definitions.
Contains service-layer logic.
Has module-local tests.
```

## File Structure

### lib/cloudplayplus_core.dart

Shared core library for iTerm2 remote streaming.

### lib/entities/capture_target.dart

Capture target type for streaming.

### lib/entities/iterm2_session.dart

Information about an iTerm2 session (panel).

### lib/entities/stream_mode.dart

Streaming mode: video (real-time capture) or chat (text buffer).

### lib/entities/stream_settings.dart

No documentation available.

### test/entities/capture_target_test.dart

No documentation available.

### test/entities/iterm2_session_test.dart

No documentation available.

### test/entities/stream_mode_test.dart

No documentation available.

### test/entities/stream_settings_test.dart

No documentation available.

## Debug Notes

No debug notes documented yet.

## Error Log

No errors recorded yet.

## Update History

## [0.1.0] - Initial Release
- Initial module structure
- CI gates enabled
- Placeholder implementation

