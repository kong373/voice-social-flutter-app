import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

WalletSummary wallet(String amount, {IncomeRole? role = IncomeRole.ordinary}) =>
    WalletSummary(
      giftCoinBalance: 100,
      coinPrecision: GiftCoinBalance(
        available: GiftCoinAmount.fromTenths(amount),
        frozen: GiftCoinAmount.fromTenths('2'),
      ),
      incomeCapability: role == null
          ? const IncomeCapability.unavailable()
          : IncomeCapability(
              role,
              role != IncomeRole.ordinary,
              role != IncomeRole.ordinary,
            ),
      cashBalance: 120,
      frozenBalance: 0,
      totalEarnings: 0,
      yesterdayEarnings: 0,
      totalWithdrawn: 0,
      realNameVerified: true,
      bankCard: const BankCardSummary(
        id: 'card-1',
        accountType: 'BANK_REFERENCE',
        maskedAccount: '****8001',
        holderNameMasked: 'A*',
      ),
      agentEarnings: null,
      superAgentEarnings: null,
    );

void main() {
  testWidgets(
    'S07 recharge and gift catalog display the retained fractional balance',
    (tester) async {
      final dependencies = await createQaDependencies();
      addTearDown(dependencies.dispose);
      (dependencies.commerceRepository as MockCommerceRepository).giftCoins =
          GiftCoinAmount.fromTenths('1005');
      for (final page in const [RechargeCatalogPage(), GiftCatalogPage()]) {
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(home: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('100.5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('S07 exact large coin balance is visible without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = IdentityWallet()..value = wallet('92233720368547758079');
    await tester.pumpWidget(MaterialApp(home: WalletPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('9223372036854775807.9'), findsOneWidget);
    expect(find.text('冻结礼物币 0.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.changes.dispose();
  });

  testWidgets(
    'S08 ordinary and missing capability expose history but no earnings or new form',
    (tester) async {
      for (final role in [IncomeRole.ordinary, null]) {
        final repo = IdentityWallet()..value = wallet('1148', role: role);
        await tester.pumpWidget(
          MaterialApp(
            home: CommerceHubPage(account: 'A', repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('114.8'), findsOneWidget);
        expect(find.text('主播收益'), findsNothing);
        expect(find.text('结算与提现'), findsNothing);
        await tester.ensureVisible(find.text('历史提现记录'));
        await tester.tap(find.text('历史提现记录'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('申请提现'), findsNothing);
        expect(find.text('提现记录'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(home: EarningsPage(repository: repo)),
        );
        await tester.pumpAndSettle();
        expect(find.text('当前身份没有现金收益入口'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.changes.dispose();
      }
    },
  );

  testWidgets(
    'S08 anchor and guild chair keep explicit income and withdrawal entry',
    (tester) async {
      for (final role in [IncomeRole.anchor, IncomeRole.guildChair]) {
        final repo = IdentityWallet()..value = wallet('1148', role: role);
        await tester.pumpWidget(
          MaterialApp(
            home: CommerceHubPage(account: 'A', repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('主播收益'), 150);
        expect(find.text('主播收益'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('结算与提现'), 150);
        expect(find.text('结算与提现'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repo.changes.dispose();
      }
    },
  );

  testWidgets(
    'S07 account ABA clears money immediately and rejects late result',
    (tester) async {
      final repo = IdentityWallet()
        ..value = wallet('1148', role: IncomeRole.anchor);
      await tester.pumpWidget(MaterialApp(home: WalletPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('114.8'), findsOneWidget);
      final b = Completer<WalletSummary>();
      repo.next = b;
      repo.switchTo('B');
      await tester.pump();
      expect(find.text('114.8'), findsNothing);
      repo.value = wallet('22');
      repo.switchTo('A');
      await tester.pumpAndSettle();
      expect(find.text('2.2'), findsOneWidget);
      b.complete(wallet('9999'));
      await tester.pumpAndSettle();
      expect(find.text('999.9'), findsNothing);
      expect(find.text('2.2'), findsOneWidget);
      repo.switchTo(null);
      await tester.pumpAndSettle();
      expect(find.text('2.2'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );

  testWidgets(
    'S08 ordinary pending recovery keeps locked quote and original account',
    (tester) async {
      final repo = IdentityWallet()..value = wallet('1148');
      repo.pending = const ConfirmedWithdrawal(
        amount: 101,
        payoutAccountId: 'original-account',
        quote: WithdrawalQuote(
          quotedAmount: 101,
          feeAmount: .51,
          receivedAmount: 100.49,
          feeRateBasisPoints: 50,
          feePolicyVersion: 7,
          feeRateText: '0.50%',
          minimumAmount: 100,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '101',
      );
      await tester.ensureVisible(find.text('申请提现'));
      await tester.tap(find.text('申请提现'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计到账：¥100.49'), findsOneWidget);
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(repo.applied!.payoutAccountId, 'original-account');
      expect(repo.applied!.quote.feePolicyVersion, 7);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('提现记录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );

  testWidgets('S07 fast ledger filter change fences a late expense page', (
    tester,
  ) async {
    final repo = IdentityWallet();
    await tester.pumpWidget(MaterialApp(home: WalletPage(repository: repo)));
    await tester.pumpAndSettle();
    final delayed = Completer<CommercePage<LedgerEntry>>();
    repo.nextLedger = delayed;
    await tester.tap(find.text('支出'));
    await tester.pump();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('+300 礼物币'), findsOneWidget);
    delayed.complete(
      CommercePage(
        items: [
          LedgerEntry(
            id: 'stale',
            direction: LedgerDirection.expense,
            kind: LedgerKind.giftExpense,
            title: '旧支出',
            amount: null,
            coinAmount: GiftCoinAmount.fromTenths('123'),
            createdAt: DateTime.utc(2026, 9, 9),
            relatedUserName: '',
            businessName: '',
            rawSubtype: 'GIFT_SEND',
          ),
        ],
        page: 1,
        pageSize: 50,
        total: 1,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧支出'), findsNothing);
    expect(find.text('+300 礼物币'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.changes.dispose();
  });
}

class IdentityWallet extends MockCommerceRepository {
  final changes = ChangeNotifier();
  String? actor = 'A';
  int generation = 1;
  WalletSummary value = wallet('1148');
  Completer<WalletSummary>? next;
  Completer<CommercePage<LedgerEntry>>? nextLedger;
  ConfirmedWithdrawal? pending;
  ConfirmedWithdrawal? applied;
  @override
  ConfirmedWithdrawal? get pendingWithdrawal => pending;
  @override
  (String?, int) get withdrawalIdentity => (actor, generation);
  @override
  Listenable get withdrawalIdentityChanges => changes;
  void switchTo(String? user) {
    actor = user;
    generation++;
    changes.notifyListeners();
  }

  @override
  Future<WalletSummary> fetchWalletSummary() {
    final deferred = next;
    next = null;
    return deferred?.future ?? Future.value(value);
  }

  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) {
    final deferred = nextLedger;
    nextLedger = null;
    return deferred?.future ??
        super.fetchLedger(
          currency: currency,
          direction: direction,
          page: page,
          pageSize: pageSize,
        );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async {
    applied = ConfirmedWithdrawal(
      amount: amount,
      payoutAccountId: payoutAccountId!,
      quote: confirmedQuote,
    );
    pending = null;
    return (await fetchWithdrawalRecords(page: 1, pageSize: 20)).items.first;
  }
}
