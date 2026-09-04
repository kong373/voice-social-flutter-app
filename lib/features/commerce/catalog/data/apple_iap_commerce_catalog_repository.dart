import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

/// iOS implementation of the existing recharge contract.
///
/// This class is constructed only for an iOS live client. The first-party
/// catalog uses internal product IDs; every StoreKit product ID and
/// appAccountToken comes from the authenticated order endpoint.
class AppleIapCommerceCatalogRepository implements CommerceCatalogRepository {
  AppleIapCommerceCatalogRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required AppleIapPurchaseCoordinator coordinator,
    BackendCommerceCatalogRepository? sharedRepository,
    DateTime Function()? now,
  }) : _apiClient = apiClient,
       _routes = routes,
       _coordinator = coordinator,
       _sharedRepository =
           sharedRepository ??
           BackendCommerceCatalogRepository(apiClient: apiClient, routes: routes),
       _now = now ?? DateTime.now;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final AppleIapPurchaseCoordinator _coordinator;
  final BackendCommerceCatalogRepository _sharedRepository;
  final DateTime Function() _now;

  bool _orderCreationReady = false;

  @override
  bool get supportsRechargeCatalog => true;

  @override
  bool get supportsPaymentChannelInvocation => _orderCreationReady;

  @override
  List<PaymentChannelType> availableChannels(ClientStorePlatform platform) =>
      _orderCreationReady
      ? const <PaymentChannelType>[PaymentChannelType.appleIap]
      : const <PaymentChannelType>[];

  @override
  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  }) async {
    _orderCreationReady = false;
    final ApiResponse response = await _apiClient.get(
      _routes.rechargeProducts,
      query: const <String, String>{'platform': 'IOS'},
    );
    final Map<String, Object?> envelope = _requireMap(
      response.data,
      'iOS 充值商品目录',
    );
    if (_requiredString(envelope, 'platform', 'iOS 充值商品目录').toUpperCase() !=
        'IOS') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品目录返回了错误平台',
      );
    }
    final String creationStatus = _requiredString(
      envelope,
      'orderCreationStatus',
      'iOS 充值商品目录',
    ).toUpperCase();
    if (creationStatus != 'READY' && creationStatus != 'VENDOR_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品目录返回了未知支付状态',
      );
    }
    final List<Object?> rawItems = _requireList(
      envelope['items'] ?? envelope['list'],
      'iOS 充值商品目录 items',
    );
    final List<RechargeProduct> products = rawItems
        .map<RechargeProduct>(_productFromMap)
        .toList(growable: false);
    if (products.map((RechargeProduct item) => item.id).toSet().length !=
        products.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品目录包含重复内部商品 ID',
      );
    }
    final bool nativeAvailable = await _coordinator.isAvailable;
    if (nativeAvailable) {
      await _coordinator.activateAuthenticatedSession();
    }
    _orderCreationReady = creationStatus == 'READY' && nativeAvailable;
    return products;
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
    if (!_orderCreationReady) {
      return const RechargeEligibility(
        allowed: false,
        message: 'Apple IAP 尚未就绪，当前不能创建充值订单',
      );
    }
    return const RechargeEligibility(allowed: true, message: '');
  }

  @override
  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  }) async {
    if (channel != PaymentChannelType.appleIap || !_orderCreationReady) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: 'Apple IAP 当前不可用',
      );
    }
    if (youthModeEnabled) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '青少年模式已开启，暂不能创建新的充值订单',
      );
    }
    if (account.isEmpty || account.trim() != account || !product.enabled) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '充值账号或商品无效，请刷新后重试',
      );
    }
    final AppleIapOrderBinding binding = await _coordinator.createOrder(
      product.id,
    );
    final int? amountMinor = product.amountMinor;
    if (binding.productId != product.id ||
        amountMinor == null ||
        binding.amountMinor != amountMinor ||
        binding.giftCoinAmount != product.totalGiftCoins) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 订单金额、商品或礼物币数量与当前档位不一致',
      );
    }
    return RechargeOrder(
      orderNo: binding.orderNo,
      account: account,
      product: product,
      channel: PaymentChannelType.appleIap,
      state: RechargeOrderState.created,
      createdAt: _now().toUtc(),
      message: 'Apple 订单已创建，等待 StoreKit 购买',
    );
  }

  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async {
    if (order.channel != PaymentChannelType.appleIap) {
      return _sharedRepository.invokePayment(order);
    }
    final AppleIapFlowResult result = await _coordinator.purchaseOrder(
      order.orderNo,
    );
    return order.copyWith(
      state: switch (result.state) {
        AppleIapFlowState.delivered => RechargeOrderState.succeeded,
        AppleIapFlowState.confirming || AppleIapFlowState.pending =>
          RechargeOrderState.confirming,
        AppleIapFlowState.canceled => RechargeOrderState.canceled,
        AppleIapFlowState.failed => RechargeOrderState.failed,
        AppleIapFlowState.unavailable => RechargeOrderState.unavailable,
      },
      message: result.message,
    );
  }

  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) async {
    if (order.channel != PaymentChannelType.appleIap) {
      return _sharedRepository.queryRechargeOrder(order);
    }
    final AppleIapOrderStatus status = await _coordinator.queryOrderStatus(
      order.orderNo,
    );
    return order.copyWith(
      state: switch (status.status) {
        'CREATED' => RechargeOrderState.created,
        'CONFIRMING' || 'PENDING' => RechargeOrderState.confirming,
        'SUCCEEDED' => RechargeOrderState.succeeded,
        'FAILED' => RechargeOrderState.failed,
        'CANCELLED' => RechargeOrderState.canceled,
        _ => throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'Apple 订单状态包含未知值',
        ),
      },
      message: status.status == 'SUCCEEDED'
          ? 'Apple 充值已由服务端确认到账'
          : 'Apple 订单状态以服务端为准',
    );
  }

  Future<List<AppleIapFlowResult>> restoreUnfinishedRecharge() =>
      _coordinator.restoreUnfinishedTransactions(synchronize: true);

  Future<void> dispose() => _coordinator.dispose();

  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() =>
      _sharedRepository.fetchGiftCatalog();

  @override
  Future<List<DecorationItem>> fetchDecorations() =>
      _sharedRepository.fetchDecorations();

  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) =>
      _sharedRepository.purchaseDecoration(decorationId);

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) => _sharedRepository.setDecorationEquipped(
    decorationId: decorationId,
    equipped: equipped,
  );

  static RechargeProduct _productFromMap(Object? raw) {
    final Map<String, Object?> data = _requireMap(raw, 'iOS 充值商品');
    final String productId = _firstString(
      data,
      const <String>['productId', 'publicId', 'id'],
      'iOS 充值商品 ID',
    );
    final int amountMinor = _firstPositiveInt(
      data,
      const <String>['amountMinor', 'priceMinor'],
      'iOS 充值商品金额',
    );
    final int bonus = _optionalNonNegativeInt(
      data['bonusGiftCoins'] ?? data['bonus'],
    );
    final int? declaredBase = _optionalPositiveInt(data['giftCoins']);
    final int? declaredTotal = _optionalPositiveInt(data['giftCoinAmount']);
    final int baseGiftCoins;
    final int totalGiftCoins;
    if (declaredBase != null && declaredTotal != null) {
      if (declaredBase + bonus != declaredTotal) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'iOS 充值商品的礼物币总数与赠送数量不一致',
        );
      }
      baseGiftCoins = declaredBase;
      totalGiftCoins = declaredTotal;
    } else if (declaredTotal != null) {
      if (declaredTotal <= bonus) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'iOS 充值商品的礼物币总数无效',
        );
      }
      baseGiftCoins = declaredTotal - bonus;
      totalGiftCoins = declaredTotal;
    } else if (declaredBase != null) {
      baseGiftCoins = declaredBase;
      totalGiftCoins = declaredBase + bonus;
    } else {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品缺少礼物币数量',
      );
    }
    if (totalGiftCoins <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品礼物币数量无效',
      );
    }
    return RechargeProduct(
      id: productId,
      giftCoins: baseGiftCoins,
      bonusGiftCoins: bonus,
      priceCny: amountMinor / 100,
      amountMinor: amountMinor,
      label: _optionalString(data['label']) ?? '',
      recommended: data['recommended'] == true,
      enabled: data['enabled'] != false,
    );
  }

  static Map<String, Object?> _requireMap(Object? raw, String label) {
    if (raw is! Map) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应不是对象',
      );
    }
    return raw.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>(
        key.toString(),
        value,
      ),
    );
  }

  static List<Object?> _requireList(Object? raw, String label) {
    if (raw is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label不是数组',
      );
    }
    return raw.cast<Object?>();
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key,
    String label,
  ) => _firstString(data, <String>[key], '$label $key');

  static String _firstString(
    Map<String, Object?> data,
    List<String> keys,
    String label,
  ) {
    for (final String key in keys) {
      final Object? raw = data[key];
      if (raw is String && raw.isNotEmpty && raw.trim() == raw) {
        return raw;
      }
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '$label 缺失或无效',
    );
  }

  static int _firstPositiveInt(
    Map<String, Object?> data,
    List<String> keys,
    String label,
  ) {
    for (final String key in keys) {
      final int? value = _optionalPositiveInt(data[key]);
      if (value != null) {
        return value;
      }
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '$label 缺失或无效',
    );
  }

  static int? _optionalPositiveInt(Object? raw) =>
      raw is int && raw > 0 ? raw : null;

  static int _optionalNonNegativeInt(Object? raw) =>
      raw is int && raw >= 0 ? raw : 0;

  static String? _optionalString(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! String || raw.trim() != raw || raw.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'iOS 充值商品包含无效可选文本字段',
      );
    }
    return raw;
  }
}
