import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

const request = RefundRequest(
  account: '13800138000',
  realName: '测试用户',
  age: 25,
  amount: 1,
  reason: '退款测试原因',
  receivingAccount: 'masked',
  receivingName: '测*',
  guardianName: '',
  guardianPhone: '',
);

void main() {
  test('Q10-04 and Q15-06 remove share and refund registrations', () {
    for (final id in ['RM-009', 'CM-007', 'CM-008']) {
      expect(appPageManifest.where((page) => page.id == id), isEmpty);
      expect(qaPageCatalog.where((page) => page.id == id), isEmpty);
      expect(removedProductPages[id], 'REMOVED_BY_PRODUCT');
    }
  });

  for (final backend in [true, false]) {
    test(
      '${backend ? 'Backend' : 'Mock'} refund writes reject without HTTP or state changes',
      () async {
        final client = _NoNetwork();
        final CommerceRepository repository = backend
            ? BackendCommerceRepository(
                apiClient: client,
                routes: const BackendRouteCatalog(),
              )
            : MockCommerceRepository();
        final before = backend
            ? null
            : await repository.fetchRefundApplications('13800138000');
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            repository.submitRefund(request),
            throwsA(isA<UnsupportedError>()),
          );
          await expectLater(
            repository.resubmitRefund(
              before?.first.id ?? 'refund-1',
              expectedOrderNo: request.account,
            ),
            throwsA(isA<UnsupportedError>()),
          );
        }
        expect(client.calls, 0);
        if (before != null) {
          final after = await repository.fetchRefundApplications('13800138000');
          expect(
            after.map((row) => (row.id, row.status)),
            before.map((row) => (row.id, row.status)),
          );
        }
      },
    );
  }

  testWidgets('wallet keeps orders and ledger without refund entry', (
    tester,
  ) async {
    final dependencies = AppDependencies.mock();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: CommerceHubPage(account: '13800138000')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退款申请'), findsNothing);
    expect(find.text('订单退款'), findsNothing);
    expect(find.text('充值订单'), findsOneWidget);
    expect(find.text('钱包与流水'), findsOneWidget);
  });
}

class _NoNetwork implements ApiClient {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected request ${invocation.memberName}');
  }
}
