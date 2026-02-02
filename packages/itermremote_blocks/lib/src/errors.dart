class BlockError implements Exception {
  BlockError(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'BlockError($code): $message';
}

