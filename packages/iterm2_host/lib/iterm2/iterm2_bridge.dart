import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus_core/cloudplayplus_core.dart';

/// Bridge to iTerm2 Python API.
///
/// In Phase-0/Phase-2 bootstrap, this is wired to mock scripts under
/// `scripts/python/` so we can unit test deterministically.
class ITerm2Bridge {
  static const String sourcesScriptPath = 'scripts/python/iterm2_sources.py';
  static const String activateScriptPath =
      'scripts/python/iterm2_activate_and_crop.py';
  static const String sendTextScriptPath = 'scripts/python/iterm2_send_text.py';
  static const String sessionReaderScriptPath =
      'scripts/python/iterm2_session_reader.py';

  /// List iTerm2 sessions (panels).
  Future<List<ITerm2SessionInfo>> getSessions() async {
    final res = await _runPythonFile(sourcesScriptPath, const []);
    if (res.exitCode != 0) {
      throw ITerm2Exception('getSessions failed: ${res.stderr}');
    }
    final any = jsonDecode((res.stdout as String).trim());
    if (any is! Map) return const [];
    final panelsAny = any['panels'];
    if (panelsAny is! List) return const [];
    return panelsAny
        .whereType<Map>()
        .map((m) => ITerm2SessionInfo.fromJson(
            m.map((k, v) => MapEntry(k.toString(), v))))
        .toList(growable: false);
  }

  /// Activate a session and return metadata for cropping.
  Future<Map<String, dynamic>> activateSession(String sessionId) async {
    final res = await _runPythonFile(activateScriptPath, [sessionId]);
    if (res.exitCode != 0) {
      throw ITerm2Exception('activateSession failed: ${res.stderr}');
    }
    final any = jsonDecode((res.stdout as String).trim());
    if (any is Map) {
      return any.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  /// Send UTF-8 text into a session.
  Future<bool> sendText(String sessionId, String text) async {
    final b64 = base64Encode(utf8.encode(text));
    final res = await _runPythonFile(sendTextScriptPath, [sessionId, b64]);
    if (res.exitCode != 0) return false;
    final out = (res.stdout as String).trim();
    if (out.isEmpty) return true;
    try {
      final any = jsonDecode(out);
      if (any is Map && any['ok'] is bool) return any['ok'] as bool;
    } catch (_) {}
    return true;
  }

  /// Read session buffer (chat mode). Returns decoded UTF-8 text.
  Future<String> readSessionBuffer(String sessionId, int maxBytes) async {
    final res =
        await _runPythonFile(sessionReaderScriptPath, [sessionId, '$maxBytes']);
    if (res.exitCode != 0) {
      throw ITerm2Exception('readSessionBuffer failed: ${res.stderr}');
    }
    final any = jsonDecode((res.stdout as String).trim());
    if (any is! Map) return '';
    final textB64 = any['text'];
    if (textB64 is! String || textB64.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(textB64));
    } catch (_) {
      return '';
    }
  }

  Future<ProcessResult> _runPythonFile(String scriptPath, List<String> args) {
    final scriptFile = File(scriptPath);
    if (!scriptFile.existsSync()) {
      return Future.error(ITerm2Exception('missing script: $scriptPath'));
    }
    return Process.run('python3', [scriptPath, ...args]);
  }
}

class ITerm2Exception implements Exception {
  final String message;
  ITerm2Exception(this.message);

  @override
  String toString() => 'ITerm2Exception: $message';
}

