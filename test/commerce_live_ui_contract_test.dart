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
  testWidgets('withdrawal UI refuses invalid amounts before quote or write', (
    tester,
  ) async {
    final repository = _WithdrawalAmountSpy();
    await tester.pumpWidget(
      MaterialApp(home: WithdrawalPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    for (final amount in [
      '99',
      '100.01',
      '100.000000000000001',
      'NaN',
      'Infinity',
      '1e308',
      '90071992547410',
    ]) {
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), amount);
      await tester.ensureVisible(find.text('计算到账金额'));
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();
      expect(repository.quotes, 0, reason: amount);
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
    }
    expect(repository.quotes, 0);
    expect(repository.writes, 0);
  });

  testWidgets(
    'confirmation shows authoritative nonzero fee and daily conflict stays visible',
    (tester) async {
      final repository = _WithdrawalAmountSpy();
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '100');
      await tester.ensureVisible(find.text('计算到账金额'));
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('提现金额：¥100.00\n手续费（5.00%）：¥5.00\n预计到账：¥95.00'),
        findsOneWidget,
      );
      expect(repository.writes, 0);
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(find.text('北京时间今日已提交提现申请，请次日重新申请'), findsOneWidget);
      expect(find.text('提现申请已提交'), findsNothing);
    },
  );

  testWidgets(
    'balance under 100 leaves history visible but disables submission',
    (tester) async {
      final repository = MockCommerceRepository(initialCashBalance: 99.99);
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '申请提现'))
            .onPressed,
        isNull,
      );
      expect(find.text('提现记录'), findsOneWidget);
    },
  );

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
    expect(find.text('输入整元金额后计算手续费和预计到账金额'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('计算到账金额'));
    await tester.pumpAndSettle();
    expect(find.textContaining('持卡人 晚*'), findsOneWidget);
    expect(find.textContaining('服务端报价'), findsOneWidget);
    expect(find.textContaining('预计到账 ¥100.00'), findsOneWidget);
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
      minimumAmount: 100,
    );
  }
}

class _WithdrawalAmountSpy extends MockCommerceRepository {
  int quotes = 0;
  int writes = 0;

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) async {
    quotes++;
    return WithdrawalQuote(
      quotedAmount: amount,
      feeAmount: 5,
      receivedAmount: amount - 5,
      feeRate: .05,
      feeRateText: '5.00%',
      minimumAmount: 100,
    );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    String? payoutAccountId,
  }) async {
    writes++;
    throw const ApiException(
      kind: ApiFailureKind.conflict,
      httpStatus: 409,
      message: '北京时间今日已提交提现申请，请次日重新申请',
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
