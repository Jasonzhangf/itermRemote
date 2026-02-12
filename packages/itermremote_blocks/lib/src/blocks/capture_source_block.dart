import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

import '../block.dart';

class CaptureSourceBlock implements Block {
  CaptureSourceBlock();

  late BlockContext _ctx;

  @override
  String get name => 'capturesource';

  Map<String, Object?> _state = const {
    'ready': false,
    'sources': <Map<String, Object?>>[],
  };

  @override
  Map<String, Object?> get state => _state;

  @override
  Future<void> init(BlockContext ctx) async {
    _ctx = ctx;
    _state = const {
      'ready': true,
      'sources': <Map<String, Object?>>[],
    };
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
    _state = const {
      'ready': false,
      'sources': <Map<String, Object?>>[],
    };
  }

  @override
  Future<Ack> handle(Command cmd) async {
    try {
      switch (cmd.action) {
        case 'listSources':
          return await _listSources(cmd);
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
        code: 'capture_source_error',
        message: e.toString(),
      );
    }
  }

  Future<Ack> _listSources(Command cmd) async {
    final sources = <Map<String, Object?>>[];

    try {
      final allSources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
      );

      for (final src in allSources) {
        sources.add({
          'id': src.id,
          'name': src.name,
          'type': src.type == SourceType.Screen ? 'screen' : 'window',
          'label': src.name.isNotEmpty
              ? src.name
              : '${src.type == SourceType.Screen ? "Screen" : "Window"} ${sources.length + 1}',
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('[CaptureSource] desktopCapturer error: $e');
    }

    if (sources.isEmpty) {
      sources.add({
        'id': 'screen:0',
        'name': 'Screen 1',
        'type': 'screen',
        'label': 'Screen 1',
      });
    }

    _state = {
      ..._state,
      'sources': sources,
    };

    return Ack.ok(
      id: cmd.id,
      data: {
        'sources': sources,
        'count': sources.length,
      },
    );
  }
}
