import 'dart:async';

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
  testWidgets('U01 account switch hides A intent and ignores late A success', (
    tester,
  ) async {
    final repository = _IdentityWithdrawalSpy();
    await tester.pumpWidget(
      MaterialApp(home: WithdrawalPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '101');
    repository.changes.notifyListeners();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '101',
    );
    await tester.ensureVisible(find.text('计算到账金额'));
    await tester.tap(find.text('计算到账金额'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('申请提现'));
    await tester.tap(find.text('申请提现'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提现'));
    await tester.pump();
    expect(repository.pendingWithdrawal?.amount, 101);
    repository.switchTo(null);
    await tester.pump();
    repository.switchTo('B');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(repository.pendingWithdrawal, isNull);
    repository.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('提现申请已提交'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    repository.switchTo('A');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '101',
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(repository.pendingWithdrawal?.amount, 101);
    await tester.pumpWidget(const SizedBox());
    repository.changes.dispose();
  });

  testWidgets(
    'U01 page recreation restores unresolved confirmed intent without new quote',
    (tester) async {
      final repository = _ResumeWithdrawalSpy();
      final frozenBefore =
          (await repository.fetchWalletSummary()).frozenBalance;
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '101');
      await tester.ensureVisible(find.text('计算到账金额'));
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repository.pendingWithdrawal, isNotNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '101',
      );
      expect(repository.quoteCalls, 1);
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计到账：¥101.00'), findsOneWidget);
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repository.quoteCalls, 1);
      expect(repository.attempts, 2);
      expect(repository.pendingWithdrawal, isNull);
      expect(
        (await repository.fetchWalletSummary()).frozenBalance,
        frozenBefore + 101,
      );
    },
  );
  testWidgets(
    'U01 confirmation captures amount account quote and 409 requires a new confirmation',
    (tester) async {
      final repository = _FeePolicySpy()..updateWithdrawalFeePolicy(50);
      final frozenBefore =
          (await repository.fetchWalletSummary()).frozenBalance;
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '101');
      await tester.ensureVisible(find.text('计算到账金额'));
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计到账：¥100.49'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      field.controller!.text =
          '200'; // An external update cannot replace the confirmed intent.
      repository.updateWithdrawalFeePolicy(100);
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repository.submissions.single.amount, 101);
      expect(repository.submissions.single.payoutAccountId, 'card-1');
      expect(repository.submissions.single.quote.feeAmount, .51);
      expect(find.textContaining('提现报价已变化'), findsOneWidget);
      expect(repository.submissions, hasLength(1));
      await tester.enterText(find.byType(TextField), '101');
      await tester.ensureVisible(find.text('计算到账金额'));
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();
      expect(repository.submissions, hasLength(1));
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计到账：¥99.99'), findsOneWidget);
      expect(repository.submissions, hasLength(1));
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repository.submissions, hasLength(2));
      expect(
        (await repository.fetchWalletSummary()).frozenBalance,
        frozenBefore + 101,
      );
    },
  );
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

class _IdentityWithdrawalSpy extends MockCommerceRepository {
  final changes = ChangeNotifier();
  final release = Completer<void>();
  String? user = 'A';
  int generation = 0;
  ConfirmedWithdrawal? pendingA;
  @override
  (String?, int) get withdrawalIdentity => (user, generation);
  @override
  ChangeNotifier get withdrawalIdentityChanges => changes;
  @override
  ConfirmedWithdrawal? get pendingWithdrawal => user == 'A' ? pendingA : null;
  void switchTo(String? next) {
    user = next;
    generation++;
    changes.notifyListeners();
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async {
    pendingA = ConfirmedWithdrawal(
      amount: amount,
      payoutAccountId: payoutAccountId!,
      quote: confirmedQuote,
    );
    final receipt = (await fetchWithdrawalRecords(
      page: 1,
      pageSize: 20,
    )).items.first;
    await release.future;
    // Deliberately deliver an old success to verify the page's independent guard.
    return receipt;
  }
}

class _ResumeWithdrawalSpy extends MockCommerceRepository {
  ConfirmedWithdrawal? _pending;
  int attempts = 0;
  int quoteCalls = 0;
  @override
  ConfirmedWithdrawal? get pendingWithdrawal => _pending;
  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) {
    quoteCalls++;
    return super.fetchWithdrawalQuote(amount: amount);
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async {
    attempts++;
    if (attempts == 1) {
      _pending = ConfirmedWithdrawal(
        amount: amount,
        payoutAccountId: payoutAccountId!,
        quote: confirmedQuote,
      );
      throw const ApiException(
        kind: ApiFailureKind.server,
        message: '结果未知，请重试原申请',
      );
    }
    expect(amount, _pending!.amount);
    expect(payoutAccountId, _pending!.payoutAccountId);
    expect(identical(confirmedQuote, _pending!.quote), isTrue);
    final result = await super.applyWithdrawal(
      amount: amount,
      confirmedQuote: confirmedQuote,
      payoutAccountId: payoutAccountId,
    );
    _pending = null;
    return result;
  }
}

class _FeePolicySpy extends MockCommerceRepository {
  @override
  bool get supportsPayoutAccountSelection => true;
  final submissions = <ConfirmedWithdrawal>[];
  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) {
    submissions.add(
      ConfirmedWithdrawal(
        amount: amount,
        payoutAccountId: payoutAccountId!,
        quote: confirmedQuote,
      ),
    );
    return super.applyWithdrawal(
      amount: amount,
      confirmedQuote: confirmedQuote,
      payoutAccountId: payoutAccountId,
    );
  }
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
      feeRateBasisPoints: 200,
      feePolicyVersion: 0,
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
      feeRateBasisPoints: 500,
      feePolicyVersion: 0,
      feeRateText: '5.00%',
      minimumAmount: 100,
    );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
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
