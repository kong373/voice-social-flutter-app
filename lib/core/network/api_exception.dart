enum ApiFailureKind {
  configuration,
  network,
  timeout,
  unauthorized,
  forbidden,
  validation,
  conflict,
  business,
  server,
  protocol,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.code,
    this.httpStatus,
    this.cause,
  });

  final ApiFailureKind kind;
  final String message;
  final int? code;
  final int? httpStatus;
  final Object? cause;

  bool get isAuthenticationFailure =>
      kind == ApiFailureKind.unauthorized ||
      httpStatus == 401 ||
      (code != null && code! >= 40100 && code! < 40200);

  @override
  String toString() =>
      'ApiException($kind, code=$code, httpStatus=$httpStatus, $message)';
}
