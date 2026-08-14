enum ApiFailureKind {
  configuration,
  network,
  timeout,
  unauthorized,
  forbidden,
  validation,
  business,
  server,
  protocol,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.code,
    this.cause,
  });

  final ApiFailureKind kind;
  final String message;
  final int? code;
  final Object? cause;

  @override
  String toString() => 'ApiException($kind, $code, $message)';
}
