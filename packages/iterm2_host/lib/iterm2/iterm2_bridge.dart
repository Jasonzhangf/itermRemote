import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus_core/cloudplayplus_core.dart';

/// Bridge to iTerm2 Python API.
///
/// In Phase-0/Phase-2 bootstrap, this is wired to mock scripts under
/// `scripts/python/` so we can unit test deterministically.
class ITerm2Bridge {
  /// Python script paths are repo-relative by default.
  ///
  /// Callers can override by passing custom paths to the constructor.
  final String sourcesScriptPath;
  final String activateScriptPath;
  final String sendTextScriptPath;
  final String sessionReaderScriptPath;
  final String windowFramesScriptPath;
  final String? repoRoot;

  ITerm2Bridge({
    this.sourcesScriptPath = 'scripts/python/iterm2_sources.py',
    this.activateScriptPath = 'scripts/python/iterm2_activate_and_crop.py',
    this.sendTextScriptPath = 'scripts/python/iterm2_send_text.py',
    this.sessionReaderScriptPath = 'scripts/python/iterm2_session_reader.py',
    this.windowFramesScriptPath = 'scripts/python/iterm2_window_frames.py',
    this.repoRoot,
  });

  Future<List<Map<String, dynamic>>> getWindowFrames() async {
    final res = await _runPythonFile(windowFramesScriptPath, const []);
    if (res.exitCode != 0) {
      throw ITerm2Exception('getWindowFrames failed: ${res.stderr}');
    }
    final any = jsonDecode((res.stdout as String).trim());
    if (any is! Map) return const [];
    final listAny = any['windows'];
    if (listAny is! List) return const [];
    return listAny.whereType<Map>().map((m) {
      return m.map((k, v) => MapEntry(k.toString(), v));
    }).toList(growable: false);
  }

  static bool get forceMockScripts =>
      (Platform.environment['ITERMREMOTE_ITERM2_MOCK'] ?? '').trim() == '1';

  /// List iTerm2 sessions (panels).
  Future<List<ITerm2SessionInfo>> getSessions() async {
    final res = await _runPythonFile(sourcesScriptPath, const []);
    if (res.exitCode != 0) {
      throw ITerm2Exception('getSessions failed: ${res.stderr}');
    }
    final outStr = (res.stdout as String).trim();
    final any = jsonDecode(outStr);
    if (any is! Map) return const [];
    final panelsAny = any['panels'];
    if (panelsAny is! List) return const [];
    return panelsAny
        .whereType<Map>()
        .map((m) => ITerm2SessionInfo.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ))
        .toList(growable: false);
  }

  /// Activate a session and return metadata for cropping.
  Future<Map<String, dynamic>> activateSession(String sessionId) async {
    final res = await _runPythonFile(activateScriptPath, [sessionId]);
    if (res.exitCode != 0) {
      throw ITerm2Exception('activateSession failed: ${res.stderr}');
    }
    final outStr = (res.stdout as String).trim();
    // ignore: avoid_print
    print('ITerm2Bridge.activateSession stdout: $outStr');
    final any = jsonDecode(outStr);
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
    final cwd = Directory.current.path;
    final effectiveScriptPath = forceMockScripts
        ? scriptPath.replaceAll(RegExp(r'\.py$'), '_mock.py')
        : scriptPath;
    final configuredRoot = (repoRoot ?? Platform.environment['ITERMREMOTE_REPO_ROOT'] ?? '').trim();
    final candidates = <String>[
      // Add the script path itself (may be absolute).
      effectiveScriptPath,
      '../../$effectiveScriptPath',
      '../../../$effectiveScriptPath',
      '../../../../$effectiveScriptPath',
      // macOS sandboxed Flutter apps run with a container cwd. When launched
      // from our repo, scripts usually live relative to the workspace root.
      if (configuredRoot.isNotEmpty) '$configuredRoot/$effectiveScriptPath',
      // Common default path for this repo on the author's machine.
      '/Users/fanzhang/Documents/github/itermRemote/$effectiveScriptPath',
    ].where((p) => p.trim().isNotEmpty).toList(growable: false);

    for (final p in candidates) {
      final f = File(p);
      if (f.existsSync()) {
        return _runPythonWithFallback(f.path, args);
      }
    }

    return Future.error(ITerm2Exception(
        'missing script: $effectiveScriptPath (cwd=$cwd). Set ITERMREMOTE_REPO_ROOT to workspace root.'));
  }

  Future<ProcessResult> _runPythonWithFallback(
      String scriptPath, List<String> args) async {
    // Prefer system python3 over Xcode python3 (which may have security restrictions).
    final candidates = <String>['/usr/bin/python3', 'python3', '/usr/local/bin/python3'];
    ProcessResult? last;
    for (final bin in candidates) {
      try {
        final res = await _runPythonWithTimeout(bin, scriptPath, args);
        last = res;
        // If the interpreter ran, return immediately and let caller handle non-zero.
        return res;
      } catch (e) {
        last = ProcessResult(0, 1, '', '$bin failed: $e');
      }
    }
    return last ?? ProcessResult(0, 1, '', 'no python runtime available');
  }

  Future<ProcessResult> _runPythonWithTimeout(
      String bin, String scriptPath, List<String> args) async {
    final timeoutMs = int.tryParse(
            Platform.environment['ITERMREMOTE_PY_TIMEOUT_MS'] ?? '') ??
        3000;
    final proc = await Process.start(
      bin,
      [scriptPath, ...args],
      environment: {
        // iTerm2 Python API can hang waiting for prompt in non-UI contexts.
        'ITERMREMOTE_NO_PROMPT': '1',
        'PYTHONUNBUFFERED': '1',
      },
    );
    final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
    final stderrFuture = proc.stderr.transform(utf8.decoder).join();

    final exitFuture = proc.exitCode.then((code) => ('exit', code));
    final timeoutFuture = Future.delayed(
      Duration(milliseconds: timeoutMs),
      () => ('timeout', null),
    );
    final result = await Future.any([exitFuture, timeoutFuture]);
    if (result.$1 == 'timeout') {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return ProcessResult(
        proc.pid,
        124,
        '',
        'timeout after ${timeoutMs}ms',
      );
    }
    final exitCode = result.$2 as int;

    final out = await stdoutFuture;
    final err = await stderrFuture;
    return ProcessResult(proc.pid, exitCode, out, err);
  }
}

class ITerm2Exception implements Exception {
  final String message;
  ITerm2Exception(this.message);

  @override
  String toString() => 'ITerm2Exception: $message';
}
