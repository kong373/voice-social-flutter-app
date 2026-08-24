import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/domain/refund_request_id.dart';

void main() {
  test('commerce refund request IDs are bounded and safe for headers', () {
    final String requestId = newCommerceRefundRequestId();
    expect(requestId.length, lessThanOrEqualTo(80));
    expect(normalizeCommerceRefundRequestId(requestId), requestId);
  });

  test('refund intent keys are deterministic opaque digests', () {
    const String orderNo = 'order-user-sensitive-20260823';
    const String reason = '退款原因包含用户输入';
    final String first = commerceRefundIntentDigest(
      scope: 'refund-submit',
      fields: const <String>[orderNo, reason],
    );
    final String second = commerceRefundIntentDigest(
      scope: 'refund-submit',
      fields: const <String>[orderNo, reason],
    );
    final String changed = commerceRefundIntentDigest(
      scope: 'refund-submit',
      fields: const <String>[orderNo, '不同原因'],
    );

    expect(first, second);
    expect(first, isNot(changed));
    expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(first, isNot(contains(orderNo)));
    expect(first, isNot(contains(reason)));
  });

  test(
    'refund retry retention classifies ambiguous and definitive failures',
    () {
      expect(
        shouldRetainCommerceRefundRequest(
          const ApiException(kind: ApiFailureKind.timeout, message: 'timeout'),
        ),
        isTrue,
      );
      expect(
        shouldRetainCommerceRefundRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40901,
            message: 'pending',
          ),
        ),
        isTrue,
      );
      expect(
        shouldRetainCommerceRefundRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40902,
            message: 'in progress',
          ),
        ),
        isTrue,
      );
      expect(
        shouldRetainCommerceRefundRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40903,
            message: 'fingerprint mismatch',
          ),
        ),
        isFalse,
      );
    },
  );
}
