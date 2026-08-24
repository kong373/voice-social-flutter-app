import 'dart:math';

import 'package:voice_social_app/core/network/api_exception.dart';

final Random _discoveryRequestIdRandom = Random.secure();
final RegExp _discoveryRequestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');
const int _discoveryRequestIdMaximumLength = 80;
const int _discoveryRequestIdEntropyLength = 32;

String newDiscoveryRequestId([String prefix = 'flutter-discovery']) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty ||
      !_discoveryRequestIdPattern.hasMatch(normalizedPrefix) ||
      normalizedPrefix.length + 1 + _discoveryRequestIdEntropyLength >
          _discoveryRequestIdMaximumLength) {
    throw StateError('发现写入请求幂等 ID 前缀无效');
  }
  final String entropy = List<String>.generate(
    _discoveryRequestIdEntropyLength,
    (_) => _discoveryRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

String normalizeDiscoveryRequestId(String requestId) {
  final String value = requestId.trim();
  if (!_discoveryRequestIdPattern.hasMatch(value)) {
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '发现写入请求幂等 ID 格式无效',
    );
  }
  return value;
}

bool shouldRetainDiscoveryWriteRequest(Object error) {
  if (error is! ApiException) {
    return true;
  }
  if (error.code == 40901 || error.code == 40902) {
    return true;
  }
  if (error.code == 40903 || error.kind == ApiFailureKind.conflict) {
    return false;
  }
  return switch (error.kind) {
    ApiFailureKind.network ||
    ApiFailureKind.timeout ||
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
