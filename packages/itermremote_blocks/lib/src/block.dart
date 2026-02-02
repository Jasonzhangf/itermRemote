import 'dart:async';

import 'package:itermremote_protocol/itermremote_protocol.dart';

typedef JsonMap = Map<String, Object?>;

class BlockContext {
  BlockContext({required this.bus});

  final EventBus bus;
}

abstract class EventBus {
  void publish(Event evt);
}

abstract class Block {
  String get name;

  Future<void> init(BlockContext ctx);
  Future<void> dispose();

  /// Handle a command that has already been routed to this block.
  Future<Ack> handle(Command cmd);

  /// Optional: provide a state snapshot for UI hydration.
  JsonMap get state;
}

