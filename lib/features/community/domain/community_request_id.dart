import 'dart:math';

import 'package:voice_social_app/core/network/api_exception.dart';

final Random _communityRequestIdRandom = Random.secure();
final RegExp _communityRequestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');
const int _communityRequestIdMaximumLength = 80;
const int _communityRequestIdEntropyLength = 32;

/// Creates a bounded, cryptographically random idempotency key for a
/// first-party community mutation.
String newCommunityRequestId([String prefix = 'flutter-community']) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty) {
    throw StateError('社区写入请求幂等 ID 前缀不能为空');
  }
  if (!_communityRequestIdPattern.hasMatch(normalizedPrefix) ||
      normalizedPrefix.length + 1 + _communityRequestIdEntropyLength >
          _communityRequestIdMaximumLength) {
    throw StateError('社区写入请求幂等 ID 前缀过长或格式无效');
  }
  final String entropy = List<String>.generate(
    _communityRequestIdEntropyLength,
    (_) => _communityRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

/// Validates an idempotency key before it is sent to the backend.
String normalizeCommunityRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty || !_communityRequestIdPattern.hasMatch(value)) {
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '请求幂等 ID 格式无效',
    );
  }
  return value;
}

/// Returns whether a failed mutation can safely be retried with its existing
/// idempotency key. Unknown outcomes retain the key; definitive failures get
/// a fresh key for a later user intent.
bool shouldRetainCommunityWriteRequest(Object error) {
  if (error is! ApiException) {
    return true;
  }
  if (error.code == 40901 || error.code == 40902) {
    return true;
  }
  if (error.code == 40903) {
    return false;
  }
  if (error.kind == ApiFailureKind.conflict) {
    return false;
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
