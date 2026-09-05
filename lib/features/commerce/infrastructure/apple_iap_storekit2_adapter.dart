import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

typedef AppleIapMethodInvoker =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

abstract interface class AppleIapStoreKit2Adapter {
  bool get isPlatformSupported;

  Stream<AppleIapTransaction> get transactionUpdates;

  Future<AppleIapAvailabilityStatus> availability();

  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds);

  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  });

  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  });

  /// Completes a StoreKit transaction after the backend has acknowledged
  /// delivery. Callers must never invoke this before a `DELIVERED` or
  /// `ALREADY_DELIVERED` response with `finishAllowed=true`.
  Future<bool> finish(String transactionId);
}

/// Optional recovery capability. It never starts or retries a native
/// purchase; existing adapter fakes do not need to implement it.
abstract interface class AppleIapPendingPurchaseRecovery {
  Future<AppleIapPurchaseResult?> readRetainedPurchaseOutcome({
    required String productId,
    required String appAccountToken,
  });
}

class DisabledAppleIapStoreKit2Adapter implements AppleIapStoreKit2Adapter {
  const DisabledAppleIapStoreKit2Adapter();

  @override
  bool get isPlatformSupported => false;

  @override
  Stream<AppleIapTransaction> get transactionUpdates =>
      const Stream<AppleIapTransaction>.empty();

  @override
  Future<AppleIapAvailabilityStatus> availability() async =>
      const AppleIapAvailabilityStatus(
        state: AppleIapAvailability.unsupportedPlatform,
      );

  @override
  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds) async =>
      const <AppleStoreProduct>[];

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async => const AppleIapPurchaseResult(
    outcome: AppleIapPurchaseOutcome.unavailable,
    reason: 'unsupported_platform',
  );

  @override
  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  }) async => const <AppleIapTransaction>[];

  @override
  Future<bool> finish(String transactionId) async => false;
}

class MethodChannelAppleIapStoreKit2Adapter
    implements AppleIapStoreKit2Adapter, AppleIapPendingPurchaseRecovery {
  MethodChannelAppleIapStoreKit2Adapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    AppleIapMethodInvoker? invoker,
    Stream<Object?>? transactionEventStream,
    bool Function()? isIos,
    Duration nativeTimeout = const Duration(seconds: 45),
  }) : _methodChannel = methodChannel ?? _defaultMethodChannel,
       _eventChannel = eventChannel ?? _defaultEventChannel,
       _invoker = invoker,
       _transactionEventStream = transactionEventStream,
       _isIos = isIos ?? _defaultIsIos,
       _nativeTimeout = nativeTimeout {
    if (nativeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        nativeTimeout,
        'nativeTimeout',
        'must be greater than zero',
      );
    }
  }

  static const MethodChannel _defaultMethodChannel = MethodChannel(
    'voice_social_app/apple_iap_storekit2',
  );
  static const EventChannel _defaultEventChannel = EventChannel(
    'voice_social_app/apple_iap_storekit2/transactions',
  );
  static const int _maximumProductCount = 100;
  static const int _maximumIdentifierLength = 255;
  static const int _maximumJwsLength = 128 * 1024;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final AppleIapMethodInvoker? _invoker;
  final Stream<Object?>? _transactionEventStream;
  final bool Function() _isIos;
  final Duration _nativeTimeout;
  final Map<(String, String), _AppleIapPurchaseFlight> _purchaseFlights =
      <(String, String), _AppleIapPurchaseFlight>{};
  final Map<(String, String), AppleIapPurchaseResult> _retainedPurchaseResults =
      <(String, String), AppleIapPurchaseResult>{};
  final Map<(String, String), _AppleIapPurchaseFailure>
  _retainedPurchaseFailures = <(String, String), _AppleIapPurchaseFailure>{};
  StreamController<AppleIapTransaction>? _transactionUpdatesController;
  StreamSubscription<Object?>? _transactionSourceSubscription;
  bool _transactionSourceIsBroadcast = false;
  final List<AppleIapTransaction> _lateTransactions = <AppleIapTransaction>[];

  @override
  bool get isPlatformSupported => _isIos();

  @override
  Stream<AppleIapTransaction> get transactionUpdates {
    if (!isPlatformSupported) {
      return const Stream<AppleIapTransaction>.empty();
    }
    return (_transactionUpdatesController ??=
            StreamController<AppleIapTransaction>.broadcast(
              onListen: _startTransactionUpdates,
              onCancel: _stopTransactionUpdates,
            ))
        .stream;
  }

  void _startTransactionUpdates() {
    if (_transactionSourceSubscription != null) {
      _flushLateTransactions();
      return;
    }
    final Stream<Object?> source =
        _transactionEventStream ?? _eventChannel.receiveBroadcastStream();
    _transactionSourceIsBroadcast = source.isBroadcast;
    _transactionSourceSubscription = source.listen(
      (Object? raw) {
        try {
          _emitTransaction(_parseTransaction(raw, expectedSource: null));
        } catch (error, stackTrace) {
          _transactionUpdatesController?.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _transactionUpdatesController?.addError(error, stackTrace);
      },
      onDone: () {
        _transactionSourceSubscription = null;
      },
    );
    _flushLateTransactions();
  }

  Future<void> _stopTransactionUpdates() async {
    // A test/injected single-subscription stream cannot be listened to again
    // after cancellation. Keep that one upstream subscription alive while the
    // adapter's broadcast listeners come and go; EventChannel's real stream is
    // broadcast and is cancelled normally.
    if (!_transactionSourceIsBroadcast) {
      return;
    }
    final StreamSubscription<Object?>? subscription =
        _transactionSourceSubscription;
    _transactionSourceSubscription = null;
    await subscription?.cancel();
  }

  void _flushLateTransactions() {
    final StreamController<AppleIapTransaction>? controller =
        _transactionUpdatesController;
    if (controller == null ||
        !controller.hasListener ||
        _lateTransactions.isEmpty) {
      return;
    }
    final List<AppleIapTransaction> pending = List<AppleIapTransaction>.from(
      _lateTransactions,
    );
    _lateTransactions.clear();
    for (final AppleIapTransaction transaction in pending) {
      controller.add(transaction);
    }
  }

  void _emitTransaction(AppleIapTransaction transaction) {
    final StreamController<AppleIapTransaction>? controller =
        _transactionUpdatesController;
    if (controller == null || !controller.hasListener) {
      _lateTransactions.add(transaction);
      return;
    }
    controller.add(transaction);
  }

  @override
  Future<AppleIapPurchaseResult?> readRetainedPurchaseOutcome({
    required String productId,
    required String appAccountToken,
  }) async {
    if (!isPlatformSupported) {
      return null;
    }
    final (String, String) key = (
      _identifier(productId, 'productId'),
      _canonicalUuid(appAccountToken, 'appAccountToken'),
    );
    if (_purchaseFlights.containsKey(key)) {
      return const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.pending,
        reason: 'native_purchase_in_flight',
      );
    }
    final AppleIapPurchaseResult? result = _retainedPurchaseResults[key];
    if (result != null) {
      return result;
    }
    if (_retainedPurchaseFailures.containsKey(key)) {
      return const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.pending,
        reason: 'native_purchase_unknown',
      );
    }
    return null;
  }

  @override
  Future<AppleIapAvailabilityStatus> availability() async {
    if (!isPlatformSupported) {
      return const AppleIapAvailabilityStatus(
        state: AppleIapAvailability.unsupportedPlatform,
      );
    }
    final Object? raw = await _invoke(
      'availability',
      const <String, Object?>{},
    );
    final Map<String, Object?> data = _requireMap(raw, 'StoreKit availability');
    final String minimumOsVersion =
        _optionalString(data['minimumOsVersion']) ?? '15.0';
    final AppleIapAvailability state = switch (_requiredString(
      data['state'],
      'state',
    ).toLowerCase()) {
      'available' => AppleIapAvailability.available,
      'payments_disabled' => AppleIapAvailability.paymentsDisabled,
      'unsupported_os' => AppleIapAvailability.unsupportedOs,
      'unsupported_platform' => AppleIapAvailability.unsupportedPlatform,
      _ => AppleIapAvailability.unavailable,
    };
    return AppleIapAvailabilityStatus(
      state: state,
      minimumOsVersion: minimumOsVersion,
    );
  }

  @override
  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds) async {
    if (!isPlatformSupported) {
      return const <AppleStoreProduct>[];
    }
    final List<String> normalized = _normalizeIdentifiers(
      productIds,
      label: 'StoreKit product IDs',
    );
    final Object? raw = await _invoke('loadProducts', <String, Object?>{
      'productIds': normalized,
    });
    if (raw is! List<Object?>) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 商品响应不是数组',
      );
    }
    final List<AppleStoreProduct> products = <AppleStoreProduct>[];
    for (final Object? item in raw) {
      final Map<String, Object?> map = _requireMap(item, 'StoreKit product');
      final AppleStoreProduct product = AppleStoreProduct(
        id: _identifier(map['id'], 'id'),
        displayName: _requiredString(map['displayName'], 'displayName'),
        description: _requiredString(map['description'], 'description'),
        displayPrice: _requiredString(map['displayPrice'], 'displayPrice'),
        priceMilliunits: _parsePriceMilliunits(map['price']),
        currencyCode: _parseCurrency(map['currencyCode']),
        productType: _requiredString(map['productType'], 'productType'),
      );
      if (!product.isConsumable) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'StoreKit 返回了非消耗型充值商品',
        );
      }
      products.add(product);
    }
    if (products.map((AppleStoreProduct item) => item.id).toSet().length !=
        products.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 商品响应包含重复标识',
      );
    }
    return products;
  }

  static int _parsePriceMilliunits(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$').hasMatch(raw)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 商品价格格式无效',
      );
    }
    final List<String> parts = raw.split('.');
    final int value =
        int.parse(parts.first) * 1000 +
        int.parse(parts.length == 1 ? '000' : parts[1].padRight(3, '0'));
    if (value <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 商品价格必须大于零',
      );
    }
    return value;
  }

  static String _parseCurrency(Object? raw) {
    if (raw is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(raw)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'Apple 商品币种无效',
      );
    }
    return raw;
  }

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async {
    if (!isPlatformSupported) {
      return const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.unavailable,
        reason: 'unsupported_platform',
      );
    }
    final String normalizedProductId = _identifier(productId, 'productId');
    final String normalizedToken = _canonicalUuid(
      appAccountToken,
      'appAccountToken',
    );
    final (String, String) key = (normalizedProductId, normalizedToken);
    final AppleIapPurchaseResult? retainedResult =
        _retainedPurchaseResults[key];
    if (retainedResult != null) {
      return retainedResult;
    }
    final _AppleIapPurchaseFailure? retainedFailure =
        _retainedPurchaseFailures[key];
    if (retainedFailure != null) {
      Error.throwWithStackTrace(
        retainedFailure.error,
        retainedFailure.stackTrace,
      );
    }
    if (_purchaseFlights.containsKey(key)) {
      return const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.pending,
        reason: 'native_purchase_in_flight',
      );
    }

    final _AppleIapPurchaseFlight flight = _AppleIapPurchaseFlight(key);
    late final Future<AppleIapPurchaseResult> operation;
    operation =
        _purchaseNative(
          productId: normalizedProductId,
          appAccountToken: normalizedToken,
        ).then(
          (AppleIapPurchaseResult result) {
            _completePurchase(flight, result);
            return result;
          },
          onError: (Object error, StackTrace stackTrace) {
            _failPurchase(flight, error, stackTrace);
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    flight.operation = operation;
    _purchaseFlights[key] = flight;

    return operation.timeout(
      _nativeTimeout,
      onTimeout: () {
        flight.callerTimedOut = true;
        throw _purchaseOutcomeUnknownTimeout();
      },
    );
  }

  Future<AppleIapPurchaseResult> _purchaseNative({
    required String productId,
    required String appAccountToken,
  }) async {
    final Object? raw = await _invoke('purchase', <String, Object?>{
      'productId': productId,
      'appAccountToken': appAccountToken,
    }, waitForNativeCompletion: true);
    final Map<String, Object?> data = _requireMap(raw, 'StoreKit purchase');
    final String outcome = _requiredString(
      data['outcome'],
      'outcome',
    ).toLowerCase();
    return switch (outcome) {
      'transaction' => AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.transaction,
        transaction: _parseTransaction(
          data['transaction'],
          expectedSource: AppleIapTransactionSource.purchase,
        ),
      ),
      'pending' => const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.pending,
        reason: 'pending',
      ),
      'user_cancelled' => const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.userCancelled,
        reason: 'user_cancelled',
      ),
      'failed' => const AppleIapPurchaseResult(
        outcome: AppleIapPurchaseOutcome.failed,
        reason: 'storekit_failed',
      ),
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 返回了未知购买状态',
      ),
    };
  }

  void _completePurchase(
    _AppleIapPurchaseFlight flight,
    AppleIapPurchaseResult result,
  ) {
    _retainedPurchaseResults[flight.key] = result;
    if (flight.callerTimedOut &&
        result.outcome == AppleIapPurchaseOutcome.transaction &&
        result.transaction != null) {
      _emitTransaction(result.transaction!);
    }
    if (identical(_purchaseFlights[flight.key], flight)) {
      _purchaseFlights.remove(flight.key);
    }
  }

  void _failPurchase(
    _AppleIapPurchaseFlight flight,
    Object error,
    StackTrace stackTrace,
  ) {
    _retainedPurchaseFailures[flight.key] = _AppleIapPurchaseFailure(
      error,
      stackTrace,
    );
    if (identical(_purchaseFlights[flight.key], flight)) {
      _purchaseFlights.remove(flight.key);
    }
  }

  @override
  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  }) async {
    if (!isPlatformSupported) {
      return const <AppleIapTransaction>[];
    }
    final Object? raw = await _invoke(
      'recoverUnfinished',
      <String, Object?>{'synchronizeStore': synchronizeStore},
      timeout: synchronizeStore ? const Duration(seconds: 90) : null,
    );
    if (raw is! List<Object?>) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 未完成交易响应不是数组',
      );
    }
    final List<AppleIapTransaction> transactions = raw
        .map<AppleIapTransaction>(
          (Object? item) => _parseTransaction(
            item,
            expectedSource: AppleIapTransactionSource.unfinished,
          ),
        )
        .toList(growable: false);
    if (transactions
            .map((AppleIapTransaction item) => item.transactionId)
            .toSet()
            .length !=
        transactions.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 未完成交易响应包含重复交易',
      );
    }
    return transactions;
  }

  @override
  Future<bool> finish(String transactionId) async {
    if (!isPlatformSupported) {
      return false;
    }
    final Object? raw = await _invoke('finish', <String, Object?>{
      'transactionId': _transactionId(transactionId),
    });
    if (raw is! bool) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 完成交易响应不是布尔值',
      );
    }
    return raw;
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> arguments, {
    Duration? timeout,
    bool waitForNativeCompletion = false,
  }) async {
    try {
      final Future<Object?> request = _invoker != null
          ? _invoker(method, arguments)
          : _methodChannel.invokeMethod<Object?>(method, arguments);
      if (waitForNativeCompletion) {
        return await request;
      }
      return await request.timeout(timeout ?? _nativeTimeout);
    } on TimeoutException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.timeout,
        message: 'StoreKit 原生操作超时，交易保持未完成并等待恢复',
        cause: error,
      );
    } on MissingPluginException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.configuration,
        message: 'StoreKit 2 原生桥未注册',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw ApiException(
        kind: switch (error.code) {
          'unsupported_os' => ApiFailureKind.configuration,
          'purchase_in_flight' => ApiFailureKind.timeout,
          _ => ApiFailureKind.business,
        },
        message: switch (error.code) {
          'unsupported_os' => '当前 iOS 版本不支持 StoreKit 2 充值',
          'payments_disabled' => '系统已禁止 App 内购买',
          'product_not_found' => 'Apple 充值商品暂不可用',
          'invalid_request' => 'Apple 充值请求无效',
          'purchase_in_flight' =>
            'Apple purchase outcome is unknown; native purchase remains in flight',
          _ => 'Apple IAP 暂不可用，交易不会被客户端认定为成功',
        },
        cause: error,
      );
    }
  }

  static ApiException _purchaseOutcomeUnknownTimeout() => ApiException(
    kind: ApiFailureKind.timeout,
    message:
        'Apple purchase outcome is unknown; native purchase remains in flight',
    cause: TimeoutException(
      'Apple purchase outcome is unknown; native purchase remains in flight',
    ),
  );

  static AppleIapTransaction _parseTransaction(
    Object? raw, {
    required AppleIapTransactionSource? expectedSource,
  }) {
    final Map<String, Object?> data = _requireMap(raw, 'StoreKit transaction');
    final String sourceName = _requiredString(data['source'], 'source');
    final AppleIapTransactionSource source = switch (sourceName.toLowerCase()) {
      'purchase' => AppleIapTransactionSource.purchase,
      'updates' => AppleIapTransactionSource.updates,
      'unfinished' => AppleIapTransactionSource.unfinished,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易来源无效',
      ),
    };
    if (expectedSource != null && source != expectedSource) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易来源与当前操作不一致',
      );
    }
    final String verificationName = _requiredString(
      data['verification'],
      'verification',
    );
    final AppleIapVerification verification = switch (verificationName
        .toLowerCase()) {
      'verified' => AppleIapVerification.verified,
      'unverified' => AppleIapVerification.unverified,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易验证状态无效',
      ),
    };
    final String signedTransaction = _requiredString(
      data['signedTransaction'],
      'signedTransaction',
    );
    if (signedTransaction.length > _maximumJwsLength ||
        signedTransaction.split('.').length != 3) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易 JWS 格式无效',
      );
    }
    final DateTime? purchaseDate = DateTime.tryParse(
      _requiredString(data['purchaseDate'], 'purchaseDate'),
    );
    if (purchaseDate == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易时间无效',
      );
    }
    return AppleIapTransaction(
      transactionId: _transactionId(data['transactionId']),
      originalTransactionId: _transactionId(data['originalTransactionId']),
      productId: _identifier(data['productId'], 'productId'),
      appAccountToken: switch (_optionalString(data['appAccountToken'])) {
        final String value => _canonicalUuid(value, 'appAccountToken'),
        null => null,
      },
      purchaseDate: purchaseDate.toUtc(),
      signedTransaction: signedTransaction,
      verification: verification,
      source: source,
    );
  }

  static Map<String, Object?> _requireMap(Object? raw, String label) {
    if (raw is! Map<Object?, Object?>) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label 响应不是对象',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      if (entry.key is! String) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label 包含非字符串字段',
        );
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static String _requiredString(Object? raw, String field) {
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 响应缺少有效 $field',
      );
    }
    return raw;
  }

  static String? _optionalString(Object? raw) {
    if (raw == null) {
      return null;
    }
    return _requiredString(raw, 'optional field');
  }

  static List<String> _normalizeIdentifiers(
    List<String> values, {
    required String label,
  }) {
    if (values.isEmpty || values.length > _maximumProductCount) {
      throw ArgumentError.value(values, label, '数量需为 1～100');
    }
    final List<String> normalized = values
        .map((String value) => _identifier(value, label))
        .toList(growable: false);
    if (normalized.toSet().length != normalized.length) {
      throw ArgumentError.value(values, label, '不得包含重复标识');
    }
    return normalized;
  }

  static String _identifier(Object? raw, String field) {
    final String value = _requiredString(raw, field);
    if (value.length > _maximumIdentifierLength ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit $field 格式无效',
      );
    }
    return value;
  }

  static String _transactionId(Object? raw) {
    final String value = _requiredString(raw, 'transactionId');
    if (value.length > 32 || !RegExp(r'^[0-9]+$').hasMatch(value)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit transactionId 格式无效',
      );
    }
    return value;
  }

  static String _canonicalUuid(String raw, String field) {
    final String value = raw.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit $field 不是有效 UUID',
      );
    }
    return value;
  }

  static bool _defaultIsIos() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && Platform.isIOS;
}

final class _AppleIapPurchaseFlight {
  _AppleIapPurchaseFlight(this.key);

  final (String, String) key;
  late final Future<AppleIapPurchaseResult> operation;
  bool callerTimedOut = false;
}

final class _AppleIapPurchaseFailure {
  _AppleIapPurchaseFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
