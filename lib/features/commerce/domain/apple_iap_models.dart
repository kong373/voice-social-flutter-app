enum AppleIapAvailability {
  available,
  paymentsDisabled,
  unsupportedOs,
  unsupportedPlatform,
  unavailable,
}

class AppleIapAvailabilityStatus {
  const AppleIapAvailabilityStatus({
    required this.state,
    this.minimumOsVersion = '15.0',
  });

  final AppleIapAvailability state;
  final String minimumOsVersion;

  bool get canMakePayments => state == AppleIapAvailability.available;
}

class AppleStoreProduct {
  const AppleStoreProduct({
    required this.id,
    required this.displayName,
    required this.description,
    required this.displayPrice,
    required this.productType,
  });

  final String id;
  final String displayName;
  final String description;
  final String displayPrice;
  final String productType;

  bool get isConsumable => productType.toLowerCase() == 'consumable';
}

enum AppleIapVerification { verified, unverified }

enum AppleIapTransactionSource { purchase, updates, unfinished }

class AppleIapTransaction {
  const AppleIapTransaction({
    required this.transactionId,
    required this.originalTransactionId,
    required this.productId,
    required this.appAccountToken,
    required this.purchaseDate,
    required this.signedTransaction,
    required this.verification,
    required this.source,
  });

  final String transactionId;
  final String originalTransactionId;
  final String productId;
  final String? appAccountToken;
  final DateTime purchaseDate;

  /// Apple-signed JWS held only in memory while the authenticated backend
  /// verifies and records the transaction. It must never be logged or used by
  /// the client as delivery authority.
  final String signedTransaction;
  final AppleIapVerification verification;
  final AppleIapTransactionSource source;
}

enum AppleIapPurchaseOutcome {
  transaction,
  pending,
  userCancelled,
  failed,
  unavailable,
}

class AppleIapPurchaseResult {
  const AppleIapPurchaseResult({
    required this.outcome,
    this.transaction,
    this.reason = '',
  });

  final AppleIapPurchaseOutcome outcome;
  final AppleIapTransaction? transaction;
  final String reason;
}

class AppleIapCatalogItem {
  const AppleIapCatalogItem({
    required this.productId,
    required this.storeProductId,
    required this.giftCoins,
    required this.priceCny,
    required this.enabled,
    this.amountMinor,
    this.bonusGiftCoins = 0,
    this.label = '',
    this.recommended = false,
  });

  final String productId;
  final String storeProductId;
  final int giftCoins;
  final double priceCny;
  final int? amountMinor;
  final int bonusGiftCoins;
  final String label;
  final bool recommended;
  final bool enabled;
}

class AppleIapCatalog {
  const AppleIapCatalog({
    required this.orderCreationReady,
    required this.items,
  });

  final bool orderCreationReady;
  final List<AppleIapCatalogItem> items;
}

class AppleIapOrderBinding {
  const AppleIapOrderBinding({
    required this.orderNo,
    required this.storeProductId,
    required this.appAccountToken,
    required this.environment,
    required this.status,
    required this.createdAt,
  });

  final String orderNo;
  final String storeProductId;
  final String appAccountToken;
  final String environment;
  final String status;
  final DateTime createdAt;
}

enum AppleIapDeliveryState {
  delivered,
  alreadyDelivered,
  pending,
  rejected,
}

extension AppleIapDeliveryStateX on AppleIapDeliveryState {
  bool get delivered =>
      this == AppleIapDeliveryState.delivered ||
      this == AppleIapDeliveryState.alreadyDelivered;
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
  final AppleIapDeliveryState deliveryState;
  final int creditedGiftCoins;
  final bool finishAllowed;

  bool get delivered => deliveryState.delivered;
}

class AppleIapOrderStatus {
  const AppleIapOrderStatus({
    required this.orderNo,
    required this.status,
    required this.creditedGiftCoins,
    required this.finishAllowed,
    this.transactionId,
    this.environment,
  });

  final String orderNo;
  final String status;
  final int creditedGiftCoins;
  final bool finishAllowed;
  final String? transactionId;
  final String? environment;
}

class AppleIapRecoveryResult {
  const AppleIapRecoveryResult({
    required this.observed,
    required this.delivered,
    required this.finished,
    required this.deferred,
  });

  final int observed;
  final int delivered;
  final int finished;
  final int deferred;
}
