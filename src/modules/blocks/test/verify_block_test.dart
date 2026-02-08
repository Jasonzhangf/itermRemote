import 'dart:io';
import 'dart:convert';

import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('VerifyBlock', () {
    late VerifyBlock block;
    late InMemoryEventBus bus;
    late BlockContext ctx;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('verify_block_test');
      bus = InMemoryEventBus();
      ctx = BlockContext(bus: bus);
      block = VerifyBlock();
      await block.init(ctx);
    });

    tearDown(() async {
      await block.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('name is "verify"', () {
      expect(block.name, 'verify');
    });

    test('captureEvidence requires valid payload', () async {
      final cmd = Command(
        version: 1,
        id: '1',
        target: 'verify',
        action: 'captureEvidence',
        payload: {},
      );
      final ack = await block.handle(cmd);
      expect(ack.success, isFalse);
      expect(ack.error?.code, 'invalid_payload');
    });

    // Note: We can't easily test real screencapture/python execution in unit tests
    // without mocking Process.run. For now we just test the argument validation
    // which covers the pure logic part. Real execution is covered by E2E scripts.

    test('verifyCrop requires valid payload', () async {
      final cmd = Command(
        version: 1,
        id: '1',
        target: 'verify',
        action: 'verifyCrop',
        payload: {},
      );
      final ack = await block.handle(cmd);
      expect(ack.success, isFalse);
      expect(ack.error?.code, 'invalid_payload');
    });

    test('verifyCrop handles missing file', () async {
      final cmd = Command(
        version: 1,
        id: '1',
        target: 'verify',
        action: 'verifyCrop',
        payload: {'evidencePath': '${tempDir.path}/missing.json'},
      );
      final ack = await block.handle(cmd);
      expect(ack.success, isFalse);
      expect(ack.error?.code, 'evidence_not_found');
    });
  });
}
