import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/commerce/data/apple_iap_purchase_journal.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

abstract interface class AppleIapBackendPort {
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  });

  Future<AppleIapDeliveryAck> deliverTransaction({
    required String? orderNo,
    required AppleIapTransaction transaction,
    required String requestId,
  });

  Future<AppleIapOrderStatus> readOrderStatus(String orderNo);
}

/// Coordinates StoreKit 2 with the first-party backend authority.
///
/// Native verification is useful diagnostic evidence, but it never credits a
/// wallet and never authorizes `Transaction.finish()`. The signed JWS is sent
/// to the backend, and the native transaction remains unfinished across every
/// timeout, protocol error, or non-delivered response.
class AppleIapPurchaseCoordinator {
  AppleIapPurchaseCoordinator({
    required AppleIapStoreKit2Adapter storeKit,
    required AppleIapBackendPort backend,
    required Object? Function() authenticatedSession,
    required String? Function() authenticatedAccount,
    required KeyValueStore purchaseStore,
  }) : _storeKit = storeKit,
       _backend = backend,
       _authenticatedSession = authenticatedSession,
       _authenticatedAccount = authenticatedAccount,
       _journal = AppleIapPurchaseJournal(purchaseStore);

  final AppleIapPurchaseJournal _journal;
  final Set<String> _loadedAccounts = <String>{};
  final Map<(String, Object), Future<void>> _journalLoads =
      <(String, Object), Future<void>>{};
  final Set<String> _attemptedOrders = <String>{};
  final Map<String, String> _terminalOrders = <String, String>{};

  final AppleIapStoreKit2Adapter _storeKit;
  final AppleIapBackendPort _backend;
  final Object? Function() _authenticatedSession;
  final String? Function() _authenticatedAccount;
  final Map<String, String> _orderOwners = <String, String>{};
  final Map<String, (Object, AppleIapOrderBinding)> _boundOrders =
      <String, (Object, AppleIapOrderBinding)>{};
  final Map<(Object, String), Future<AppleIapPurchaseFlow>> _deliveries =
      <(Object, String), Future<AppleIapPurchaseFlow>>{};
  final Map<Object, Future<AppleIapRecoveryResult>> _recoveries =
      <Object, Future<AppleIapRecoveryResult>>{};
  final Map<String, AppleIapOrderBinding> _unresolvedOrders =
      <String, AppleIapOrderBinding>{};
  final Map<String, Future<AppleIapPurchaseFlow>> _purchaseFlights =
      <String, Future<AppleIapPurchaseFlow>>{};
  StreamSubscription<AppleIapTransaction>? _updatesSubscription;
  bool _disposed = false;

  bool get isPlatformSupported => _storeKit.isPlatformSupported;

  Future<AppleIapAvailabilityStatus> availability() => _storeKit.availability();

  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  }) async {
    final Object session = _captureSession();
    await _restoreJournal(session);
    _requireSession(session);
    if (_unresolvedOrders.isNotEmpty) {
      for (final AppleIapOrderBinding pending in _unresolvedOrders.values) {
        if (pending.productId == productId &&
            _orderOwners[pending.orderNo] == _authenticatedAccount()) {
          _boundOrders[pending.orderNo] = (session, pending);
          return pending;
        }
      }
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '仍有待确认的 Apple 购买，请先恢复原交易，不要重复下单',
      );
    }
    final AppleIapOrderBinding order = await _backend.createOrder(
      productId: productId,
      requestId: requestId,
    );
    _requireSession(session);
    _boundOrders[order.orderNo] = (session, order);
    _orderOwners[order.orderNo] = _authenticatedAccount()!;
    return order;
  }

  Future<List<AppleStoreProduct>> validateProducts(
    List<String> productIds,
  ) async {
    final AppleIapAvailabilityStatus status = await _storeKit.availability();
    if (!status.canMakePayments) {
      return const <AppleStoreProduct>[];
    }
    final List<AppleStoreProduct> products = await _storeKit.loadProducts(
      productIds,
    );
    final Set<String> expected = productIds.toSet();
    final Set<String> actual = products
        .map((AppleStoreProduct product) => product.id)
        .toSet();
    if (products.length != productIds.length || !actual.containsAll(expected)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 商品目录与服务端配置不一致',
      );
    }
    return products;
  }

  Future<AppleIapPurchaseFlow> purchase(AppleIapOrderBinding binding) async {
    final Object session = _captureSession();
    final (Object, AppleIapOrderBinding)? created =
        _boundOrders[binding.orderNo];
    if (created == null ||
        !identical(created.$1, session) ||
        created.$2.productId != binding.productId ||
        created.$2.storeProductId != binding.storeProductId ||
        created.$2.appAccountToken != binding.appAccountToken ||
        created.$2.amountMinor != binding.amountMinor ||
        created.$2.giftCoinAmount != binding.giftCoinAmount) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: 'Apple 订单不属于当前购买会话，请恢复已有交易',
      );
    }
    final Future<AppleIapPurchaseFlow>? pending =
        _purchaseFlights[binding.orderNo];
    if (pending != null) {
      return pending;
    }
    late final Future<AppleIapPurchaseFlow> operation;
    operation = _purchaseOnce(binding, session).whenComplete(() {
      if (identical(_purchaseFlights[binding.orderNo], operation)) {
        _purchaseFlights.remove(binding.orderNo);
      }
    });
    _purchaseFlights[binding.orderNo] = operation;
    return operation;
  }

  Future<AppleIapPurchaseFlow> _purchaseOnce(
    AppleIapOrderBinding binding,
    Object session,
  ) async {
    if (_terminalOrders[binding.orderNo] == 'CANCELLED_CONFIRMED') {
      return const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.userCancelled,
        reason: 'user_cancelled',
      );
    }
    if (_attemptedOrders.contains(binding.orderNo)) {
      final AppleIapStoreKit2Adapter adapter = _storeKit;
      final AppleIapPurchaseResult? retained =
          adapter is AppleIapPendingPurchaseRecovery
          ? await (adapter as AppleIapPendingPurchaseRecovery)
                .readRetainedPurchaseOutcome(
                  productId: binding.storeProductId,
                  appAccountToken: binding.appAccountToken,
                )
          : null;
      _requireSession(session);
      if (retained != null) {
        return _consumePurchaseOutcome(binding, session, retained);
      }
      // Empty unfinished does not prove that the original attempt was cancelled.
      return const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.awaitingBackend,
        reason: 'original_purchase_requires_recovery',
      );
    }
    final List<AppleStoreProduct> products = await validateProducts(<String>[
      binding.storeProductId,
    ]);
    _requireSession(session);
    if (products.length != 1 || !products.single.isConsumable) {
      return const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.unavailable,
        reason: 'store_product_unavailable',
      );
    }
    requireCatalogPrice(products.single, binding.amountMinor);
    // Storage must succeed before a native attempt; no JWS is persisted here.
    final String account = _authenticatedAccount()!;
    try {
      await _journal.start(account, binding);
    } catch (_) {
      // A platform storage call can fail after persisting. Re-read before any
      // subsequent order rather than assuming no durable attempt exists.
      _loadedAccounts.remove(account);
      rethrow;
    }
    _attemptedOrders.add(binding.orderNo);
    _unresolvedOrders[binding.orderNo] = binding;
    _requireSession(session);
    final AppleIapPurchaseResult result;
    try {
      result = await _storeKit.purchase(
        productId: binding.storeProductId,
        appAccountToken: binding.appAccountToken,
      );
    } catch (_) {
      _requireSession(session);
      return const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.awaitingBackend,
        reason: 'native_purchase_outcome_unknown',
      );
    }
    _requireSession(session);
    return _consumePurchaseOutcome(binding, session, result);
  }

  Future<AppleIapPurchaseFlow> _consumePurchaseOutcome(
    AppleIapOrderBinding binding,
    Object session,
    AppleIapPurchaseResult result,
  ) async {
    _requireSession(session);
    if (result.outcome == AppleIapPurchaseOutcome.userCancelled) {
      await _markTerminal(binding.orderNo, 'CANCELLED_CONFIRMED', session);
    }
    return switch (result.outcome) {
      AppleIapPurchaseOutcome.transaction => _deliver(
        result.transaction!,
        expectedBinding: binding,
        expectedSession: session,
      ),
      AppleIapPurchaseOutcome.pending => const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.pending,
        reason: 'storekit_pending',
      ),
      AppleIapPurchaseOutcome.userCancelled => const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.userCancelled,
        reason: 'user_cancelled',
      ),
      AppleIapPurchaseOutcome.failed ||
      AppleIapPurchaseOutcome.unavailable => const AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.awaitingBackend,
        reason: 'native_purchase_outcome_unknown',
      ),
    };
  }

  Future<AppleIapOrderStatus> readOrderStatus(String orderNo) async {
    final Object session = _captureSession();
    final AppleIapOrderStatus status = await _backend.readOrderStatus(orderNo);
    _requireSession(session);
    return status;
  }

  /// This release's first-party catalog settles CNY only. Do not let an App
  /// Store storefront/price mismatch charge money that the backend must reject.
  static void requireCatalogPrice(AppleStoreProduct product, int amountMinor) {
    if (!product.isConsumable ||
        amountMinor <= 0 ||
        amountMinor > 99999999999 ||
        product.currencyCode != 'CNY' ||
        product.priceMilliunits != amountMinor * 10) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: 'Apple 商品币种或价格与服务端目录不一致，暂不能购买',
      );
    }
  }

  /// Starts one process-scoped listener. Update failures are deliberately
  /// retained by StoreKit and retried by [recoverUnfinished] after sign-in.
  void startListening() {
    if (_disposed ||
        _updatesSubscription != null ||
        !_storeKit.isPlatformSupported) {
      return;
    }
    _updatesSubscription = _storeKit.transactionUpdates.listen(
      (AppleIapTransaction transaction) {
        unawaited(_deliverUpdate(transaction));
      },
      onError: (_) {
        // The native stream is not a delivery authority. StoreKit keeps every
        // unfinished transaction available to the explicit recovery pass.
      },
    );
  }

  Future<void> _deliverUpdate(AppleIapTransaction transaction) async {
    try {
      await _restoreJournal(_captureSession());
      await _deliver(transaction, expectedBinding: null);
    } catch (_) {
      // Never finish on an ambiguous backend outcome. StoreKit owns the
      // durable unfinished transaction and the next authenticated recovery.
    }
  }

  Future<AppleIapRecoveryResult> recoverUnfinished({
    bool synchronizeStore = false,
  }) {
    final Object session = _captureSession();
    final Future<AppleIapRecoveryResult>? pending = _recoveries[session];
    if (pending != null) {
      return pending;
    }
    late final Future<AppleIapRecoveryResult> operation;
    operation = _recoverUnfinished(session, synchronizeStore: synchronizeStore)
        .whenComplete(() {
          if (identical(_recoveries[session], operation)) {
            _recoveries.remove(session);
          }
        });
    _recoveries[session] = operation;
    return operation;
  }

  Future<AppleIapRecoveryResult> _recoverUnfinished(
    Object session, {
    required bool synchronizeStore,
  }) async {
    await _restoreJournal(session);
    if (!_storeKit.isPlatformSupported) {
      return const AppleIapRecoveryResult(
        observed: 0,
        delivered: 0,
        finished: 0,
        deferred: 0,
      );
    }
    // Late explicit cancellation is read without starting another purchase.
    final AppleIapStoreKit2Adapter adapter = _storeKit;
    if (adapter is AppleIapPendingPurchaseRecovery) {
      for (final AppleIapOrderBinding order in List<AppleIapOrderBinding>.of(
        _unresolvedOrders.values,
      )) {
        if (_orderOwners[order.orderNo] != _authenticatedAccount()) {
          continue;
        }
        final AppleIapPurchaseResult? retained =
            await (adapter as AppleIapPendingPurchaseRecovery)
                .readRetainedPurchaseOutcome(
                  productId: order.storeProductId,
                  appAccountToken: order.appAccountToken,
                );
        _requireSession(session);
        if (retained?.outcome == AppleIapPurchaseOutcome.userCancelled) {
          await _markTerminal(order.orderNo, 'CANCELLED_CONFIRMED', session);
        }
      }
    }
    final List<AppleIapTransaction> transactions = await _storeKit
        .recoverUnfinished(synchronizeStore: synchronizeStore);
    _requireSession(session);
    final Set<String> seen = <String>{};
    int delivered = 0;
    int finished = 0;
    int deferred = 0;
    for (final AppleIapTransaction transaction in transactions) {
      if (!seen.add(transaction.transactionId)) {
        continue;
      }
      try {
        final AppleIapPurchaseFlow result = await _deliver(
          transaction,
          expectedBinding: null,
          expectedSession: session,
        );
        if (result.state == AppleIapPurchaseFlowState.delivered) {
          delivered += 1;
          if (result.reason == 'native_finish_deferred') {
            deferred += 1;
          } else {
            finished += 1;
          }
        } else {
          deferred += 1;
        }
      } catch (_) {
        deferred += 1;
      }
    }
    deferred += _unresolvedOrders.values
        .where(
          (AppleIapOrderBinding order) =>
              _orderOwners[order.orderNo] == _authenticatedAccount() &&
              !transactions.any(
                (AppleIapTransaction transaction) =>
                    transaction.appAccountToken == order.appAccountToken &&
                    transaction.productId == order.storeProductId,
              ),
        )
        .length;
    return AppleIapRecoveryResult(
      observed: transactions.length,
      delivered: delivered,
      finished: finished,
      deferred: deferred,
    );
  }

  Future<AppleIapPurchaseFlow> _deliver(
    AppleIapTransaction transaction, {
    required AppleIapOrderBinding? expectedBinding,
    Object? expectedSession,
  }) {
    final Object session = expectedSession ?? _captureSession();
    _requireSession(session);
    AppleIapOrderBinding? effectiveBinding = expectedBinding;
    if (effectiveBinding == null) {
      for (final (Object, AppleIapOrderBinding) bound in _boundOrders.values) {
        if (_orderOwners[bound.$2.orderNo] == _authenticatedAccount() &&
            bound.$2.appAccountToken == transaction.appAccountToken) {
          effectiveBinding = bound.$2;
          break;
        }
      }
    }
    if (effectiveBinding != null &&
        (transaction.productId != effectiveBinding.storeProductId ||
            transaction.appAccountToken != effectiveBinding.appAccountToken)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易与服务端订单绑定不一致',
      );
    }
    final (Object, String) key = (session, transaction.transactionId);
    final Future<AppleIapPurchaseFlow>? pending = _deliveries[key];
    if (pending != null) {
      return pending;
    }
    late final Future<AppleIapPurchaseFlow> operation;
    operation =
        _deliverOnce(
          transaction,
          expectedBinding: effectiveBinding,
          expectedSession: session,
        ).whenComplete(() {
          if (identical(_deliveries[key], operation)) {
            _deliveries.remove(key);
          }
        });
    _deliveries[key] = operation;
    return operation;
  }

  Future<AppleIapPurchaseFlow> _deliverOnce(
    AppleIapTransaction transaction, {
    required AppleIapOrderBinding? expectedBinding,
    required Object expectedSession,
  }) async {
    final AppleIapDeliveryAck ack = await _backend.deliverTransaction(
      orderNo: expectedBinding?.orderNo,
      transaction: transaction,
      requestId: _deliveryRequestId(transaction.transactionId),
    );
    _requireSession(expectedSession);
    final AppleIapOrderBinding? localBinding =
        expectedBinding ?? _boundOrders[ack.orderNo]?.$2;
    if (localBinding == null) {
      // The backend may resolve/credit a recovered JWS, but a missing local
      // snapshot is not proof that our order/price/coin finish gate passed.
      return AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.awaitingBackend,
        deliveryAck: ack,
        reason: 'recovery_binding_missing',
      );
    }
    if (ack.transactionId != transaction.transactionId ||
        ack.orderNo != localBinding.orderNo ||
        _orderOwners[localBinding.orderNo] != _authenticatedAccount() ||
        localBinding.storeProductId != transaction.productId ||
        localBinding.appAccountToken != transaction.appAccountToken ||
        (ack.delivered &&
            ack.creditedGiftCoins != localBinding.giftCoinAmount) ||
        (ack.finishAllowed && !ack.delivered)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 交易服务端确认响应不一致',
      );
    }
    if (ack.delivered && ack.finishAllowed) {
      await _markTerminal(ack.orderNo, 'DELIVERED', expectedSession);
      bool finished = false;
      try {
        finished = await _storeKit.finish(transaction.transactionId);
      } catch (_) {
        // Financial delivery stays confirmed; only native cleanup retries.
      }
      _requireSession(expectedSession);
      if (finished) {
        try {
          await _journal.markTerminal(
            _authenticatedAccount()!,
            ack.orderNo,
            'FINISHED',
            stillCurrent: () =>
                !_disposed &&
                identical(_authenticatedSession(), expectedSession),
          );
        } catch (_) {
          // Retain DELIVERED on disk if cleanup bookkeeping fails; never
          // downgrade financial delivery or invoke another native purchase.
        }
        _requireSession(expectedSession);
        _unresolvedOrders.remove(ack.orderNo);
        return AppleIapPurchaseFlow(
          state: AppleIapPurchaseFlowState.delivered,
          deliveryAck: ack,
        );
      }
      return AppleIapPurchaseFlow(
        state: AppleIapPurchaseFlowState.delivered,
        deliveryAck: ack,
        reason: 'native_finish_deferred',
      );
    }
    return AppleIapPurchaseFlow(
      state: ack.deliveryState == AppleIapDeliveryState.rejected
          ? AppleIapPurchaseFlowState.failed
          : AppleIapPurchaseFlowState.awaitingBackend,
      deliveryAck: ack,
      reason: ack.deliveryState.name,
    );
  }

  Future<void> _restoreJournal(Object session) async {
    _requireSession(session);
    final String account = _authenticatedAccount()!;
    if (_loadedAccounts.contains(account)) {
      return;
    }
    final key = (account, session);
    final Future<void>? pending = _journalLoads[key];
    if (pending != null) {
      return pending;
    }
    late final Future<void> operation;
    operation = _loadJournal(account, session).whenComplete(() {
      if (identical(_journalLoads[key], operation)) {
        _journalLoads.remove(key);
      }
    });
    _journalLoads[key] = operation;
    await operation;
  }

  Future<void> _loadJournal(String account, Object session) async {
    final List<AppleIapJournalEntry> entries = await _journal.readAll(account);
    _requireSession(session);
    for (final entry in entries) {
      final AppleIapOrderBinding binding = entry.binding;
      _orderOwners[binding.orderNo] = account;
      _boundOrders[binding.orderNo] = (session, binding);
      _attemptedOrders.add(binding.orderNo);
      if (entry.state == 'ATTEMPTED') {
        _unresolvedOrders[binding.orderNo] = binding;
      } else {
        _terminalOrders[binding.orderNo] = entry.state;
      }
    }
    _loadedAccounts.add(account);
  }

  Future<void> _markTerminal(
    String orderNo,
    String state,
    Object session,
  ) async {
    _requireSession(session);
    final String account = _authenticatedAccount()!;
    await _journal.markTerminal(
      account,
      orderNo,
      state,
      stillCurrent: () =>
          !_disposed && identical(_authenticatedSession(), session),
    );
    _requireSession(session);
    if (_terminalOrders[orderNo] != 'DELIVERED') {
      _terminalOrders[orderNo] = state;
    }
    _unresolvedOrders.remove(orderNo);
  }

  static String _deliveryRequestId(String transactionId) {
    final String digest = sha256
        .convert(utf8.encode('voice-social:apple-iap-delivery:$transactionId'))
        .toString();
    return 'apple-tx-$digest';
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('Apple IAP coordinator is disposed');
    }
  }

  Object _captureSession() {
    _ensureActive();
    final Object? session = _authenticatedSession();
    if (session == null || _authenticatedAccount()?.isNotEmpty != true) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '请先登录后恢复 Apple 交易',
      );
    }
    return session;
  }

  void _requireSession(Object expected) {
    _ensureActive();
    if (!identical(_authenticatedSession(), expected)) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录会话已变化，Apple 交易将在重新登录后恢复',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
  }
}
