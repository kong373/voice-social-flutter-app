import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/decoration_purchase_request_id.dart';

void main() {
  test(
    'generated decoration purchase request ids stay within backend limit',
    () {
      final String requestId = newDecorationPurchaseRequestId();
      expect(requestId.length, lessThanOrEqualTo(80));
      expect(normalizeDecorationPurchaseRequestId(requestId), requestId);
    },
  );

  test(
    'decoration purchase retry classification follows backend idempotency codes',
    () {
      expect(
        shouldRetainDecorationPurchaseRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40901,
            message: '状态冲突，请重试',
          ),
        ),
        isTrue,
      );
      expect(
        shouldRetainDecorationPurchaseRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40902,
            message: '相同请求正在处理中',
          ),
        ),
        isTrue,
      );
      expect(
        shouldRetainDecorationPurchaseRequest(
          const ApiException(
            kind: ApiFailureKind.conflict,
            code: 40903,
            message: '请求指纹不一致',
          ),
        ),
        isFalse,
      );
      expect(
        shouldRetainDecorationPurchaseRequest(
          const ApiException(kind: ApiFailureKind.validation, message: '商品不存在'),
        ),
        isFalse,
      );
    },
  );
}
