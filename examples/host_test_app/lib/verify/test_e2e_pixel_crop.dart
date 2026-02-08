#!/usr/bin/env dart
// E2E 像素级裁切验证脚本
//
// 验证流程：
// 1) 连接 host_daemon WebSocket
// 2) iterm2.getSessions
// 3) 对每个 session 调用 verify.runFullValidation
// 4) 输出证据目录，人工检查 overlay_*.png 红框是否准确

import 'dart:convert';
import 'dart:io';

import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String defaultWsUrl = 'ws://127.0.0.1:8766';

Future<void> main(List<String> args) async {
  final wsUrl = args.isNotEmpty ? args[0] : defaultWsUrl;
  // ignore: avoid_print
  print('[E2E] ws=$wsUrl');

  final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

  Future<Ack> sendCmd(Command cmd) async {
    channel.sink.add(jsonEncode(cmd.toJson()));
    final msg = await channel.stream.first;
    final env = Envelope.fromJson(jsonDecode(msg as String));
    if (env is! Ack) {
      throw StateError('Expected Ack, got ${env.runtimeType}');
    }
    return env;
  }

  try {
    final sessionsAck = await sendCmd(
      Command(
        version: itermremoteProtocolVersion,
        id: 'getSessions',
        target: 'iterm2',
        action: 'getSessions',
        payload: const {},
      ),
    );
    if (!sessionsAck.success) {
      throw StateError('getSessions failed: ${sessionsAck.error?.message}');
    }

    final sessionsRaw = sessionsAck.data?['sessions'];
    if (sessionsRaw is! List || sessionsRaw.isEmpty) {
      // ignore: avoid_print
      print('[E2E] no sessions');
      return;
    }

    final sessions = sessionsRaw.cast<Map>();

    final evidenceDir = Directory(
      '/tmp/itermremote-e2e-${DateTime.now().millisecondsSinceEpoch}',
    );
    await evidenceDir.create(recursive: true);
    // ignore: avoid_print
    print('[E2E] evidenceDir=${evidenceDir.path}');

    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final sessionId = s['id'];
      final title = s['title'];

      // ignore: avoid_print
      print('[E2E] (${i + 1}/${sessions.length}) $title $sessionId');
      if (sessionId is! String || sessionId.isEmpty) continue;

      final validateAck = await sendCmd(
        Command(
          version: itermremoteProtocolVersion,
          id: 'validate_$i',
          target: 'verify',
          action: 'runFullValidation',
          payload: {
            'sessionId': sessionId,
            'evidenceDir': evidenceDir.path,
          },
        ),
      );

      if (!validateAck.success) {
        // ignore: avoid_print
        print('  FAIL: ${validateAck.error?.code} ${validateAck.error?.message}');
        continue;
      }

      final evidencePath = validateAck.data?['evidencePath'];
      // ignore: avoid_print
      print('  OK: evidencePath=$evidencePath');
    }

    // ignore: avoid_print
    print('[E2E] done. open "${evidenceDir.path}"');
  } finally {
    await channel.sink.close();
  }
}
