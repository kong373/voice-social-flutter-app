import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Shared by payment return and explicit order-detail recovery. Never contains
/// a signed payment string; one first-party order retains one recovery key.
String alipayReconcileRequestId(String orderNo) {
  final digest = sha256
      .convert(utf8.encode('voice-social:alipay-reconcile:$orderNo'))
      .toString();
  return 'alipay-rec-$digest';
}
