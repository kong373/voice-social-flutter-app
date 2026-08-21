enum LedgerDirection { income, expense }

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

enum RefundStatus { reviewing, approved, rejected, resubmitted, unavailable }

enum RefundScope { accountLegacy, order }

enum WithdrawalStatus { pending, approved, rejected, paying, succeeded, failed }

class BankCardSummary {
  const BankCardSummary({
    required this.id,
    required this.bankName,
    required this.maskedNumber,
    required this.holderName,
  });

  final String id;
  final String bankName;
  final String maskedNumber;
  final String holderName;
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
  final double agentEarnings;
  final double superAgentEarnings;
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
}

class PaymentOrder {
  const PaymentOrder({
    required this.orderNo,
    required this.amount,
    required this.giftCoinAmount,
    required this.channelName,
    required this.createdAt,
    required this.status,
  });

  final String orderNo;
  final double amount;
  final int giftCoinAmount;
  final String channelName;
  final DateTime createdAt;
  final PaymentOrderStatus status;

  PaymentOrder copyWith({PaymentOrderStatus? status}) {
    return PaymentOrder(
      orderNo: orderNo,
      amount: amount,
      giftCoinAmount: giftCoinAmount,
      channelName: channelName,
      createdAt: createdAt,
      status: status ?? this.status,
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
  });

  final String id;
  final String account;
  final double amount;
  final RefundStatus status;
  final String statusText;
  final String rejectedReason;
  final DateTime createdAt;

  RefundApplication copyWith({
    RefundStatus? status,
    String? statusText,
    String? rejectedReason,
  }) {
    return RefundApplication(
      id: id,
      account: account,
      amount: amount,
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      createdAt: createdAt,
    );
  }
}

class WithdrawalQuote {
  const WithdrawalQuote({
    required this.feeRate,
    required this.feeRateText,
    required this.minimumAmount,
  });

  final double feeRate;
  final String feeRateText;
  final double minimumAmount;

  double feeFor(double amount) => amount * feeRate;
  double receivedFor(double amount) => amount - feeFor(amount);
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
    required this.bankName,
    required this.maskedCard,
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
  final String bankName;
  final String maskedCard;
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
  RefundScope get refundScope;

  Future<WalletSummary> fetchWalletSummary();

  Future<CommercePage<LedgerEntry>> fetchLedger({
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

  Future<RefundApplication> submitRefund(RefundRequest request);

  Future<RefundApplication> fetchRefundResult(String applicationId);

  Future<RefundApplication> resubmitRefund(String applicationId);

  Future<List<RefundApplication>> fetchRefundApplications(String account);

  Future<WithdrawalQuote> fetchWithdrawalQuote();

  Future<WithdrawalRecord> applyWithdrawal({required double amount});

  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  });

  Future<WithdrawalRecord> fetchWithdrawalRecord(String id);
}
