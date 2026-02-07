/// Multi-panel switching test for iTermRemote daemon.
///
/// - Enumerates panels in spatial order (row-major): top-to-bottom, left-to-right
/// - For each panel:
///   - activateSession
///   - captureEvidence (screenshot + crop + red border overlay)
/// - Writes a summary.json into outputDir
///
/// Usage:
///   dart scripts/test/iterm2_panel_switching_test.dart \
///     --ws-url=ws://127.0.0.1:8766 \
///     --output-dir=/tmp/itermremote-panel-switching \
///     --duration=5

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class _WsRpc {
  _WsRpc(this._ws);

  final WebSocketChannel _ws;
  int _seq = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  void start() {
    _ws.stream.listen((message) {
      final obj = jsonDecode(message as String);
      if (obj is! Map<String, dynamic>) return;
      final id = obj['id'];
      if (id is! String) return;
      final c = _pending.remove(id);
      c?.complete(obj);
    });
  }

  Future<Map<String, dynamic>> cmd(
    String target,
    String action,
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final id = '${action}_${_seq++}_${DateTime.now().millisecondsSinceEpoch}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;

    _ws.sink.add(
      jsonEncode({
        'type': 'cmd',
        'version': 1,
        'id': id,
        'target': target,
        'action': action,
        'payload': payload,
      }),
    );

    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('timeout waiting ack for $target.$action');
      },
    );
  }
}

double _numToDouble(Object? v) {
  if (v is num) return v.toDouble();
  return 0.0;
}

List<Map<String, dynamic>> _sortPanelsSpatial(List<Map<String, dynamic>> panels) {
  // iTerm2 frame is in window coordinates with origin at bottom-left.
  // "Row-major" as user asked: first row then column, which in screen terms means:
  // higher y is visually higher row. So sort y DESC, then x ASC.
  final sorted = [...panels];
  sorted.sort((a, b) {
    final fa = (a['frame'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fb = (b['frame'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ya = _numToDouble(fa['y']);
    final yb = _numToDouble(fb['y']);
    if (ya != yb) return yb.compareTo(ya);
    final xa = _numToDouble(fa['x']);
    final xb = _numToDouble(fb['x']);
    return xa.compareTo(xb);
  });
  return sorted;
}

Future<void> main(List<String> args) async {
  var wsUrl = 'ws://127.0.0.1:8766';
  var outputDir =
      '/tmp/itermremote-panel-switching/${DateTime.now().millisecondsSinceEpoch}';
  var durationSec = 5;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--ws-url' && i + 1 < args.length) {
      wsUrl = args[++i];
    } else if (a == '--output-dir' && i + 1 < args.length) {
      outputDir = args[++i];
    } else if (a == '--duration' && i + 1 < args.length) {
      durationSec = int.parse(args[++i]);
    }
  }

  final dir = Directory(outputDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  stdout.writeln('[panel_switch] wsUrl=$wsUrl');
  stdout.writeln('[panel_switch] outputDir=$outputDir');
  stdout.writeln('[panel_switch] durationSec=$durationSec');

  final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
  await ws.ready;
  final rpc = _WsRpc(ws);
  rpc.start();

  // list panels
  final listAck = await rpc.cmd('iterm2', 'getSessions', {});
  if (listAck['success'] != true) {
    throw StateError('getSessions failed: ${listAck['error']}');
  }
  final sessionsRaw = (listAck['data'] as Map)['sessions'] as List;
  final panels = sessionsRaw.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
  final sorted = _sortPanelsSpatial(panels);

  final results = <Map<String, dynamic>>[];

  for (var i = 0; i < sorted.length; i++) {
    final p = sorted[i];
    final title = (p['title'] ?? '').toString();
    final sid = (p['id'] ?? '').toString();
    stdout.writeln('[panel_switch] (${i + 1}/${sorted.length}) activate title=$title sid=$sid');

    final r = <String, dynamic>{
      'order': i + 1,
      'title': title,
      'sessionId': sid,
      'status': 'pending',
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final actAck = await rpc.cmd('iterm2', 'activateSession', {'sessionId': sid});
      if (actAck['success'] != true) {
        throw StateError('activateSession failed: ${actAck['error']}');
      }
      final meta = (actAck['data'] as Map)['meta'] as Map;
      r['cropMeta'] = meta;

      // settle
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // capture
      final capAck = await rpc.cmd(
        'verify',
        'captureEvidence',
        {
          'evidenceDir': outputDir,
          'sessionId': sid,
          'cropMeta': meta,
        },
        timeout: const Duration(seconds: 60),
      );
      if (capAck['success'] != true) {
        throw StateError('captureEvidence failed: ${capAck['error']}');
      }
      final data = capAck['data'] as Map;
      r['screenshotPng'] = data['screenshotPng'];
      r['croppedPng'] = data['croppedPng'];
      r['overlayPng'] = data['overlayPng'];
      r['metaJson'] = data['metaJson'];
      r['status'] = 'success';

      stdout.writeln('[panel_switch]   overlay=${r['overlayPng']}');

      // user asked 5s per panel. We don't yet record video here, but we keep the timing.
      await Future<void>.delayed(Duration(seconds: durationSec));
    } catch (e) {
      r['status'] = 'error';
      r['error'] = e.toString();
      stdout.writeln('[panel_switch]   ERROR: $e');
    }

    results.add(r);
  }

  await ws.sink.close();

  final summary = {
    'ts': DateTime.now().toIso8601String(),
    'wsUrl': wsUrl,
    'order': 'row-major (top-to-bottom, left-to-right) using frame.y desc then frame.x asc',
    'durationSec': durationSec,
    'total': results.length,
    'success': results.where((e) => e['status'] == 'success').length,
    'failed': results.where((e) => e['status'] != 'success').length,
    'results': results,
  };
  File('$outputDir/summary.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));

  stdout.writeln('[panel_switch] wrote summary: $outputDir/summary.json');
}

