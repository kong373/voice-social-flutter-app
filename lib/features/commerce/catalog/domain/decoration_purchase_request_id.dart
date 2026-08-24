import 'dart:math';

import 'package:voice_social_app/core/network/api_exception.dart';

final Random _decorationPurchaseRequestIdRandom = Random.secure();
final RegExp _decorationPurchaseRequestIdPattern = RegExp(
  r'^[A-Za-z0-9._:-]{1,80}$',
);
const int _maxDecorationPurchaseRequestIdLength = 80;
const int _decorationPurchaseRequestEntropyLength = 32;

String newDecorationPurchaseRequestId([
  String prefix = 'flutter-decoration-purchase',
]) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty) {
    throw StateError('装扮购买请求幂等 ID 前缀不能为空');
  }
  if (normalizedPrefix.length + 1 + _decorationPurchaseRequestEntropyLength >
      _maxDecorationPurchaseRequestIdLength) {
    throw StateError('装扮购买请求幂等 ID 前缀过长');
  }
  final String entropy = List<String>.generate(
    _decorationPurchaseRequestEntropyLength,
    (_) => _decorationPurchaseRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

String normalizeDecorationPurchaseRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty || !_decorationPurchaseRequestIdPattern.hasMatch(value)) {
    throw StateError('装扮购买请求幂等 ID 无效');
  }
  return value;
}

bool shouldRetainDecorationPurchaseRequest(Object error) {
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
