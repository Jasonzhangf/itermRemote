#!/usr/bin/env dart
/// E2E 像素级裁切验证测试
///
/// 此脚本连接到 host_daemon WebSocket 服务，执行完整的像素级裁切验证：
/// 1. 获取 iTerm2 sessions
/// 2. 对每个 session 执行 runFullValidation（activate + capture + overlay）
/// 3. 生成证据截图和红框覆盖图
/// 4. 输出验证结果
///
/// 用法：
///   dart scripts/e2e_pixel_crop_test.dart
///
/// 环境变量：
///   ITERMREMOTE_WS_URL=ws://127.0.0.1:8766 dart scripts/e2e_pixel_crop_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String defaultWsUrl = 'ws://127.0.0.1:8766';

Future<void> main(List<String> args) async {
  final wsUrl = Platform.environment['ITERMREMOTE_WS_URL'] ?? defaultWsUrl;
  print('[E2E] Connecting to $wsUrl');

  final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
  final wsStream = channel.stream.asBroadcastStream();

  Future<Ack> sendCmd(Command cmd) async {
    channel.sink.add(jsonEncode(cmd.toJson()));
    final msg = await wsStream.first;
    final env = Envelope.fromJson(jsonDecode(msg as String));
    if (env is! Ack) {
      throw StateError('Expected Ack, got ${env.runtimeType}');
    }
    return env;
  }

  try {
    // 获取 sessions
    print('[E2E] Fetching iTerm2 sessions...');
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
      print('[E2E] Failed to get sessions: ${sessionsAck.error?.message}');
      exit(1);
    }

    final sessionsRaw = sessionsAck.data?['sessions'];
    if (sessionsRaw is! List || sessionsRaw.isEmpty) {
      print('[E2E] No iTerm2 sessions found. Please open iTerm2 with split panes.');
      exit(1);
    }

    final sessions = sessionsRaw.cast<Map>();
    print('[E2E] Found ${sessions.length} sessions\n');

    // 创建证据目录
    final evidenceDir = Directory(
      '/tmp/itermremote-e2e-${DateTime.now().millisecondsSinceEpoch}',
    );
    await evidenceDir.create(recursive: true);
    print('[E2E] Evidence directory: ${evidenceDir.path}\n');

    final results = <Map<String, Object?>>[];

    // 对每个 session 运行验证
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final sessionId = s['id'];
      final title = s['title'] ?? '<no title>';

      print('[E2E] (${i + 1}/${sessions.length}) $title ($sessionId)');
      if (sessionId is! String || sessionId.isEmpty) {
        print('[E2E]   SKIP: invalid sessionId\n');
        continue;
      }

      try {
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
          print('[E2E]   FAIL: ${validateAck.error?.code} ${validateAck.error?.message}\n');
          results.add({
            'sessionId': sessionId,
            'title': title,
            'verified': false,
            'error': validateAck.error?.message,
          });
          continue;
        }

        final capture = validateAck.data?['capture'] as Map?;
        final verify = validateAck.data?['verify'] as Map?;
        final result = verify?['result'] as Map?;
        final verified = result?['verified'] == true;
        final overlayPng = result?['overlayPng'] as String?;

        if (verified) {
          print('[E2E]   OK: verified=true');
          if (overlayPng != null) {
            print('[E2E]   → overlay: $overlayPng');
          }
        } else {
          print('[E2E]   FAIL: verified=false');
        }

        results.add({
          'sessionId': sessionId,
          'title': title,
          'verified': verified,
          'overlayPng': overlayPng,
        });
      } catch (e) {
        print('[E2E]   ERROR: $e\n');
        results.add({
          'sessionId': sessionId,
          'title': title,
          'verified': false,
          'error': e.toString(),
        });
      }
      print('');
    }

    // 汇总
    print('[E2E] ===== Summary =====');
    final passed = results.where((r) => r['verified'] == true).length;
    final total = results.length;
    print('[E2E] Passed: $passed / $total');

    if (passed == total && total > 0) {
      print('[E2E] ✓ All crops verified successfully!');

      // 打开第一个证据图片
      final firstOverlay = results.firstOrNull?['overlayPng'] as String?;
      if (firstOverlay != null && File(firstOverlay).existsSync()) {
        print('[E2E] Opening sample overlay: $firstOverlay');
        Process.run('open', [firstOverlay]);
      }

      print('[E2E] Evidence directory: ${evidenceDir.path}');
    } else {
      print('[E2E] ✗ Some crops failed. Check evidence directory:');
      print('[E2E]   ${evidenceDir.path}');
      exit(1);
    }
  } finally {
    await channel.sink.close();
  }
}
