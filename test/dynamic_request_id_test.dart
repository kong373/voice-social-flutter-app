import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_request_id.dart';

void main() {
  test('generated dynamic request ids stay within backend limit', () {
    final String requestId = newDynamicRequestId('dynamic-like');
    expect(requestId.length, lessThanOrEqualTo(80));
    expect(normalizeDynamicRequestId(requestId), requestId);
  });

  test('conflict retry classification follows backend idempotency codes', () {
    expect(
      shouldRetainDynamicWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40901,
          message: '状态冲突，请重试',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainDynamicWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40902,
          message: '相同请求正在处理中',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainDynamicWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40903,
          message: '请求指纹不一致',
        ),
      ),
      isFalse,
    );
  });
}
