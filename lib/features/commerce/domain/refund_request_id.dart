import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

final Random _commerceRefundRequestIdRandom = Random.secure();
final RegExp _commerceRefundRequestIdPattern = RegExp(
  r'^[A-Za-z0-9._:-]{1,80}$',
);
const int _commerceRefundRequestIdMaximumLength = 80;
const int _commerceRefundRequestIdEntropyLength = 32;

String newCommerceRefundRequestId([String prefix = 'flutter-commerce-refund']) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty) {
    throw StateError('退款请求幂等 ID 前缀不能为空');
  }
  if (normalizedPrefix.length + 1 + _commerceRefundRequestIdEntropyLength >
      _commerceRefundRequestIdMaximumLength) {
    throw StateError('退款请求幂等 ID 前缀过长');
  }
  final String entropy = List<String>.generate(
    _commerceRefundRequestIdEntropyLength,
    (_) => _commerceRefundRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}

String normalizeCommerceRefundRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty || !_commerceRefundRequestIdPattern.hasMatch(value)) {
    throw StateError('退款请求幂等 ID 无效');
  }
  return value;
}

/// Produces an opaque, stable key for coordinating a logical refund intent.
///
/// Raw order numbers and user-authored refund reasons must not remain in
/// process-wide map keys or diagnostic snapshots. Length-prefixing the UTF-8
/// values keeps the canonical representation unambiguous before hashing.
String commerceRefundIntentDigest({
  required String scope,
  required List<String> fields,
}) {
  final List<int> bytes = <int>[];

  void append(String value) {
    final List<int> encoded = utf8.encode(value);
    bytes
      ..addAll(utf8.encode('${encoded.length}:'))
      ..addAll(encoded);
  }

  append(scope);
  for (final String field in fields) {
    append(field);
  }
  return sha256.convert(bytes).toString();
}

/// Returns whether a failed economic write may be retried with its existing
/// idempotency key.  Unknown outcomes keep the key; a new key is reserved for
/// definitive failures so a later attempt cannot be mistaken for the old one.
bool shouldRetainCommerceRefundRequest(Object error) {
  if (error is! ApiException) {
    return true;
  }
  if (error.code == 40903) {
    return false;
  }
  if (error.code == 40901 || error.code == 40902) {
    return true;
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
    ApiFailureKind.business => false,
    ApiFailureKind.conflict => false,
  };
}
