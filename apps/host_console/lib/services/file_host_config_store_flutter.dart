import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:iterm2_host/config/file_host_config_store.dart';
import 'package:iterm2_host/config/host_config.dart';
import 'package:iterm2_host/config/host_config_store.dart';

/// Flutter-friendly wrapper that chooses a default config location.
///
/// We avoid platform plugins in Phase-1; store under user's HOME.
class FileHostConfigStoreFlutter implements HostConfigStore {
  late final FileHostConfigStore _inner;

  FileHostConfigStoreFlutter() {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.itermremote');
    final f = File('${dir.path}/host_config.json');
    _inner = FileHostConfigStore(file: f);
    if (kDebugMode) {
      // ignore: avoid_print
      print('Host config path: ${f.path}');
    }
  }

  @override
  Future<HostConfig> load() => _inner.load();

  @override
  Future<void> save(HostConfig config) => _inner.save(config);

  @override
  Stream<HostConfig> watch() => _inner.watch();
}
