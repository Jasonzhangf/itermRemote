import 'dart:async';
import 'dart:io';

import 'host_config.dart';
import 'host_config_store.dart';

/// File-based config store.
///
/// The UI app decides where to store the file. This class is pure VM Dart.
class FileHostConfigStore implements HostConfigStore {
  final File file;
  final StreamController<HostConfig> _controller =
      StreamController<HostConfig>.broadcast();

  HostConfig? _cached;

  FileHostConfigStore({required this.file});

  @override
  Future<HostConfig> load() async {
    if (_cached != null) return _cached!;
    if (!await file.exists()) {
      final cfg = HostConfig(
        accountId: 'acc',
        stableId: 'stable',
        signalingServerUrl: '',
      );
      _cached = cfg;
      return cfg;
    }
    final s = await file.readAsString();
    final cfg = HostConfig.decode(s);
    _cached = cfg;
    return cfg;
  }

  @override
  Future<void> save(HostConfig config) async {
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(config.encode());
    _cached = config;
    _controller.add(config);
  }

  @override
  Stream<HostConfig> watch() async* {
    // Emit cached if already loaded.
    if (_cached != null) {
      yield _cached!;
    }
    yield* _controller.stream;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

