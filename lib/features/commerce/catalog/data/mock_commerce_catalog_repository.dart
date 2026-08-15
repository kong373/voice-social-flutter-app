import 'dart:async';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';

class MockCommerceCatalogRepository implements CommerceCatalogRepository {
  MockCommerceCatalogRepository()
      : _decorations = <DecorationItem>[
          const DecorationItem(
            id: 'decor-frame-starlight',
            name: '星光头像框',
            kind: DecorationKind.avatarFrame,
            priceGiftCoins: 520,
            owned: true,
            equipped: true,
          ),
          const DecorationItem(
            id: 'decor-entrance-night',
            name: '夜色进场装扮',
            kind: DecorationKind.entrance,
            priceGiftCoins: 880,
            owned: false,
            equipped: false,
          ),
          const DecorationItem(
            id: 'decor-wave-soft',
            name: '温柔声波',
            kind: DecorationKind.voiceWave,
            priceGiftCoins: 360,
            owned: true,
            equipped: false,
          ),
        ],
        _backpack = <BackpackGiftItem>[
          BackpackGiftItem(
            id: 'pack-rose',
            gift: const GiftCatalogItem(
              id: 101,
              name: '玫瑰',
              price: 10,
              category: GiftCatalogCategory.companionship,
            ),
            quantity: 12,
            expiresAt: DateTime.now().add(const Duration(days: 20)),
          ),
          BackpackGiftItem(
            id: 'pack-star',
            gift: const GiftCatalogItem(
              id: 102,
              name: '星光',
              price: 66,
              category: GiftCatalogCategory.popular,
            ),
            quantity: 3,
          ),
        ];

  final List<RechargeOrder> _orders = <RechargeOrder>[];
  final List<DecorationItem> _decorations;
  final List<BackpackGiftItem> _backpack;
  final Map<String, int> _orderQueries = <String, int>{};
  int _giftCoinBalance = 1680;
  bool _membershipActive = false;
  DateTime? _membershipExpiresAt;

  static const List<GiftCatalogItem> _gifts = <GiftCatalogItem>[
    GiftCatalogItem(
      id: 101,
      name: '玫瑰',
      price: 10,
      category: GiftCatalogCategory.companionship,
    ),
    GiftCatalogItem(
      id: 102,
      name: '星光',
      price: 66,
      category: GiftCatalogCategory.popular,
    ),
    GiftCatalogItem(
      id: 103,
      name: '晚安灯',
      price: 188,
      category: GiftCatalogCategory.companionship,
    ),
    GiftCatalogItem(
      id: 104,
      name: '庆祝烟花',
      price: 520,
      category: GiftCatalogCategory.celebration,
    ),
  ];

  static const List<MembershipPlan> _plans = <MembershipPlan>[
    MembershipPlan(
      id: 'vip-30',
      name: '月度会员',
      priceGiftCoins: 880,
      durationDays: 30,
      benefits: <String>['会员标识', '专属昵称样式', '每月装扮体验卡'],
    ),
    MembershipPlan(
      id: 'vip-90',
      name: '季度会员',
      priceGiftCoins: 2280,
      durationDays: 90,
      benefits: <String>['会员标识', '专属昵称样式', '季度头像框'],
    ),
  ];

  @override
  bool get supportsRechargeCatalog => true;

  @override
  bool get supportsPaymentChannelInvocation => true;

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
    await _delay();
    return const <RechargeProduct>[
      RechargeProduct(id: 'recharge-6', giftCoins: 60, priceCny: 6),
      RechargeProduct(id: 'recharge-30', giftCoins: 300, priceCny: 30),
      RechargeProduct(
        id: 'recharge-68',
        giftCoins: 680,
        bonusGiftCoins: 20,
        priceCny: 68,
        label: '常用',
        recommended: true,
      ),
      RechargeProduct(
        id: 'recharge-198',
        giftCoins: 1980,
        bonusGiftCoins: 100,
        priceCny: 198,
      ),
      RechargeProduct(
        id: 'recharge-648',
        giftCoins: 6480,
        bonusGiftCoins: 420,
        priceCny: 648,
      ),
    ];
  }

  @override
  Future<RechargeEligibility> checkRechargeEligibility({
    required bool youthModeEnabled,
  }) async {
    await _delay();
    return RechargeEligibility(
      allowed: !youthModeEnabled,
      message: youthModeEnabled
          ? '青少年模式已开启，暂不能创建新的充值订单'
          : '当前账号可以创建充值订单',
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
    await _delay();
    final RechargeEligibility eligibility = await checkRechargeEligibility(
      youthModeEnabled: youthModeEnabled,
    );
    if (!eligibility.allowed) {
      throw ApiException(
        kind: ApiFailureKind.forbidden,
        message: eligibility.message,
      );
    }
    if (!product.enabled || product.priceCny <= 0 || product.giftCoins <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值商品已失效，请刷新后重新选择',
      );
    }
    if (!availableChannels(platform).contains(channel)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '当前平台不支持所选支付方式',
      );
    }
    final RechargeOrder order = RechargeOrder(
      orderNo: 'RC${DateTime.now().microsecondsSinceEpoch}',
      account: account.trim(),
      product: product,
      channel: channel,
      state: RechargeOrderState.created,
      createdAt: DateTime.now(),
      message: '订单已创建，等待调起支付',
    );
    _orders.add(order);
    _orderQueries[order.orderNo] = 0;
    return order;
  }

  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async {
    await _delay();
    final int index = _indexForOrder(order.orderNo);
    if (_orders[index].state != RechargeOrderState.created) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '订单状态已变化，请刷新后重试',
      );
    }
    final RechargeOrder updated = order.copyWith(
      state: RechargeOrderState.confirming,
      message: '支付返回后正在等待服务端确认',
    );
    _orders[index] = updated;
    return updated;
  }

  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) async {
    await _delay();
    final int index = _indexForOrder(order.orderNo);
    final RechargeOrder current = _orders[index];
    if (current.state == RechargeOrderState.confirming) {
      final int queries = (_orderQueries[current.orderNo] ?? 0) + 1;
      _orderQueries[current.orderNo] = queries;
      if (queries >= 2) {
        final RechargeOrder succeeded = current.copyWith(
          state: RechargeOrderState.succeeded,
          message: '服务端已确认到账',
        );
        _orders[index] = succeeded;
        _giftCoinBalance += current.product.totalGiftCoins;
        return succeeded;
      }
    }
    return current;
  }

  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() async {
    await _delay();
    return List<GiftCatalogItem>.unmodifiable(_gifts);
  }

  @override
  Future<List<BackpackGiftItem>> fetchBackpackGifts() async {
    await _delay();
    return List<BackpackGiftItem>.unmodifiable(_backpack);
  }

  @override
  Future<MembershipSnapshot> fetchMembershipSnapshot() async {
    await _delay();
    return MembershipSnapshot(
      giftCoinBalance: _giftCoinBalance,
      active: _membershipActive,
      levelName: _membershipActive ? '会员' : '普通用户',
      expiresAt: _membershipExpiresAt,
      plans: _plans,
      decorations: List<DecorationItem>.unmodifiable(_decorations),
      backpack: List<BackpackGiftItem>.unmodifiable(_backpack),
    );
  }

  @override
  Future<MembershipSnapshot> purchaseMembership(String planId) async {
    await _delay();
    MembershipPlan? plan;
    for (final MembershipPlan item in _plans) {
      if (item.id == planId) {
        plan = item;
        break;
      }
    }
    if (plan == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '会员商品已失效',
      );
    }
    if (_giftCoinBalance < plan.priceGiftCoins) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '礼物币余额不足',
      );
    }
    _giftCoinBalance -= plan.priceGiftCoins;
    _membershipActive = true;
    final DateTime base = _membershipExpiresAt != null &&
            _membershipExpiresAt!.isAfter(DateTime.now())
        ? _membershipExpiresAt!
        : DateTime.now();
    _membershipExpiresAt = base.add(Duration(days: plan.durationDays));
    return fetchMembershipSnapshot();
  }

  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) async {
    await _delay();
    final int index = _indexForDecoration(decorationId);
    final DecorationItem current = _decorations[index];
    if (current.owned) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '已经拥有该装扮',
      );
    }
    if (_giftCoinBalance < current.priceGiftCoins) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '礼物币余额不足',
      );
    }
    _giftCoinBalance -= current.priceGiftCoins;
    final DecorationItem purchased = current.copyWith(
      owned: true,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    _decorations[index] = purchased;
    return purchased;
  }

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) async {
    await _delay();
    final int index = _indexForDecoration(decorationId);
    final DecorationItem current = _decorations[index];
    if (!current.owned) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '尚未拥有该装扮',
      );
    }
    if (equipped) {
      for (int i = 0; i < _decorations.length; i += 1) {
        final DecorationItem item = _decorations[i];
        if (item.kind == current.kind && item.equipped) {
          _decorations[i] = item.copyWith(equipped: false);
        }
      }
    }
    final DecorationItem updated = current.copyWith(equipped: equipped);
    _decorations[index] = updated;
    return updated;
  }

  int _indexForOrder(String orderNo) {
    final int index = _orders.indexWhere(
      (RechargeOrder item) => item.orderNo == orderNo,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值订单不存在',
      );
    }
    return index;
  }

  int _indexForDecoration(String id) {
    final int index = _decorations.indexWhere(
      (DecorationItem item) => item.id == id,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '装扮不存在或已下架',
      );
    }
    return index;
  }

  static Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 35));
}
