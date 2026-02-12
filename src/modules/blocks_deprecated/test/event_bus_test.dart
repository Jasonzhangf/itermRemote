import 'dart:async';
import 'package:test/test.dart';
import 'package:itermremote_blocks/itermremote_blocks.dart';
import 'package:itermremote_protocol/itermremote_protocol.dart';

void main() {
  group('InMemoryEventBus', () {
    test('publish and stream', () async {
      final bus = InMemoryEventBus();
      final events = <Event>[];

      final sub = bus.stream.listen(events.add);

      bus.publish(Event(version: 1, source: 'test', event: 'test', ts: 0, payload: {'key': 'value'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.length, 1);
      expect(events.first.source, 'test');
      expect(events.first.payload?['key'], 'value');

      await sub.cancel();
    });

    test('multiple listeners receive same event', () async {
      final bus = InMemoryEventBus();
      final events1 = <Event>[];
      final events2 = <Event>[];

      final sub1 = bus.stream.listen(events1.add);
      final sub2 = bus.stream.listen(events2.add);

      bus.publish(Event(version: 1, source: 'test', event: 'test', ts: 0, payload: {'data': 'hello'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events1.length, 1);
      expect(events2.length, 1);
      expect(events1.first.payload?['data'], 'hello');
      expect(events2.first.payload?['data'], 'hello');

      await sub1.cancel();
      await sub2.cancel();
    });

    test('publish different events', () async {
      final bus = InMemoryEventBus();
      final events = <Event>[];

      final sub = bus.stream.listen(events.add);

      bus.publish(Event(version: 1, source: 'source1', event: 'evt1', ts: 0, payload: {'msg': 'one'}));
      bus.publish(Event(version: 1, source: 'source2', event: 'evt2', ts: 0, payload: {'msg': 'two'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.length, 2);
      expect(events[0].source, 'source1');
      expect(events[0].payload?['msg'], 'one');
      expect(events[1].source, 'source2');
      expect(events[1].payload?['msg'], 'two');

      await sub.cancel();
    });
  });
}
