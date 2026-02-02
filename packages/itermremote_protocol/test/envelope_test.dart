import 'package:itermremote_protocol/itermremote_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('Cmd -> json -> decode roundtrip', () {
    const codec = EnvelopeJsonCodec();
    const cmd = Command(
      version: itermremoteProtocolVersion,
      id: '1',
      target: 'iterm2',
      action: 'list',
      payload: {'k': 'v'},
    );

    final text = codec.encode(cmd);
    final decoded = codec.decode(text);

    expect(decoded, isA<Command>());
    final c = decoded as Command;
    expect(c.version, itermremoteProtocolVersion);
    expect(c.id, '1');
    expect(c.target, 'iterm2');
    expect(c.action, 'list');
    expect(c.payload, {'k': 'v'});
  });

  test('Version mismatch throws ProtocolVersionMismatch', () {
    const codec = EnvelopeJsonCodec(expectedVersion: 123);
    const ack = Ack(
      version: itermremoteProtocolVersion,
      id: 'x',
      success: true,
      data: {'ok': true},
    );

    expect(() => codec.decode(codec.encode(ack)), throwsA(isA<ProtocolVersionMismatch>()));
  });
}

