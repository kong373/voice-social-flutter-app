enum AppleIapPurchaseState {
  verified,
  unverified,
  pending,
  canceled,
  failed,
  unavailable,
}

class AppleIapStoreProduct {
  const AppleIapStoreProduct({
    required this.storeProductId,
    required this.displayName,
    required this.description,
    required this.displayPrice,
  });

  final String storeProductId;
  final String displayName;
  final String description;
  final String displayPrice;
}

class AppleIapTransaction {
  const AppleIapTransaction({
    required this.transactionId,
    required this.storeProductId,
    required this.appAccountToken,
    required this.signedTransaction,
    required this.locallyVerified,
    this.originalTransactionId,
  });

  final String transactionId;
  final String? originalTransactionId;
  final String storeProductId;
  final String? appAccountToken;

  /// Apple-signed JWS retained in memory only until the authenticated Backend
  /// acknowledges exactly-once delivery. It must never be logged or persisted.
  final String signedTransaction;
  final bool locallyVerified;

  @override
  String toString() =>
      'AppleIapTransaction(transactionId: $transactionId, '
      'storeProductId: $storeProductId, locallyVerified: $locallyVerified, '
      'signedTransaction: [REDACTED])';
}

class AppleIapPurchaseResult {
  const AppleIapPurchaseResult({
    required this.state,
    this.transaction,
    this.message = '',
  });

  final AppleIapPurchaseState state;
  final AppleIapTransaction? transaction;
  final String message;
}

class AppleIapOrderBinding {
  const AppleIapOrderBinding({
    required this.orderNo,
    required this.productId,
    required this.storeProductId,
    required this.appAccountToken,
    required this.amountMinor,
    required this.giftCoinAmount,
    required this.status,
  });

  final String orderNo;

  /// First-party internal recharge-product identifier. It is never passed to
  /// StoreKit as an App Store product identifier.
  final String productId;
  final String storeProductId;
  final String appAccountToken;
  final int amountMinor;
  final int giftCoinAmount;
  final String status;

  Map<String, Object?> toJson() => <String, Object?>{
    'orderNo': orderNo,
    'productId': productId,
    'storeProductId': storeProductId,
    'appAccountToken': appAccountToken,
    'amountMinor': amountMinor,
    'giftCoinAmount': giftCoinAmount,
    'status': status,
  };

  factory AppleIapOrderBinding.fromJson(Map<String, Object?> json) {
    final Object? orderNo = json['orderNo'];
    final Object? productId = json['productId'];
    final Object? storeProductId = json['storeProductId'];
    final Object? appAccountToken = json['appAccountToken'];
    final Object? amountMinor = json['amountMinor'];
    final Object? giftCoinAmount = json['giftCoinAmount'];
    final Object? status = json['status'];
    final String normalizedToken = appAccountToken is String
        ? appAccountToken.toLowerCase()
        : '';
    if (orderNo is! String ||
        productId is! String ||
        storeProductId is! String ||
        appAccountToken is! String ||
        amountMinor is! int ||
        giftCoinAmount is! int ||
        status is! String ||
        orderNo.isEmpty ||
        productId.isEmpty ||
        storeProductId.isEmpty ||
        amountMinor <= 0 ||
        giftCoinAmount <= 0 ||
        status.isEmpty ||
        !_uuidPattern.hasMatch(normalizedToken)) {
      throw const FormatException('Invalid Apple IAP order binding');
    }
    return AppleIapOrderBinding(
      orderNo: orderNo,
      productId: productId,
      storeProductId: storeProductId,
      appAccountToken: normalizedToken,
      amountMinor: amountMinor,
      giftCoinAmount: giftCoinAmount,
      status: status.toUpperCase(),
    );
  }

  @override
  String toString() =>
      'AppleIapOrderBinding(orderNo: $orderNo, productId: $productId, '
      'storeProductId: $storeProductId, amountMinor: $amountMinor, '
      'giftCoinAmount: $giftCoinAmount, status: $status, '
      'appAccountToken: [REDACTED])';
}

class AppleIapDeliveryAck {
  const AppleIapDeliveryAck({
    required this.orderNo,
    required this.transactionId,
    required this.deliveryState,
    required this.creditedGiftCoins,
    required this.finishAllowed,
  });

  final String orderNo;
  final String transactionId;
  final String deliveryState;
  final int creditedGiftCoins;
  final bool finishAllowed;

  bool get delivered =>
      deliveryState == 'DELIVERED' ||
      deliveryState == 'ALREADY_DELIVERED';
}

class AppleIapOrderStatus {
  const AppleIapOrderStatus({
    required this.orderNo,
    required this.status,
    required this.creditedGiftCoins,
    required this.finishAllowed,
    this.transactionId,
  });

  final String orderNo;
  final String status;
  final int creditedGiftCoins;
  final bool finishAllowed;
  final String? transactionId;

  bool get delivered => status == 'SUCCEEDED';
}

enum AppleIapFlowState {
  delivered,
  confirming,
  pending,
  canceled,
  failed,
  unavailable,
}

class AppleIapFlowResult {
  const AppleIapFlowResult._({
    required this.state,
    required this.orderNo,
    this.transactionId,
    this.message = '',
  });

  factory AppleIapFlowResult.delivered({
    required String orderNo,
    required String transactionId,
  }) => AppleIapFlowResult._(
    state: AppleIapFlowState.delivered,
    orderNo: orderNo,
    transactionId: transactionId,
    message: 'Apple 充值已由服务端确认到账',
  );

  factory AppleIapFlowResult.confirming({
    required String orderNo,
    String? transactionId,
  }) => AppleIapFlowResult._(
    state: AppleIapFlowState.confirming,
    orderNo: orderNo,
    transactionId: transactionId,
    message: 'Apple 交易正在等待服务端确认',
  );

  factory AppleIapFlowResult.pending({required String orderNo}) =>
      AppleIapFlowResult._(
        state: AppleIapFlowState.pending,
        orderNo: orderNo,
        message: 'Apple 交易待处理',
      );

  factory AppleIapFlowResult.canceled({required String orderNo}) =>
      AppleIapFlowResult._(
        state: AppleIapFlowState.canceled,
        orderNo: orderNo,
        message: '已取消 Apple 购买',
      );

  factory AppleIapFlowResult.failed({
    required String orderNo,
    required String message,
  }) => AppleIapFlowResult._(
    state: AppleIapFlowState.failed,
    orderNo: orderNo,
    message: message,
  );

  factory AppleIapFlowResult.unavailable({required String orderNo}) =>
      AppleIapFlowResult._(
        state: AppleIapFlowState.unavailable,
        orderNo: orderNo,
        message: '当前设备无法使用 Apple IAP',
      );

  final AppleIapFlowState state;
  final String orderNo;
  final String? transactionId;
  final String message;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
