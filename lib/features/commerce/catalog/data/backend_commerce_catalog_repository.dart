import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/decoration_purchase_request_id.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';

class BackendCommerceCatalogRepository implements CommerceCatalogRepository {
  BackendCommerceCatalogRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    String Function()? decorationPurchaseRequestIdGenerator,
  }) : _apiClient = apiClient,
       _routes = routes,
       _decorationPurchaseRequestIdGenerator =
           decorationPurchaseRequestIdGenerator ??
           newDecorationPurchaseRequestId;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final String Function() _decorationPurchaseRequestIdGenerator;
  final Map<String, Future<DecorationItem>> _pendingDecorationPurchases =
      <String, Future<DecorationItem>>{};
  final Map<String, Future<DecorationItem>> _pendingDecorationEquips =
      <String, Future<DecorationItem>>{};
  final Map<String, Future<void>> _decorationMutationTails =
      <String, Future<void>>{};
  final Map<String, String> _decorationPurchaseRequestIds = <String, String>{};
  final Map<String, String> _decorationEquipRequestIds = <String, String>{};

  @override
  bool get supportsRechargeCatalog => true;

  @override
  bool get supportsPaymentChannelInvocation => false;

  @override
  List<PaymentChannelType> availableChannels(ClientStorePlatform platform) =>
      platform == ClientStorePlatform.ios
      ? const <PaymentChannelType>[PaymentChannelType.appleIap]
      : const <PaymentChannelType>[
          PaymentChannelType.wechat,
          PaymentChannelType.alipay,
        ];

  @override
  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  }) async {
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
    if (_string(envelope['platform']).toUpperCase() != expectedPlatform ||
        _string(envelope['orderCreationStatus']).toUpperCase() !=
            'VENDOR_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值商品目录平台或支付失败关闭状态与请求不一致',
      );
    }
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
    return const RechargeEligibility(
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
    if (!availableChannels(platform).contains(channel)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '当前平台不支持所选支付方式',
      );
    }
    if (!product.enabled || product.id.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值商品无效，请刷新商品目录后重试',
      );
    }
    final RechargeEligibility eligibility = await checkRechargeEligibility(
      youthModeEnabled: youthModeEnabled,
    );
    throw ApiException(
      kind: youthModeEnabled
          ? ApiFailureKind.forbidden
          : ApiFailureKind.configuration,
      message: eligibility.message,
    );
  }

  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '支付渠道 SDK 尚未接入，当前版本不能调起支付',
    );
  }

  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) async {
    final ApiResponse response = await _apiClient.get(
      _routes.rechargeOrderStatus,
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
