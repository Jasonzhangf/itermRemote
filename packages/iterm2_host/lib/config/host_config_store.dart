import 'dart:async';

import 'host_config.dart';

/// Storage interface for [HostConfig].
///
/// Implementations must be usable on the Dart VM.
abstract class HostConfigStore {
  Future<HostConfig> load();
  Future<void> save(HostConfig config);

  /// Emits the latest config whenever it changes.
  Stream<HostConfig> watch();
}

