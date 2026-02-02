import 'dart:convert';

import 'envelope.dart';
import 'errors.dart';
import 'version.dart';

class EnvelopeJsonCodec {
  const EnvelopeJsonCodec({this.expectedVersion = itermremoteProtocolVersion});

  final int expectedVersion;

  String encode(Envelope env) => jsonEncode(env.toJson());

  Envelope decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw ProtocolError('invalid_json', 'Expected a JSON object');
    }
    final m = decoded.cast<String, Object?>();
    final env = Envelope.fromJson(m);
    if (env.version != expectedVersion) {
      throw ProtocolVersionMismatch(expected: expectedVersion, actual: env.version);
    }
    return env;
  }
}

