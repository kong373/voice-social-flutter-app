import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/decoration_purchase_request_id.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/alipay_request_id.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

class BackendCommerceCatalogRepository implements CommerceCatalogRepository {
  BackendCommerceCatalogRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    String Function()? decorationPurchaseRequestIdGenerator,
    String Function()? alipayCreateRequestIdGenerator,
    AlipayAppPayAdapter? alipayAppPayAdapter,
  }) : _apiClient = apiClient,
       _routes = routes,
       _decorationPurchaseRequestIdGenerator =
           decorationPurchaseRequestIdGenerator ??
           newDecorationPurchaseRequestId,
       _alipayCreateRequestIdGenerator =
           alipayCreateRequestIdGenerator ?? newAlipayCreateRequestId,
       _alipayAppPayAdapter =
           alipayAppPayAdapter ?? const DisabledAlipayAppPayAdapter();

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final String Function() _decorationPurchaseRequestIdGenerator;
  final String Function() _alipayCreateRequestIdGenerator;
  final AlipayAppPayAdapter _alipayAppPayAdapter;
  final Map<String, Future<DecorationItem>> _pendingDecorationPurchases =
      <String, Future<DecorationItem>>{};
  final Map<String, Future<DecorationItem>> _pendingDecorationEquips =
      <String, Future<DecorationItem>>{};
  final Map<String, Future<void>> _decorationMutationTails =
      <String, Future<void>>{};
  final Map<String, String> _decorationPurchaseRequestIds = <String, String>{};
  final Map<String, String> _decorationEquipRequestIds = <String, String>{};
  final Map<String, Future<RechargeOrder>> _pendingAlipayOrderCreations =
      <String, Future<RechargeOrder>>{};
  final Map<String, String> _alipayCreateRequestIds = <String, String>{};
  // The native bridge is only one half of the payment boundary.  Keep the
  // server's catalog readiness separately so a local SDK cannot enable order
  // creation while the authenticated backend port is fail-closed.
  bool _serverOrderCreationReady = false;

  @override
  bool get supportsRechargeCatalog => true;

  @override
  bool get supportsPaymentChannelInvocation =>
      _serverOrderCreationReady && _alipayAppPayAdapter.isAvailable;

  @override
  List<PaymentChannelType> availableChannels(ClientStorePlatform platform) =>
      !supportsPaymentChannelInvocation
      ? const <PaymentChannelType>[]
      : platform == ClientStorePlatform.ios
      ? const <PaymentChannelType>[PaymentChannelType.appleIap]
      : _alipayAppPayAdapter.isAvailable
      ? const <PaymentChannelType>[PaymentChannelType.alipay]
      : const <PaymentChannelType>[];

  @override
  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  }) async {
    // A refresh that is in flight must not leave an earlier READY result
    // usable if the server later reports a blocked or malformed contract.
    _serverOrderCreationReady = false;
    final String expectedPlatform = platform == ClientStorePlatform.android
        ? 'ANDROID'
        : 'IOS';
    final ApiResponse response = await _apiClient.get(
      _routes.rechargeProducts,
      query: <String, String>{'platform': expectedPlatform},
    );
    final List<Map<String, Object?>> items = _catalogList(
      response.data,
      label: '充值商品目录',
    );
    final Map<String, Object?> envelope =
        response.data! as Map<String, Object?>;
    final String orderCreationStatus = _string(
      envelope['orderCreationStatus'],
    ).toUpperCase();
    final bool validOrderCreationStatus =
        orderCreationStatus == 'READY' ||
        orderCreationStatus == 'VENDOR_BLOCKED';
    // The catalog endpoint is the server authority.  Local SDK availability
    // is intentionally not folded into this protocol check; it is intersected
    // by supportsPaymentChannelInvocation after the response is accepted.
    if (_string(envelope['platform']).toUpperCase() != expectedPlatform ||
        !validOrderCreationStatus ||
        (expectedPlatform != 'ANDROID' && orderCreationStatus == 'READY')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值商品目录平台或支付可用状态与请求不一致',
      );
    }
    _serverOrderCreationReady =
        expectedPlatform == 'ANDROID' && orderCreationStatus == 'READY';
    return items.map(_rechargeProductFromMap).toList(growable: false);
  }

  @override
  Future<RechargeEligibility> checkRechargeEligibility({
    required bool youthModeEnabled,
  }) async {
    if (youthModeEnabled) {
      return const RechargeEligibility(
        allowed: false,
        message: '青少年模式已开启，暂不能创建新的充值订单',
      );
    }
    return supportsPaymentChannelInvocation
        ? const RechargeEligibility(allowed: true, message: '')
        : const RechargeEligibility(
            allowed: false,
            message: '正式支付渠道尚未接入，当前只能查看充值商品，不能创建或支付订单',
          );
  }

  @override
  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  }) async {
    if (platform != ClientStorePlatform.android ||
        channel != PaymentChannelType.alipay ||
        !supportsPaymentChannelInvocation) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '支付宝支付尚未配置或当前平台不可用',
      );
    }
    if (!_isValidAlipayProduct(product)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值商品无效，请刷新商品目录后重试',
      );
    }
    if (account.isEmpty || account.trim() != account) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值账号无效，请重新登录后重试',
      );
    }
    if (youthModeEnabled) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '青少年模式已开启，暂不能创建新的充值订单',
      );
    }
    final String intentKey = _alipayCreateIntentKey(
      account: account,
      productId: product.id,
      platform: platform,
    );
    final Future<RechargeOrder>? pending =
        _pendingAlipayOrderCreations[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _alipayCreateRequestIds.putIfAbsent(
      intentKey,
      _alipayCreateRequestIdGenerator,
    );
    late final Future<RechargeOrder> operation;
    operation = _createAlipayRechargeOrder(
      intentKey: intentKey,
      requestId: requestId,
      account: account,
      product: product,
    );
    late final Future<RechargeOrder> retainedOperation;
    retainedOperation = operation.whenComplete(() {
      if (identical(
        _pendingAlipayOrderCreations[intentKey],
        retainedOperation,
      )) {
        _pendingAlipayOrderCreations.remove(intentKey);
      }
    });
    _pendingAlipayOrderCreations[intentKey] = retainedOperation;
    return retainedOperation;
  }

  Future<RechargeOrder> _createAlipayRechargeOrder({
    required String intentKey,
    required String requestId,
    required String account,
    required RechargeProduct product,
  }) async {
    try {
      final ApiResponse response = await _apiClient.post(
        _routes.createAlipayRechargeOrder,
        headers: <String, String>{'X-Request-Id': requestId},
        body: <String, Object?>{
          // The backend must bind account to the authenticated principal. It
          // is included for the legacy contract, never used as an authority
          // by the client.
          'account': account,
          'productId': product.id,
          'channel': 'ALIPAY',
          'platform': 'ANDROID',
        },
      );
      final RechargeOrder order = _alipayRechargeOrderFromResponse(
        response.data,
        account: account,
        product: product,
      );
      // A valid server response closes this logical creation intent. An
      // ambiguous failure deliberately retains the key for a later retry.
      if (_alipayCreateRequestIds[intentKey] == requestId) {
        _alipayCreateRequestIds.remove(intentKey);
      }
      return order;
    } catch (error) {
      if (!_shouldRetainAlipayCreateRequestId(error) &&
          _alipayCreateRequestIds[intentKey] == requestId) {
        _alipayCreateRequestIds.remove(intentKey);
      }
      rethrow;
    }
  }

  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async {
    if (order.channel != PaymentChannelType.alipay ||
        !supportsPaymentChannelInvocation) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '支付宝支付尚未配置或当前平台不可用',
      );
    }
    final String? orderString = order.paymentOrderString;
    if (orderString == null || orderString.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回有效的支付宝支付串',
      );
    }
    final AlipayAppPayResult result = await _alipayAppPayAdapter.pay(
      orderNo: order.orderNo,
      orderString: orderString,
    );
    // Every native outcome remains a provisional UI status.  Even 9000 is
    // followed by queryRechargeOrder, which is the only authority allowed to
    // report a successful recharge.
    final String message = switch (result.outcome) {
      AlipayAppPayOutcome.sdkCompleted => '支付宝已返回完成，正在等待服务端确认',
      AlipayAppPayOutcome.processing => '支付宝处理中，正在等待服务端确认',
      AlipayAppPayOutcome.userCanceled => '已取消支付宝页面，订单状态仍需服务端核验',
      AlipayAppPayOutcome.networkError => '支付宝网络状态不确定，订单状态仍需服务端核验',
      AlipayAppPayOutcome.failed => '支付宝返回失败，订单状态仍需服务端核验',
      AlipayAppPayOutcome.unavailable => '支付宝支付当前不可用，订单状态仍需服务端核验',
    };
    final RechargeOrder provisional = order.copyWith(
      state: RechargeOrderState.confirming,
      message: message,
      nativeSdkCompleted: result.sdkCompleted,
      nativeResultStatus: result.resultStatus,
    );
    // A native result is never authoritative.  Reconciliation is an explicit
    // authenticated write path, while the following GET is a DB-only
    // projection.  The recovery method also runs from the result page, so an
    // app killed between PayTask and this call can still recover the order.
    try {
      return await queryRechargeOrder(provisional);
    } catch (_) {
      return provisional;
    }
  }

  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) async {
    if (order.channel == PaymentChannelType.alipay &&
        !_isTerminalAlipayOrderState(order.state)) {
      // Best effort: the read below remains mandatory even if provider
      // reconciliation is unavailable. This keeps the DB projection the only
      // source of final payment authority and makes manual refresh recoverable.
      try {
        await _reconcileAlipayRechargeOrder(order);
      } catch (_) {
        // Continue to the read-only status endpoint.
      }
    }
    final String statusRoute = order.channel == PaymentChannelType.alipay
        ? _routes.alipayRechargeOrderStatus
        : _routes.rechargeOrderStatus;
    final ApiResponse response = await _apiClient.get(
      statusRoute,
      query: <String, String>{'orderNo': order.orderNo},
    );
    final Object? raw = response.data;
    if (raw is! Map<String, Object?> || raw.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单状态响应不是有效对象',
      );
    }
    final Map<String, Object?> data = raw;
    if (_requiredString(data, 'orderNo', '充值订单状态') != order.orderNo) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单状态响应与请求订单不一致',
      );
    }
    final String status = _requiredString(
      data,
      'status',
      '充值订单状态',
    ).toUpperCase();
    final RechargeOrderState state = switch (status) {
      'CONFIRMING' => RechargeOrderState.confirming,
      'SUCCEEDED' => RechargeOrderState.succeeded,
      'FAILED' => RechargeOrderState.failed,
      'CANCELLED' => RechargeOrderState.canceled,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单状态响应包含未知状态',
      ),
    };
    final Object? rawSucceeded = data['bool'];
    if (rawSucceeded is! bool ||
        rawSucceeded != (state == RechargeOrderState.succeeded)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单状态响应中的到账字段与状态矛盾',
      );
    }
    return order.copyWith(
      state: state,
      message: state == RechargeOrderState.succeeded
          ? '服务端已确认到账'
          : state == RechargeOrderState.failed
          ? '服务端确认订单失败'
          : state == RechargeOrderState.canceled
          ? '订单已取消'
          : '服务端仍在确认订单',
    );
  }

  Future<void> _reconcileAlipayRechargeOrder(RechargeOrder order) async {
    final String requestId = _alipayReconcileRequestId(order.orderNo);
    await _apiClient.post(
      _routes.reconcileAlipayRechargeOrder,
      query: <String, String>{'orderNo': order.orderNo},
      headers: <String, String>{'X-Request-Id': requestId},
    );
  }

  static bool _isTerminalAlipayOrderState(RechargeOrderState state) =>
      switch (state) {
        RechargeOrderState.succeeded ||
        RechargeOrderState.failed ||
        RechargeOrderState.canceled ||
        RechargeOrderState.unavailable => true,
        RechargeOrderState.created ||
        RechargeOrderState.invoking ||
        RechargeOrderState.confirming => false,
      };

  /// Stable for one first-party order, so retries of an uncertain native
  /// outcome share the backend's idempotency boundary without exposing the
  /// signed order string or any credential.
  static String _alipayReconcileRequestId(String orderNo) {
    final String digest = sha256
        .convert(utf8.encode('voice-social:alipay-reconcile:$orderNo'))
        .toString();
    return 'alipay-reconcile-$digest';
  }

  static String _alipayCreateIntentKey({
    required String account,
    required String productId,
    required ClientStorePlatform platform,
  }) {
    final String canonical = <String>[
      'voice-social:alipay-create',
      account.length.toString(),
      account,
      productId.length.toString(),
      productId,
      platform.name,
    ].join(':');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static bool _shouldRetainAlipayCreateRequestId(Object error) {
    if (error is! ApiException) {
      return true;
    }
    if (error.kind == ApiFailureKind.conflict) {
      return error.code != 40903;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.configuration ||
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden ||
      ApiFailureKind.validation ||
      ApiFailureKind.business => false,
      ApiFailureKind.conflict => false,
    };
  }

  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() async {
    final ApiResponse response = await _apiClient.get(
      _routes.normalGiftCatalog,
    );
    final List<Map<String, Object?>> items = _catalogList(
      response.data,
      label: '礼物目录',
      requireRetiredCategoriesFlag: true,
    );
    return items.map(_giftFromMap).toList(growable: false);
  }

  @override
  Future<List<DecorationItem>> fetchDecorations() async {
    final ApiResponse response = await _apiClient.get(_routes.userDecorations);
    final List<Map<String, Object?>> items = _catalogList(
      response.data,
      label: '装扮目录',
    );
    return items.map(_decorationFromMap).toList(growable: false);
  }

  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) async {
    final String normalizedId = decorationId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效装扮商品',
      );
    }
    return _singleFlight(_pendingDecorationPurchases, normalizedId, () async {
      return _serializeDecorationMutation(normalizedId, () async {
        final String requestId = _decorationPurchaseRequestIds.putIfAbsent(
          normalizedId,
          _newDecorationPurchaseRequestId,
        );
        try {
          final ApiResponse response = await _apiClient.post(
            _routes.purchaseMallGoods,
            headers: <String, String>{'X-Request-Id': requestId},
            body: <String, Object?>{'decorationId': normalizedId},
          );
          _validateDecorationPurchaseResponse(
            response.data,
            decorationId: normalizedId,
          );
          final DecorationItem item = await _findPurchasedDecoration(
            normalizedId,
            missingMessage: '购买成功后未查询到对应装扮',
          );
          _decorationPurchaseRequestIds.remove(normalizedId);
          return item;
        } catch (error) {
          if (error is _DecorationAuthorityException) {
            _decorationPurchaseRequestIds.remove(normalizedId);
            rethrow;
          }
          final DecorationItem? reconciled =
              await _reconcilePurchasedDecoration(
                normalizedId,
                requestId: requestId,
                error: error,
              );
          if (reconciled != null) {
            _decorationPurchaseRequestIds.remove(normalizedId);
            return reconciled;
          }
          if (!shouldRetainDecorationPurchaseRequest(error)) {
            _decorationPurchaseRequestIds.remove(normalizedId);
          }
          rethrow;
        }
      });
    });
  }

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) async {
    final String normalizedId = decorationId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效装扮',
      );
    }
    return _singleFlight(
      _pendingDecorationEquips,
      '$normalizedId:$equipped',
      () async {
        return _serializeDecorationMutation(normalizedId, () async {
          final String intent = '$normalizedId:$equipped';
          final String requestId = _decorationEquipRequestIds.putIfAbsent(
            intent,
            _decorationPurchaseRequestIdGenerator,
          );
          try {
            final ApiResponse response = await _apiClient.post(
              _routes.equipUserDecoration,
              headers: <String, String>{
                'X-Request-Id': normalizeDecorationPurchaseRequestId(requestId),
              },
              body: <String, Object?>{
                'decorationId': normalizedId,
                'equipped': equipped,
              },
            );
            _validateDecorationEquipResponse(
              response.data,
              decorationId: normalizedId,
              equipped: equipped,
            );
            final DecorationItem result = await _findDecoration(
              normalizedId,
              missingMessage: '装扮状态已更新，但服务端未返回对应记录',
              expectedEquipped: equipped,
            );
            _decorationEquipRequestIds.remove(intent);
            return result;
          } catch (error) {
            if (error is _DecorationAuthorityException) {
              _decorationEquipRequestIds.remove(intent);
              rethrow;
            }
            if (!shouldRetainDecorationPurchaseRequest(error)) {
              _decorationEquipRequestIds.remove(intent);
            }
            rethrow;
          }
        });
      },
    );
  }

  Future<T> _serializeDecorationMutation<T>(
    String decorationId,
    Future<T> Function() operation,
  ) {
    final Future<void> previous =
        _decorationMutationTails[decorationId] ?? Future<void>.value();
    final Future<void> ready = previous.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    final Future<T> result = ready.then<T>((_) => operation());
    late final Future<void> tail;
    tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          if (identical(_decorationMutationTails[decorationId], tail)) {
            _decorationMutationTails.remove(decorationId);
          }
        });
    _decorationMutationTails[decorationId] = tail;
    return result;
  }

  Future<DecorationItem> _findDecoration(
    String decorationId, {
    required String missingMessage,
    bool? expectedEquipped,
  }) async {
    final List<DecorationItem> decorations = await fetchDecorations();
    DecorationItem? match;
    for (final DecorationItem item in decorations) {
      if (item.id == decorationId) {
        if (match != null) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '装扮目录包含重复的目标记录',
          );
        }
        match = item;
      }
    }
    if (match == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: missingMessage,
      );
    }
    if (expectedEquipped != null && match.equipped != expectedEquipped) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '装扮状态更新后服务端权威状态与请求不一致',
      );
    }
    return match;
  }

  Future<DecorationItem> _findPurchasedDecoration(
    String decorationId, {
    required String missingMessage,
  }) async {
    final DecorationItem item = await _findDecoration(
      decorationId,
      missingMessage: missingMessage,
    );
    if (!item.owned) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '装扮购买后服务端仍返回未拥有状态',
      );
    }
    return item;
  }

  Future<DecorationItem?> _reconcilePurchasedDecoration(
    String decorationId, {
    required String requestId,
    required Object error,
  }) async {
    if (!shouldRetainDecorationPurchaseRequest(error)) {
      return null;
    }
    try {
      final ApiResponse response = await _apiClient.get(
        _routes.userDecorations,
      );
      final Object? raw = response.data;
      if (raw is! Map<String, Object?>) {
        return null;
      }
      final Map<String, Object?> envelope = raw;
      final List<Map<String, Object?>> records = _catalogList(
        raw,
        label: '装扮目录',
      );
      final bool envelopeEvidence = _requestIdMatches(
        envelope,
        requestId,
        keys: const <String>[
          'requestId',
          'purchaseRequestId',
          'idempotencyKey',
          'idempotencyRequestId',
          'lastPurchaseRequestId',
          'lastMutationRequestId',
        ],
      );
      DecorationItem? reconciled;
      for (final Map<String, Object?> record in records) {
        if (_string(record['decorationId']) != decorationId ||
            record['owned'] != true) {
          continue;
        }
        final bool itemEvidence = _requestIdMatches(
          record,
          requestId,
          keys: const <String>[
            'requestId',
            'purchaseRequestId',
            'idempotencyKey',
            'idempotencyRequestId',
            'lastPurchaseRequestId',
            'lastMutationRequestId',
          ],
        );
        if (itemEvidence || envelopeEvidence) {
          if (reconciled != null) {
            throw const ApiException(
              kind: ApiFailureKind.protocol,
              message: '装扮目录包含重复的对账目标记录',
            );
          }
          reconciled = _decorationFromMap(record);
        }
      }
      return reconciled;
    } on ApiException {
      // Keep the original write failure so the caller can retry with the same
      // idempotency key instead of masking it with a fetch error.
    }
    return null;
  }

  String _newDecorationPurchaseRequestId() {
    return normalizeDecorationPurchaseRequestId(
      _decorationPurchaseRequestIdGenerator(),
    );
  }

  static Future<T> _singleFlight<T>(
    Map<String, Future<T>> pending,
    String key,
    Future<T> Function() operation,
  ) {
    final Future<T>? existing = pending[key];
    if (existing != null) {
      return existing;
    }
    late final Future<T> future;
    future = operation().whenComplete(() {
      if (identical(pending[key], future)) {
        pending.remove(key);
      }
    });
    pending[key] = future;
    return future;
  }

  static RechargeProduct _rechargeProductFromMap(Map<String, Object?> item) {
    final String id = _string(item['productId']);
    final String title = _string(item['title']);
    final int? amountMinor = _asInt(item['amountMinor']);
    final double? amount = _asDouble(item['amount']);
    final int? giftCoins = _asInt(item['giftCoinAmount']);
    final int? bonusGiftCoins = _asInt(item['bonusGiftCoin']);
    if (!_isUuid(id) ||
        title.isEmpty ||
        amountMinor == null ||
        amountMinor <= 0 ||
        amount == null ||
        (amount - (amountMinor / 100)).abs() > 0.000001 ||
        giftCoins == null ||
        giftCoins <= 0 ||
        bonusGiftCoins == null ||
        bonusGiftCoins < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值商品目录包含无效的金额或商品数据',
      );
    }
    return RechargeProduct(
      id: id,
      giftCoins: giftCoins,
      priceCny: amount,
      bonusGiftCoins: bonusGiftCoins,
      label: title,
      enabled: true,
    );
  }

  static bool _isValidAlipayProduct(RechargeProduct product) {
    if (!product.enabled ||
        product.id.isEmpty ||
        product.id.trim() != product.id ||
        product.id.codeUnits.any(
          (int codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
        ) ||
        product.giftCoins <= 0 ||
        product.bonusGiftCoins < 0 ||
        product.totalGiftCoins <= 0 ||
        !product.priceCny.isFinite ||
        product.priceCny <= 0) {
      return false;
    }
    final double amountMinor = product.priceCny * 100;
    return amountMinor.isFinite && amountMinor > 0 && amountMinor.round() > 0;
  }

  static RechargeOrder _alipayRechargeOrderFromResponse(
    Object? value, {
    required String account,
    required RechargeProduct product,
  }) {
    if (value is! Map<String, Object?> || value.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝下单响应不是有效对象',
      );
    }
    final String orderNo = _requiredString(value, 'orderNo', '支付宝下单');
    final String? orderString = _strictOptionalString(
      value['orderStr'] ?? value['orderString'] ?? value['orderInfo'],
    );
    if (orderString == null ||
        orderString.length > 64 * 1024 ||
        orderString.trim() != orderString ||
        orderString.codeUnits.any(
          (int codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
        )) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝下单响应缺少有效支付串',
      );
    }
    final String? responseProductId = _strictOptionalString(
      value['productId'] ?? value['rechargeProductId'],
    );
    final int? responseAmountMinor = _strictInt(value['amountMinor']);
    final int? responseGiftCoinAmount = _strictInt(
      value['giftCoinAmount'] ?? value['ncoin'],
    );
    final int expectedAmountMinor = (product.priceCny * 100).round();
    if (responseProductId == null || responseProductId != product.id) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单商品与请求不一致',
      );
    }
    if (responseAmountMinor == null ||
        responseAmountMinor != expectedAmountMinor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单金额与请求商品不一致',
      );
    }
    if (responseGiftCoinAmount == null ||
        responseGiftCoinAmount != product.totalGiftCoins) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单礼物币数量与请求商品不一致',
      );
    }
    final String? responseChannel = _optionalString(
      value['channel'] ?? value['channelName'] ?? value['payType'],
    );
    if (responseChannel != null &&
        !const <String>{
          'ALIPAY',
          '支付宝',
          'ALIPAY_APP',
        }.contains(responseChannel.toUpperCase())) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单支付方式与请求不一致',
      );
    }
    final String? responsePlatform = _optionalString(value['platform']);
    if (responsePlatform != null &&
        !const <String>{
          'ANDROID',
          'ANDROID_APP',
        }.contains(responsePlatform.toUpperCase())) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单平台与请求不一致',
      );
    }
    final String status = _string(
      value['status'],
      fallback: 'CREATED',
    ).toUpperCase();
    if (!const <String>{'CREATED', 'PENDING', 'CONFIRMING'}.contains(status)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '支付宝订单初始状态无效',
      );
    }
    // `account` is retained in the in-memory order for the legacy model only;
    // the authenticated backend remains the authority for account ownership.
    return RechargeOrder(
      orderNo: orderNo,
      account: account,
      product: product,
      channel: PaymentChannelType.alipay,
      state: RechargeOrderState.created,
      createdAt: DateTime.now(),
      message: '订单已创建，等待调起支付宝',
      paymentOrderString: orderString,
    );
  }

  static GiftCatalogItem _giftFromMap(Map<String, Object?> item) {
    final String rawCategory = _string(
      item['category'] ??
          item['categoryName'] ??
          item['groupName'] ??
          item['tag'],
    ).toUpperCase();
    final String id = _string(item['giftId']);
    final String name = _string(item['giftName']);
    final int? price = _asInt(item['unitCostGiftCoin']);
    final int? repeatedPrice = _asInt(item['price']);
    if (!_isUuid(id) ||
        name.isEmpty ||
        price == null ||
        price <= 0 ||
        repeatedPrice != price ||
        !const <String>{'NORMAL', 'POPULAR'}.contains(rawCategory) ||
        _isRetiredGift(item)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物目录包含无效、退役或禁止的商品数据',
      );
    }
    final GiftCatalogCategory category = switch (rawCategory) {
      'NORMAL' => GiftCatalogCategory.companionship,
      'POPULAR' => GiftCatalogCategory.popular,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物目录包含未知分类',
      ),
    };
    return GiftCatalogItem(
      id: id,
      name: name,
      price: price,
      category: category,
      assetUrl: _optionalString(
        item['assetKey'] ??
            item['iconUrl'] ??
            item['giftImgUrl'] ??
            item['picUrl'],
      ),
      enabled: true,
    );
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value.trim());

  static DecorationItem _decorationFromMap(Map<String, Object?> item) {
    final String id = _string(item['decorationId']);
    final String name = _string(item['name']);
    final String type = _string(item['type']).toUpperCase();
    final int? price = _asInt(item['giftCoinCost']);
    final Object? rawOwned = item['owned'];
    final Object? rawEquipped = item['equipped'];
    if (!_isUuid(id) ||
        name.isEmpty ||
        !const <String>{
          'AVATAR_FRAME',
          'ROOM_ENTRY',
          'PROFILE_BADGE',
          'NICKNAME',
          'VOICE_WAVE',
        }.contains(type) ||
        price == null ||
        price < 0 ||
        rawOwned is! bool ||
        rawEquipped is! bool ||
        (rawEquipped && !rawOwned)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '装扮目录包含无效的商品数据',
      );
    }
    final DateTime? expiresAt = _optionalDateTime(item['expiresAt']);
    if (item['expiresAt'] != null && expiresAt == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '装扮目录 expiresAt 无效',
      );
    }
    return DecorationItem(
      id: id,
      name: name,
      kind: switch (type) {
        'AVATAR_FRAME' || '1' => DecorationKind.avatarFrame,
        'ROOM_ENTRY' || '2' => DecorationKind.entrance,
        'NICKNAME' || '3' => DecorationKind.nickname,
        'VOICE_WAVE' || '4' => DecorationKind.voiceWave,
        _ => DecorationKind.profileCard,
      },
      priceGiftCoins: price,
      owned: rawOwned,
      equipped: rawEquipped,
      assetUrl: _optionalString(item['assetKey']),
      expiresAt: expiresAt,
    );
  }

  static void _validateDecorationEquipResponse(
    Object? value, {
    required String decorationId,
    required bool equipped,
  }) {
    final Map<String, Object?> data = _validateDecorationMutationEnvelope(
      value,
      decorationId: decorationId,
      operation: '装扮状态',
    );
    final String responseId = _string(data['decorationId']);
    final Object? rawEquipped = data['equipped'];
    if (responseId != decorationId ||
        rawEquipped is! bool ||
        rawEquipped != equipped) {
      throw const _DecorationAuthorityException('装扮状态响应与请求不一致');
    }
  }

  static void _validateDecorationPurchaseResponse(
    Object? value, {
    required String decorationId,
  }) {
    final Map<String, Object?> data = _validateDecorationMutationEnvelope(
      value,
      decorationId: decorationId,
      operation: '装扮购买',
    );
    bool hasPositiveEvidence = false;
    for (final String key in <String>['success', 'accepted']) {
      if (!data.containsKey(key)) {
        continue;
      }
      final Object? raw = data[key];
      if (raw is! bool) {
        throw _DecorationAuthorityException('装扮购买 $key 不是有效布尔值');
      }
      if (!raw) {
        throw _DecorationAuthorityException('装扮购买响应明确报告失败');
      }
      hasPositiveEvidence = true;
    }
    if (data.containsKey('owned')) {
      if (data['owned'] is! bool) {
        throw const _DecorationAuthorityException('装扮购买 owned 不是有效布尔值');
      }
      if (data['owned'] != true) {
        throw const _DecorationAuthorityException('装扮购买响应明确报告未拥有');
      }
      hasPositiveEvidence = true;
    }
    if (_positiveDecorationState(data['state']) ||
        _positiveDecorationState(data['status'])) {
      hasPositiveEvidence = true;
    }
    if (!hasPositiveEvidence) {
      throw const _DecorationAuthorityException('装扮购买响应缺少成功权威字段');
    }
  }

  static Map<String, Object?> _validateDecorationMutationEnvelope(
    Object? value, {
    required String decorationId,
    required String operation,
  }) {
    if (value is! Map<String, Object?> || value.isEmpty) {
      throw _DecorationAuthorityException('$operation响应不是有效对象');
    }
    final String? responseId = _optionalString(value['decorationId']);
    if (responseId != null && responseId != decorationId) {
      throw _DecorationAuthorityException('$operation响应与请求装扮不一致');
    }
    if (value.containsKey('providerInvocation')) {
      final Object? invocation = value['providerInvocation'];
      if (invocation is! bool || invocation) {
        throw _DecorationAuthorityException(
          '$operation providerInvocation 必须为 false',
        );
      }
    }
    for (final String key in <String>['state', 'status']) {
      if (!value.containsKey(key)) {
        continue;
      }
      final String raw = _string(value[key]).toUpperCase();
      if (raw.isEmpty || _failedDecorationState(raw)) {
        throw _DecorationAuthorityException('$operation响应明确报告失败状态');
      }
      if (!_knownDecorationState(raw)) {
        throw _DecorationAuthorityException('$operation响应包含未知状态');
      }
    }
    if (value.containsKey('success') && value['success'] is! bool) {
      throw const _DecorationAuthorityException('装扮写入 success 不是有效布尔值');
    }
    if (value['success'] == false) {
      throw const _DecorationAuthorityException('装扮写入响应明确报告失败');
    }
    if (value.containsKey('accepted') && value['accepted'] is! bool) {
      throw const _DecorationAuthorityException('装扮写入 accepted 不是有效布尔值');
    }
    if (value['accepted'] == false) {
      throw const _DecorationAuthorityException('装扮写入响应明确报告未接受');
    }
    return value;
  }

  static bool _failedDecorationState(String value) => const <String>{
    'FAILED',
    'FAILURE',
    'REJECTED',
    'DECLINED',
    'ERROR',
    'CANCELLED',
    'CANCELED',
    'UNSUCCESSFUL',
  }.contains(value);

  static bool _knownDecorationState(String value) => const <String>{
    'SUCCESS',
    'SUCCEEDED',
    'ACCEPTED',
    'COMPLETED',
    'OK',
    'PENDING',
    'PROCESSING',
    'CONFIRMING',
  }.contains(value);

  static bool _positiveDecorationState(Object? value) => const <String>{
    'SUCCESS',
    'SUCCEEDED',
    'ACCEPTED',
    'COMPLETED',
    'OK',
  }.contains(_string(value).toUpperCase());

  static bool _requestIdMatches(
    Map<String, Object?> data,
    String requestId, {
    required List<String> keys,
  }) {
    for (final String key in keys) {
      if (_string(data[key]) == requestId) {
        return true;
      }
    }
    return false;
  }

  static List<Map<String, Object?>> _catalogList(
    Object? value, {
    required String label,
    bool requireRetiredCategoriesFlag = false,
  }) {
    if (value is! Map<String, Object?>) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应不是对象',
      );
    }
    final List<Object?> rawList = _requiredCatalogList(value, label: label);
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (final Object? raw in rawList) {
      if (raw is! Map<String, Object?>) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label list 包含非对象条目',
        );
      }
      items.add(raw);
    }
    final int? total = _asInt(value['total']);
    if (total == null || total < 0 || total != items.length) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label total 与 list 数量不一致',
      );
    }
    if (value['providerInvocation'] != false) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label providerInvocation 必须为 false',
      );
    }
    if (requireRetiredCategoriesFlag &&
        value['retiredCategoriesPresent'] != false) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label包含已退役或禁止分类',
      );
    }
    return List<Map<String, Object?>>.unmodifiable(items);
  }

  static List<Object?> _requiredCatalogList(
    Map<String, Object?> data, {
    required String label,
  }) {
    List<Object?>? selected;
    for (final String key in <String>['records', 'list', 'items']) {
      if (!data.containsKey(key)) {
        continue;
      }
      final Object? raw = data[key];
      if (raw is! List) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label的 $key 不是有效列表',
        );
      }
      final List<Object?> candidate = List<Object?>.from(raw);
      if (selected != null && !_deepEqual(selected, candidate)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label的多个列表别名内容不一致',
        );
      }
      selected = candidate;
    }
    if (selected == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label缺少服务端列表',
      );
    }
    return selected;
  }

  static bool _deepEqual(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (int index = 0; index < left.length; index += 1) {
        if (!_deepEqual(left[index], right[index])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is num && right is num) return left == right;
    return left == right;
  }

  static bool _isRetiredGift(Map<String, Object?> item) {
    final String text = <Object?>[
      item['giftName'],
      item['name'],
      item['categoryName'],
      item['category'],
      item['groupName'],
      item['typeName'],
    ].whereType<Object>().join(' ').toLowerCase();
    return const <String>[
      '红包',
      'red packet',
      'ktv',
      '点歌',
      '演唱',
      '合唱',
      '盲盒',
      'blind box',
      '魔法球',
      'magic ball',
      '团子',
      'dango',
      '情书',
      'love letter',
      'membership',
      'vip',
      '会员',
    ].any(text.contains);
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final Object? raw = data[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label缺少有效 $key',
      );
    }
    return raw.trim();
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _strictOptionalString(Object? value) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      return null;
    }
    if (value.codeUnits.any(
      (int codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
    )) {
      return null;
    }
    return value;
  }

  static int? _strictInt(Object? value) => value is int ? value : null;

  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static double? _asDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static DateTime? _optionalDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
}

/// A protocol-shaped failure whose payload is authoritative negative write
/// evidence. It must not enter the ambiguous-write reconciliation path.
class _DecorationAuthorityException extends ApiException {
  const _DecorationAuthorityException(String message)
    : super(kind: ApiFailureKind.protocol, message: message);
}
