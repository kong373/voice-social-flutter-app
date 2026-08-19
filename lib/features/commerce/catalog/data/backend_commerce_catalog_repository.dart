import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';

class BackendCommerceCatalogRepository implements CommerceCatalogRepository {
  BackendCommerceCatalogRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  bool get supportsRechargeCatalog => false;

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
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端未提供权威充值商品目录，正式商品配置完成后才能创建订单',
    );
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
    await _apiClient.post(_routes.rechargePrecheck);
    return const RechargeEligibility(allowed: true, message: '当前账号可以创建充值订单');
  }

  @override
  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  }) async {
    final RechargeEligibility eligibility = await checkRechargeEligibility(
      youthModeEnabled: youthModeEnabled,
    );
    if (!eligibility.allowed) {
      throw ApiException(
        kind: ApiFailureKind.forbidden,
        message: eligibility.message,
      );
    }
    if (!availableChannels(platform).contains(channel)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '当前平台不支持所选支付方式',
      );
    }
    if (channel == PaymentChannelType.appleIap) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: 'Apple IAP 商品和收据校验尚未接入，不能创建虚假 iOS 充值订单',
      );
    }
    final String route = channel == PaymentChannelType.wechat
        ? _routes.createWechatRechargeOrder
        : _routes.createAlipayRechargeOrder;
    final ApiResponse response = await _apiClient.post(
      route,
      query: <String, String>{'amount': _money(product.priceCny)},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String orderNo = _string(
      data['orderNo'] ?? data['outTradeNo'] ?? data['tradeNo'],
    );
    if (orderNo.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回有效充值订单号',
      );
    }
    return RechargeOrder(
      orderNo: orderNo,
      account: account.trim(),
      product: product,
      channel: channel,
      state: RechargeOrderState.created,
      createdAt: DateTime.now(),
      message: '订单已创建，等待支付渠道 SDK 调起',
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
    if (raw is bool) {
      return order.copyWith(
        state: raw
            ? RechargeOrderState.succeeded
            : RechargeOrderState.confirming,
        message: raw ? '服务端已确认到账' : '服务端仍在确认订单',
      );
    }
    final Map<String, Object?> data = _asMap(raw);
    final String status = _string(
      data['status'] ?? data['orderStatus'] ?? data['payStatus'],
    ).toLowerCase();
    final bool success = _asBool(
      data['success'] ?? data['isSuccess'] ?? data['paid'],
    );
    final RechargeOrderState state =
        success ||
            const <String>{'success', 'succeeded', 'paid', '2'}.contains(status)
        ? RechargeOrderState.succeeded
        : const <String>{'failed', 'failure', '3'}.contains(status)
        ? RechargeOrderState.failed
        : const <String>{'canceled', 'cancelled', '4'}.contains(status)
        ? RechargeOrderState.canceled
        : RechargeOrderState.confirming;
    return order.copyWith(
      state: state,
      message: state == RechargeOrderState.succeeded
          ? '服务端已确认到账'
          : _string(data['message'], fallback: '服务端仍在确认订单'),
    );
  }

  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() async {
    final ApiResponse response = await _apiClient.get(
      _routes.normalGiftCatalog,
    );
    return _extractList(response.data)
        .where((Map<String, Object?> item) => !_isRetiredGift(item))
        .map(_giftFromMap)
        .where((GiftCatalogItem item) => item.id > 0 && item.enabled)
        .toList(growable: false);
  }

  @override
  Future<List<BackpackGiftItem>> fetchBackpackGifts() async {
    final ApiResponse response = await _apiClient.post(
      _routes.userBackpackGifts,
      body: <String, Object?>{'pageNum': 1, 'pageSize': 100},
    );
    return _extractList(response.data)
        .where((Map<String, Object?> item) => !_isRetiredGift(item))
        .map(_backpackFromMap)
        .where((BackpackGiftItem item) => item.gift.id > 0 && item.quantity > 0)
        .toList(growable: false);
  }

  @override
  Future<MembershipSnapshot> fetchMembershipSnapshot() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient
          .post(_routes.vipInformation)
          .then((ApiResponse value) => value.data),
      _apiClient
          .post(
            _routes.userDecorations,
            body: <String, Object?>{'pageNum': 1, 'pageSize': 100},
          )
          .then((ApiResponse value) => value.data),
      fetchBackpackGifts(),
      _apiClient
          .get(_routes.ncoinBalance)
          .then((ApiResponse value) => value.data),
    ]);
    final Map<String, Object?> vip = _asMap(results[0]);
    final List<DecorationItem> decorations = _extractList(results[1])
        .map(_decorationFromMap)
        .where((DecorationItem item) => item.id.isNotEmpty)
        .toList(growable: false);
    final List<BackpackGiftItem> backpack =
        results[2] as List<BackpackGiftItem>;
    final int balance = _balanceFrom(results[3]);
    final List<MembershipPlan> plans =
        _asMapList(vip['plans'] ?? vip['vipList'] ?? vip['products'])
            .map(_membershipPlanFromMap)
            .where((MembershipPlan plan) => plan.id.isNotEmpty)
            .toList(growable: false);
    final DateTime? expiresAt = _optionalDateTime(
      vip['expireTime'] ?? vip['expiresAt'] ?? vip['vipEndTime'],
    );
    final bool active =
        _asBool(vip['isVip'] ?? vip['active'] ?? vip['vipStatus']) ||
        (expiresAt?.isAfter(DateTime.now()) ?? false);
    return MembershipSnapshot(
      giftCoinBalance: balance,
      active: active,
      levelName: _string(
        vip['vipName'] ?? vip['levelName'],
        fallback: active ? '会员' : '普通用户',
      ),
      expiresAt: expiresAt,
      plans: plans,
      decorations: decorations,
      backpack: backpack,
    );
  }

  @override
  Future<MembershipSnapshot> purchaseMembership(String planId) async {
    if (planId.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效会员商品',
      );
    }
    await _apiClient.post(
      _routes.purchaseVipWithGiftCoins,
      body: <String, Object?>{'vipId': _numericId(planId)},
    );
    return fetchMembershipSnapshot();
  }

  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) async {
    if (decorationId.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效装扮商品',
      );
    }
    await _apiClient.post(
      _routes.purchaseMallGoods,
      body: <String, Object?>{'goodsId': _numericId(decorationId), 'buyNum': 1},
    );
    final MembershipSnapshot snapshot = await fetchMembershipSnapshot();
    for (final DecorationItem item in snapshot.decorations) {
      if (item.id == decorationId) {
        return item;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '购买成功后未查询到对应装扮',
    );
  }

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) async {
    await _apiClient.patch(
      _routes.equipUserDecoration,
      body: <String, Object?>{
        'id': _numericId(decorationId),
        'isPutOn': equipped ? 1 : 0,
      },
    );
    final MembershipSnapshot snapshot = await fetchMembershipSnapshot();
    for (final DecorationItem item in snapshot.decorations) {
      if (item.id == decorationId) {
        return item;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '装扮状态已更新，但服务端未返回对应记录',
    );
  }

  static GiftCatalogItem _giftFromMap(Map<String, Object?> item) {
    final String rawCategory = _string(
      item['categoryName'] ?? item['groupName'] ?? item['tag'],
    );
    return GiftCatalogItem(
      id: _asInt(item['giftId'] ?? item['id']) ?? 0,
      name: _string(item['giftName'] ?? item['name'], fallback: '普通礼物'),
      price: _asInt(item['price'] ?? item['diamond'] ?? item['ncoin']) ?? 0,
      category: rawCategory.contains('庆')
          ? GiftCatalogCategory.celebration
          : rawCategory.contains('陪')
          ? GiftCatalogCategory.companionship
          : GiftCatalogCategory.popular,
      assetUrl: _optionalString(
        item['iconUrl'] ?? item['giftImgUrl'] ?? item['picUrl'],
      ),
      enabled:
          !_asBool(item['disabled']) &&
          (_asInt(item['status'] ?? item['isShow']) ?? 1) != 0,
    );
  }

  static BackpackGiftItem _backpackFromMap(Map<String, Object?> item) {
    final Map<String, Object?> giftData = _asMap(item['gift']);
    final GiftCatalogItem gift = _giftFromMap(
      giftData.isEmpty ? item : giftData,
    );
    return BackpackGiftItem(
      id: _string(item['id'] ?? item['packGiftId']),
      gift: gift,
      quantity:
          _asInt(item['quantity'] ?? item['number'] ?? item['giftNum']) ?? 0,
      expiresAt: _optionalDateTime(item['expireTime'] ?? item['expiresAt']),
    );
  }

  static DecorationItem _decorationFromMap(Map<String, Object?> item) {
    final int type = _asInt(item['type'] ?? item['decorationType']) ?? 0;
    return DecorationItem(
      id: _string(item['id'] ?? item['decorationId']),
      name: _string(item['name'] ?? item['decorationName'], fallback: '装扮'),
      kind: switch (type) {
        1 => DecorationKind.avatarFrame,
        2 => DecorationKind.entrance,
        3 => DecorationKind.nickname,
        4 => DecorationKind.voiceWave,
        _ => DecorationKind.profileCard,
      },
      priceGiftCoins:
          _asInt(item['price'] ?? item['ncoin'] ?? item['diamond']) ?? 0,
      owned:
          !_asBool(item['notOwned']) &&
          (_asBool(item['owned']) || item['userDecorationId'] != null),
      equipped: _asBool(item['isPutOn'] ?? item['equipped'] ?? item['putOn']),
      assetUrl: _optionalString(
        item['iconUrl'] ?? item['picUrl'] ?? item['resourceUrl'],
      ),
      expiresAt: _optionalDateTime(item['expireTime'] ?? item['expiresAt']),
    );
  }

  static MembershipPlan _membershipPlanFromMap(Map<String, Object?> item) {
    return MembershipPlan(
      id: _string(item['id'] ?? item['vipId']),
      name: _string(item['name'] ?? item['vipName'], fallback: '会员'),
      priceGiftCoins:
          _asInt(item['price'] ?? item['ncoin'] ?? item['diamond']) ?? 0,
      durationDays: _asInt(item['days'] ?? item['durationDays']) ?? 0,
      benefits: _split(item['benefits'] ?? item['privileges']),
    );
  }

  static bool _isRetiredGift(Map<String, Object?> item) {
    final String text = <Object?>[
      item['giftName'],
      item['name'],
      item['categoryName'],
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
    ].any(text.contains);
  }

  static int _balanceFrom(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final Map<String, Object?> map = _asMap(value);
    return _asInt(map['balance'] ?? map['ncoin'] ?? map['availableBalance']) ??
        0;
  }

  static List<Map<String, Object?>> _extractList(Object? value) {
    final Map<String, Object?> map = _asMap(value);
    final Object? source =
        map['records'] ??
        map['list'] ??
        map['rows'] ??
        map['items'] ??
        map['data'] ??
        value;
    return _asMapList(source);
  }

  static String _money(double value) => value.toStringAsFixed(2);
  static Object _numericId(String value) => int.tryParse(value) ?? value;
  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static List<Map<String, Object?>> _asMapList(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList(growable: false)
      : const <Map<String, Object?>>[];
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
  static bool _asBool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';
  static DateTime? _optionalDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
  static List<String> _split(Object? value) {
    if (value is List) {
      return value
          .map((Object? item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return (value?.toString() ?? '')
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
