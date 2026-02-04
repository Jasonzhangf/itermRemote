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
    final windowPng = File('${dir.path}/window_$timestamp.png');
    final metaJson = File('${dir.path}/meta_$timestamp.json');
    final overlayPng = File('${dir.path}/overlay_$timestamp.png');

    if (cropMeta is! Map) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'captureEvidence requires payload.cropMeta (Map)',
      );
    }

    metaJson.writeAsStringSync(const JsonEncoder().convert(cropMeta));

    final cgWindowId = cropMeta['cgWindowId'];
    if (cgWindowId is! int || cgWindowId <= 0) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_crop_meta',
        message: 'captureEvidence requires cropMeta.cgWindowId (int)',
      );
    }

    final captureResult = await Process.run(
      '/usr/sbin/screencapture',
      ['-l', '$cgWindowId', '-x', windowPng.path],
    );
    if (captureResult.exitCode != 0) {
      return Ack.fail(
        id: cmd.id,
        code: 'screencapture_failed',
        message: 'screencapture failed: ${captureResult.stderr}',
      );
    }

    final overlayResult = await Process.run(
      'python3',
      [
        'scripts/python/overlay_crop_box.py',
        windowPng.path,
        metaJson.path,
        overlayPng.path,
      ],
    );

    final evidence = {
      'timestamp': timestamp,
      'sessionId': sessionId,
      'cropMeta': cropMeta,
      'metaJson': metaJson.path,
      'windowPng': windowPng.path,
      'overlayPng': overlayPng.path,
      'overlaySuccess': overlayResult.exitCode == 0,
      'status': 'captured',
    };

    evidenceFile.writeAsStringSync(const JsonEncoder().convert(evidence));

    _state = {
      ..._state,
      'lastCaptureTime': timestamp,
      'lastEvidencePath': evidenceFile.path,
      'lastSessionId': sessionId,
      'lastOverlaySuccess': overlayResult.exitCode == 0,
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
        'windowPng': windowPng.path,
        'overlayPng': overlayPng.path,
        'metaJson': metaJson.path,
        'evidence': evidence,
      },
    );
  }

  Future<Ack> _verifyCrop(Command cmd) async {
    final evidencePath = cmd.payload?['evidencePath'];
    if (evidencePath is! String || evidencePath.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'verifyCrop requires payload.evidencePath',
      );
    }

    final file = File(evidencePath);
    if (!file.existsSync()) {
      return Ack.fail(
        id: cmd.id,
        code: 'evidence_not_found',
        message: 'Evidence file not found: $evidencePath',
      );
    }

    final evidence = const JsonDecoder().convert(file.readAsStringSync());
    if (evidence is! Map) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_evidence',
        message: 'Evidence is not a JSON object',
      );
    }

    final overlaySuccess = evidence['overlaySuccess'] == true;
    final overlayPng = evidence['overlayPng'];
    final verified =
        overlaySuccess && overlayPng is String && overlayPng.isNotEmpty;

    final result = {
      'verified': verified,
      'message': verified
          ? 'Crop verification passed (overlay generated)'
          : 'Crop verification failed (overlay missing)',
      'evidencePath': evidencePath,
      'overlayPng': overlayPng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _state = {
      ..._state,
      'lastVerifyResult': result,
    };

    return Ack.ok(id: cmd.id, data: {'result': result});
  }
}
