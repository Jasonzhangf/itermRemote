import 'dart:async';

import 'package:itermremote_protocol/itermremote_protocol.dart';

import 'block.dart';

class InMemoryEventBus implements EventBus {
  InMemoryEventBus();

  final _controller = StreamController<Event>.broadcast();

  Stream<Event> get stream => _controller.stream;

  @override
  void publish(Event evt) {
    _controller.add(evt);
  }

  Future<void> close() => _controller.close();
}

