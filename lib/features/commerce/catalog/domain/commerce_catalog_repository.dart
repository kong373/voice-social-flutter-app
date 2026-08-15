import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

abstract interface class CommerceCatalogRepository {
  bool get supportsRechargeCatalog;
  bool get supportsPaymentChannelInvocation;

  List<PaymentChannelType> availableChannels(ClientStorePlatform platform);

  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  });

  Future<RechargeEligibility> checkRechargeEligibility({
    required bool youthModeEnabled,
  });

  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  });

  Future<RechargeOrder> invokePayment(RechargeOrder order);

  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order);

  Future<List<GiftCatalogItem>> fetchGiftCatalog();

  Future<List<BackpackGiftItem>> fetchBackpackGifts();

  Future<MembershipSnapshot> fetchMembershipSnapshot();

  Future<MembershipSnapshot> purchaseMembership(String planId);

  Future<DecorationItem> purchaseDecoration(String decorationId);

  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  });
}
