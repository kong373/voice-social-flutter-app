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

enum PayoutAccountStatus { verified, pending, disabled, unknown }

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
  });

  final String payoutAccountId;
  final String accountType;
  final String accountMasked;
  final String holderNameMasked;
  final PayoutAccountStatus status;
  final bool selectable;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class PayoutAccountSelection {
  const PayoutAccountSelection({
    required this.accounts,
    required this.selectedPayoutAccountId,
    required this.selectionRequired,
  });

  final List<PayoutAccount> accounts;
  final String? selectedPayoutAccountId;
  final bool selectionRequired;

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
    );
  }
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
  });

  final int? giftCoinBalance;
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
  });

  final String id;
  final LedgerDirection direction;
  final LedgerKind kind;
  final String title;
  final double amount;
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

class WithdrawalQuote {
  const WithdrawalQuote({
    required this.quotedAmount,
    required this.feeAmount,
    required this.receivedAmount,
    required this.feeRate,
    required this.feeRateText,
    required this.minimumAmount,
    this.currency = LedgerCurrency.cashCny,
  });

  final double quotedAmount;
  final double feeAmount;
  final double receivedAmount;
  final double feeRate;
  final String feeRateText;
  final double minimumAmount;
  final LedgerCurrency currency;

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

  bool canUseNonRechargeFeature({required bool youthModeEnabled}) => true;

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

  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    String? payoutAccountId,
  });

  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  });

  Future<WithdrawalRecord> fetchWithdrawalRecord(String id);
}
