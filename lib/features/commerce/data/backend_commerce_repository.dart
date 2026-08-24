import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/domain/refund_request_id.dart';

class BackendCommerceRepository implements CommerceRepository {
  BackendCommerceRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final Map<String, Future<RefundApplication>> _pendingRefundSubmissions =
      <String, Future<RefundApplication>>{};
  final Map<String, Future<RefundApplication>> _pendingRefundRetries =
      <String, Future<RefundApplication>>{};
  final Map<String, String> _retainedRefundSubmissionRequestIds =
      <String, String>{};
  final Map<String, String> _retainedRefundRetryRequestIds = <String, String>{};
  final Set<String> _refundSubmissionWritesStarted = <String>{};
  final Set<String> _refundRetryWritesStarted = <String>{};
  Future<PayoutAccountSelection>? _payoutAccountsInFlight;
  bool _payoutAccountsEndpointAvailable = false;
  final Map<String, Future<WithdrawalRecord>> _pendingWithdrawalApplications =
      <String, Future<WithdrawalRecord>>{};
  final Map<String, String> _retainedWithdrawalRequestIds = <String, String>{};
  final Set<String> _withdrawalWritesStarted = <String>{};

  static const Set<String> _retiredLedgerSubtypes = <String>{
    'BLIND_BOX',
    'RED_PACKET',
    'KTV',
    'MAGIC_BALL',
    'DANGO',
    'LOVE_LETTER',
    // The Backend F2 retirement is forward-only and intentionally preserves
    // old audit rows. Keep the permanently excluded membership product from
    // resurfacing through the otherwise-authoritative wallet history.
    'VIP_PURCHASE',
  };

  static const int _maximumCommerceBackendPages = 100;

  @override
  bool get supportsPaymentChannelInvocation => false;

  @override
  bool get supportsRefundHistory => true;

  @override
  bool get supportsWithdrawalApplication => _payoutAccountsEndpointAvailable;

  @override
  bool get supportsPayoutAccountSelection => _payoutAccountsEndpointAvailable;

  @override
  RefundScope get refundScope => RefundScope.order;

  @override
  Future<WalletSummary> fetchWalletSummary() async {
    final ApiResponse ncoinResponse = await _apiClient.get(
      _routes.ncoinBalance,
    );
    final ApiResponse walletResponse = await _apiClient.get(
      _routes.walletOverview,
    );
    final Map<String, Object?> ncoin = _asMap(ncoinResponse.data);
    final Map<String, Object?> wallet = _asMap(walletResponse.data);
    final Map<String, Object?> card = _asMap(wallet['defaultBankCard']);
    return WalletSummary(
      giftCoinBalance: _requiredNonNegativeInt(ncoin, <String>[
        'integer',
        'value',
      ], field: '礼物币余额'),
      cashBalance: _requiredNonNegativeDouble(wallet, 'balance'),
      frozenBalance: _requiredNonNegativeDouble(wallet, 'frozenBalance'),
      totalEarnings: _requiredNonNegativeDouble(wallet, 'totalEarnings'),
      yesterdayEarnings: _requiredNonNegativeDouble(
        wallet,
        'yesterdayEarnings',
      ),
      totalWithdrawn: _requiredNonNegativeDouble(wallet, 'totalWithdraw'),
      realNameVerified: _requiredBool(wallet, 'isRealName'),
      bankCard: card.isEmpty
          ? null
          : BankCardSummary(
              id: _requiredString(card, 'id', field: '银行卡 ID'),
              bankName: _requiredString(card, 'bankName', field: '银行名称'),
              maskedNumber: _requiredString(
                card,
                'cardNumberMasked',
                field: '银行卡号',
              ),
              holderName: _requiredString(card, 'cardHolderName', field: '持卡人'),
            ),
      agentEarnings: _requiredNonNegativeDouble(wallet, 'agentEarnings'),
      superAgentEarnings: _requiredNonNegativeDouble(
        wallet,
        'superAgentEarnings',
      ),
    );
  }

  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) async {
    _validatePageArguments(page: page, pageSize: pageSize);
    const int backendPageSize = 100;
    final List<LedgerEntry> matching = <LedgerEntry>[];
    final Set<String> seenLedgerIds = <String>{};
    _PageMetadata? expectedMetadata;
    var backendPage = 1;
    var hasMore = true;
    while (hasMore && backendPage <= _maximumCommerceBackendPages) {
      final ApiResponse response = await _apiClient.get(
        _routes.walletAccountDetails,
        query: <String, String>{
          'currency': currency == LedgerCurrency.giftCoin
              ? 'GIFT_COIN'
              : 'CASH_CNY',
          'pageNum': '$backendPage',
          'pageSize': '$backendPageSize',
        },
      );
      final Map<String, Object?> data = _asMap(response.data);
      final LedgerCurrency responseCurrency = _requiredCurrency(
        data,
        field: '流水币种',
      );
      if (responseCurrency != currency) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '流水币种与请求币种不一致',
        );
      }
      final List<Object?> rawEntries = _requiredList(data, field: '流水列表');
      final _PageMetadata metadata = _requiredPageMetadata(
        data,
        requestedPage: backendPage,
        requestedPageSize: backendPageSize,
      );
      expectedMetadata = _validateStablePageMetadata(
        expected: expectedMetadata,
        actual: metadata,
      );
      _validatePageItemCount(rawEntries, metadata, field: '钱包流水');
      for (final Object? raw in rawEntries) {
        if (raw is! Map<String, Object?>) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '钱包流水记录结构无法识别',
          );
        }
        final String authoritativeId = _requiredString(
          raw,
          'transactionId',
          field: '流水 ID',
        );
        if (!seenLedgerIds.add(authoritativeId)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '多页钱包流水包含重复的权威流水 ID',
          );
        }
        final LedgerEntry? entry = _ledgerEntry(
          raw,
          currency: currency,
          direction: direction,
        );
        if (entry != null) matching.add(entry);
      }
      hasMore = metadata.current < metadata.pages;
      if (hasMore && rawEntries.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '钱包流水分页响应为空但仍声明存在下一页',
        );
      }
      backendPage += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '钱包流水超过客户端安全分页上限',
      );
    }
    final int start = (page - 1) * pageSize;
    final int end = start >= matching.length
        ? start
        : (start + pageSize).clamp(start, matching.length);
    final List<LedgerEntry> items = start >= matching.length
        ? const <LedgerEntry>[]
        : matching.sublist(start, end);
    return CommercePage<LedgerEntry>(
      items: items,
      page: page,
      pageSize: pageSize,
      total: matching.length,
      hasMore: end < matching.length,
    );
  }

  static LedgerEntry? _ledgerEntry(
    Map<String, Object?> raw, {
    required LedgerCurrency currency,
    required LedgerDirection direction,
  }) {
    final String businessType = _string(raw['businessType']).toUpperCase();
    if (_retiredLedgerSubtypes.contains(businessType)) {
      return null;
    }
    final LedgerDirection? entryDirection = _ledgerDirection(raw['type']);
    if (entryDirection == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '流水缺少有效服务端方向',
      );
    }
    if (entryDirection != direction) return null;
    final String id = _requiredString(raw, 'transactionId', field: '流水 ID');
    _validateOptionalCurrency(raw, currency, field: '流水币种');
    final int amountMinor = _requiredInt(raw, <String>[
      'amountMinor',
    ], field: '流水金额');
    if (amountMinor < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '流水金额不能为负数',
      );
    }
    final DateTime createdAt = _requiredDateTime(
      raw,
      'createdAt',
      field: '流水时间',
    );
    return LedgerEntry(
      id: id,
      direction: entryDirection,
      kind: _ledgerKind(businessType),
      title: _string(
        raw['description'],
        fallback: direction == LedgerDirection.income ? '收入' : '支出',
      ),
      amount: currency == LedgerCurrency.giftCoin
          ? amountMinor.toDouble()
          : _minorToMajor(amountMinor),
      createdAt: createdAt,
      relatedUserName: _string(raw['counterpartyUserId']),
      businessName: _string(raw['businessId']),
      rawSubtype: businessType.toLowerCase(),
      currency: currency,
    );
  }

  @override
  Future<CommercePage<PaymentOrder>> fetchOrders({
    required int page,
    required int pageSize,
  }) async {
    _validatePageArguments(page: page, pageSize: pageSize);
    final List<PaymentOrder> allOrders = <PaymentOrder>[];
    final Set<String> seenOrderIds = <String>{};
    _PageMetadata? expectedMetadata;
    var backendPage = 1;
    var hasMore = true;
    while (hasMore && backendPage <= _maximumCommerceBackendPages) {
      final ApiResponse response = await _apiClient.post(
        _routes.paymentOrders,
        body: <String, Object?>{'pageNum': backendPage, 'pageSize': pageSize},
      );
      final Map<String, Object?> data = _asMap(response.data);
      final List<Object?> rawOrders = _requiredList(data, field: '充值订单列表');
      final _PageMetadata metadata = _requiredOrderPageMetadata(
        data,
        requestedPage: backendPage,
        requestedPageSize: pageSize,
      );
      expectedMetadata = _validateStablePageMetadata(
        expected: expectedMetadata,
        actual: metadata,
      );
      _validatePageItemCount(rawOrders, metadata, field: '充值订单');
      for (final Object? raw in rawOrders) {
        if (raw is! Map<String, Object?>) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '充值订单记录结构无法识别',
          );
        }
        final PaymentOrder order = _paymentOrderFromMap(
          raw,
          currency: LedgerCurrency.cashCny,
        );
        if (!seenOrderIds.add(order.orderNo)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '多页充值订单包含重复的权威订单号',
          );
        }
        allOrders.add(order);
      }
      hasMore = metadata.current < metadata.pages;
      if (hasMore && rawOrders.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '充值订单分页响应为空但仍声明存在下一页',
        );
      }
      backendPage += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单超过客户端安全分页上限',
      );
    }
    final _PageMetadata metadata = expectedMetadata!;
    if ((metadata.pages == 0 && page != 1) ||
        (metadata.pages > 0 && page > metadata.pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单请求页超过服务端页数',
      );
    }
    final int start = (page - 1) * pageSize;
    final int end = start >= allOrders.length
        ? start
        : (start + pageSize).clamp(start, allOrders.length);
    final List<PaymentOrder> orders = start >= allOrders.length
        ? const <PaymentOrder>[]
        : allOrders.sublist(start, end);
    return CommercePage<PaymentOrder>(
      items: orders,
      page: page,
      pageSize: metadata.pageSize,
      total: metadata.total,
      hasMore: page < metadata.pages,
    );
  }

  @override
  Future<PaymentOrder> queryOrderStatus(PaymentOrder order) async {
    final ApiResponse response = await _apiClient.get(
      _routes.paymentOrderResult,
      query: <String, String>{'orderNo': order.orderNo},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String returnedOrderNo = _requiredString(
      data,
      'orderNo',
      field: '订单号',
    );
    if (returnedOrderNo != order.orderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单状态响应与请求订单不一致',
      );
    }
    final PaymentOrder authoritative = _paymentOrderFromMap(
      data,
      currency: LedgerCurrency.cashCny,
    );
    final Object? rawSuccess = data['bool'];
    if (!data.containsKey('bool') || rawSuccess is! bool) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单状态响应缺少严格的 bool 权威字段',
      );
    }
    final bool statusSuccess =
        authoritative.status == PaymentOrderStatus.succeeded;
    if (rawSuccess != statusSuccess) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单状态响应的 bool 与 status 不一致',
      );
    }
    if (authoritative.orderNo != order.orderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单状态响应与请求订单不一致',
      );
    }
    return authoritative;
  }

  @override
  Future<RefundEligibility> checkRefundEligibility(String account) async {
    final String orderNo = account.trim();
    if (orderNo.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择需要退款的充值订单',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.refundCheck,
      query: <String, String>{'orderNo': orderNo},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String responseOrderNo = _requiredString(
      data,
      'orderNo',
      field: '退款订单号',
    );
    if (responseOrderNo != orderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款资格响应与请求订单不一致',
      );
    }
    final bool allowed = _requiredBool(data, 'eligible');
    _requireVendorBlocked(data, field: 'providerStatus', label: '退款资格');
    _validateOptionalCurrency(data, LedgerCurrency.cashCny, field: '退款币种');
    final int amountMinor = _requiredInt(data, <String>[
      'amountMinor',
    ], field: '退款订单金额');
    final int giftCoinAmount = _requiredInt(data, <String>[
      'giftCoinAmount',
    ], field: '退款订单礼物币');
    final String reason = _requiredString(
      data,
      'reason',
      field: '退款资格原因',
    ).toUpperCase();
    if (amountMinor <= 0 ||
        giftCoinAmount <= 0 ||
        (allowed && reason != 'ELIGIBLE') ||
        (!allowed && reason == 'ELIGIBLE')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款资格响应的金额、结论或原因相互矛盾',
      );
    }
    return RefundEligibility(
      allowed: allowed,
      existingApplicationId: null,
      message: _refundEligibilityMessage(reason, allowed: allowed),
    );
  }

  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() {
    final Future<PayoutAccountSelection>? inFlight = _payoutAccountsInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<PayoutAccountSelection> future;
    future = _fetchPayoutAccounts().whenComplete(() {
      if (identical(_payoutAccountsInFlight, future)) {
        _payoutAccountsInFlight = null;
      }
    });
    _payoutAccountsInFlight = future;
    return future;
  }

  Future<PayoutAccountSelection> _fetchPayoutAccounts() async {
    final ApiResponse response = await _apiClient.get(_routes.payoutAccounts);
    final Map<String, Object?> data = _asMap(response.data);
    final List<Object?> rawAccounts = _requiredList(data, field: '收款账户列表');
    final int total = _requiredNonNegativeIntField(
      data,
      'total',
      field: '收款账户总数',
    );
    if (rawAccounts.length != total) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收款账户列表数量与服务端 total 不一致',
      );
    }
    final List<PayoutAccount> accounts = <PayoutAccount>[];
    final Set<String> seenIds = <String>{};
    for (final Object? raw in rawAccounts) {
      if (raw is! Map<String, Object?>) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '收款账户记录结构无法识别',
        );
      }
      final String id = _requiredAliasedString(raw, <String>[
        'payoutAccountId',
        'accountId',
      ], field: '收款账户 ID');
      if (!seenIds.add(id)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '收款账户列表包含重复的权威 ID',
        );
      }
      final String accountType = _requiredString(
        raw,
        'accountType',
        field: '收款账户类型',
      );
      final String accountMasked = _requiredAliasedString(raw, <String>[
        'accountMasked',
        'maskedAccount',
      ], field: '收款账户脱敏账号');
      final String holderNameMasked = _requiredAliasedString(raw, <String>[
        'holderNameMasked',
        'holderMasked',
      ], field: '收款账户脱敏姓名');
      final String rawStatus = _requiredString(
        raw,
        'status',
        field: '收款账户状态',
      ).toUpperCase();
      final PayoutAccountStatus status = _payoutAccountStatus(rawStatus);
      if (status == PayoutAccountStatus.unknown) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '收款账户状态不是受支持的服务端状态',
        );
      }
      final bool selectable = _requiredBool(raw, 'selectable');
      final bool expectedSelectable = status == PayoutAccountStatus.verified;
      if (selectable != expectedSelectable) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '收款账户 selectable 与服务端状态不一致',
        );
      }
      accounts.add(
        PayoutAccount(
          payoutAccountId: id,
          accountType: accountType,
          accountMasked: accountMasked,
          holderNameMasked: holderNameMasked,
          status: status,
          selectable: selectable,
          createdAt: _optionalDateTime(raw['createdAt']),
          updatedAt: _optionalDateTime(raw['updatedAt']),
        ),
      );
    }
    if (_requiredBool(data, 'providerInvocation')) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '收款账户响应声明了不允许的厂商调用',
      );
    }
    final String? selected = _optionalTrimmedString(
      data['selectedPayoutAccountId'],
    );
    final String? defaultSelected = _optionalTrimmedString(
      data['defaultPayoutAccountId'],
    );
    if (selected != null &&
        defaultSelected != null &&
        selected != defaultSelected) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收款账户 selected 与 default 不一致',
      );
    }
    final String? resolvedSelected = selected ?? defaultSelected;
    if (resolvedSelected != null) {
      final PayoutAccount? selectedAccount = _findPayoutAccount(
        accounts,
        resolvedSelected,
      );
      if (selectedAccount == null || !selectedAccount.selectable) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端选中的收款账户不可提现',
        );
      }
    }
    final bool selectionRequired = data.containsKey('selectionRequired')
        ? _requiredBool(data, 'selectionRequired')
        : resolvedSelected == null;
    if (selectionRequired != (resolvedSelected == null)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收款账户 selectionRequired 与选择结果不一致',
      );
    }
    _payoutAccountsEndpointAvailable = true;
    return PayoutAccountSelection(
      accounts: List<PayoutAccount>.unmodifiable(accounts),
      selectedPayoutAccountId: resolvedSelected,
      selectionRequired: selectionRequired,
    );
  }

  @override
  Future<RefundApplication> submitRefund(RefundRequest request) async {
    final String orderNo = request.account.trim();
    final String reason = request.reason.trim();
    if (orderNo.isEmpty || reason.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值订单和退款原因不能为空',
      );
    }
    final String intentKey = _refundSubmissionIntentKey(
      orderNo: orderNo,
      reason: reason,
    );
    final Future<RefundApplication>? pending =
        _pendingRefundSubmissions[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedRefundSubmissionRequestIds.putIfAbsent(
      intentKey,
      () => normalizeCommerceRefundRequestId(newCommerceRefundRequestId()),
    );
    final bool replayingRetainedWrite = _refundSubmissionWritesStarted.contains(
      intentKey,
    );
    late final Future<RefundApplication> future;
    future =
        _submitRefundOnce(
          orderNo,
          reason,
          requestId,
          intentKey: intentKey,
          replayingRetainedWrite: replayingRetainedWrite,
        ).then<RefundApplication>(
          (RefundApplication value) {
            if (identical(_pendingRefundSubmissions[intentKey], future)) {
              _pendingRefundSubmissions.remove(intentKey);
            }
            _retainedRefundSubmissionRequestIds.remove(intentKey);
            _refundSubmissionWritesStarted.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_pendingRefundSubmissions[intentKey], future)) {
              _pendingRefundSubmissions.remove(intentKey);
            }
            if (!shouldRetainCommerceRefundRequest(error)) {
              _retainedRefundSubmissionRequestIds.remove(intentKey);
              _refundSubmissionWritesStarted.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingRefundSubmissions[intentKey] = future;
    return future;
  }

  Future<RefundApplication> _submitRefundOnce(
    String orderNo,
    String reason,
    String requestId, {
    required String intentKey,
    required bool replayingRetainedWrite,
  }) async {
    if (!replayingRetainedWrite) {
      final RefundEligibility eligibility = await checkRefundEligibility(
        orderNo,
      );
      if (!eligibility.allowed) {
        throw ApiException(
          kind: ApiFailureKind.conflict,
          message: eligibility.message,
        );
      }
    }
    // The eligibility check is only a precondition for a new write. Once the
    // POST has started, a later attempt is an idempotent replay and must not
    // be blocked by the now-mutated order eligibility state.
    _refundSubmissionWritesStarted.add(intentKey);
    final ApiResponse response = await _apiClient.post(
      _routes.refundApplication,
      headers: <String, String>{'X-Request-Id': requestId},
      body: <String, Object?>{'orderNo': orderNo, 'reason': reason},
    );
    return _refundFromMap(
      _asMap(response.data),
      currency: LedgerCurrency.cashCny,
      expectedOrderNo: orderNo,
    );
  }

  @override
  Future<RefundApplication> fetchRefundResult(
    String applicationId, {
    String? expectedOrderNo,
  }) async {
    final String refundId = applicationId.trim();
    final String? orderNo = _optionalExpectedOrderNo(expectedOrderNo);
    if (refundId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '退款申请编号不能为空',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.refundResult,
      query: <String, String>{'refundId': refundId},
    );
    return _refundFromMap(
      _asMap(response.data),
      currency: LedgerCurrency.cashCny,
      expectedRefundId: refundId,
      expectedOrderNo: orderNo,
    );
  }

  @override
  Future<RefundApplication> resubmitRefund(
    String applicationId, {
    String? expectedOrderNo,
  }) async {
    final String refundId = applicationId.trim();
    final String? orderNo = _optionalExpectedOrderNo(expectedOrderNo);
    if (refundId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '退款申请编号不能为空',
      );
    }
    final String intentKey = _refundRetryIntentKey(refundId: refundId);
    final Future<RefundApplication>? pending = _pendingRefundRetries[intentKey];
    if (pending != null) {
      return pending.then(
        (RefundApplication value) =>
            _validateExpectedRefundOrder(value, expectedOrderNo: orderNo),
      );
    }
    final String requestId = _retainedRefundRetryRequestIds.putIfAbsent(
      intentKey,
      () => normalizeCommerceRefundRequestId(newCommerceRefundRequestId()),
    );
    final bool replayingRetainedWrite = _refundRetryWritesStarted.contains(
      intentKey,
    );
    late final Future<RefundApplication> future;
    future =
        _resubmitRefundOnce(
          refundId,
          requestId,
          expectedOrderNo: orderNo,
          intentKey: intentKey,
          replayingRetainedWrite: replayingRetainedWrite,
        ).then<RefundApplication>(
          (RefundApplication value) {
            if (identical(_pendingRefundRetries[intentKey], future)) {
              _pendingRefundRetries.remove(intentKey);
            }
            _retainedRefundRetryRequestIds.remove(intentKey);
            _refundRetryWritesStarted.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_pendingRefundRetries[intentKey], future)) {
              _pendingRefundRetries.remove(intentKey);
            }
            if (!shouldRetainCommerceRefundRequest(error)) {
              _retainedRefundRetryRequestIds.remove(intentKey);
              _refundRetryWritesStarted.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingRefundRetries[intentKey] = future;
    return future;
  }

  Future<RefundApplication> _resubmitRefundOnce(
    String refundId,
    String requestId, {
    String? expectedOrderNo,
    required String intentKey,
    required bool replayingRetainedWrite,
  }) async {
    final ApiResponse currentResponse = await _apiClient.get(
      _routes.refundResult,
      query: <String, String>{'refundId': refundId},
    );
    final Map<String, Object?> current = _asMap(currentResponse.data);
    final RefundApplication currentApplication = _refundFromMap(
      current,
      currency: LedgerCurrency.cashCny,
      expectedRefundId: refundId,
      expectedOrderNo: expectedOrderNo,
    );
    if (currentApplication.status != RefundStatus.rejected) {
      if (replayingRetainedWrite &&
          _refundRetryAppliedStatus(currentApplication.status)) {
        // A previous repeat POST may have committed before its response was
        // lost. Treat a server-confirmed submitted/terminal state as the
        // idempotent reconciliation result instead of issuing a second POST
        // or rejecting it on the pre-write REJECTED gate.
        return currentApplication;
      }
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '只有已拒绝的退款申请可以重新提交',
      );
    }
    final String reason = _string(current['reason']);
    if (reason.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果未返回原申请原因，无法安全重新提交',
      );
    }
    _refundRetryWritesStarted.add(intentKey);
    final ApiResponse response = await _apiClient.post(
      _routes.refundRepeat,
      headers: <String, String>{'X-Request-Id': requestId},
      body: <String, Object?>{'refundId': refundId, 'reason': reason},
    );
    return _refundFromMap(
      _asMap(response.data),
      currency: LedgerCurrency.cashCny,
      expectedRefundId: refundId,
      expectedOrderNo: expectedOrderNo,
    );
  }

  static bool _refundRetryAppliedStatus(RefundStatus status) =>
      status == RefundStatus.reviewing ||
      status == RefundStatus.resubmitted ||
      status == RefundStatus.approved;

  @override
  Future<List<RefundApplication>> fetchRefundApplications(
    String account,
  ) async {
    final List<RefundApplication> applications = <RefundApplication>[];
    final Set<String> seenRefundIds = <String>{};
    _PageMetadata? expectedMetadata;
    var backendPage = 1;
    var hasMore = true;
    while (hasMore && backendPage <= _maximumCommerceBackendPages) {
      const int backendPageSize = 100;
      final ApiResponse response = await _apiClient.get(
        _routes.refundHistory,
        query: <String, String>{
          'pageNum': '$backendPage',
          'pageSize': '$backendPageSize',
        },
      );
      final Map<String, Object?> data = _asMap(response.data);
      _requireVendorBlocked(data, field: 'providerStatus', label: '退款历史');
      if (data['providerInvocation'] != false) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '退款历史不得触发正式支付厂商',
        );
      }
      final List<Object?> rawApplications = _requiredList(
        data,
        field: '退款历史列表',
      );
      final _PageMetadata metadata = _requiredPageMetadata(
        data,
        requestedPage: backendPage,
        requestedPageSize: backendPageSize,
      );
      expectedMetadata = _validateStablePageMetadata(
        expected: expectedMetadata,
        actual: metadata,
      );
      _validatePageItemCount(rawApplications, metadata, field: '退款历史');
      for (final Object? raw in rawApplications) {
        if (raw is! Map<String, Object?>) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '退款历史记录结构无法识别',
          );
        }
        final RefundApplication application = _refundFromMap(
          raw,
          currency: LedgerCurrency.cashCny,
        );
        if (!seenRefundIds.add(application.id)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '多页退款历史包含重复的权威退款 ID',
          );
        }
        applications.add(application);
      }
      hasMore = metadata.current < metadata.pages;
      if (hasMore && rawApplications.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '退款历史分页为空但仍声明存在下一页',
        );
      }
      backendPage += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款历史超过客户端安全分页上限',
      );
    }
    return List<RefundApplication>.unmodifiable(applications);
  }

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) async {
    if (!amount.isFinite || amount <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '提现金额必须大于 0',
      );
    }
    final double scaledAmount = amount * 100;
    final int amountMinor = scaledAmount.round();
    if (amountMinor <= 0 || (scaledAmount - amountMinor).abs() > 0.000001) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '提现金额最多保留两位小数',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.withdrawalFeeRate,
      query: <String, String>{'amountMinor': '$amountMinor'},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final int requestedMinor = amountMinor;
    final int quotedMinor = _requiredInt(data, <String>[
      'amountMinor',
    ], field: '提现报价金额');
    if (quotedMinor != requestedMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现报价金额与请求金额不一致',
      );
    }
    const LedgerCurrency currency = LedgerCurrency.cashCny;
    _validateOptionalCurrency(data, currency, field: '提现报价币种');
    final int feeMinor = _requiredInt(data, <String>[
      'feeMinor',
    ], field: '提现手续费');
    final int netMinor = _requiredInt(data, <String>[
      'netAmountMinor',
    ], field: '提现到账金额');
    final int minimumMinor = _requiredInt(data, <String>[
      'minimumAmountMinor',
    ], field: '提现最低金额');
    final int basisPoints = _requiredInt(data, <String>[
      'feeRateBasisPoints',
    ], field: '提现费率');
    final String settlementMode = _requiredString(
      data,
      'settlementMode',
      field: '提现结算模式',
    );
    if (settlementMode != 'FIRST_PARTY_REVIEW_PROVIDER_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '提现结算模式未保持第一方人工审核与厂商关闭状态',
      );
    }
    if (feeMinor < 0 || netMinor < 0 || minimumMinor < 0 || basisPoints < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现报价金额或费率不能为负数',
      );
    }
    if (requestedMinor - feeMinor != netMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现报价手续费与到账金额不一致',
      );
    }
    final double rate = basisPoints / 10000;
    return WithdrawalQuote(
      quotedAmount: _minorToMajor(quotedMinor),
      feeAmount: _minorToMajor(feeMinor),
      receivedAmount: _minorToMajor(netMinor),
      feeRate: rate,
      feeRateText: '${(rate * 100).toStringAsFixed(2)}%',
      minimumAmount: _minorToMajor(minimumMinor),
      currency: currency,
    );
  }

  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    String? payoutAccountId,
  }) async {
    final int amountMinor = _validatedMinorAmount(amount, field: '提现金额');
    final String accountId = payoutAccountId?.trim() ?? '';
    if (accountId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '没有选中的有效收款账户，不能提交提现',
      );
    }
    final String intentKey =
        'withdrawal:${commerceRefundIntentDigest(scope: 'withdrawal-apply', fields: <String>['$amountMinor', accountId])}';
    final Future<WithdrawalRecord>? pending =
        _pendingWithdrawalApplications[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedWithdrawalRequestIds.putIfAbsent(
      intentKey,
      () => normalizeCommerceRefundRequestId(
        newCommerceRefundRequestId('flutter-commerce-withdrawal'),
      ),
    );
    final bool replayingRetainedWrite = _withdrawalWritesStarted.contains(
      intentKey,
    );
    late final Future<WithdrawalRecord> future;
    future =
        _applyWithdrawalOnce(
          amountMinor: amountMinor,
          payoutAccountId: accountId,
          requestId: requestId,
          intentKey: intentKey,
          replayingRetainedWrite: replayingRetainedWrite,
        ).then<WithdrawalRecord>(
          (WithdrawalRecord value) {
            if (identical(_pendingWithdrawalApplications[intentKey], future)) {
              _pendingWithdrawalApplications.remove(intentKey);
            }
            _retainedWithdrawalRequestIds.remove(intentKey);
            _withdrawalWritesStarted.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_pendingWithdrawalApplications[intentKey], future)) {
              _pendingWithdrawalApplications.remove(intentKey);
            }
            if (!_shouldRetainWithdrawalRequest(error)) {
              _retainedWithdrawalRequestIds.remove(intentKey);
              _withdrawalWritesStarted.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingWithdrawalApplications[intentKey] = future;
    return future;
  }

  Future<WithdrawalRecord> _applyWithdrawalOnce({
    required int amountMinor,
    required String payoutAccountId,
    required String requestId,
    required String intentKey,
    required bool replayingRetainedWrite,
  }) async {
    if (!replayingRetainedWrite) {
      final PayoutAccountSelection selection = await fetchPayoutAccounts();
      final PayoutAccount? account = _findPayoutAccount(
        selection.accounts,
        payoutAccountId,
      );
      if (account == null || !account.selectable) {
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: '选中的收款账户已失效，请刷新后重新选择',
        );
      }
    }
    _withdrawalWritesStarted.add(intentKey);
    final ApiResponse response = await _apiClient.post(
      _routes.withdrawalApply,
      headers: <String, String>{'X-Request-Id': requestId},
      body: <String, Object?>{
        'amountMinor': amountMinor,
        'payoutAccountId': payoutAccountId,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final bool providerInvocation = _requiredBool(data, 'providerInvocation');
    if (providerInvocation) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '提现厂商状态被阻断，不能当作已提交',
      );
    }
    final String payoutStatus = _requiredString(
      data,
      'payoutStatus',
      field: '提现打款状态',
    );
    if (payoutStatus != 'MANUAL_REVIEW_PENDING') {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '提现打款状态未保持人工审核等待状态',
      );
    }
    final String responsePayoutAccountId = _requiredString(
      data,
      'payoutAccountId',
      field: '提现收款账户 ID',
    );
    if (responsePayoutAccountId != payoutAccountId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现响应与选中的收款账户不一致',
      );
    }
    final int responseAmountMinor = _requiredInt(data, <String>[
      'amountMinor',
    ], field: '提现申请金额');
    if (responseAmountMinor != amountMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现响应与请求金额不一致',
      );
    }
    final int feeMinor = _requiredInt(data, <String>[
      'feeMinor',
    ], field: '提现申请手续费');
    final int netMinor = _requiredInt(data, <String>[
      'netAmountMinor',
    ], field: '提现申请到账金额');
    if (feeMinor < 0 || netMinor < 0 || amountMinor - feeMinor != netMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现申请金额不一致',
      );
    }
    final String status = _requiredString(
      data,
      'status',
      field: '提现申请状态',
    ).toUpperCase();
    if (status != 'SUBMITTED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现申请响应不是服务端已提交状态',
      );
    }
    final String withdrawalId = _requiredString(
      data,
      'withdrawalId',
      field: '提现申请 ID',
    );
    final DateTime submittedAt = _requiredDateTime(
      data,
      'submittedAt',
      field: '提现申请时间',
    );
    final String holderNameMasked = _requiredString(
      data,
      'holderNameMasked',
      field: '提现收款人脱敏姓名',
    );
    final String accountMasked = _requiredString(
      data,
      'accountMasked',
      field: '提现收款账户脱敏账号',
    );
    return WithdrawalRecord(
      id: withdrawalId,
      withdrawalNo: withdrawalId,
      amount: _minorToMajor(amountMinor),
      fee: _minorToMajor(feeMinor),
      receivedAmount: _minorToMajor(netMinor),
      status: _requiredWithdrawalStatus(status),
      statusText: _withdrawalStatusText(_requiredWithdrawalStatus(status)),
      createdAt: submittedAt,
      rejectedReason: _string(data['resultMessage']),
      payoutAccountId: responsePayoutAccountId,
      holderNameMasked: holderNameMasked,
      maskedCard: accountMasked,
      currency: LedgerCurrency.cashCny,
    );
  }

  @override
  Future<CommercePage<WithdrawalRecord>> fetchWithdrawalRecords({
    WithdrawalStatus? status,
    required int page,
    required int pageSize,
  }) async {
    _validatePageArguments(page: page, pageSize: pageSize);
    if (status == null) {
      return _fetchWithdrawalPage(page: page, pageSize: pageSize);
    }
    final List<WithdrawalRecord> matching = <WithdrawalRecord>[];
    final Set<String> seenWithdrawalIds = <String>{};
    _PageMetadata? expectedMetadata;
    int backendPage = 1;
    bool hasMore = true;
    while (hasMore && backendPage <= _maximumCommerceBackendPages) {
      final CommercePage<WithdrawalRecord> result = await _fetchWithdrawalPage(
        page: backendPage,
        pageSize: 100,
      );
      final _PageMetadata metadata = _PageMetadata(
        current: result.page,
        pageSize: result.pageSize,
        total: result.total,
        pages: result.total == 0
            ? 0
            : (result.total + result.pageSize - 1) ~/ result.pageSize,
      );
      expectedMetadata = _validateStablePageMetadata(
        expected: expectedMetadata,
        actual: metadata,
      );
      _validateWithdrawalPageProgress(result, requestedPage: backendPage);
      for (final WithdrawalRecord item in result.items) {
        if (!seenWithdrawalIds.add(item.id)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '多页提现记录包含重复的权威提现 ID',
          );
        }
      }
      matching.addAll(
        result.items.where((WithdrawalRecord item) => item.status == status),
      );
      hasMore = result.hasMore;
      backendPage += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录超过客户端安全分页上限',
      );
    }
    final int start = (page - 1) * pageSize;
    final int end = start + pageSize < matching.length
        ? start + pageSize
        : matching.length;
    final List<WithdrawalRecord> items = start >= matching.length
        ? const <WithdrawalRecord>[]
        : matching.sublist(start, end);
    return CommercePage<WithdrawalRecord>(
      items: items,
      page: page,
      pageSize: pageSize,
      total: matching.length,
      hasMore: end < matching.length,
    );
  }

  Future<CommercePage<WithdrawalRecord>> _fetchWithdrawalPage({
    required int page,
    required int pageSize,
  }) async {
    final Map<String, String> query = <String, String>{
      'pageNum': '$page',
      'pageSize': '$pageSize',
    };
    final ApiResponse response = await _apiClient.get(
      _routes.withdrawalRecords,
      query: query,
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<Object?> rawRecords = _requiredList(data, field: '提现记录列表');
    final _PageMetadata metadata = _requiredPageMetadata(
      data,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
    _validatePageItemCount(rawRecords, metadata, field: '提现记录');
    final List<WithdrawalRecord> records = <WithdrawalRecord>[
      for (final Object? raw in rawRecords)
        if (raw is! Map<String, Object?>)
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '提现记录结构无法识别',
          )
        else
          _withdrawalFromMap(raw, currency: LedgerCurrency.cashCny),
    ];
    return CommercePage<WithdrawalRecord>(
      items: records,
      page: metadata.current,
      pageSize: metadata.pageSize,
      total: metadata.total,
      hasMore: metadata.current < metadata.pages,
    );
  }

  @override
  Future<WithdrawalRecord> fetchWithdrawalRecord(String id) async {
    final String normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '提现记录 ID 不能为空',
      );
    }
    _PageMetadata? expectedMetadata;
    int backendPage = 1;
    bool hasMore = true;
    final Set<String> seenWithdrawalIds = <String>{};
    while (hasMore && backendPage <= _maximumCommerceBackendPages) {
      final CommercePage<WithdrawalRecord> page = await _fetchWithdrawalPage(
        page: backendPage,
        pageSize: 100,
      );
      final _PageMetadata metadata = _PageMetadata(
        current: page.page,
        pageSize: page.pageSize,
        total: page.total,
        pages: page.total == 0
            ? 0
            : (page.total + page.pageSize - 1) ~/ page.pageSize,
      );
      expectedMetadata = _validateStablePageMetadata(
        expected: expectedMetadata,
        actual: metadata,
      );
      _validateWithdrawalPageProgress(page, requestedPage: backendPage);
      for (final WithdrawalRecord record in page.items) {
        if (!seenWithdrawalIds.add(record.id)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '多页提现记录包含重复的权威提现 ID',
          );
        }
        if (record.id == normalizedId) {
          return record;
        }
      }
      hasMore = page.hasMore;
      backendPage += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录超过客户端安全分页上限',
      );
    }
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '提现记录不存在或不在当前可查询范围',
    );
  }

  static String _refundSubmissionIntentKey({
    required String orderNo,
    required String reason,
  }) {
    return 'refund:${commerceRefundIntentDigest(scope: 'refund-submit', fields: <String>[orderNo, reason])}';
  }

  static String _refundRetryIntentKey({required String refundId}) {
    return 'refund-retry:${commerceRefundIntentDigest(scope: 'refund-retry', fields: <String>[refundId])}';
  }

  static String? _optionalExpectedOrderNo(String? value) {
    final String? normalized = value?.trim();
    if (normalized != null && normalized.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '退款订单号不能为空',
      );
    }
    return normalized;
  }

  static RefundApplication _validateExpectedRefundOrder(
    RefundApplication application, {
    required String? expectedOrderNo,
  }) {
    if (expectedOrderNo != null && application.account != expectedOrderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果与选中订单不一致',
      );
    }
    return application;
  }

  static LedgerDirection? _ledgerDirection(Object? value) {
    return switch (_string(value).toUpperCase()) {
      'CREDIT' || 'RELEASE' => LedgerDirection.income,
      'DEBIT' || 'HOLD' => LedgerDirection.expense,
      _ => null,
    };
  }

  static LedgerKind _ledgerKind(String businessType) {
    return switch (businessType) {
      'GIFT_INCOME' => LedgerKind.giftIncome,
      'GIFT_SEND' => LedgerKind.giftExpense,
      'AGENT_INCOME' => LedgerKind.agentIncome,
      'SUPER_AGENT_INCOME' => LedgerKind.superAgentIncome,
      'RECHARGE' || 'RECHARGE_CREDIT' => LedgerKind.recharge,
      'REFUND' ||
      'REFUND_RESERVE' ||
      'REFUND_RETRY_RESERVE' => LedgerKind.refund,
      'WITHDRAWAL' || 'WITHDRAWAL_HOLD' => LedgerKind.withdrawal,
      _ => LedgerKind.other,
    };
  }

  static PaymentOrderStatus _paymentOrderStatus(Object? value) {
    return switch (_string(value).toUpperCase()) {
      'PENDING' || 'CREATED' => PaymentOrderStatus.pending,
      'CONFIRMING' || 'PROCESSING' => PaymentOrderStatus.confirming,
      'SUCCEEDED' || 'SUCCESS' || 'PAID' => PaymentOrderStatus.succeeded,
      'FAILED' || 'FAILURE' => PaymentOrderStatus.failed,
      'CANCELED' || 'CANCELLED' => PaymentOrderStatus.canceled,
      _ => PaymentOrderStatus.unknown,
    };
  }

  static PaymentOrderStatus _requiredPaymentOrderStatus(Object? value) {
    final PaymentOrderStatus status = _paymentOrderStatus(value);
    if (status == PaymentOrderStatus.unknown) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单响应缺少有效服务端状态',
      );
    }
    return status;
  }

  static PaymentOrder _paymentOrderFromMap(
    Map<String, Object?> raw, {
    required LedgerCurrency currency,
  }) {
    final String orderNo = _requiredString(raw, 'orderNo', field: '订单号');
    final double amount = _requiredDouble(raw, 'amount');
    final int giftCoinAmount = _requiredInt(raw, <String>[
      'ncoin',
      'giftCoinAmount',
    ], field: '订单礼物币金额');
    if (amount < 0 || giftCoinAmount < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单金额不能为负数',
      );
    }
    _validateOptionalCurrency(raw, currency, field: '订单币种');
    final DateTime createdAt = _requiredDateTime(
      raw,
      'createDate',
      field: '订单创建时间',
    );
    return PaymentOrder(
      orderNo: orderNo,
      amount: amount,
      giftCoinAmount: giftCoinAmount,
      channelName: _requiredString(raw, 'payType', field: '支付渠道'),
      createdAt: createdAt,
      status: _requiredPaymentOrderStatus(raw['status']),
      currency: currency,
    );
  }

  static RefundApplication _refundFromMap(
    Map<String, Object?> raw, {
    required LedgerCurrency currency,
    String? expectedRefundId,
    String? expectedOrderNo,
  }) {
    final String id = _requiredString(raw, 'refundId', field: '退款申请编号');
    final String orderNo = _requiredString(raw, 'orderNo', field: '退款订单号');
    if (expectedRefundId != null && id != expectedRefundId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果与请求退款申请不一致',
      );
    }
    if (expectedOrderNo != null && orderNo != expectedOrderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果与选中订单不一致',
      );
    }
    _validateOptionalCurrency(raw, currency, field: '退款币种');
    _requireVendorBlocked(raw, field: 'providerStatus', label: '退款结果');
    final int amountMinor = _requiredInt(raw, <String>[
      'amountMinor',
    ], field: '退款金额');
    if (amountMinor <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款金额必须大于 0',
      );
    }
    final String rawStatus = _requiredString(
      raw,
      'status',
      field: '退款状态',
    ).toUpperCase();
    final RefundStatus status = _requiredRefundStatus(rawStatus);
    final bool completed = _requiredBool(raw, 'completed');
    if (completed != (rawStatus == 'COMPLETED')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款结果 completed 与服务端状态矛盾',
      );
    }
    _requiredString(raw, 'reason', field: '退款申请原因');
    final String resultMessage = _string(raw['resultMessage']);
    if (status == RefundStatus.rejected && resultMessage.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '已拒绝退款缺少服务端拒绝原因',
      );
    }
    final DateTime submittedAt = _requiredDateTime(
      raw,
      'submittedAt',
      field: '退款提交时间',
    );
    return RefundApplication(
      id: id,
      account: orderNo,
      amount: _minorToMajor(amountMinor),
      status: status,
      statusText: _refundStatusText(status),
      rejectedReason: status == RefundStatus.rejected ? resultMessage : '',
      createdAt: submittedAt,
      currency: currency,
    );
  }

  static RefundStatus? _refundStatus(Object? value) {
    return switch (_string(value).toUpperCase()) {
      'APPROVED' || 'COMPLETED' => RefundStatus.approved,
      'REJECTED' => RefundStatus.rejected,
      'CANCELLED' || 'CANCELED' => RefundStatus.unavailable,
      'RESUBMITTED' => RefundStatus.resubmitted,
      'SUBMITTED' ||
      'PENDING' ||
      'PROCESSING' ||
      'REVIEWING' => RefundStatus.reviewing,
      _ => null,
    };
  }

  static RefundStatus _requiredRefundStatus(Object? value) {
    final RefundStatus? status = _refundStatus(value);
    if (status == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '退款响应缺少有效服务端状态',
      );
    }
    return status;
  }

  static String _refundEligibilityMessage(
    String reason, {
    required bool allowed,
  }) {
    if (allowed) {
      return '该充值订单可以提交退款申请；正式渠道退款仍等待厂商接入。';
    }
    return switch (reason.toUpperCase()) {
      'ACTIVE_REFUND_EXISTS' => '该订单已有退款申请正在处理。',
      'GIFT_COIN_ALREADY_CONSUMED' => '该订单对应礼物币已消费，当前不能退款。',
      _ => reason.isEmpty ? '该充值订单当前不能退款。' : reason,
    };
  }

  static WithdrawalRecord _withdrawalFromMap(
    Map<String, Object?> raw, {
    required LedgerCurrency currency,
  }) {
    final WithdrawalStatus status = _requiredWithdrawalStatus(raw['status']);
    final String id = _requiredString(raw, 'withdrawalId', field: '提现记录 ID');
    final String payoutAccountId = _requiredString(
      raw,
      'payoutAccountId',
      field: '提现收款账户 ID',
    );
    _validateOptionalCurrency(raw, currency, field: '提现记录币种');
    if (currency != LedgerCurrency.cashCny) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录币种不是 CASH_CNY',
      );
    }
    final int amountMinor = _requiredInt(raw, <String>[
      'amountMinor',
    ], field: '提现金额');
    final int feeMinor = _requiredInt(raw, <String>[
      'feeMinor',
    ], field: '提现手续费');
    final int netMinor = _requiredInt(raw, <String>[
      'netAmountMinor',
    ], field: '提现到账金额');
    if (amountMinor < 0 ||
        feeMinor < 0 ||
        netMinor < 0 ||
        amountMinor - feeMinor != netMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录金额不一致',
      );
    }
    return WithdrawalRecord(
      id: id,
      withdrawalNo: id,
      amount: _minorToMajor(amountMinor),
      fee: _minorToMajor(feeMinor),
      receivedAmount: _minorToMajor(netMinor),
      status: status,
      statusText: _withdrawalStatusText(status),
      createdAt: _requiredDateTime(raw, 'submittedAt', field: '提现提交时间'),
      rejectedReason: _string(raw['resultMessage']),
      payoutAccountId: payoutAccountId,
      holderNameMasked: _string(raw['holderNameMasked']),
      maskedCard: _string(raw['accountMasked']),
      currency: currency,
    );
  }

  static List<Object?> _requiredList(
    Map<String, Object?> data, {
    required String field,
  }) {
    List<Object?>? selected;
    for (final String key in <String>['records', 'list', 'items']) {
      if (!data.containsKey(key)) {
        continue;
      }
      final Object? value = data[key];
      if (value is! List) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field的 $key 不是有效列表',
        );
      }
      final List<Object?> candidate = List<Object?>.from(value);
      if (selected != null && !_deepEqual(selected, candidate)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field的多个列表别名内容不一致',
        );
      }
      selected = candidate;
    }
    if (selected != null) {
      return selected;
    }
    throw ApiException(kind: ApiFailureKind.protocol, message: '$field缺少服务端列表');
  }

  static _PageMetadata _requiredPageMetadata(
    Map<String, Object?> data, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final int current = _requiredAliasedInt(data, <String>[
      'pageNum',
      'current',
    ], field: '服务端当前页');
    final int pageSize = _requiredAliasedInt(data, <String>[
      'pageSize',
      'size',
    ], field: '服务端分页大小');
    final int total = _requiredAliasedInt(data, <String>[
      'total',
    ], field: '服务端总数');
    final int pages = _requiredAliasedInt(data, <String>[
      'pages',
      'totalPages',
    ], field: '服务端总页数');
    if (current < 1 || pageSize < 1 || total < 0 || pages < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '分页响应缺少有效服务端页码元数据',
      );
    }
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 current 或 pageSize 与请求不一致，页码未向前进展',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages ||
        (pages == 0 && current != 1) ||
        (pages > 0 && current > pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '分页响应的总数与页数不一致',
      );
    }
    return _PageMetadata(
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
  }

  static _PageMetadata _requiredOrderPageMetadata(
    Map<String, Object?> data, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final int current = _requiredAliasedInt(data, <String>[
      'pageNum',
      'current',
    ], field: '充值订单当前页');
    final int pageSize = _requiredAliasedInt(data, <String>[
      'pageSize',
      'size',
    ], field: '充值订单分页大小');
    final int total = _requiredAliasedInt(data, <String>[
      'total',
    ], field: '充值订单总数');
    if (current < 1 || pageSize < 1 || total < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单分页缺少有效服务端页码元数据',
      );
    }
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单分页 current 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    final int? reportedPages = _optionalAliasedInt(data, <String>[
      'pages',
      'totalPages',
    ], field: '充值订单总页数');
    final int pages = reportedPages ?? expectedPages;
    if (pages < 0 || pages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单分页的 pages 与 total 不一致',
      );
    }
    if ((pages == 0 && current != 1) || (pages > 0 && current > pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单分页当前页超过服务端页数',
      );
    }
    return _PageMetadata(
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
  }

  static void _validateWithdrawalPageProgress(
    CommercePage<WithdrawalRecord> page, {
    required int requestedPage,
  }) {
    if (!page.hasMore) {
      return;
    }
    if (page.items.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录分页响应为空但仍声明存在下一页',
      );
    }
    if (page.page != requestedPage) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录分页 current 与请求页不一致',
      );
    }
  }

  static _PageMetadata _validateStablePageMetadata({
    required _PageMetadata? expected,
    required _PageMetadata actual,
  }) {
    if (expected == null) {
      return actual;
    }
    if (expected.pageSize != actual.pageSize ||
        expected.total != actual.total ||
        expected.pages != actual.pages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页元数据在请求间发生变化',
      );
    }
    return expected;
  }

  static void _validatePageItemCount(
    List<Object?> items,
    _PageMetadata metadata, {
    required String field,
  }) {
    if (items.length > metadata.pageSize) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field分页记录数超过服务端 pageSize',
      );
    }
    if (metadata.pages == 0 && items.isNotEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field空分页包含记录',
      );
    }
    if (metadata.total == 0) {
      if (items.isNotEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field分页总数为零但包含记录',
        );
      }
      return;
    }
    if (items.isEmpty && metadata.current < metadata.pages) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field分页响应为空但仍声明存在下一页',
      );
    }
    final int expectedCount = metadata.current < metadata.pages
        ? metadata.pageSize
        : metadata.total - (metadata.pages - 1) * metadata.pageSize;
    if (expectedCount <= 0 ||
        expectedCount > metadata.pageSize ||
        items.length != expectedCount) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field分页记录数与服务端 total/pageSize/pages 不一致',
      );
    }
  }

  static void _validatePageArguments({
    required int page,
    required int pageSize,
  }) {
    if (page < 1 || pageSize < 1) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '分页页码和 pageSize 必须大于 0',
      );
    }
    if (page > _maximumCommerceBackendPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页超过客户端安全上限',
      );
    }
  }

  static String _refundStatusText(RefundStatus status) => switch (status) {
    RefundStatus.reviewing => '审核中',
    RefundStatus.approved => '已通过',
    RefundStatus.rejected => '已拒绝',
    RefundStatus.resubmitted => '已重新提交',
    RefundStatus.unavailable => '不可用',
  };

  static WithdrawalStatus? _withdrawalStatus(Object? value) =>
      switch (_string(value).toUpperCase()) {
        'PENDING' || 'CREATED' || 'SUBMITTED' => WithdrawalStatus.pending,
        'APPROVED' => WithdrawalStatus.approved,
        'REJECTED' || 'CANCELLED' || 'CANCELED' => WithdrawalStatus.rejected,
        'PAYING' || 'PROCESSING' => WithdrawalStatus.paying,
        'SETTLED' || 'SUCCEEDED' => WithdrawalStatus.succeeded,
        'FAILED' => WithdrawalStatus.failed,
        _ => null,
      };

  static WithdrawalStatus _requiredWithdrawalStatus(Object? value) {
    final WithdrawalStatus? status = _withdrawalStatus(value);
    if (status == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '提现记录缺少有效服务端状态',
      );
    }
    return status;
  }

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

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static int _requiredAliasedInt(
    Map<String, Object?> data,
    List<String> keys, {
    required String field,
  }) {
    final int? value = _optionalAliasedInt(data, keys, field: field);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端整数',
      );
    }
    return value;
  }

  static int? _optionalAliasedInt(
    Map<String, Object?> data,
    List<String> keys, {
    required String field,
  }) {
    int? selected;
    for (final String key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }
      final int? value = _asInt(data[key]);
      if (value == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field的 $key 不是有效服务端整数',
        );
      }
      if (selected != null && selected != value) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field的多个分页别名不一致',
        );
      }
      selected = value;
    }
    return selected;
  }

  static bool _deepEqual(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (int index = 0; index < left.length; index += 1) {
        if (!_deepEqual(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is num && right is num) {
      return left == right;
    }
    return left == right;
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static double _minorToMajor(int value) => value / 100;

  static int _requiredInt(
    Map<String, Object?> data,
    List<String> keys, {
    required String field,
  }) {
    for (final String key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }
      final int? value = _asInt(data[key]);
      if (value != null) {
        return value;
      }
      break;
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '$field缺少有效服务端整数',
    );
  }

  static int _requiredNonNegativeInt(
    Map<String, Object?> data,
    List<String> keys, {
    required String field,
  }) {
    final int value = _requiredInt(data, keys, field: field);
    if (value < 0) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field不能为负数');
    }
    return value;
  }

  static int _requiredNonNegativeIntField(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) => _requiredNonNegativeInt(data, <String>[key], field: field);

  static String _requiredAliasedString(
    Map<String, Object?> data,
    List<String> keys, {
    required String field,
  }) {
    String? resolved;
    for (final String key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }
      final String value = _string(data[key]);
      if (value.isEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field的 $key 不是有效字符串',
        );
      }
      if (resolved != null && resolved != value) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field别名值不一致',
        );
      }
      resolved ??= value;
    }
    if (resolved == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端字符串',
      );
    }
    return resolved;
  }

  static PayoutAccountStatus _payoutAccountStatus(String value) =>
      switch (value) {
        'VERIFIED' || 'ACTIVE' => PayoutAccountStatus.verified,
        'PENDING' || 'REVIEWING' => PayoutAccountStatus.pending,
        'DISABLED' || 'REVOKED' => PayoutAccountStatus.disabled,
        _ => PayoutAccountStatus.unknown,
      };

  static PayoutAccount? _findPayoutAccount(
    Iterable<PayoutAccount> accounts,
    String accountId,
  ) {
    for (final PayoutAccount account in accounts) {
      if (account.payoutAccountId == accountId) {
        return account;
      }
    }
    return null;
  }

  static String? _optionalTrimmedString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final DateTime? parsed = _asDateTime(value);
    if (parsed == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收款账户时间不是有效服务端时间',
      );
    }
    return parsed;
  }

  static int _validatedMinorAmount(double amount, {required String field}) {
    if (!amount.isFinite || amount <= 0) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '$field必须大于 0',
      );
    }
    final double scaled = amount * 100;
    final int minor = scaled.round();
    if (minor <= 0 || (scaled - minor).abs() > 0.000001) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '$field最多保留两位小数',
      );
    }
    return minor;
  }

  static bool _shouldRetainWithdrawalRequest(Object error) {
    if (error is! ApiException) {
      return true;
    }
    if (error.code == 40901 || error.code == 40902) {
      return true;
    }
    if (error.code == 40903 || error.kind == ApiFailureKind.conflict) {
      return false;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      _ => false,
    };
  }

  static double _requiredDouble(Map<String, Object?> data, String key) {
    final double? value = _asDouble(data[key]);
    if (!data.containsKey(key) || value == null || !value.isFinite) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$key缺少有效服务端金额',
      );
    }
    return value;
  }

  static double _requiredNonNegativeDouble(
    Map<String, Object?> data,
    String key,
  ) {
    final double value = _requiredDouble(data, key);
    if (value < 0) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$key不能为负数');
    }
    return value;
  }

  static bool _requiredBool(Map<String, Object?> data, String key) {
    if (!data.containsKey(key)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$key缺少服务端布尔值',
      );
    }
    final bool? value = _asNullableBool(data[key]);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$key不是有效服务端布尔值',
      );
    }
    return value;
  }

  static void _requireVendorBlocked(
    Map<String, Object?> data, {
    required String field,
    required String label,
  }) {
    final Object? raw = data[field];
    if (raw is! String || raw.trim().toUpperCase() != 'VENDOR_BLOCKED') {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label缺少正式厂商失败关闭状态',
      );
    }
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final String value = _string(data[key]);
    if (!data.containsKey(key) || value.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端字符串',
      );
    }
    return value;
  }

  static DateTime _requiredDateTime(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final DateTime? value = _asDateTime(data[key]);
    if (!data.containsKey(key) || value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端时间',
      );
    }
    return value;
  }

  static LedgerCurrency _requiredCurrency(
    Map<String, Object?> data, {
    required String field,
  }) {
    final String value = _string(
      data['currency'] ?? data['currencyCode'] ?? data['currencyType'],
    ).toUpperCase();
    return switch (value) {
      'GIFT_COIN' || 'GIFTCOIN' || 'NCOIN' => LedgerCurrency.giftCoin,
      'CASH_CNY' || 'CNY' || 'CASH' => LedgerCurrency.cashCny,
      _ => throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端币种',
      ),
    };
  }

  static void _validateOptionalCurrency(
    Map<String, Object?> data,
    LedgerCurrency expected, {
    required String field,
  }) {
    final bool present =
        data.containsKey('currency') ||
        data.containsKey('currencyCode') ||
        data.containsKey('currencyType');
    if (!present) {
      return;
    }
    final LedgerCurrency actual = _requiredCurrency(data, field: field);
    if (actual != expected) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field与服务端接口币种不一致',
      );
    }
  }

  static bool? _asNullableBool(Object? value) {
    if (value is bool) return value;
    if (value is num && (value == 0 || value == 1)) return value == 1;
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    if (<String>{'true', '1', 'yes'}.contains(normalized)) return true;
    if (<String>{'false', '0', 'no'}.contains(normalized)) return false;
    return null;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      } on RangeError {
        return null;
      }
    }
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

class _PageMetadata {
  const _PageMetadata({
    required this.current,
    required this.pageSize,
    required this.total,
    required this.pages,
  });

  final int current;
  final int pageSize;
  final int total;
  final int pages;
}
