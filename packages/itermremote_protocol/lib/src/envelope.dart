import 'version.dart';

typedef JsonMap = Map<String, Object?>;

enum EnvelopeType {
  cmd,
  ack,
  evt,
}

EnvelopeType _parseType(String v) {
  switch (v) {
    case 'cmd':
      return EnvelopeType.cmd;
    case 'ack':
      return EnvelopeType.ack;
    case 'evt':
      return EnvelopeType.evt;
  }
  throw ArgumentError('Unknown envelope type: $v');
}

abstract class Envelope {
  const Envelope({required this.version, required this.type});

  final int version;
  final EnvelopeType type;

  JsonMap toJson();

  static Envelope fromJson(JsonMap json) {
    final version = json['version'];
    if (version is! int) {
      throw ArgumentError('Missing/invalid version');
    }
    final t = json['type'];
    if (t is! String) {
      throw ArgumentError('Missing/invalid type');
    }
    final type = _parseType(t);
    switch (type) {
      case EnvelopeType.cmd:
        return Command.fromJson(json);
      case EnvelopeType.ack:
        return Ack.fromJson(json);
      case EnvelopeType.evt:
        return Event.fromJson(json);
    }
  }

  static JsonMap baseJson({required EnvelopeType type, int? version}) => {
        'version': version ?? itermremoteProtocolVersion,
        'type': switch (type) {
          EnvelopeType.cmd => 'cmd',
          EnvelopeType.ack => 'ack',
          EnvelopeType.evt => 'evt',
        },
      };
}

class Command extends Envelope {
  const Command({
    required super.version,
    required this.id,
    required this.target,
    required this.action,
    this.payload,
  }) : super(type: EnvelopeType.cmd);

  final String id;
  final String target;
  final String action;
  final JsonMap? payload;

  @override
  JsonMap toJson() => {
        ...Envelope.baseJson(type: type, version: version),
        'id': id,
        'target': target,
        'action': action,
        'payload': payload,
      };

  static Command fromJson(JsonMap json) {
    final version = json['version'];
    final id = json['id'];
    final target = json['target'];
    final action = json['action'];
    if (version is! int || id is! String || target is! String || action is! String) {
      throw ArgumentError('Invalid cmd');
    }
    final payload = json['payload'];
    return Command(
      version: version,
      id: id,
      target: target,
      action: action,
      payload: payload is Map<String, Object?> ? payload : (payload is Map ? payload.cast<String, Object?>() : null),
    );
  }
}

class AckError {
  const AckError({required this.code, required this.message, this.details});

  final String code;
  final String message;
  final Object? details;

  JsonMap toJson() => {
        'code': code,
        'message': message,
        'details': details,
      };

  static AckError fromJson(Object? v) {
    if (v is! Map) throw ArgumentError('Invalid ack.error');
    final m = v.cast<String, Object?>();
    final code = m['code'];
    final message = m['message'];
    if (code is! String || message is! String) {
      throw ArgumentError('Invalid ack.error');
    }
    return AckError(code: code, message: message, details: m['details']);
  }
}

class Ack extends Envelope {
  const Ack({
    required super.version,
    required this.id,
    required this.success,
    this.data,
    this.error,
  }) : super(type: EnvelopeType.ack);

  final String id;
  final bool success;
  final JsonMap? data;
  final AckError? error;

  factory Ack.ok({required String id, JsonMap? data, int? version}) => Ack(
        version: version ?? itermremoteProtocolVersion,
        id: id,
        success: true,
        data: data,
      );

  factory Ack.fail({
    required String id,
    required String code,
    required String message,
    Object? details,
    int? version,
  }) =>
      Ack(
        version: version ?? itermremoteProtocolVersion,
        id: id,
        success: false,
        error: AckError(code: code, message: message, details: details),
      );

  @override
  JsonMap toJson() => {
        ...Envelope.baseJson(type: type, version: version),
        'id': id,
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error!.toJson(),
      };

  static Ack fromJson(JsonMap json) {
    final version = json['version'];
    final id = json['id'];
    final success = json['success'];
    if (version is! int || id is! String || success is! bool) {
      throw ArgumentError('Invalid ack');
    }
    final data = json['data'];
    final error = json['error'];
    return Ack(
      version: version,
      id: id,
      success: success,
      data: data is Map<String, Object?> ? data : (data is Map ? data.cast<String, Object?>() : null),
      error: error == null ? null : AckError.fromJson(error),
    );
  }
}

class Event extends Envelope {
  const Event({
    required super.version,
    required this.source,
    required this.event,
    required this.ts,
    this.payload,
  }) : super(type: EnvelopeType.evt);

  final String source;
  final String event;
  final int ts;
  final JsonMap? payload;

  @override
  JsonMap toJson() => {
        ...Envelope.baseJson(type: type, version: version),
        'source': source,
        'event': event,
        'ts': ts,
        'payload': payload,
      };

  static Event fromJson(JsonMap json) {
    final version = json['version'];
    final source = json['source'];
    final event = json['event'];
    final ts = json['ts'];
    if (version is! int || source is! String || event is! String || ts is! int) {
      throw ArgumentError('Invalid evt');
    }
    final payload = json['payload'];
    return Event(
      version: version,
      source: source,
      event: event,
      ts: ts,
      payload: payload is Map<String, Object?> ? payload : (payload is Map ? payload.cast<String, Object?>() : null),
    );
  }
}

