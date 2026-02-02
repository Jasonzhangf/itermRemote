import 'package:cloudplayplus_core/cloudplayplus_core.dart';
import 'package:test/test.dart';
import 'package:iterm2_host/iterm2/iterm2_bridge.dart';
import 'package:iterm2_host/streaming/stream_host.dart';

void main() {
  group('StreamHost', () {
    test('initialize loads sessions and sets state to ready', () async {
      final bridge = _FakeBridge(okSessions: const [
        ITerm2SessionInfo(
          sessionId: 'sess-1',
          title: '1.1.1',
          detail: 'bash',
          index: 0,
        ),
        ITerm2SessionInfo(
          sessionId: 'sess-2',
          title: '1.1.2',
          detail: 'python',
          index: 1,
        ),
      ]);

      final host = StreamHost(iterm2Bridge: bridge, enableWebRTC: false);
      await host.initialize();
      expect(host.state.value, StreamState.ready);
      expect(host.sessions.value.length, 2);
      host.dispose();
    });

    test('initialize throws and sets state=error when session fetch fails',
        () async {
      final host = StreamHost(iterm2Bridge: _FailingBridge(), enableWebRTC: false);
      await expectLater(
        host.initialize(),
        throwsA(isA<StreamHostException>()),
      );
      expect(host.state.value, StreamState.error);
      host.dispose();
    });

    test('refreshSessions updates sessions list', () async {
      final bridge = _FakeBridge(okSessions: const []);
      final host = StreamHost(iterm2Bridge: bridge, enableWebRTC: false);
      await host.initialize();

      bridge.okSessions = const [
        ITerm2SessionInfo(
          sessionId: 'sess-3',
          title: '1.1.3',
          detail: 'node',
          index: 2,
        ),
      ];

      await host.refreshSessions();
      expect(host.state.value, StreamState.ready);
      expect(host.sessions.value.length, 1);
      expect(host.sessions.value.first.sessionId, 'sess-3');
      host.dispose();
    });
  });
}

class _FakeBridge extends ITerm2Bridge {
  List<ITerm2SessionInfo> okSessions;
  _FakeBridge({required this.okSessions});

  @override
  Future<List<ITerm2SessionInfo>> getSessions() async => okSessions;

  // Not used in these tests; keep deterministic stubs.
  @override
  Future<Map<String, dynamic>> activateSession(String sessionId) async =>
      <String, dynamic>{'sessionId': sessionId};

  @override
  Future<bool> sendText(String sessionId, String text) async => true;

  @override
  Future<String> readSessionBuffer(String sessionId, int maxBytes) async => '';
}

class _FailingBridge extends ITerm2Bridge {
  @override
  Future<List<ITerm2SessionInfo>> getSessions() async {
    throw Exception('boom');
  }

  @override
  Future<Map<String, dynamic>> activateSession(String sessionId) async {
    throw Exception('boom');
  }

  @override
  Future<bool> sendText(String sessionId, String text) async {
    throw Exception('boom');
  }

  @override
  Future<String> readSessionBuffer(String sessionId, int maxBytes) async {
    throw Exception('boom');
  }
}
