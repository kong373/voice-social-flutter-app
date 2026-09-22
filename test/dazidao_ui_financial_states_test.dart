import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/domain/payout_account_binding.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/golden_font_gate.dart';

// Visual states from explicitly synthetic authorities. Any write is a failure.
const _matrix = bool.fromEnvironment('UI_MATRIX');
const _only = String.fromEnvironment('UI_CASE');
const _readError = '测试状态：暂时无法读取资产信息';

enum _Mode { normal, loading, error, empty, unknown, noAccount }

class _Case {
  const _Case(this.page, this.role, [this.mode = _Mode.normal]);
  final String page;
  final IncomeRole role;
  final _Mode mode;
  String get id => '$page-${role.name}-${mode.name}';
}

void main() {
  setUpAll(loadGoldenFonts);
  final cases = <_Case>[
    for (final role in IncomeRole.values)
      for (final page in ['CM-001-hub', 'CM-011', 'CM-012']) _Case(page, role),
    for (final mode in [
      _Mode.loading,
      _Mode.error,
      _Mode.empty,
      _Mode.unknown,
      _Mode.noAccount,
    ])
      _Case('CM-012', IncomeRole.anchor, mode),
    const _Case('CM-012', IncomeRole.guildChair, _Mode.unknown),
    const _Case('CM-012', IncomeRole.ordinary, _Mode.unknown),
    const _Case('CM-012-payout-alipay', IncomeRole.anchor),
    const _Case('CM-012-payout-bank', IncomeRole.anchor),
  ];
  final variants = _matrix
      ? <(Size, double)>[
          for (final size in const [
            Size(375, 667),
            Size(390, 844),
            Size(402, 874),
          ])
            for (final scale in [1.0, 1.3]) (size, scale),
        ]
      : <(Size, double)>[(const Size(390, 844), 1.0)];
  for (final item in cases) {
    if (_only.isNotEmpty && !_only.split(',').contains(item.id)) continue;
    for (final variant in variants) {
      testWidgets('financial ${item.id} ${variant.$1} text=${variant.$2}', (
        tester,
      ) async {
        final repository = _FinancialRepository(item.role, item.mode);
        await renderDazidaoScenario(
          tester,
          id: item.id,
          size: variant.$1,
          scale: variant.$2,
          useProductionHostTheme: item.page.startsWith('CM-012-payout'),
          builder: (_) => switch (item.page) {
            'CM-001-hub' => CommerceHubPage(
              account: 'synthetic',
              repository: repository,
            ),
            'CM-011' => EarningsPage(repository: repository),
            'CM-012-payout-alipay' ||
            'CM-012-payout-bank' => WithdrawalPage(repository: repository),
            _ => WithdrawalPage(repository: repository),
          },
          exercise: (tester, _) => _verify(tester, item, repository),
          release: repository.release,
          annotations: {
            'manifestId': item.page == 'CM-001-hub'
                ? 'CM-001'
                : item.page.startsWith('CM-012')
                ? 'CM-012'
                : 'CM-011',
            'incomeRole': item.role.name,
            'state': item.mode.name,
            'writeOperationsAllowed': false,
            'realPayoutOrLedgerEvidence': false,
          },
        );
        expect(repository.writes, 0);
      });
    }
  }
}

Future<void> _verify(
  WidgetTester tester,
  _Case item,
  _FinancialRepository repository,
) async {
  final eligible = item.role != IncomeRole.ordinary;
  if (item.mode == _Mode.loading) {
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('申请提现'), findsNothing);
    return;
  }
  if (item.mode == _Mode.error) {
    await _waitFor(tester, find.text(_readError));
    expect(find.text('申请提现'), findsNothing);
    return;
  }
  if (item.page == 'CM-001-hub') {
    await _waitFor(tester, find.text('钱包与流水'));
    await _scrollTo(tester, find.text(eligible ? '结算与提现' : '历史提现记录'));
    expect(find.text('主播收益'), eligible ? findsOneWidget : findsNothing);
    expect(find.text(eligible ? '历史提现记录' : '结算与提现'), findsNothing);
  } else if (item.page == 'CM-011') {
    await _waitFor(tester, find.text(eligible ? '收益明细' : '当前身份没有现金收益入口'));
    expect(find.text('申请提现'), findsNothing);
  } else if (item.page.startsWith('CM-012-payout')) {
    await _waitFor(tester, find.text('新增 / 更换收款账户'));
    await _scrollTo(tester, find.text('新增 / 更换收款账户'));
    await tester.tap(find.text('新增 / 更换收款账户').hitTestable());
    await _waitFor(tester, find.byType(PayoutAccountBindingPage));
    await _waitFor(tester, find.byType(DropdownButtonFormField<String>));
    if (item.page.endsWith('bank')) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _waitFor(tester, find.text('银行卡').hitTestable());
      await tester.tap(find.text('银行卡').hitTestable());
      await _waitFor(tester, find.text('开户银行'));
      expect(find.byType(TextFormField), findsNWidgets(3));
    } else {
      expect(find.byType(TextFormField), findsNWidgets(2));
    }
    await _scrollTo(tester, find.text('确认绑定'));
    expect(find.textContaining('不代表银行或支付宝已核验'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Form))).brightness,
      Brightness.light,
      reason:
          'Payout must retain the asset/account light surface after real navigation',
    );
    expect(find.byType(SocialPageScaffold), findsOneWidget);
  } else {
    await _waitFor(tester, find.text('提现记录'));
    final action = item.mode == _Mode.unknown ? '恢复原提现申请' : '申请提现';
    expect(
      find.text(action),
      eligible || item.mode == _Mode.unknown ? findsOneWidget : findsNothing,
    );
    if (item.mode == _Mode.unknown) {
      expect(find.textContaining('上一笔提现结果尚未确定'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '计算到账金额'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('提现申请已提交'), findsNothing);
      expect(find.textContaining('提现申请已安全禁用'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '恢复原提现申请'))
            .onPressed,
        isNotNull,
      );
      await _scrollTo(tester, find.text('恢复原提现申请'));
    } else if (item.mode == _Mode.noAccount) {
      expect(find.text('暂无可用于提现的收款账户。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '申请提现'))
            .onPressed,
        isNull,
      );
    } else if (item.mode == _Mode.empty) {
      await _scrollTo(tester, find.text('暂无提现记录'));
    } else {
      await _scrollTo(tester, find.text('¥200.00 · 已打款'));
      expect(find.text('持卡人 测* ****1234'), findsOneWidget);
      expect(find.text('到账\n¥200.00'), findsOneWidget);
    }
  }
  expect(
    repository.writes,
    0,
    reason: 'Visual review must not submit or retry a financial command',
  );
  expect(tester.takeException(), isNull);
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    100,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 25,
  );
  await _waitFor(tester, target.hitTestable());
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (target.evaluate().length == 1) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
  }
  expect(target, findsOneWidget, reason: 'Financial fixture readiness barrier');
}

class _FinancialRepository extends MockCommerceRepository
    implements PayoutAccountBindingRepository {
  _FinancialRepository(this.role, this.mode);
  final IncomeRole role;
  final _Mode mode;
  final Completer<WalletSummary> _waiting = Completer<WalletSummary>();
  int writes = 0;
  @override
  bool get supportsPayoutAccountSelection => true;
  @override
  bool get supportsWithdrawalApplication => true;
  @override
  (String?, int) get withdrawalIdentity => ('synthetic-visual-viewer', 0);
  @override
  Listenable? get withdrawalIdentityChanges => null;
  WalletSummary get _wallet => WalletSummary(
    giftCoinBalance: 3600,
    cashBalance: 800,
    frozenBalance: 200,
    totalEarnings: 1000,
    yesterdayEarnings: 20,
    totalWithdrawn: 200,
    realNameVerified: true,
    bankCard: const BankCardSummary(
      id: 'synthetic-payout',
      accountType: '支付宝',
      maskedAccount: '****1234',
      holderNameMasked: '测*',
    ),
    agentEarnings: null,
    superAgentEarnings: null,
    incomeCapability: IncomeCapability(
      role,
      role != IncomeRole.ordinary,
      role != IncomeRole.ordinary,
    ),
  );
  @override
  Future<WalletSummary> fetchWalletSummary() async {
    if (mode == _Mode.loading) return _waiting.future;
    if (mode == _Mode.error) {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: _readError,
      );
    }
    return _wallet;
  }

  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() async =>
      PayoutAccountSelection(
        accounts: mode == _Mode.noAccount
            ? []
            : const [
                PayoutAccount(
                  payoutAccountId: 'synthetic-payout',
                  accountType: 'ALIPAY',
                  accountMasked: '****1234',
                  holderNameMasked: '测*',
                  status: PayoutAccountStatus.bound,
                  selectable: true,
                  verificationSource: 'USER_DECLARED',
                ),
              ],
        selectedPayoutAccountId: mode == _Mode.noAccount
            ? null
            : 'synthetic-payout',
        selectionRequired: mode == _Mode.noAccount,
        canBind: true,
        bindingBlockReason: 'NONE',
      );
  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) async => CommercePage(
    items: [
      LedgerEntry(
        id: 'synthetic-income',
        direction: direction,
        kind: LedgerKind.giftIncome,
        title: '测试礼物收益',
        amount: 20,
        createdAt: DateTime.utc(2026, 9, 21),
        relatedUserName: '合成用户',
        businessName: '合成房间',
        rawSubtype: role == IncomeRole.guildChair
            ? 'GUILD_GIFT_INCOME'
            : 'GIFT_INCOME',
        currency: currency,
      ),
    ],
    page: page,
    pageSize: pageSize,
    total: 1,
    hasMore: false,
  );
  @override
  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  }) async {
    final records = mode == _Mode.empty ? <WithdrawalRecord>[] : [_record];
    return CommercePage(
      items: records,
      page: page,
      pageSize: pageSize,
      total: records.length,
      hasMore: false,
    );
  }

  WithdrawalRecord get _record => WithdrawalRecord(
    id: 'synthetic-record',
    withdrawalNo: 'SYNTHETIC-RECORD',
    amount: 200,
    fee: 0,
    receivedAmount: 200,
    status: WithdrawalStatus.succeeded,
    statusText: '已打款',
    createdAt: DateTime.utc(2026, 9, 20),
    rejectedReason: '',
    payoutAccountId: 'original-synthetic-payout',
    holderNameMasked: '测*',
    maskedCard: '****1234',
  );
  static const _quote = WithdrawalQuote(
    quotedAmount: 200,
    feeAmount: 0,
    receivedAmount: 200,
    feeRateBasisPoints: 0,
    feeRateText: '0%',
    minimumAmount: 100,
    feePolicyVersion: 1,
  );
  @override
  ConfirmedWithdrawal? get pendingWithdrawal => mode == _Mode.unknown
      ? const ConfirmedWithdrawal(
          amount: 200,
          payoutAccountId: 'synthetic-payout',
          quote: _quote,
        )
      : null;
  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({
    required double amount,
  }) async => _quote;
  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async {
    writes++;
    throw StateError(
      'Financial capture is read-only: application not permitted',
    );
  }

  @override
  Future<PayoutAccountSelection> bindPayoutAccount(
    PayoutAccountInput input, {
    required String requestId,
  }) async {
    writes++;
    throw StateError('Financial capture is read-only: binding not permitted');
  }

  void release() {
    if (!_waiting.isCompleted) _waiting.complete(_wallet);
  }
}
