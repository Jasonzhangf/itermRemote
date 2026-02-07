import 'package:cloudplayplus_core/iterm2/iterm2_session.dart' as core;

/// Re-export ITerm2SessionInfo from cloudplayplus_core for convenience.
///
/// This allows packages that depend on iterm2_host to access session info
/// without directly depending on cloudplayplus_core.
export 'package:cloudplayplus_core/iterm2/iterm2_session.dart';

/// Extension methods for ITerm2SessionInfo specific to host operations.
extension ITerm2SessionInfoHostExtension on core.ITerm2SessionInfo {
  /// Create a copy with updated session ID.
  core.ITerm2SessionInfo withSessionId(String sessionId) {
    return core.ITerm2SessionInfo(
      sessionId: sessionId,
      title: title,
      frame: frame,
      connectionId: connectionId,
      burkeySessionId: burkeySessionId,
      typicalSize: typicalSize,
      gridSize: gridSize,
    );
  }
}
