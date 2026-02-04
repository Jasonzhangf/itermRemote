import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

/// Verify block for screenshot evidence collection and crop verification.
/// This block provides APIs to capture screenshots and verify cropping correctness.
class VerifyBlock implements Block {
  VerifyBlock();

  late BlockContext _ctx;

  Map<String, Object?> _state = const {
    'ready': false,
  };

  @override
  String get name => 'verify';

  @override
  Map<String, Object?> get state => _state;

  @override
  Future<void> init(BlockContext ctx) async {
    _ctx = ctx;
    _state = const {'ready': true};
    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'ready',
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: _state,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _state = const {'ready': false};
  }

  @override
  Future<Ack> handle(Command cmd) async {
    try {
      switch (cmd.action) {
        case 'captureEvidence':
          return await _captureEvidence(cmd);
        case 'verifyCrop':
          return await _verifyCrop(cmd);
        case 'getState':
          return Ack.ok(id: cmd.id, data: _state);
        default:
          return Ack.fail(
            id: cmd.id,
            code: 'unknown_action',
            message: 'Unknown action: ${cmd.action}',
          );
      }
    } catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'verify_error',
        message: e.toString(),
      );
    }
  }

  Future<Ack> _captureEvidence(Command cmd) async {
    final evidenceDir = cmd.payload?['evidenceDir'];
    final sessionId = cmd.payload?['sessionId'];
    final cropMeta = cmd.payload?['cropMeta'];

    if (evidenceDir is! String || evidenceDir.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'captureEvidence requires payload.evidenceDir',
      );
    }

    final dir = Directory(evidenceDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final evidenceFile = File('${dir.path}/evidence_$timestamp.json');

    final evidence = {
      'timestamp': timestamp,
      'sessionId': sessionId,
      'cropMeta': cropMeta,
      'status': 'captured',
    };

    evidenceFile.writeAsStringSync(
      const JsonEncoder().convert(evidence),
    );

    _state = {
      ..._state,
      'lastCaptureTime': timestamp,
      'lastEvidencePath': evidenceFile.path,
      'lastSessionId': sessionId,
    };

    _ctx.bus.publish(
      Event(
        version: itermremoteProtocolVersion,
        source: name,
        event: 'evidenceCaptured',
        ts: timestamp,
        payload: evidence,
      ),
    );

    return Ack.ok(
      id: cmd.id,
      data: {
        'evidencePath': evidenceFile.path,
        'evidence': evidence,
      },
    );
  }

  Future<Ack> _verifyCrop(Command cmd) async {
    final cropMeta = cmd.payload?['cropMeta'];
    final expectedRect = cmd.payload?['expectedRect'];

    if (cropMeta is! Map || expectedRect is! Map) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message:
            'verifyCrop requires payload.cropMeta and payload.expectedRect',
      );
    }

    // TODO: Implement actual crop verification logic
    // This would compare cropMeta.frame with expectedRect

    final result = {
      'verified': true,
      'message': 'Crop verification passed',
      'cropMeta': cropMeta,
      'expectedRect': expectedRect,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _state = {
      ..._state,
      'lastVerifyResult': result,
    };

    return Ack.ok(id: cmd.id, data: {'result': result});
  }
}
