import 'dart:math';

import 'package:voice_social_app/core/network/api_exception.dart';

final Random _dynamicRequestIdRandom = Random.secure();
final RegExp _dynamicRequestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');
const int _maxDynamicRequestIdLength = 80;
const int _dynamicRequestEntropyLength = 32;

String newDynamicRequestId(String prefix) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty) {
    throw StateError('动态请求幂等 ID 前缀不能为空');
  }
  if (normalizedPrefix.length + 1 + _dynamicRequestEntropyLength >
      _maxDynamicRequestIdLength) {
    throw StateError('动态请求幂等 ID 前缀过长');
  }
  final String entropy = List<String>.generate(
    _dynamicRequestEntropyLength,
    (_) => _dynamicRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

String normalizeDynamicRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty || !_dynamicRequestIdPattern.hasMatch(value)) {
    throw StateError('动态请求幂等 ID 无效');
  }
  return value;
}

bool shouldRetainDynamicWriteRequest(Object error) {
  if (error is! ApiException) {
    return true;
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
    ApiFailureKind.business => false,
    ApiFailureKind.conflict => false,
  };
}
