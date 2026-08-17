enum ClientStorePlatform { android, ios }

enum PaymentChannelType { wechat, alipay, appleIap }

extension PaymentChannelLabel on PaymentChannelType {
  String get label => switch (this) {
        PaymentChannelType.wechat => '微信支付',
        PaymentChannelType.alipay => '支付宝',
        PaymentChannelType.appleIap => 'Apple IAP',
      };
}

enum RechargeOrderState {
  created,
  invoking,
  confirming,
  succeeded,
  failed,
  canceled,
  unavailable,
}

extension RechargeOrderStateLabel on RechargeOrderState {
  String get label => switch (this) {
        RechargeOrderState.created => '订单已创建',
        RechargeOrderState.invoking => '正在调起支付',
        RechargeOrderState.confirming => '服务端确认中',
        RechargeOrderState.succeeded => '充值成功',
        RechargeOrderState.failed => '充值失败',
        RechargeOrderState.canceled => '已取消',
        RechargeOrderState.unavailable => '暂不可用',
      };
}

class RechargeProduct {
  const RechargeProduct({
    required this.id,
    required this.giftCoins,
    required this.priceCny,
    this.bonusGiftCoins = 0,
    this.label = '',
    this.recommended = false,
    this.enabled = true,
  });

  final String id;
  final int giftCoins;
  final double priceCny;
  final int bonusGiftCoins;
  final String label;
  final bool recommended;
  final bool enabled;

  int get totalGiftCoins => giftCoins + bonusGiftCoins;
}

class RechargeEligibility {
  const RechargeEligibility({
    required this.allowed,
    required this.message,
  });

  final bool allowed;
  final String message;
}

class RechargeOrder {
  const RechargeOrder({
    required this.orderNo,
    required this.account,
    required this.product,
    required this.channel,
    required this.state,
    required this.createdAt,
    this.message = '',
  });

  final String orderNo;
  final String account;
  final RechargeProduct product;
  final PaymentChannelType channel;
  final RechargeOrderState state;
  final DateTime createdAt;
  final String message;

  RechargeOrder copyWith({
    RechargeOrderState? state,
    String? message,
  }) {
    return RechargeOrder(
      orderNo: orderNo,
      account: account,
      product: product,
      channel: channel,
      state: state ?? this.state,
      createdAt: createdAt,
      message: message ?? this.message,
    );
  }
}

enum GiftCatalogCategory { popular, companionship, celebration }

extension GiftCatalogCategoryLabel on GiftCatalogCategory {
  String get label => switch (this) {
        GiftCatalogCategory.popular => '热门',
        GiftCatalogCategory.companionship => '陪伴',
        GiftCatalogCategory.celebration => '庆祝',
      };
}

class GiftCatalogItem {
  const GiftCatalogItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.assetUrl,
    this.enabled = true,
  });

  final int id;
  final String name;
  final int price;
  final GiftCatalogCategory category;
  final String? assetUrl;
  final bool enabled;
}

class BackpackGiftItem {
  const BackpackGiftItem({
    required this.id,
    required this.gift,
    required this.quantity,
    this.expiresAt,
  });

  final String id;
  final GiftCatalogItem gift;
  final int quantity;
  final DateTime? expiresAt;
}

enum DecorationKind {
  avatarFrame,
  entrance,
  nickname,
  voiceWave,
  profileCard,
}

extension DecorationKindLabel on DecorationKind {
  String get label => switch (this) {
        DecorationKind.avatarFrame => '头像框',
        DecorationKind.entrance => '进场装扮',
        DecorationKind.nickname => '昵称装扮',
        DecorationKind.voiceWave => '声波装扮',
        DecorationKind.profileCard => '资料卡装扮',
      };
}

class DecorationItem {
  const DecorationItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.priceGiftCoins,
    required this.owned,
    required this.equipped,
    this.assetUrl,
    this.expiresAt,
  });

  final String id;
  final String name;
  final DecorationKind kind;
  final int priceGiftCoins;
  final bool owned;
  final bool equipped;
  final String? assetUrl;
  final DateTime? expiresAt;

  DecorationItem copyWith({
    bool? owned,
    bool? equipped,
    DateTime? expiresAt,
  }) {
    return DecorationItem(
      id: id,
      name: name,
      kind: kind,
      priceGiftCoins: priceGiftCoins,
      owned: owned ?? this.owned,
      equipped: equipped ?? this.equipped,
      assetUrl: assetUrl,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.priceGiftCoins,
    required this.durationDays,
    this.benefits = const <String>[],
  });

  final String id;
  final String name;
  final int priceGiftCoins;
  final int durationDays;
  final List<String> benefits;
}

class MembershipSnapshot {
  const MembershipSnapshot({
    required this.giftCoinBalance,
    required this.active,
    required this.levelName,
    required this.plans,
    required this.decorations,
    required this.backpack,
    this.expiresAt,
  });

  final int giftCoinBalance;
  final bool active;
  final String levelName;
  final DateTime? expiresAt;
  final List<MembershipPlan> plans;
  final List<DecorationItem> decorations;
  final List<BackpackGiftItem> backpack;

  MembershipSnapshot copyWith({
    int? giftCoinBalance,
    bool? active,
    String? levelName,
    DateTime? expiresAt,
    List<MembershipPlan>? plans,
    List<DecorationItem>? decorations,
    List<BackpackGiftItem>? backpack,
  }) {
    return MembershipSnapshot(
      giftCoinBalance: giftCoinBalance ?? this.giftCoinBalance,
      active: active ?? this.active,
      levelName: levelName ?? this.levelName,
      expiresAt: expiresAt ?? this.expiresAt,
      plans: plans ?? this.plans,
      decorations: decorations ?? this.decorations,
      backpack: backpack ?? this.backpack,
    );
  }
}
