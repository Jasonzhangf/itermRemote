import 'dart:io';

import 'package:iterm2_host/config/file_host_config_store.dart';
import 'package:iterm2_host/config/host_config.dart';
import 'package:test/test.dart';

void main() {
  group('FileHostConfigStore', () {
    test('save then load roundtrip', () async {
      final dir = await Directory.systemTemp.createTemp('host_config_store_test');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });

      final f = File('${dir.path}/host_config.json');
      final store = FileHostConfigStore(file: f);

      final cfg = HostConfig(
        accountId: 'acc',
        stableId: 'stable',
        signalingServerUrl: 'wss://s',
        logLevel: 'info',
      );

      await store.save(cfg);
      final loaded = await store.load();
      expect(loaded.accountId, 'acc');
      expect(loaded.stableId, 'stable');
      expect(loaded.signalingServerUrl, 'wss://s');
    });
  });
}

