import 'dart:math';

final RegExp _messageRequestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');

/// Creates a bounded, opaque request key for one user submission.
///
/// The UI keeps this value while a send is retried. It is deliberately not
/// derived from message content, so two later identical submissions remain
/// distinct operations.
String createMessageRequestId() {
  final Random random = Random.secure();
  final String entropy = List<String>.generate(
    4,
    (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
  return 'flutter-message-$entropy';
}

String normalizeMessageRequestId(String? requestId) {
  final String value = requestId?.trim() ?? '';
  if (value.isEmpty) {
    return createMessageRequestId();
  }
  if (!_messageRequestIdPattern.hasMatch(value)) {
    throw StateError('消息请求幂等 ID 无效');
  }
  return value;
}
