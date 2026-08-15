import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

class BackendCommerceRepository implements CommerceRepository {
  BackendCommerceRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  })  : _apiClient = apiClient,
        _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final Map<String, RefundApplication> _knownRefunds =
      <String, RefundApplication>{};

  static const Set<String> _retiredLedgerSubtypes = <String>{
    'blind_box',
    'red_packet',
    'ktv',
    'magic_ball',
    'dango',
    'love_letter',
  };

  @override
  bool get supportsPaymentChannelInvocation => false;

  @override
  bool get supportsRefundHistory => false;

  @override
  RefundScope get refundScope => RefundScope.accountLegacy;

  @override
  Future<WalletSummary> fetchWalletSummary() async {
    final ApiResponse ncoinResponse = await _apiClient.get(_routes.ncoinBalance);
    final ApiResponse walletResponse = await _apiClient.get(
      _routes.walletOverview,
    );
    final Map<String, Object?> ncoin = _asMap(ncoinResponse.data);
    final Map<String, Object?> wallet = _asMap(walletResponse.data);
    final Map<String, Object?> card = _asMap(wallet['defaultBankCard']);
    return WalletSummary(
      giftCoinBalance: _asInt(ncoin['integer'] ?? ncoin['value']),
      cashBalance: _asDouble(wallet['balance']) ?? 0,
      frozenBalance: _asDouble(wallet['frozenBalance']) ?? 0,
      totalEarnings: _asDouble(wallet['totalEarnings']) ?? 0,
      yesterdayEarnings: _asDouble(wallet['yesterdayEarnings']) ?? 0,
      totalWithdrawn: _asDouble(wallet['totalWithdraw']) ?? 0,
      realNameVerified: _asBool(wallet['isRealName']),
      bankCard: card.isEmpty
          ? null
          : BankCardSummary(
              id: _string(card['id']),
              bankName: _string(card['bankName'], fallback: '银行卡'),
              maskedNumber: _string(card['cardNumberMasked']),
              holderName: _string(card['cardHolderName']),
            ),
      agentEarnings: _asDouble(wallet['agentEarnings']) ?? 0,
      superAgentEarnings: _asDouble(wallet['superAgentEarnings']) ?? 0,
    );
  }

  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.walletAccountDetails,
      query: <String, String>{
        'type': direction == LedgerDirection.income ? '1' : '2',
        'page': '$page',
        'size': '$pageSize',
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<LedgerEntry> entries = <LedgerEntry>[];
    for (final Object? raw in _asList(data['records'] ?? data['list'])) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final String subtype = _string(raw['subType']).toLowerCase();
      if (_retiredLedgerSubtypes.contains(subtype)) {
        continue;
      }
      entries.add(
        LedgerEntry(
          id: _string(raw['id']),
          direction: direction,
          kind: _ledgerKind(subtype, direction),
          title: _string(
            raw['subTypeName'],
            fallback: direction == LedgerDirection.income ? '收入' : '支出',
          ),
          amount: _asDouble(raw['amount']) ?? 0,
          createdAt: _asDateTime(raw['createTime']) ?? DateTime.now(),
          relatedUserName: _string(raw['relatedUserName']),
          businessName: _string(raw['businessName']),
          rawSubtype: subtype,
        ),
      );
    }
    return _commercePage(data, entries, page: page, pageSize: pageSize);
  }

  @override
  Future<CommercePage<PaymentOrder>> fetchOrders({
    required int page,
    required int pageSize,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.paymentOrders,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<PaymentOrder> orders = <PaymentOrder>[
      for (final Object? raw in _asList(data['list']))
        if (raw is Map<String, Object?>)
          PaymentOrder(
            orderNo: _string(raw['orderNo']),
            amount: _asDouble(raw['amount']) ?? 0,
            giftCoinAmount: _asInt(raw['ncoin']) ?? 0,
            channelName: _string(raw['payType'], fallback: '支付渠道'),
            createdAt: _asDateTime(raw['createDate']) ?? DateTime.now(),
            status: PaymentOrderStatus.unknown,
          ),
    ];
    return _commercePage(data, orders, page: page, pageSize: pageSize);
  }

  @override
  Future<PaymentOrder> queryOrderStatus(PaymentOrder order) async {
    final ApiResponse response = await _apiClient.get(
      _routes.paymentOrderResult,
      query: <String, String>{'orderNo': order.orderNo},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final bool succeeded = _asBool(data['bool'] ?? data['value']);
    return order.copyWith(
      status: succeeded
          ? PaymentOrderStatus.succeeded
          : PaymentOrderStatus.confirming,
    );
  }

  @override
  Future<RefundEligibility> checkRefundEligibility(String account) async {
    final ApiResponse response = await _apiClient.get(
      _routes.refundCheck,
      query: <String, String>{'loginName': account},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String existingId = _string(data['string']);
    return RefundEligibility(
      allowed: existingId.isEmpty || existingId == 'null',
      existingApplicationId:
          existingId.isEmpty || existingId == 'null' ? null : existingId,
      message: existingId.isEmpty || existingId == 'null'
          ? '当前账号可以提交账户退款申请。'
          : '已有账户退款申请正在处理，请先查看结果。',
    );
  }

  @override
  Future<RefundApplication> submitRefund(RefundRequest request) async {
    final RefundEligibility eligibility =
        await checkRefundEligibility(request.account);
    if (!eligibility.allowed && eligibility.existingApplicationId != null) {
      return fetchRefundResult(eligibility.existingApplicationId!);
    }
    final ApiResponse response = await _apiClient.post(
      _routes.refundApplication,
      body: <String, Object?>{
        'loginName': request.account,
        'realName': request.realName,
        'age': request.age,
        'refundAmount': request.amount,
        'refundReason': request.reason,
        'alipayAccount': request.receivingAccount,
        'alipayRealName': request.receivingName,
        'payEvidenceImgUrls': '',
        'custodianName': request.guardianName,
        'custodianPhone': request.guardianPhone,
        'custodianIdcardNo': '',
        'custodianCertificateImgUrls': '',
        'rechargeNotCustodianEvidenceImgUrls': '',
      },
    );
    final String id = _string(_asMap(response.data)['string']);
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款申请提交成功但未返回申请编号',
      );
    }
    final RefundApplication application = RefundApplication(
      id: id,
      account: request.account,
      amount: request.amount,
      status: RefundStatus.reviewing,
      statusText: '审核中',
      rejectedReason: '',
      createdAt: DateTime.now(),
    );
    _knownRefunds[id] = application;
    return application;
  }

  @override
  Future<RefundApplication> fetchRefundResult(String applicationId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.refundResult,
      query: <String, String>{'id': applicationId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final int code = _asInt(data['status']) ?? 0;
    final RefundStatus status = switch (code) {
      1 => RefundStatus.approved,
      2 => RefundStatus.rejected,
      3 => RefundStatus.resubmitted,
      _ => RefundStatus.reviewing,
    };
    final RefundApplication base = _knownRefunds[applicationId] ??
        RefundApplication(
          id: applicationId,
          account: '',
          amount: 0,
          status: status,
          statusText: _refundStatusText(status),
          rejectedReason: '',
          createdAt: DateTime.now(),
        );
    final RefundApplication updated = base.copyWith(
      status: status,
      statusText: _refundStatusText(status),
      rejectedReason: _string(data['rejectedReason']),
    );
    _knownRefunds[applicationId] = updated;
    return updated;
  }

  @override
  Future<RefundApplication> resubmitRefund(String applicationId) async {
    await _apiClient.get(
      _routes.refundRepeat,
      query: <String, String>{'id': applicationId},
    );
    final RefundApplication current = await fetchRefundResult(applicationId);
    final RefundApplication updated = current.copyWith(
      status: RefundStatus.resubmitted,
      statusText: '已重新提交',
      rejectedReason: '',
    );
    _knownRefunds[applicationId] = updated;
    return updated;
  }

  @override
  Future<List<RefundApplication>> fetchRefundApplications(String account) async {
    final RefundEligibility eligibility = await checkRefundEligibility(account);
    final String? id = eligibility.existingApplicationId;
    if (id == null) {
      return _knownRefunds.values
          .where((RefundApplication item) => item.account == account)
          .toList(growable: false);
    }
    final RefundApplication application = await fetchRefundResult(id);
    if (application.account.isEmpty) {
      final RefundApplication withAccount = RefundApplication(
        id: application.id,
        account: account,
        amount: application.amount,
        status: application.status,
        statusText: application.statusText,
        rejectedReason: application.rejectedReason,
        createdAt: application.createdAt,
      );
      _knownRefunds[id] = withAccount;
      return <RefundApplication>[withAccount];
    }
    return <RefundApplication>[application];
  }

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote() async {
    final ApiResponse response = await _apiClient.get(
      _routes.withdrawalFeeRate,
    );
    final Map<String, Object?> data = _asMap(response.data);
    final double rate = _asDouble(data['feeRate']) ?? 0;
    return WithdrawalQuote(
      feeRate: rate,
      feeRateText: _string(
        data['feeRateDisplay'],
        fallback: '${(rate * 100).toStringAsFixed(2)}%',
      ),
      minimumAmount: 100,
    );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({required double amount}) async {
    final ApiResponse response = await _apiClient.post(
      _routes.withdrawalApply,
      body: <String, Object?>{'amount': amount},
    );
    final String id = _string(response.data);
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现申请未返回记录编号',
      );
    }
    try {
      return await fetchWithdrawalRecord(id);
    } on ApiException {
      final WithdrawalQuote quote = await fetchWithdrawalQuote();
      return WithdrawalRecord(
        id: id,
        withdrawalNo: id,
        amount: amount,
        fee: quote.feeFor(amount),
        receivedAmount: quote.receivedFor(amount),
        status: WithdrawalStatus.pending,
        statusText: '待审核',
        createdAt: DateTime.now(),
        rejectedReason: '',
        bankName: '',
        maskedCard: '',
      );
    }
  }

  @override
  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  }) async {
    final Map<String, String> query = <String, String>{
      'page': '$page',
      'size': '$pageSize',
      if (status != null) 'status': '${_withdrawalStatusCode(status)}',
    };
    final ApiResponse response = await _apiClient.get(
      _routes.withdrawalRecords,
      query: query,
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<WithdrawalRecord> records = <WithdrawalRecord>[
      for (final Object? raw in _asList(data['records'] ?? data['list']))
        if (raw is Map<String, Object?>) _withdrawalFromMap(raw),
    ];
    return _commercePage(data, records, page: page, pageSize: pageSize);
  }

  @override
  Future<WithdrawalRecord> fetchWithdrawalRecord(String id) async {
    final ApiResponse response = await _apiClient.get(
      '${_routes.withdrawalRecords}/$id',
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录响应为空',
      );
    }
    return _withdrawalFromMap(data);
  }

  static LedgerKind _ledgerKind(
    String subtype,
    LedgerDirection direction,
  ) {
    return switch (subtype) {
      'gift_income' => LedgerKind.giftIncome,
      'send_gift' => LedgerKind.giftExpense,
      'agent_income' => LedgerKind.agentIncome,
      'super_agent_income' => LedgerKind.superAgentIncome,
      'withdrawal' => LedgerKind.withdrawal,
      _ => direction == LedgerDirection.income
          ? LedgerKind.other
          : LedgerKind.other,
    };
  }

  static WithdrawalRecord _withdrawalFromMap(Map<String, Object?> raw) {
    final WithdrawalStatus status = _withdrawalStatus(
      _asInt(raw['status']) ?? 0,
    );
    return WithdrawalRecord(
      id: _string(raw['id']),
      withdrawalNo: _string(raw['withdrawalNo']),
      amount: _asDouble(raw['amount']) ?? 0,
      fee: _asDouble(raw['fee']) ?? 0,
      receivedAmount: _asDouble(raw['actualAmount']) ?? 0,
      status: status,
      statusText: _string(raw['statusName'], fallback: _withdrawalStatusText(status)),
      createdAt: _asDateTime(raw['createTime']) ?? DateTime.now(),
      rejectedReason: _string(raw['rejectReason']),
      bankName: _string(raw['bankCardName']),
      maskedCard: _string(raw['bankCardId']),
    );
  }

  static CommercePage<T> _commercePage<T>(
    Map<String, Object?> data,
    List<T> items, {
    required int page,
    required int pageSize,
  }) {
    final int current = _asInt(data['current']) ?? page;
    final int size = _asInt(data['size']) ?? pageSize;
    final int total = _asInt(data['total']) ?? items.length;
    final int pages = _asInt(data['pages']) ??
        (size <= 0 ? 1 : (total / size).ceil());
    return CommercePage<T>(
      items: items,
      page: current,
      pageSize: size,
      total: total,
      hasMore: current < pages,
    );
  }

  static String _refundStatusText(RefundStatus status) => switch (status) {
        RefundStatus.reviewing => '审核中',
        RefundStatus.approved => '已通过',
        RefundStatus.rejected => '已拒绝',
        RefundStatus.resubmitted => '已重新提交',
        RefundStatus.unavailable => '不可用',
      };

  static WithdrawalStatus _withdrawalStatus(int code) => switch (code) {
        1 => WithdrawalStatus.approved,
        2 => WithdrawalStatus.rejected,
        3 => WithdrawalStatus.paying,
        4 => WithdrawalStatus.succeeded,
        5 => WithdrawalStatus.failed,
        _ => WithdrawalStatus.pending,
      };

  static int _withdrawalStatusCode(WithdrawalStatus status) => switch (status) {
        WithdrawalStatus.pending => 0,
        WithdrawalStatus.approved => 1,
        WithdrawalStatus.rejected => 2,
        WithdrawalStatus.paying => 3,
        WithdrawalStatus.succeeded => 4,
        WithdrawalStatus.failed => 5,
      };

  static String _withdrawalStatusText(WithdrawalStatus status) =>
      switch (status) {
        WithdrawalStatus.pending => '待审核',
        WithdrawalStatus.approved => '审核通过',
        WithdrawalStatus.rejected => '审核拒绝',
        WithdrawalStatus.paying => '打款中',
        WithdrawalStatus.succeeded => '打款成功',
        WithdrawalStatus.failed => '打款失败',
      };

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : const <Object?>[];

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return _asInt(value) == 1;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.tryParse(value?.toString() ?? '');
  }
}
