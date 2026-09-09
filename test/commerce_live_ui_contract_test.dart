import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

void main() {
  // REMOVED_BY_PRODUCT Q15-06: refund form positives; see retirement ledger.
  testWidgets('withdrawal quote is requested for the entered amount', (
    WidgetTester tester,
  ) async {
    final dependencies = await createQaDependencies();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const WithdrawalPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('计算到账金额'), findsOneWidget);
    expect(find.text('输入金额后计算手续费和预计到账金额'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('计算到账金额'));
    await tester.pumpAndSettle();
    expect(find.textContaining('持卡人 晚*'), findsOneWidget);
    expect(find.textContaining('服务端报价'), findsOneWidget);
    expect(find.textContaining('预计到账 ¥98.00'), findsOneWidget);
  });

  testWidgets(
    'live withdrawal blocker leaves the first-party quote and records visible',
    (WidgetTester tester) async {
      final _WithdrawalUiSpyRepository repository =
          _WithdrawalUiSpyRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: WithdrawalPage(repository: repository),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('基于 payoutAccountId 的提现申请'), findsOneWidget);
      expect(find.text('计算到账金额'), findsOneWidget);
      expect(find.text('提现记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '100');
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();

      expect(find.textContaining('服务端报价'), findsOneWidget);
      expect(find.textContaining('预计到账 ¥98.00'), findsOneWidget);
      final FilledButton apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '申请提现'),
      );
      expect(apply.onPressed, isNull);
    },
  );

  testWidgets(
    'payout account transport failures remain visible and retryable',
    (WidgetTester tester) async {
      final _FailingPayoutAccountRepository repository =
          _FailingPayoutAccountRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: WithdrawalPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收款账户服务连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('尚未提供 payoutAccountId'), findsNothing);
    },
  );

  // REMOVED_BY_PRODUCT Q15-06: remaining refund form/result/retry positives.
}

class _WithdrawalUiSpyRepository extends MockCommerceRepository {
  @override
  bool get supportsWithdrawalApplication => false;

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) async {
    return WithdrawalQuote(
      quotedAmount: amount,
      feeAmount: amount * 0.02,
      receivedAmount: amount * 0.98,
      feeRate: 0.02,
      feeRateText: '2.00%',
      minimumAmount: 10,
    );
  }
}

class _FailingPayoutAccountRepository extends MockCommerceRepository {
  @override
  bool get supportsWithdrawalApplication => true;

  @override
  bool get supportsPayoutAccountSelection => true;

  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() =>
      Future<PayoutAccountSelection>.error(
        const ApiException(kind: ApiFailureKind.network, message: '收款账户服务连接失败'),
      );
}
