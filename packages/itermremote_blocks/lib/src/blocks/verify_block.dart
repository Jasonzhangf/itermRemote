import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

/// Verify block for screenshot evidence collection and crop verification.
///
/// Key responsibilities:
/// - Capture OS-level window screenshots (`screencapture -l <cgWindowId>`)
/// - Draw a red crop rectangle overlay based on iTerm2-reported panel frame
/// - Persist evidence JSON + images for manual inspection (human-in-the-loop)
class VerifyBlock implements Block {
  VerifyBlock();

  ITerm2Bridge? _iterm2Bridge;
  late BlockContext _ctx;

  Map<String, Object?> _state = const {
    'ready': false,
  };

  void setDependencies({ITerm2Bridge? iterm2Bridge}) {
    _iterm2Bridge = iterm2Bridge;
  }

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
        case 'renderMultiPanelOverlay':
          return await _renderMultiPanelOverlay(cmd);
        case 'verifyCrop':
          return await _verifyCrop(cmd);
        case 'runFullValidation':
          return await _runFullValidation(cmd);
        case 'getState':
          return Ack.ok(id: cmd.id, data: _state);
        default:
          return Ack.fail(
            id: cmd.id,
            code: 'unknown_action',
            message: 'Unknown action: ${cmd.action}',
          );
      }
    } on TimeoutException catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'timeout',
        message: e.message ?? 'Timed out while handling ${cmd.action}',
      );
    } catch (e) {
      return Ack.fail(
        id: cmd.id,
        code: 'verify_error',
        message: e.toString(),
      );
    }
  }

  /// Render a single screenshot with multiple panel boxes + order labels.
  ///
  /// payload:
  /// - screenshotPng: String (path)
  /// - windowMeta.rawWindowFrame: {x,y,w,h}
  /// - panels: [{order:int, title:String?, sessionId:String?, frame:{x,y,w,h}}]
  /// - outputPng: String
  /// - outputJson: String
  Future<Ack> _renderMultiPanelOverlay(Command cmd) async {
    final screenshotPngPath = cmd.payload?['screenshotPng'];
    final panels = cmd.payload?['panels'];
    final outputPngPath = cmd.payload?['outputPng'];
    final outputJsonPath = cmd.payload?['outputJson'];
    final windowMeta = cmd.payload?['windowMeta'];

    if (screenshotPngPath is! String || screenshotPngPath.isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'renderMultiPanelOverlay requires payload.screenshotPng',
      );
    }
    if (outputPngPath is! String || outputPngPath.isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'renderMultiPanelOverlay requires payload.outputPng',
      );
    }
    if (outputJsonPath is! String || outputJsonPath.isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'renderMultiPanelOverlay requires payload.outputJson',
      );
    }
    if (panels is! List) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'renderMultiPanelOverlay requires payload.panels (List)',
      );
    }

    final screenshotFile = File(screenshotPngPath);
    if (!screenshotFile.existsSync()) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_found',
        message: 'screenshot not found: $screenshotPngPath',
      );
    }

    final bytes = await screenshotFile.readAsBytes();
    final decoded = img.decodePng(bytes);
    if (decoded == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'decode_failed',
        message: 'Failed to decode PNG: $screenshotPngPath',
      );
    }

    final rawWf = (windowMeta is Map)
        ? ((windowMeta['rawWindowFrame'] as Map?) ?? const {})
        : const {};
    final windowX = (rawWf['x'] as num?)?.toDouble() ?? 0.0;
    final windowY = (rawWf['y'] as num?)?.toDouble() ?? 0.0;

    final imgW = decoded.width;
    final imgH = decoded.height;

    final painted = <Map<String, Object?>>[];

    for (final p in panels) {
      if (p is! Map) continue;
      final order = p['order'];
      final frame = (p['frame'] as Map?) ?? const {};
      final fx = (frame['x'] as num?)?.toDouble() ?? 0.0;
      final fy = (frame['y'] as num?)?.toDouble() ?? 0.0;
      final fw = (frame['w'] as num?)?.toDouble() ?? 0.0;
      final fh = (frame['h'] as num?)?.toDouble() ?? 0.0;
      if (fw <= 0 || fh <= 0) continue;

      final left = (windowX + fx).toInt();
      final top = (imgH - (windowY + fy + fh)).toInt();
      final right = (left + fw).toInt();
      final bottom = (top + fh).toInt();

      final cl = left.clamp(0, imgW);
      final cr = right.clamp(0, imgW);
      final ct = top.clamp(0, imgH);
      final cb = bottom.clamp(0, imgH);

      // red box
      for (var i = 0; i < 3; i++) {
        img.drawRect(
          decoded,
          x1: cl - i,
          y1: ct - i,
          x2: cr + i,
          y2: cb + i,
          color: img.ColorRgb8(255, 0, 0),
          thickness: 1,
        );
      }

      // label (order number) at top-left corner of the box
      final label = (order is num) ? order.toInt().toString() : '?';
      img.drawString(
        decoded,
        label,
        font: img.arial24,
        x: cl + 6,
        y: (ct + 6).clamp(0, imgH - 1),
        color: img.ColorRgb8(255, 0, 0),
      );

      painted.add({
        'order': label,
        'box': {'left': cl, 'top': ct, 'right': cr, 'bottom': cb},
      });
    }

    final outPng = File(outputPngPath);
    outPng.parent.createSync(recursive: true);
    await outPng.writeAsBytes(img.encodePng(decoded));

    final outJson = File(outputJsonPath);
    outJson.parent.createSync(recursive: true);
    outJson.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'screenshot': screenshotPngPath,
        'output': outputPngPath,
        'windowMeta': {'rawWindowFrame': rawWf},
        'painted': painted,
      }),
    );

    return Ack.ok(
      id: cmd.id,
      data: {
        'outputPng': outputPngPath,
        'outputJson': outputJsonPath,
        'paintedCount': painted.length,
      },
    );
  }

  /// Capture screenshot evidence and draw crop overlay.
  ///
  /// payload:
  /// - evidenceDir: String
  /// - sessionId: String?
  /// - cropMeta: Map (must include cgWindowId, frame, rawWindowFrame)
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

    if (cropMeta is! Map) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'captureEvidence requires payload.cropMeta (Map)',
      );
    }

    final dir = Directory(evidenceDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final evidenceFile = File('${dir.path}/evidence_$timestamp.json');
    final screenshotPng = File('${dir.path}/screenshot_$timestamp.png');
    final croppedPng = File('${dir.path}/cropped_$timestamp.png');
    final metaJson = File('${dir.path}/meta_$timestamp.json');
    final overlayPng = File('${dir.path}/overlay_$timestamp.png');

    metaJson.writeAsStringSync(const JsonEncoder().convert(cropMeta));

    // Capture full-screen screenshot and then crop the panel region.
    // This avoids window-id capture permission issues.
    final captureResult = await Process.run(
      '/usr/sbin/screencapture',
      ['-x', screenshotPng.path],
    );
    if (captureResult.exitCode != 0) {
      return Ack.fail(
        id: cmd.id,
        code: 'screencapture_failed',
        message: 'screencapture failed: ${captureResult.stderr}',
        details: {
          'exitCode': captureResult.exitCode,
          'stdout': captureResult.stdout?.toString(),
          'stderr': captureResult.stderr?.toString(),
        },
      );
    }

    await _cropAndDrawOverlay(screenshotPng, cropMeta, croppedPng, overlayPng);

    final evidence = {
      'timestamp': timestamp,
      'sessionId': sessionId,
      'cropMeta': cropMeta,
      'metaJson': metaJson.path,
      'screenshotPng': screenshotPng.path,
      'croppedPng': croppedPng.path,
      'overlayPng': overlayPng.path,
      'overlaySuccess': true,
      'status': 'captured',
    };

    evidenceFile.writeAsStringSync(const JsonEncoder().convert(evidence));

    _state = {
      ..._state,
      'lastCaptureTime': timestamp,
      'lastEvidencePath': evidenceFile.path,
      'lastSessionId': sessionId,
      'lastOverlaySuccess': true,
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
        'screenshotPng': screenshotPng.path,
        'croppedPng': croppedPng.path,
        'overlayPng': overlayPng.path,
        'metaJson': metaJson.path,
        'evidence': evidence,
      },
    );
  }

  Future<void> _cropAndDrawOverlay(
    File screenshotPng,
    Map cropMeta,
    File croppedPng,
    File overlayPng,
  ) async {
    final f = (cropMeta['frame'] as Map?) ?? const {};
    final wf = (cropMeta['rawWindowFrame'] as Map?) ?? const {};

    final fx = (f['x'] as num?)?.toDouble() ?? 0.0;
    final fy = (f['y'] as num?)?.toDouble() ?? 0.0;
    final fw = (f['w'] as num?)?.toDouble() ?? 0.0;
    final fh = (f['h'] as num?)?.toDouble() ?? 0.0;
    final windowX = (wf['x'] as num?)?.toDouble() ?? 0.0;
    final windowY = (wf['y'] as num?)?.toDouble() ?? 0.0;

    if (fw <= 0 || fh <= 0) {
      throw ArgumentError('Invalid crop frame dimensions: $f');
    }

    final bytes = await screenshotPng.readAsBytes();
    final decoded = img.decodePng(bytes);
    if (decoded == null) {
      throw StateError('Failed to decode PNG: ${screenshotPng.path}');
    }

    final imgW = decoded.width;
    final imgH = decoded.height;

    // iTerm2: origin bottom-left; screenshot: origin top-left.
    // Convert panel rect in window coordinates to screen coordinates by adding rawWindowFrame origin.
    final left = (windowX + fx).toInt();
    final top = (imgH - (windowY + fy + fh)).toInt();
    final width = fw.toInt();
    final height = fh.toInt();

    final clampedLeft = left.clamp(0, imgW - 1);
    final clampedTop = top.clamp(0, imgH - 1);
    final clampedWidth = width.clamp(1, imgW - clampedLeft);
    final clampedHeight = height.clamp(1, imgH - clampedTop);

    final cropped = img.copyCrop(
      decoded,
      x: clampedLeft,
      y: clampedTop,
      width: clampedWidth,
      height: clampedHeight,
    );
    await croppedPng.writeAsBytes(img.encodePng(cropped));

    // Draw border on cropped image as a quick sanity check.
    for (var i = 0; i < 3; i++) {
      img.drawRect(
        cropped,
        x1: i,
        y1: i,
        x2: cropped.width - 1 - i,
        y2: cropped.height - 1 - i,
        color: img.ColorRgb8(255, 0, 0),
      );
    }
    await overlayPng.writeAsBytes(img.encodePng(cropped));
  }

  Future<void> _drawCropOverlay(
    File windowPng,
    Map cropMeta,
    File overlayPng,
  ) async {
    final f = (cropMeta['frame'] as Map?) ?? const {};
    final wf = (cropMeta['rawWindowFrame'] as Map?) ?? const {};

    final fx = (f['x'] as num?)?.toDouble() ?? 0.0;
    final fy = (f['y'] as num?)?.toDouble() ?? 0.0;
    final fw = (f['w'] as num?)?.toDouble() ?? 0.0;
    final fh = (f['h'] as num?)?.toDouble() ?? 0.0;
    final windowY = (wf['y'] as num?)?.toDouble() ?? 0.0;

    if (fw <= 0 || fh <= 0) {
      throw ArgumentError('Invalid crop frame dimensions: $f');
    }

	  final bytes = await windowPng.readAsBytes();
	  final decoded = img.decodePng(bytes);
	  if (decoded == null) {
	    throw StateError('Failed to decode PNG: ${windowPng.path}');
	  }

	  final imgW = decoded.width;
	  final imgH = decoded.height;

    // iTerm2: origin bottom-left. Screenshot: origin top-left.
    final left = fx.toInt();
    final top = (imgH - (fy + fh) - windowY).toInt();
    final right = (left + fw).toInt();
    final bottom = (top + fh).toInt();

    final clampedLeft = left.clamp(0, imgW);
    final clampedRight = right.clamp(0, imgW);
    final clampedTop = top.clamp(0, imgH);
    final clampedBottom = bottom.clamp(0, imgH);

	  for (var i = 0; i < 3; i++) {
	    img.drawRect(
	      decoded,
	      x1: clampedLeft - i,
	      y1: clampedTop - i,
	      x2: clampedRight + i,
	      y2: clampedBottom + i,
	      color: img.ColorRgb8(255, 0, 0),
	      thickness: 1,
	    );
	  }

	  await overlayPng.writeAsBytes(img.encodePng(decoded));
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

  /// runFullValidation:
  /// payload:
  /// - sessionId: String
  /// - evidenceDir: String? (optional)
  Future<Ack> _runFullValidation(Command cmd) async {
    final sessionId = cmd.payload?['sessionId'];
    final evidenceDir = cmd.payload?['evidenceDir'] ??
        '/tmp/itermremote-verify/${DateTime.now().millisecondsSinceEpoch}';

    if (sessionId is! String || sessionId.trim().isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'invalid_payload',
        message: 'runFullValidation requires payload.sessionId',
      );
    }

    if (_iterm2Bridge == null) {
      return Ack.fail(
        id: cmd.id,
        code: 'not_configured',
        message: 'ITerm2Bridge not set in VerifyBlock',
      );
    }

    final cropMeta = await _iterm2Bridge!.activateSession(sessionId);
    final captureAck = await _captureEvidence(
      Command(
        version: itermremoteProtocolVersion,
        id: '${cmd.id}_capture',
        target: name,
        action: 'captureEvidence',
        payload: {
          'evidenceDir': evidenceDir,
          'sessionId': sessionId,
          'cropMeta': cropMeta,
        },
      ),
    );
    if (!captureAck.success) {
      return Ack.fail(
        id: cmd.id,
        code: 'capture_failed',
        message: captureAck.error?.message ?? 'captureEvidence failed',
      );
    }

    final evidencePath = captureAck.data?['evidencePath'];
    if (evidencePath is! String || evidencePath.isEmpty) {
      return Ack.fail(
        id: cmd.id,
        code: 'internal_error',
        message: 'captureEvidence did not return evidencePath',
      );
    }

    final verifyAck = await _verifyCrop(
      Command(
        version: itermremoteProtocolVersion,
        id: '${cmd.id}_verify',
        target: name,
        action: 'verifyCrop',
        payload: {
          'evidencePath': evidencePath,
        },
      ),
    );

    if (!verifyAck.success) {
      return Ack.fail(
        id: cmd.id,
        code: 'verify_failed',
        message: verifyAck.error?.message ?? 'verifyCrop failed',
      );
    }

    return Ack.ok(
      id: cmd.id,
      data: {
        'evidenceDir': evidenceDir,
        'evidencePath': evidencePath,
        'capture': captureAck.data,
        'verify': verifyAck.data,
      },
    );
  }
}
