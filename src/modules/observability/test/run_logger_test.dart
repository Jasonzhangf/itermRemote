import 'dart:io';
import 'dart:typed_data';

import 'package:itermremote_observability/observability.dart';
import 'package:test/test.dart';

void main() {
  test('RunLogger.create creates a run dir and can write files', () async {
    final tmp = await Directory.systemTemp.createTemp('itermremote_obs_test_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    // Force logger to write under our temp dir.
    final old = Platform.environment['ITERMREMOTE_LOG_DIR'];
    // We can't mutate Platform.environment; so we create a child process-like
    // contract by setting env before creating the logger using a Zone override.
    // For this repo, RunLogger reads Platform.environment directly; thus we
    // only test the default path behavior here.
    expect(old, anyOf(isNull, isA<String>()));

    final logger = await RunLogger.create(appName: 'obs_test_app');
    expect(logger.runId, contains('obs_test_app-'));
    expect(logger.dir.existsSync(), isTrue);

    final f = logger.writeJson('hello', {'ok': true});
    expect(f.existsSync(), isTrue);
    expect(f.readAsStringSync(), contains('"ok"'));

    final png = logger.writePng('img', Uint8List.fromList([1, 2, 3]));
    expect(png.existsSync(), isTrue);
    expect(png.lengthSync(), 3);
  });
}

