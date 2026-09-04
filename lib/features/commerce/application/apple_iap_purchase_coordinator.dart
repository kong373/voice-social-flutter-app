import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

abstract interface class AppleIapBackendGateway {
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  });

  Future<AppleIapDeliveryAck> submitTransaction({
    required String orderNo,
    required String signedTransaction,
    required String requestId,
  });

  Future<AppleIapOrderStatus> queryOrderStatus(String orderNo);
}

class HttpAppleIapBackendGateway implements AppleIapBackendGateway {
  HttpAppleIapBackendGateway(this._apiClient);

  static const String _orderPath = '/app-economy-api/pay/apple/order';
  static const String _transactionPath =
      '/app-economy-api/pay/apple/transaction';
  static const String _statusPath =
      '/app-economy-api/pay/apple/order/status';

  final ApiClient _apiClient;

  @override
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _orderPath,
      headers: <String, String>{'X-Request-Id': requestId},
      body: <String, Object?>{'productId': productId},
    );
    final Map<String, Object?> data = _requireMap(
      response.data,
      'Apple 充值订单',
    );
    final AppleIapOrderBinding binding = AppleIapOrderBinding(
      orderNo: _requiredString(data, 'orderNo', 'Apple 充值订单'),
      productId: _requiredString(data, 'productId', 'Apple 充值订单'),
      storeProductId: _requiredString(
        data,
        'storeProductId',
        'Apple 充值订单',
      ),
      appAccountToken: _requiredUuid(
        data,
        'appAccountToken',
        'Apple 充值订单',
      ),
      amountMinor: _requiredPositiveInt(
        data,
        'amountMinor',
        'Apple 充值订单',
      ),
      giftCoinAmount: _requiredPositiveInt(
        data,
        'giftCoinAmount',
        'Apple 充值订单',
      ),
      status: _requiredString(data, 'status', 'Apple 充值订单').toUpperCase(),
    );
    if (binding.productId != productId ||
        (binding.status != 'CREATED' && binding.status != 'CONFIRMING')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 充值订单与当前商品或订单状态不一致',
      );
    }
    return binding;
  }

  @override
  Future<AppleIapDeliveryAck> submitTransaction({
    required String orderNo,
    required String signedTransaction,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _transactionPath,
      headers: <String, String>{'X-Request-Id': requestId},
      body: <String, Object?>{
        'orderNo': orderNo,
        'signedTransaction': signedTransaction,
      },
    );
    final Map<String, Object?> data = _requireMap(
      response.data,
      'Apple 交易确认',
    );
    final AppleIapDeliveryAck ack = AppleIapDeliveryAck(
      orderNo: _requiredString(data, 'orderNo', 'Apple 交易确认'),
      transactionId: _requiredString(
        data,
        'transactionId',
        'Apple 交易确认',
      ),
      deliveryState: _requiredString(
        data,
        'deliveryState',
        'Apple 交易确认',
      ).toUpperCase(),
      creditedGiftCoins: _requiredNonNegativeInt(
        data,
        'creditedGiftCoins',
        'Apple 交易确认',
      ),
      finishAllowed: _requiredBool(
        data,
        'finishAllowed',
        'Apple 交易确认',
      ),
    );
    if (!const <String>{
      'DELIVERED',
      'ALREADY_DELIVERED',
      'PENDING',
      'REJECTED',
    }.contains(ack.deliveryState)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 交易确认返回了未知交付状态',
      );
    }
    return ack;
  }

  @override
  Future<AppleIapOrderStatus> queryOrderStatus(String orderNo) async {
    final ApiResponse response = await _apiClient.get(
      _statusPath,
      query: <String, String>{'orderNo': orderNo},
    );
    final Map<String, Object?> data = _requireMap(
      response.data,
      'Apple 订单状态',
    );
    final AppleIapOrderStatus status = AppleIapOrderStatus(
      orderNo: _requiredString(data, 'orderNo', 'Apple 订单状态'),
      transactionId: _optionalString(data['transactionId']),
      status: _requiredString(data, 'status', 'Apple 订单状态').toUpperCase(),
      creditedGiftCoins: _requiredNonNegativeInt(
        data,
        'creditedGiftCoins',
        'Apple 订单状态',
      ),
      finishAllowed: _requiredBool(
        data,
        'finishAllowed',
        'Apple 订单状态',
      ),
    );
    if (!const <String>{
      'CREATED',
      'CONFIRMING',
      'PENDING',
      'SUCCEEDED',
      'FAILED',
      'CANCELLED',
    }.contains(status.status)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 订单状态返回了未知状态',
      );
    }
    return status;
  }

  static Map<String, Object?> _requireMap(Object? raw, String label) {
    if (raw is! Map) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应不是有效对象',
      );
    }
    return raw.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>(
        key.toString(),
        value,
      ),
    );
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final Object? raw = data[key];
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应缺少有效的 $key',
      );
    }
    return raw;
  }

  static String? _optionalString(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 订单状态包含无效交易号',
      );
    }
    return raw;
  }

  static String _requiredUuid(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final String value = _requiredString(data, key, label).toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应中的 $key 不是有效 UUID',
      );
    }
    return value;
  }

  static int _requiredPositiveInt(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final Object? raw = data[key];
    if (raw is! int || raw <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应中的 $key 必须为正整数',
      );
    }
    return raw;
  }

  static int _requiredNonNegativeInt(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final Object? raw = data[key];
    if (raw is! int || raw < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应中的 $key 必须为非负整数',
      );
    }
    return raw;
  }

  static bool _requiredBool(
    Map<String, Object?> data,
    String key,
    String label,
  ) {
    final Object? raw = data[key];
    if (raw is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label响应中的 $key 必须为布尔值',
      );
    }
    return raw;
  }
}

abstract interface class AppleIapBindingStore {
  Future<void> save(AppleIapOrderBinding binding);

  Future<AppleIapOrderBinding?> readByOrderNo(String orderNo);

  Future<AppleIapOrderBinding?> readByAppAccountToken(String token);

  Future<void> remove(AppleIapOrderBinding binding);
}

class SecureAppleIapBindingStore implements AppleIapBindingStore {
  SecureAppleIapBindingStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _orderPrefix = 'voice_social.apple_iap.order.';
  static const String _tokenPrefix = 'voice_social.apple_iap.token.';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save(AppleIapOrderBinding binding) async {
    final String value = jsonEncode(binding.toJson());
    await _storage.write(key: '$_orderPrefix${binding.orderNo}', value: value);
    await _storage.write(
      key: '$_tokenPrefix${binding.appAccountToken}',
      value: value,
    );
  }

  @override
  Future<AppleIapOrderBinding?> readByOrderNo(String orderNo) async =>
      _decode(await _storage.read(key: '$_orderPrefix$orderNo'));

  @override
  Future<AppleIapOrderBinding?> readByAppAccountToken(String token) async =>
      _decode(await _storage.read(key: '$_tokenPrefix${token.toLowerCase()}'));

  @override
  Future<void> remove(AppleIapOrderBinding binding) async {
    await _storage.delete(key: '$_orderPrefix${binding.orderNo}');
    await _storage.delete(
      key: '$_tokenPrefix${binding.appAccountToken}',
    );
  }

  static AppleIapOrderBinding? _decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AppleIapOrderBinding.fromJson(
        decoded.map<String, Object?>(
          (Object? key, Object? value) => MapEntry<String, Object?>(
            key.toString(),
            value,
          ),
        ),
      );
    } on Object {
      return null;
    }
  }
}

class MemoryAppleIapBindingStore implements AppleIapBindingStore {
  final Map<String, AppleIapOrderBinding> _orders =
      <String, AppleIapOrderBinding>{};
  final Map<String, AppleIapOrderBinding> _tokens =
      <String, AppleIapOrderBinding>{};

  @override
  Future<void> save(AppleIapOrderBinding binding) async {
    _orders[binding.orderNo] = binding;
    _tokens[binding.appAccountToken] = binding;
  }

  @override
  Future<AppleIapOrderBinding?> readByOrderNo(String orderNo) async =>
      _orders[orderNo];

  @override
  Future<AppleIapOrderBinding?> readByAppAccountToken(String token) async =>
      _tokens[token.toLowerCase()];

  @override
  Future<void> remove(AppleIapOrderBinding binding) async {
    _orders.remove(binding.orderNo);
    _tokens.remove(binding.appAccountToken);
  }

  Map<String, Object?> debugSnapshot() => <String, Object?>{
    'orders': _orders.keys.toList(growable: false),
    'tokens': _tokens.keys.toList(growable: false),
  };
}

class AppleIapPurchaseCoordinator {
  AppleIapPurchaseCoordinator({
    required AppleIapBackendGateway backend,
    required AppleIapStoreKit2Adapter storeKit,
    required AppleIapBindingStore bindingStore,
  }) : _backend = backend,
       _storeKit = storeKit,
       _bindingStore = bindingStore;

  final AppleIapBackendGateway _backend;
  final AppleIapStoreKit2Adapter _storeKit;
  final AppleIapBindingStore _bindingStore;
  final Map<String, Future<AppleIapOrderBinding>> _orderFlights =
      <String, Future<AppleIapOrderBinding>>{};
  final Map<String, String> _orderRequestIds = <String, String>{};
  final Map<String, Future<AppleIapFlowResult>> _transactionFlights =
      <String, Future<AppleIapFlowResult>>{};
  StreamSubscription<AppleIapTransaction>? _updatesSubscription;
  bool _authenticatedSessionActive = false;
  bool _disposed = false;

  static final Random _secureRandom = Random.secure();
  static int _orderNonce = 0;

  Future<bool> get isAvailable => _storeKit.isAvailable();

  Future<void> activateAuthenticatedSession() async {
    _ensureNotDisposed();
    if (!_authenticatedSessionActive) {
      _authenticatedSessionActive = true;
      _updatesSubscription = _storeKit.transactionUpdates.listen(
        (AppleIapTransaction transaction) {
          unawaited(_recoverTransaction(transaction));
        },
        onError: (Object _) {
          // The transaction remains unfinished. A later activation or explicit
          // restore retries it without granting local payment authority.
        },
      );
    }
    try {
      await restoreUnfinishedTransactions();
    } on Object {
      // Recovery is best effort while the session or native bridge is
      // temporarily unavailable. StoreKit retains every unfinished purchase.
    }
  }

  Future<AppleIapOrderBinding> createOrder(String productId) {
    _ensureAuthenticated();
    final String normalized = productId.trim();
    if (normalized.isEmpty || normalized != productId) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'Apple 充值商品 ID 无效',
      );
    }
    final Future<AppleIapOrderBinding>? active = _orderFlights[normalized];
    if (active != null) {
      return active;
    }
    final String requestId = _orderRequestIds.putIfAbsent(
      normalized,
      _newOrderRequestId,
    );
    late final Future<AppleIapOrderBinding> operation;
    operation = _backend
        .createOrder(productId: normalized, requestId: requestId)
        .then((AppleIapOrderBinding binding) async {
          if (binding.productId != normalized) {
            throw const ApiException(
              kind: ApiFailureKind.protocol,
              message: 'Apple 订单商品与请求商品不一致',
            );
          }
          await _bindingStore.save(binding);
          _orderRequestIds.remove(normalized);
          return binding;
        })
        .whenComplete(() {
          if (identical(_orderFlights[normalized], operation)) {
            _orderFlights.remove(normalized);
          }
        });
    _orderFlights[normalized] = operation;
    return operation;
  }

  Future<AppleIapFlowResult> purchaseOrder(String orderNo) async {
    _ensureAuthenticated();
    final AppleIapOrderBinding binding = await _requireBinding(orderNo);
    final List<AppleIapStoreProduct> products = await _storeKit.fetchProducts(
      <String>{binding.storeProductId},
    );
    if (products.length != 1 ||
        products.single.storeProductId != binding.storeProductId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'App Store 商品与服务端订单不一致',
      );
    }
    final AppleIapPurchaseResult purchase = await _storeKit.purchase(
      storeProductId: binding.storeProductId,
      appAccountToken: binding.appAccountToken,
    );
    final AppleIapTransaction? transaction = purchase.transaction;
    switch (purchase.state) {
      case AppleIapPurchaseState.verified:
      case AppleIapPurchaseState.unverified:
        if (transaction == null) {
          return AppleIapFlowResult.failed(
            orderNo: binding.orderNo,
            message: 'StoreKit 未返回可供服务端验证的交易',
          );
        }
        return _processTransaction(binding, transaction);
      case AppleIapPurchaseState.pending:
        return AppleIapFlowResult.pending(orderNo: binding.orderNo);
      case AppleIapPurchaseState.canceled:
        return AppleIapFlowResult.canceled(orderNo: binding.orderNo);
      case AppleIapPurchaseState.failed:
        return AppleIapFlowResult.failed(
          orderNo: binding.orderNo,
          message: 'Apple 购买未完成，订单尚未到账',
        );
      case AppleIapPurchaseState.unavailable:
        return AppleIapFlowResult.unavailable(orderNo: binding.orderNo);
    }
  }

  Future<AppleIapOrderStatus> queryOrderStatus(String orderNo) async {
    _ensureAuthenticated();
    final AppleIapOrderBinding binding = await _requireBinding(orderNo);
    final AppleIapOrderStatus status = await _backend.queryOrderStatus(orderNo);
    if (status.orderNo != binding.orderNo ||
        status.creditedGiftCoins > binding.giftCoinAmount ||
        (status.delivered &&
            status.creditedGiftCoins != binding.giftCoinAmount) ||
        (!status.delivered && status.finishAllowed) ||
        ((status.delivered || status.finishAllowed) &&
            status.transactionId == null)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 订单状态与当前订单绑定不一致',
      );
    }
    if (status.delivered && status.finishAllowed) {
      final List<AppleIapTransaction> unfinished =
          await _storeKit.unfinishedTransactions();
      for (final AppleIapTransaction transaction in unfinished) {
        if (transaction.transactionId == status.transactionId) {
          await _processTransaction(binding, transaction);
          break;
        }
      }
    }
    return status;
  }

  Future<List<AppleIapFlowResult>> restoreUnfinishedTransactions({
    bool synchronize = false,
  }) async {
    _ensureAuthenticated();
    if (synchronize) {
      await _storeKit.synchronize();
    }
    final List<AppleIapTransaction> unfinished =
        await _storeKit.unfinishedTransactions();
    final List<AppleIapFlowResult> results = <AppleIapFlowResult>[];
    for (final AppleIapTransaction transaction in unfinished) {
      results.add(await _recoverTransaction(transaction));
    }
    return results;
  }

  Future<AppleIapFlowResult> _recoverTransaction(
    AppleIapTransaction transaction,
  ) async {
    if (!_authenticatedSessionActive || _disposed) {
      return AppleIapFlowResult.pending(orderNo: '');
    }
    final String? appAccountToken = transaction.appAccountToken;
    if (appAccountToken == null) {
      return AppleIapFlowResult.pending(orderNo: '');
    }
    final AppleIapOrderBinding? binding = await _bindingStore
        .readByAppAccountToken(appAccountToken);
    if (binding == null) {
      // Never guess an order or finish an unbound transaction.
      return AppleIapFlowResult.pending(orderNo: '');
    }
    return _processTransaction(binding, transaction);
  }

  Future<AppleIapFlowResult> _processTransaction(
    AppleIapOrderBinding binding,
    AppleIapTransaction transaction,
  ) {
    final Future<AppleIapFlowResult>? active =
        _transactionFlights[transaction.transactionId];
    if (active != null) {
      return active;
    }
    late final Future<AppleIapFlowResult> operation;
    operation = _processTransactionOnce(binding, transaction).whenComplete(() {
      if (identical(
        _transactionFlights[transaction.transactionId],
        operation,
      )) {
        _transactionFlights.remove(transaction.transactionId);
      }
    });
    _transactionFlights[transaction.transactionId] = operation;
    return operation;
  }

  Future<AppleIapFlowResult> _processTransactionOnce(
    AppleIapOrderBinding binding,
    AppleIapTransaction transaction,
  ) async {
    if (transaction.storeProductId != binding.storeProductId ||
        transaction.appAccountToken != binding.appAccountToken ||
        transaction.signedTransaction.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易与第一方订单绑定不一致',
      );
    }
    try {
      final AppleIapDeliveryAck ack = await _backend.submitTransaction(
        orderNo: binding.orderNo,
        signedTransaction: transaction.signedTransaction,
        requestId: _transactionRequestId(transaction.transactionId),
      );
      if (ack.orderNo != binding.orderNo ||
          ack.transactionId != transaction.transactionId ||
          ack.creditedGiftCoins > binding.giftCoinAmount ||
          (ack.delivered && ack.creditedGiftCoins != binding.giftCoinAmount) ||
          (!ack.delivered && ack.creditedGiftCoins != 0) ||
          (!ack.delivered && ack.finishAllowed)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'Apple 交易确认回包与订单或交易不一致',
        );
      }
      if (ack.delivered && ack.finishAllowed) {
        final bool finished = await _storeKit.finish(transaction.transactionId);
        if (!finished) {
          return AppleIapFlowResult.confirming(
            orderNo: binding.orderNo,
            transactionId: transaction.transactionId,
          );
        }
        await _bindingStore.remove(binding);
        return AppleIapFlowResult.delivered(
          orderNo: binding.orderNo,
          transactionId: transaction.transactionId,
        );
      }
      return AppleIapFlowResult.confirming(
        orderNo: binding.orderNo,
        transactionId: transaction.transactionId,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.protocol ||
          error.kind == ApiFailureKind.validation ||
          error.kind == ApiFailureKind.conflict) {
        rethrow;
      }
      return AppleIapFlowResult.confirming(
        orderNo: binding.orderNo,
        transactionId: transaction.transactionId,
      );
    } on Object {
      return AppleIapFlowResult.confirming(
        orderNo: binding.orderNo,
        transactionId: transaction.transactionId,
      );
    }
  }

  Future<AppleIapOrderBinding> _requireBinding(String orderNo) async {
    final String normalized = orderNo.trim();
    if (normalized.isEmpty || normalized != orderNo) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'Apple 订单号无效',
      );
    }
    final AppleIapOrderBinding? binding = await _bindingStore.readByOrderNo(
      normalized,
    );
    if (binding == null) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '本机没有可恢复的 Apple 订单绑定',
      );
    }
    return binding;
  }

  static String _newOrderRequestId() {
    _orderNonce = (_orderNonce + 1) & 0x7fffffff;
    final String micros = DateTime.now().microsecondsSinceEpoch.toRadixString(
      36,
    );
    final String random = _secureRandom.nextInt(0x7fffffff).toRadixString(36);
    return 'apple-iap-order-$micros-$random-${_orderNonce.toRadixString(36)}';
  }

  static String _transactionRequestId(String transactionId) {
    final String digest = sha256
        .convert(utf8.encode('apple-iap-transaction:$transactionId'))
        .toString();
    return 'apple-iap-transaction-${digest.substring(0, 40)}';
  }

  void _ensureAuthenticated() {
    _ensureNotDisposed();
    if (!_authenticatedSessionActive) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '登录会话尚未恢复，不能处理 Apple 交易',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AppleIapPurchaseCoordinator has been disposed');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _authenticatedSessionActive = false;
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
  }
}
