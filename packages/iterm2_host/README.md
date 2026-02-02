# iterm2_host

## Module Overview

macOS host module. Responsible for iTerm2 integration via Python API scripts and hosting WebRTC sessions.

## Architecture

```
Dart/Flutter module with lib/.
Has module-local tests.
```

## File Structure

### lib/config/file_host_config_store.dart

No documentation available.

### lib/config/host_config.dart

No documentation available.

### lib/config/host_config_store.dart

No documentation available.

### lib/iterm2/iterm2_bridge.dart

No documentation available.

### lib/iterm2_host.dart

No documentation available.

### lib/main.dart

No documentation available.

### lib/network/bandwidth_tier_strategy.dart

No documentation available.

### lib/network/connection/connection_orchestrator.dart

No documentation available.

### lib/network/connection/fake_peer_connection.dart

Simulated WebRTC peer connection for local testing.

This class mimics the state transitions and failure modes of a real
WebRTC connection without requiring actual network/WebRTC dependencies.

States: New -> Checking -> Connected | Failed

### lib/network/peer_address_resolver.dart

No documentation available.

### lib/network/recovery/server_recovery_policy.dart

No documentation available.

### lib/network/signaling/fake_signaling_transport.dart

No documentation available.

### lib/network/signaling/signaling_transport.dart

No documentation available.

### lib/streaming/stream_host.dart

No documentation available.

### lib/utils/value_notifier.dart

No documentation available.

### lib/webrtc/encoding_policy/encoding_policy.dart

No documentation available.

### lib/webrtc/encoding_policy/encoding_policy_engine.dart

No documentation available.

### lib/webrtc/encoding_policy/encoding_policy_manager.dart

No documentation available.

### lib/webrtc/encoding_policy/encoding_policy_models.dart

Input context for encoding policy decision.

### lib/webrtc/encoding_policy/encoding_policy_profiles.dart

No documentation available.

### test/config/file_host_config_store_test.dart

No documentation available.

### test/config/host_config_test.dart

No documentation available.

### test/iterm2/iterm2_bridge_test.dart

No documentation available.

### test/network/bandwidth_tier_strategy_test.dart

No documentation available.

### test/network/connection/connection_orchestrator_test.dart

No documentation available.

### test/network/peer_address_resolver_test.dart

No documentation available.

### test/network/recovery/server_recovery_policy_test.dart

No documentation available.

### test/streaming/stream_host_test.dart

No documentation available.

### test/webrtc/encoding_policy/encoding_policy_engine_test.dart

No documentation available.

### test/webrtc/encoding_policy/encoding_policy_h264_test.dart

No documentation available.

### test/webrtc/encoding_policy/encoding_policy_manager_test.dart

No documentation available.

## User Notes

<!-- USER -->

<!-- /USER -->

## Debug Notes

No debug notes documented yet.

## Error Log

No errors recorded yet.

## Update History

## [0.1.0] - Initial Release
- Initial module structure
- CI gates enabled
- Placeholder implementation

