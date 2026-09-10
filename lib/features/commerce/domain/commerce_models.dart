import 'package:flutter/foundation.dart';
import 'gift_coin_precision.dart';
export 'gift_coin_precision.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

enum LedgerDirection { income, expense }

enum LedgerCurrency { giftCoin, cashCny }

enum LedgerKind {
  giftIncome,
  giftExpense,
  agentIncome,
  superAgentIncome,
  recharge,
  refund,
  withdrawal,
  other,
}

enum PaymentOrderStatus {
  pending,
  confirming,
  succeeded,
  failed,
  canceled,
  unknown,
}

/// Statuses returned by the first-party refund service.
///
/// `approved` means a human/backend approval only. It is intentionally
/// distinct from `completed`, which is the only terminal status that says the
/// refund has arrived. Neither status authorizes a client-side balance write.
enum RefundStatus {
  reviewing,
  approved,
  completed,
  rejected,
  resubmitted,
  unavailable,
}

enum RefundScope { accountLegacy, order }

enum WithdrawalStatus { pending, approved, rejected, paying, succeeded, failed }

class BankCardSummary {
  const BankCardSummary({
    required this.id,
    required this.accountType,
    required this.maskedAccount,
    required this.holderNameMasked,
  });

  final String id;
  final String accountType;
  final String maskedAccount;
  final String holderNameMasked;
}

enum PayoutAccountStatus { bound, verified, pending, disabled, unknown }

class PayoutAccount {
  const PayoutAccount({
    required this.payoutAccountId,
    required this.accountType,
    required this.accountMasked,
    required this.holderNameMasked,
    required this.status,
    required this.selectable,
    this.createdAt,
    this.updatedAt,
    this.verificationSource = '',
    this.bankName = '',
  });

  final String payoutAccountId;
  final String accountType;
  final String accountMasked;
  final String holderNameMasked;
  final PayoutAccountStatus status;
  final bool selectable;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String verificationSource;
  final String bankName;
}

class PayoutAccountSelection {
  const PayoutAccountSelection({
    required this.accounts,
    required this.selectedPayoutAccountId,
    required this.selectionRequired,
    this.canBind = false,
    this.bindingBlockReason = 'CONFIGURATION_UNAVAILABLE',
  });

  final List<PayoutAccount> accounts;
  final String? selectedPayoutAccountId;
  final bool selectionRequired;
  final bool canBind;
  final String bindingBlockReason;

  List<PayoutAccount> get selectableAccounts => accounts
      .where((PayoutAccount account) => account.selectable)
      .toList(growable: false);

  PayoutAccountSelection select(String payoutAccountId) {
    final String normalized = payoutAccountId.trim();
    PayoutAccount? account;
    for (final PayoutAccount candidate in selectableAccounts) {
      if (candidate.payoutAccountId == normalized) {
        account = candidate;
        break;
      }
    }
    if (account == null) {
      throw ArgumentError.value(
        payoutAccountId,
        'payoutAccountId',
        '不是当前权威列表中的可用收款账户',
      );
    }
    return PayoutAccountSelection(
      accounts: accounts,
      selectedPayoutAccountId: account.payoutAccountId,
      selectionRequired: false,
      canBind: canBind,
      bindingBlockReason: bindingBlockReason,
    );
  }
}

enum IncomeRole { ordinary, anchor, guildChair }

class IncomeCapability {
  const IncomeCapability(this.role, this.incomeEligible, this.canWithdraw);
  const IncomeCapability.unavailable()
    : role = null,
      incomeEligible = false,
      canWithdraw = false;
  factory IncomeCapability.parse(Map<String, Object?> data) {
    if (![
      'incomeRole',
      'incomeEligible',
      'canWithdraw',
    ].any(data.containsKey)) {
      return const IncomeCapability.unavailable();
    }
    final role = switch (data['incomeRole']) {
      'ORDINARY' => IncomeRole.ordinary,
      'ANCHOR' => IncomeRole.anchor,
      'GUILD_CHAIR' => IncomeRole.guildChair,
      _ => null,
    };
    final eligible = data['incomeEligible'];
    final withdraw = data['canWithdraw'];
    if (role == null ||
        eligible is! bool ||
        withdraw is! bool ||
        eligible != (role != IncomeRole.ordinary) ||
        withdraw != eligible) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收益身份能力响应不一致，请刷新后重试',
      );
    }
    return IncomeCapability(role, eligible, withdraw);
  }
  final IncomeRole? role;
  final bool incomeEligible;
  final bool canWithdraw;
}

class WalletSummary {
  const WalletSummary({
    required this.giftCoinBalance,
    required this.cashBalance,
    required this.frozenBalance,
    required this.totalEarnings,
    required this.yesterdayEarnings,
    required this.totalWithdrawn,
    required this.realNameVerified,
    required this.bankCard,
    required this.agentEarnings,
    required this.superAgentEarnings,
    this.coinPrecision,
    this.incomeCapability = const IncomeCapability.unavailable(),
  });

  final int? giftCoinBalance;
  final GiftCoinBalance? coinPrecision;
  final IncomeCapability incomeCapability;
  GiftCoinAmount? get giftCoins =>
      coinPrecision?.available ??
      (giftCoinBalance == null ? null : GiftCoinAmount.whole(giftCoinBalance!));
  String get giftCoinText => giftCoins?.text ?? '—';
  bool get incomeEligible => incomeCapability.incomeEligible;
  bool get canWithdraw => incomeCapability.canWithdraw;
  final double cashBalance;
  final double frozenBalance;
  final double totalEarnings;
  final double yesterdayEarnings;
  final double totalWithdrawn;
  final bool realNameVerified;
  final BankCardSummary? bankCard;

  /// Null means the first-party backend explicitly reported that no
  /// authoritative commission ledger exists for this amount.
  final double? agentEarnings;
  final double? superAgentEarnings;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.direction,
    required this.kind,
    required this.title,
    required this.amount,
    required this.createdAt,
    required this.relatedUserName,
    required this.businessName,
    required this.rawSubtype,
    this.currency = LedgerCurrency.giftCoin,
    this.coinAmount,
  });

  final String id;
  final LedgerDirection direction;
  final LedgerKind kind;
  final String title;

  /// Cash only on live responses. Coin rows use coinAmount without doubles.
  final double? amount;
  final GiftCoinAmount? coinAmount;
  final DateTime createdAt;
  final String relatedUserName;
  final String businessName;
  final String rawSubtype;
  final LedgerCurrency currency;
}

class PaymentOrder {
  const PaymentOrder({
    required this.orderNo,
    required this.amount,
    required this.giftCoinAmount,
    required this.channelName,
    required this.createdAt,
    required this.status,
    this.currency = LedgerCurrency.giftCoin,
  });

  final String orderNo;
  final double amount;
  final int giftCoinAmount;
  final String channelName;
  final DateTime createdAt;
  final PaymentOrderStatus status;
  final LedgerCurrency currency;

  PaymentOrder copyWith({PaymentOrderStatus? status}) {
    return PaymentOrder(
      orderNo: orderNo,
      amount: amount,
      giftCoinAmount: giftCoinAmount,
      channelName: channelName,
      createdAt: createdAt,
      status: status ?? this.status,
      currency: currency,
    );
  }
}

class RefundEligibility {
  const RefundEligibility({
    required this.allowed,
    required this.existingApplicationId,
    required this.message,
  });

  final bool allowed;
  final String? existingApplicationId;
  final String message;
}

class RefundRequest {
  const RefundRequest({
    required this.account,
    required this.realName,
    required this.age,
    required this.amount,
    required this.reason,
    required this.receivingAccount,
    required this.receivingName,
    required this.guardianName,
    required this.guardianPhone,
  });

  final String account;
  final String realName;
  final int age;
  final double amount;
  final String reason;
  final String receivingAccount;
  final String receivingName;
  final String guardianName;
  final String guardianPhone;
}

class RefundApplication {
  const RefundApplication({
    required this.id,
    required this.account,
    required this.amount,
    required this.status,
    required this.statusText,
    required this.rejectedReason,
    required this.createdAt,
    this.currency = LedgerCurrency.cashCny,
    this.completed = false,
  });

  final String id;
  final String account;
  final double amount;
  final RefundStatus status;
  final String statusText;
  final String rejectedReason;
  final DateTime createdAt;
  final LedgerCurrency currency;

  /// True only when the backend returned terminal `COMPLETED`.
  final bool completed;

  RefundApplication copyWith({
    RefundStatus? status,
    String? statusText,
    String? rejectedReason,
    bool? completed,
  }) {
    return RefundApplication(
      id: id,
      account: account,
      amount: amount,
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      createdAt: createdAt,
      currency: currency,
      completed: completed ?? this.completed,
    );
  }
}

/// Product amount constraints, separate from the server's configurable fee.
abstract final class WithdrawalAmountPolicy {
  static const minimum = 100.0;
  // Precision guard, not a business quota: cents must remain exact on all
  // clients, including JavaScript's safe integer range.
  static const maximumExactYuan = 90071992547409.0;
  static const message = '提现金额须为不少于 100 元的整元金额，且不能超出安全金额范围';

  static double? parseInput(String text) {
    final normalized = text.trim();
    // Validate decimal text before double parsing can erase a tiny fraction.
    if (!RegExp(r'^[0-9]+(?:\.0+)?$').hasMatch(normalized)) return null;
    return double.tryParse(normalized);
  }

  static bool isValid(double? amount) =>
      amount != null &&
      amount.isFinite &&
      amount >= minimum &&
      amount <= maximumExactYuan &&
      amount == amount.truncateToDouble();

  static int minorUnits(double amount) {
    if (!isValid(amount)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: message,
      );
    }
    return amount.toInt() * 100;
  }
}

class WithdrawalQuote {
  const WithdrawalQuote({
    required this.quotedAmount,
    required this.feeAmount,
    required this.receivedAmount,
    required this.feeRateBasisPoints,
    required this.feeRateText,
    required this.minimumAmount,
    required this.feePolicyVersion,
    this.currency = LedgerCurrency.cashCny,
  });

  final double quotedAmount;
  final int feePolicyVersion;
  final double feeAmount;
  final double receivedAmount;
  final int feeRateBasisPoints;
  double get feeRate => feeRateBasisPoints / 10000;
  final String feeRateText;
  final double minimumAmount;
  final LedgerCurrency currency;

  static int ceilingFeeMinor(int amountMinor, int basisPoints) =>
      ((BigInt.from(amountMinor) * BigInt.from(basisPoints) +
                  BigInt.from(9999)) ~/
              BigInt.from(10000))
          .toInt();

  void validateFor(double amount) {
    final int minor = WithdrawalAmountPolicy.minorUnits(amount);
    if (!feeRate.isFinite || !feeAmount.isFinite || !receivedAmount.isFinite) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现报价金额不合法',
      );
    }
    final int basisPoints = feeRateBasisPoints;
    final int fee = (feeAmount * 100).round();
    final int net = (receivedAmount * 100).round();
    if (quotedAmount != amount ||
        feePolicyVersion < 0 ||
        currency != LedgerCurrency.cashCny ||
        basisPoints < 0 ||
        basisPoints > 9999 ||
        (feeAmount * 100 - fee).abs() > 0.000001 ||
        (receivedAmount * 100 - net).abs() > 0.000001 ||
        fee != ceilingFeeMinor(minor, basisPoints) ||
        net != minor - fee ||
        net <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现报价版本或金额不合法，请重新报价确认',
      );
    }
  }

  double feeFor(double amount) {
    if ((amount - quotedAmount).abs() > 0.000001) {
      throw StateError('提现报价只适用于服务端已确认的金额');
    }
    return feeAmount;
  }

  double receivedFor(double amount) {
    if ((amount - quotedAmount).abs() > 0.000001) {
      throw StateError('提现报价只适用于服务端已确认的金额');
    }
    return receivedAmount;
  }
}

class ConfirmedWithdrawal {
  const ConfirmedWithdrawal({
    required this.amount,
    required this.payoutAccountId,
    required this.quote,
  });
  final double amount;
  final String payoutAccountId;
  final WithdrawalQuote quote;
}

class WithdrawalRecord {
  const WithdrawalRecord({
    required this.id,
    required this.withdrawalNo,
    required this.amount,
    required this.fee,
    required this.receivedAmount,
    required this.status,
    required this.statusText,
    required this.createdAt,
    required this.rejectedReason,
    this.payoutAccountId = '',
    required this.holderNameMasked,
    required this.maskedCard,
    this.currency = LedgerCurrency.cashCny,
  });

  final String id;
  final String withdrawalNo;
  final double amount;
  final double fee;
  final double receivedAmount;
  final WithdrawalStatus status;
  final String statusText;
  final DateTime createdAt;
  final String rejectedReason;

  /// Stable first-party payout-account identity returned with a withdrawal
  /// record. An empty value is retained only for Mock-mode fixtures; the live
  /// backend parser requires this authority before accepting a record.
  final String payoutAccountId;

  /// Masked payout-account holder name from the first-party backend.
  ///
  /// This is deliberately not a bank name and must never contain an
  /// unmasked account holder or account number.
  final String holderNameMasked;
  final String maskedCard;
  final LedgerCurrency currency;
}

class CommercePage<T> {
  const CommercePage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;
}

class YouthModeCommercePolicy {
  const YouthModeCommercePolicy();

  bool canCreateRechargeOrder({required bool youthModeEnabled}) =>
      !youthModeEnabled;

  // Foreground business access only. Durable settled-order recovery remains
  // a separate background reconciliation responsibility.
  bool canUseNonRechargeFeature({required bool youthModeEnabled}) =>
      !youthModeEnabled;

  String rechargeRestrictionReason({required bool youthModeEnabled}) =>
      youthModeEnabled ? '青少年模式已开启，暂不能创建新的充值订单' : '';
}

abstract interface class CommerceRepository {
  bool get supportsPaymentChannelInvocation;
  bool get supportsRefundHistory;
  bool get supportsWithdrawalApplication;

  /// Whether the UI may expose the first-party payout-account selector.
  ///
  /// This is separate from [supportsWithdrawalApplication] so deterministic
  /// fixtures can retain their compact legacy presentation while live
  /// repositories opt into the authoritative account picker.
  bool get supportsPayoutAccountSelection => false;
  RefundScope get refundScope;

  Future<WalletSummary> fetchWalletSummary();

  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  });

  Future<CommercePage<PaymentOrder>> fetchOrders({
    required int page,
    required int pageSize,
  });

  Future<PaymentOrder> queryOrderStatus(PaymentOrder order);

  Future<RefundEligibility> checkRefundEligibility(String account);

  /// Returns the authenticated user's masked, first-party payout-account
  /// projections. Implementations without the live contract fail closed.
  Future<PayoutAccountSelection> fetchPayoutAccounts() =>
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前后端未提供收款账户列表契约',
      );

  Future<RefundApplication> submitRefund(RefundRequest request);

  Future<RefundApplication> fetchRefundResult(
    String applicationId, {
    String? expectedOrderNo,
  });

  Future<RefundApplication> resubmitRefund(
    String applicationId, {
    String? expectedOrderNo,
  });

  Future<List<RefundApplication>> fetchRefundApplications(String account);

  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount});

  ConfirmedWithdrawal? get pendingWithdrawal;
  (String?, int) get withdrawalIdentity;
  Listenable? get withdrawalIdentityChanges;

  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  });

  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  });

  Future<WithdrawalRecord> fetchWithdrawalRecord(String id);
}
