import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/message/domain/message_request_id.dart';

void main() {
  test('message request IDs are bounded opaque header values', () {
    final String requestId = createMessageRequestId();

    expect(requestId.length, lessThanOrEqualTo(80));
    expect(requestId, matches(RegExp(r'^[A-Za-z0-9._:-]+$')));
    expect(normalizeMessageRequestId(requestId), requestId);
  });

  test('message request IDs reject PII-like and oversized caller values', () {
    expect(
      () => normalizeMessageRequestId('phone 13800138000'),
      throwsStateError,
    );
    expect(() => normalizeMessageRequestId('x' * 81), throwsStateError);
    expect(() => normalizeMessageRequestId('消息-请求'), throwsStateError);
  });

  test('an omitted message request ID creates a safe value', () {
    final String generated = normalizeMessageRequestId(null);
    expect(generated.length, lessThanOrEqualTo(80));
    expect(generated, matches(RegExp(r'^[A-Za-z0-9._:-]+$')));
  });
}
