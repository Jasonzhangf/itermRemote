class ProtocolError implements Exception {
  ProtocolError(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'ProtocolError($code): $message';
}

class ProtocolVersionMismatch implements Exception {
  ProtocolVersionMismatch({required this.expected, required this.actual});

  final int expected;
  final int actual;

  @override
  String toString() =>
      'ProtocolVersionMismatch(expected=$expected, actual=$actual)';
}

