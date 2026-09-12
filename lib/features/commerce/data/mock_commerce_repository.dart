import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

class MockCommerceRepository implements CommerceRepository {
  // Explicit demo identity; role loss never rewrites imported cash history.
  IncomeRole incomeRole = IncomeRole.anchor;
  GiftCoinAmount giftCoins = const GiftCoinAmount.whole(1680);
  final Set<String> _creditedRechargeOrders = {'MOCK202608150001'};
  @override
  ConfirmedWithdrawal? get pendingWithdrawal => null;
  @override
  (String?, int) get withdrawalIdentity => ('mock', 0);
  @override
  Listenable? get withdrawalIdentityChanges => null;
  int _feeBasisPoints = 0;
  int _feePolicyVersion = 0;

  void updateWithdrawalFeePolicy(int basisPoints) {
    if (basisPoints < 0 || basisPoints > 9999)
      throw ArgumentError.value(basisPoints);
    if (_feeBasisPoints != basisPoints) {
      _feeBasisPoints = basisPoints;
      _feePolicyVersion++;
    }
  }

  MockCommerceRepository({
    DateTime? now,
    DateTime Function()? clock,
    double initialCashBalance = 1288.50,
  }) : this._seeded(
         seedNow: now ?? clock?.call() ?? DateTime.now(),
         fixedNow: now,
         clock: clock,
         initialCashBalance: initialCashBalance,
       );

  MockCommerceRepository._seeded({
    required DateTime seedNow,
    required DateTime? fixedNow,
    required DateTime Function()? clock,
    required double initialCashBalance,
  }) : _fixedNow = fixedNow,
       _clock = clock,
       _cashBalance = initialCashBalance,
       _orders = <PaymentOrder>[
         PaymentOrder(
           orderNo: 'MOCK202608150001',
           amount: 30,
           giftCoinAmount: 300,
           channelName: '微信支付',
           createdAt: seedNow.subtract(const Duration(days: 2)),
           status: PaymentOrderStatus.succeeded,
         ),
         PaymentOrder(
           orderNo: 'MOCK202608150002',
           amount: 68,
           giftCoinAmount: 700,
           channelName: '支付宝',
           createdAt: seedNow.subtract(const Duration(hours: 3)),
           status: PaymentOrderStatus.confirming,
         ),
       ],
       _refunds = <String, RefundApplication>{
         'refund-1': RefundApplication(
           id: 'refund-1',
           account: '13800138000',
           amount: 30,
           status: RefundStatus.reviewing,
           statusText: '审核中',
           rejectedReason: '',
           createdAt: seedNow.subtract(const Duration(days: 1)),
         ),
       },
       _withdrawals = <WithdrawalRecord>[
         WithdrawalRecord(
           id: 'withdraw-1',
           withdrawalNo: 'WD202608120001',
           amount: 200,
           fee: 2,
           receivedAmount: 198,
           status: WithdrawalStatus.succeeded,
           statusText: '已到账',
           createdAt: seedNow.subtract(const Duration(days: 3)),
           rejectedReason: '',
           holderNameMasked: '晚*',
           maskedCard: '**** 8812',
         ),
       ],
       _incomeEntries = <LedgerEntry>[
         LedgerEntry(
           id: 'income-1',
           direction: LedgerDirection.income,
           kind: LedgerKind.giftIncome,
           title: '普通礼物收益',
           amount: 68,
           createdAt: seedNow.subtract(const Duration(hours: 2)),
           relatedUserName: '鹿屿',
           businessName: '星河灯',
           rawSubtype: 'gift_income',
           currency: LedgerCurrency.cashCny,
         ),
         LedgerEntry(
           id: 'income-2',
           direction: LedgerDirection.income,
           kind: LedgerKind.agentIncome,
           title: '渠道结算收益',
           amount: 120,
           createdAt: seedNow.subtract(const Duration(days: 1)),
           relatedUserName: '',
           businessName: '本周渠道结算',
           rawSubtype: 'agent_income',
           currency: LedgerCurrency.cashCny,
         ),
       ],
       _expenseEntries = <LedgerEntry>[
         LedgerEntry(
           id: 'expense-1',
           direction: LedgerDirection.expense,
           kind: LedgerKind.giftExpense,
           title: '赠送普通礼物',
           amount: null,
           coinAmount: const GiftCoinAmount.whole(12),
           createdAt: seedNow.subtract(const Duration(hours: 5)),
           relatedUserName: '南风',
           businessName: '晚安星光',
           rawSubtype: 'send_gift',
           currency: LedgerCurrency.giftCoin,
         ),
         LedgerEntry(
           id: 'expense-2',
           direction: LedgerDirection.expense,
           kind: LedgerKind.withdrawal,
           title: '提现申请',
           amount: 200,
           createdAt: seedNow.subtract(const Duration(days: 3)),
           relatedUserName: '',
           businessName: '招商银行 **** 8812',
           rawSubtype: 'withdrawal',
           currency: LedgerCurrency.cashCny,
         ),
       ];

  final DateTime? _fixedNow;
  final DateTime Function()? _clock;
  // Successful submissions only. Never reconstruct this from imported history.
  final Set<String> _withdrawalSubmissionDays = <String>{};
  final List<PaymentOrder> _orders;
  final Map<String, RefundApplication> _refunds;
  final List<WithdrawalRecord> _withdrawals;
  final List<LedgerEntry> _incomeEntries;
  final List<LedgerEntry> _expenseEntries;
  final List<PayoutAccount> _payoutAccounts = <PayoutAccount>[
    const PayoutAccount(
      payoutAccountId: 'card-1',
      accountType: 'BANK_REFERENCE',
      accountMasked: '6225 **** **** 8812',
      holderNameMasked: '晚*',
      status: PayoutAccountStatus.verified,
      selectable: true,
    ),
  ];
  int _withdrawalSequence = 2;
  double _cashBalance;
  double _frozenBalance = 200;

  DateTime get _currentTime => _clock?.call() ?? _fixedNow ?? DateTime.now();

  void seedWithdrawalRecordForQa(WithdrawalRecord record) {
    final index = _withdrawals.indexWhere((item) => item.id == record.id);
    if (index < 0) {
      _withdrawals.insert(0, record);
    } else {
      _withdrawals[index] = record;
    }
  }

  @override
  bool get supportsPaymentChannelInvocation => false;

  @override
  bool get supportsRefundHistory => true;

  @override
  bool get supportsWithdrawalApplication => true;

  @override
  bool get supportsPayoutAccountSelection => false;

  @override
  RefundScope get refundScope => RefundScope.accountLegacy;

  void seedPaymentOrderForQa(PaymentOrder order) {
    final int index = _orders.indexWhere(
      (PaymentOrder item) => item.orderNo == order.orderNo,
    );
    if (index < 0) {
      _orders.insert(0, order);
    } else {
      _orders[index] = order;
    }
  }

  void syncRechargeOrder(RechargeOrder order) {
    if (order.state == RechargeOrderState.succeeded &&
        _creditedRechargeOrders.add(order.orderNo)) {
      giftCoins = GiftCoinAmount.fromTenths(
        (giftCoins.tenths +
                BigInt.from(order.product.totalGiftCoins) * BigInt.from(10))
            .toString(),
      );
    }
    seedPaymentOrderForQa(
      PaymentOrder(
        orderNo: order.orderNo,
        amount: order.product.priceCny,
        giftCoinAmount: order.product.totalGiftCoins,
        channelName: order.channel.label,
        createdAt: order.createdAt,
        status: switch (order.state) {
          RechargeOrderState.created ||
          RechargeOrderState.invoking => PaymentOrderStatus.pending,
          RechargeOrderState.confirming => PaymentOrderStatus.confirming,
          RechargeOrderState.succeeded => PaymentOrderStatus.succeeded,
          RechargeOrderState.canceled => PaymentOrderStatus.canceled,
          RechargeOrderState.failed ||
          RechargeOrderState.unavailable => PaymentOrderStatus.failed,
        },
      ),
    );
  }

  void seedRefundApplicationForQa(RefundApplication application) {
    _refunds[application.id] = application;
  }

  @override
  Future<WalletSummary> fetchWalletSummary() async => WalletSummary(
    giftCoinBalance: 1680,
    coinPrecision: GiftCoinBalance(
      available: giftCoins,
      frozen: const GiftCoinAmount.whole(0),
    ),
    incomeCapability: IncomeCapability(
      incomeRole,
      incomeRole != IncomeRole.ordinary,
      incomeRole != IncomeRole.ordinary,
    ),
    cashBalance: _cashBalance,
    frozenBalance: _frozenBalance,
    totalEarnings: 5688.80,
    yesterdayEarnings: 88,
    totalWithdrawn: 4200.30,
    realNameVerified: true,
    bankCard: const BankCardSummary(
      id: 'card-1',
      accountType: '银行卡',
      maskedAccount: '6225 **** **** 8812',
      holderNameMasked: '晚*',
    ),
    agentEarnings: 500,
    superAgentEarnings: 300,
  );

  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) async {
    final List<LedgerEntry> source = switch ((currency, direction)) {
      (LedgerCurrency.giftCoin, LedgerDirection.income) => <LedgerEntry>[
        LedgerEntry(
          id: 'gift-coin-income-1',
          direction: LedgerDirection.income,
          kind: LedgerKind.recharge,
          title: '充值到账',
          amount: null,
          coinAmount: const GiftCoinAmount.whole(300),
          createdAt: _currentTime.subtract(const Duration(hours: 1)),
          relatedUserName: '',
          businessName: '礼物币充值',
          rawSubtype: 'recharge_credit',
        ),
      ],
      (LedgerCurrency.giftCoin, LedgerDirection.expense) =>
        _expenseEntries
            .where((LedgerEntry item) => item.kind == LedgerKind.giftExpense)
            .toList(growable: false),
      (LedgerCurrency.cashCny, LedgerDirection.income) => _incomeEntries,
      (LedgerCurrency.cashCny, LedgerDirection.expense) =>
        _expenseEntries
            .where((LedgerEntry item) => item.kind == LedgerKind.withdrawal)
            .toList(growable: false),
    };
    return _page(source, page: page, pageSize: pageSize);
  }

  @override
  Future<CommercePage<PaymentOrder>> fetchOrders({
    required int page,
    required int pageSize,
  }) async => _page(_orders, page: page, pageSize: pageSize);

  @override
  Future<PaymentOrder> queryOrderStatus(
    PaymentOrder order, {
    bool reconcile = false,
  }) async {
    final int index = _orders.indexWhere(
      (PaymentOrder item) => item.orderNo == order.orderNo,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '订单不存在',
      );
    }
    final PaymentOrder current = _orders[index];
    final PaymentOrder updated = current.status == PaymentOrderStatus.confirming
        ? current.copyWith(status: PaymentOrderStatus.succeeded)
        : current;
    _orders[index] = updated;
    return updated;
  }

  @override
  Future<RefundEligibility> checkRefundEligibility(String account) async {
    RefundApplication? active;
    for (final RefundApplication item in _refunds.values) {
      if (item.account == account &&
          (item.status == RefundStatus.reviewing ||
              item.status == RefundStatus.resubmitted ||
              item.status == RefundStatus.approved ||
              item.status == RefundStatus.completed)) {
        active = item;
        break;
      }
    }
    return RefundEligibility(
      allowed: active == null,
      existingApplicationId: active?.id,
      message: active == null ? '当前账号可以提交账户退款申请。' : '已有退款申请正在处理，请勿重复提交。',
    );
  }

  /// Q15-06: App refund writes are permanently retired; history stays readable.
  @override
  Future<RefundApplication> submitRefund(RefundRequest request) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  @override
  Future<RefundApplication> fetchRefundResult(
    String applicationId, {
    String? expectedOrderNo,
  }) async {
    final RefundApplication? application = _refunds[applicationId];
    if (application == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '退款申请不存在',
      );
    }
    if (expectedOrderNo != null && application.account != expectedOrderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果与选中订单不一致',
      );
    }
    return application;
  }

  @override
  Future<RefundApplication> resubmitRefund(
    String applicationId, {
    String? expectedOrderNo,
  }) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  @override
  Future<List<RefundApplication>> fetchRefundApplications(
    String account,
  ) async =>
      _refunds.values
          .where((RefundApplication item) => item.account == account)
          .toList(growable: false)
        ..sort(
          (RefundApplication left, RefundApplication right) =>
              right.createdAt.compareTo(left.createdAt),
        );

  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() async =>
      const PayoutAccountSelection(
        accounts: <PayoutAccount>[
          PayoutAccount(
            payoutAccountId: 'card-1',
            accountType: 'BANK_REFERENCE',
            accountMasked: '6225 **** **** 8812',
            holderNameMasked: '晚*',
            status: PayoutAccountStatus.verified,
            selectable: true,
          ),
        ],
        selectedPayoutAccountId: 'card-1',
        selectionRequired: false,
      );

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) async {
    final int amountMinor = WithdrawalAmountPolicy.minorUnits(amount);
    final int fee = WithdrawalQuote.ceilingFeeMinor(
      amountMinor,
      _feeBasisPoints,
    );
    return WithdrawalQuote(
      feePolicyVersion: _feePolicyVersion,
      quotedAmount: amountMinor / 100,
      feeAmount: fee / 100,
      receivedAmount: (amountMinor - fee) / 100,
      feeRateBasisPoints: _feeBasisPoints,
      feeRateText: '${(_feeBasisPoints / 100).toStringAsFixed(2)}%',
      minimumAmount: WithdrawalAmountPolicy.minimum,
    );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async {
    final WalletSummary wallet = await fetchWalletSummary();
    if (!wallet.canWithdraw) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '当前身份不支持新提现申请，历史记录仍可查看',
      );
    }
    final WithdrawalQuote quote = confirmedQuote;
    quote.validateFor(amount);
    if (quote.feePolicyVersion != _feePolicyVersion ||
        quote.feeRateBasisPoints != _feeBasisPoints) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        httpStatus: 409,
        message: '提现报价已变化，请重新报价并确认',
      );
    }
    if (!wallet.realNameVerified || wallet.bankCard == null) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '请先完成实名认证并绑定银行卡',
      );
    }
    final String selectedAccount = payoutAccountId?.trim().isNotEmpty == true
        ? payoutAccountId!.trim()
        : 'card-1';
    if (!_payoutAccounts.any(
      (PayoutAccount account) =>
          account.payoutAccountId == selectedAccount && account.selectable,
    )) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '选中的收款账户已失效，请刷新后重新选择',
      );
    }
    if (amount < quote.minimumAmount) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '单笔提现金额不得少于 ${quote.minimumAmount.toStringAsFixed(0)} 元',
      );
    }
    if (amount > _cashBalance) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '可提现余额不足',
      );
    }
    final double fee = quote.feeFor(amount);
    final DateTime now = _currentTime;
    final beijing = now.toUtc().add(const Duration(hours: 8));
    final day = '${beijing.year}-${beijing.month}-${beijing.day}';
    if (_withdrawalSubmissionDays.contains(day)) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        httpStatus: 409,
        message: '北京时间今日已提交提现申请，请次日重新申请；驳回当日仍占用次数',
      );
    }
    final WithdrawalRecord record = WithdrawalRecord(
      id: 'withdraw-${_withdrawalSequence++}',
      withdrawalNo: 'WD${now.millisecondsSinceEpoch}',
      amount: amount,
      fee: fee,
      receivedAmount: amount - fee,
      status: WithdrawalStatus.pending,
      statusText: '待审核',
      createdAt: now,
      rejectedReason: '',
      payoutAccountId: selectedAccount,
      holderNameMasked: wallet.bankCard!.holderNameMasked,
      maskedCard: wallet.bankCard!.maskedAccount,
    );
    _withdrawals.insert(0, record);
    _withdrawalSubmissionDays.add(day);
    _cashBalance -= amount;
    _frozenBalance += amount;
    return record;
  }

  @override
  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  }) async {
    final List<WithdrawalRecord> source = status == null
        ? _withdrawals
        : _withdrawals
              .where((WithdrawalRecord item) => item.status == status)
              .toList(growable: false);
    return _page(source, page: page, pageSize: pageSize);
  }

  @override
  Future<WithdrawalRecord> fetchWithdrawalRecord(String id) async {
    for (final WithdrawalRecord record in _withdrawals) {
      if (record.id == id) {
        return record;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '提现记录不存在',
    );
  }

  static CommercePage<T> _page<T>(
    List<T> items, {
    required int page,
    required int pageSize,
  }) {
    final int safePage = page < 1 ? 1 : page;
    final int safePageSize = pageSize < 1 ? 20 : pageSize;
    final int start = (safePage - 1) * safePageSize;
    final int end = (start + safePageSize).clamp(0, items.length).toInt();
    final List<T> slice = start >= items.length
        ? <T>[]
        : items.sublist(start, end);
    return CommercePage<T>(
      items: slice,
      page: safePage,
      pageSize: safePageSize,
      total: items.length,
      hasMore: end < items.length,
    );
  }
}
