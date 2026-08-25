import 'dart:math';

import 'package:voice_social_app/core/network/api_exception.dart';

final Random _accountComplianceRequestIdRandom = Random.secure();
final RegExp _accountComplianceRequestIdPattern = RegExp(
  r'^[A-Za-z0-9._:-]{1,80}$',
);
const int _accountComplianceRequestIdMaximumLength = 80;
const int _accountComplianceRequestIdEntropyLength = 32;

/// Creates an opaque, bounded idempotency key for one account mutation.
///
/// Account mutations are first-party writes.  The key is deliberately
/// random instead of being derived from PII or a PIN, and is retained only
/// while a retry may still represent the same logical operation.
String newAccountComplianceRequestId([
  String prefix = 'flutter-account-compliance',
]) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty ||
      !_accountComplianceRequestIdPattern.hasMatch(normalizedPrefix) ||
      normalizedPrefix.length + 1 + _accountComplianceRequestIdEntropyLength >
          _accountComplianceRequestIdMaximumLength) {
    throw StateError('账户合规请求幂等 ID 前缀无效或过长');
  }
  final String entropy = List<String>.generate(
    _accountComplianceRequestIdEntropyLength,
    (_) => _accountComplianceRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

String normalizeAccountComplianceRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty || !_accountComplianceRequestIdPattern.hasMatch(value)) {
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '账户合规请求幂等 ID 格式无效',
    );
  }
  return value;
}

/// Keep a key for outcomes where the server may have committed the write but
/// the client cannot prove it.  Retrying with a new key would risk a second
/// account mutation.  Definitive validation/auth/business failures can use a
/// fresh key on a later, new user intent.
bool shouldRetainAccountComplianceRequest(Object error) {
  if (error is! ApiException) {
    return true;
  }
  if (error.code == 40903) {
    return false;
  }
  if (error.kind == ApiFailureKind.conflict) {
    return error.code == 40901 || error.code == 40902;
  }
  return switch (error.kind) {
    ApiFailureKind.timeout ||
    ApiFailureKind.network ||
    ApiFailureKind.protocol ||
    ApiFailureKind.server => true,
    ApiFailureKind.configuration ||
    ApiFailureKind.unauthorized ||
    ApiFailureKind.forbidden ||
    ApiFailureKind.validation ||
    ApiFailureKind.business ||
    ApiFailureKind.conflict => false,
  };
}
