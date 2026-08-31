import 'dart:math';

final Random _alipayCreateRequestIdRandom = Random.secure();
const int _alipayCreateRequestIdEntropyLength = 32;

/// Creates an opaque idempotency key for one logical Alipay order creation.
///
/// The key is intentionally independent of the account, product, amount, and
/// signed order string. Those values are bound by the authenticated backend;
/// this value only gives an ambiguous retry a stable request boundary.
String newAlipayCreateRequestId([String prefix = 'flutter-alipay-create']) {
  final String normalizedPrefix = prefix.trim();
  if (normalizedPrefix.isEmpty) {
    throw StateError('支付宝下单请求幂等 ID 前缀不能为空');
  }
  final String entropy = List<String>.generate(
    _alipayCreateRequestIdEntropyLength,
    (_) => _alipayCreateRequestIdRandom.nextInt(16).toRadixString(16),
    growable: false,
  ).join();
  return '$normalizedPrefix-$entropy';
}
