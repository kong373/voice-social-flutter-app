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

  Future<bool> isAvailable();

  Future<List<AppleIapStoreProduct>> fetchProducts(
    Set<String> storeProductIds,
  );

  Future<AppleIapPurchaseResult> purchase({
    required String storeProductId,
    required String appAccountToken,
  });

  Future<List<AppleIapTransaction>> unfinishedTransactions();

  Future<bool> finish(String transactionId);

  Future<void> synchronize();
}

class DisabledAppleIapStoreKit2Adapter implements AppleIapStoreKit2Adapter {
  const DisabledAppleIapStoreKit2Adapter();

  @override
  bool get isPlatformSupported => false;

  @override
  Stream<AppleIapTransaction> get transactionUpdates =>
      const Stream<AppleIapTransaction>.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<AppleIapStoreProduct>> fetchProducts(
    Set<String> storeProductIds,
  ) async => const <AppleIapStoreProduct>[];

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String storeProductId,
    required String appAccountToken,
  }) async => const AppleIapPurchaseResult(
    state: AppleIapPurchaseState.unavailable,
  );

  @override
  Future<List<AppleIapTransaction>> unfinishedTransactions() async =>
      const <AppleIapTransaction>[];

  @override
  Future<bool> finish(String transactionId) async => false;

  @override
  Future<void> synchronize() async {}
}

class MethodChannelAppleIapStoreKit2Adapter
    implements AppleIapStoreKit2Adapter {
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
  static const int _maximumIdentifierLength = 255;
  static const int _maximumProductCount = 100;
  static const int _maximumJwsLength = 128 * 1024;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final AppleIapMethodInvoker? _invoker;
  final Stream<Object?>? _transactionEventStream;
  final bool Function() _isIos;
  final Duration _nativeTimeout;
  Stream<AppleIapTransaction>? _updates;

  @override
  bool get isPlatformSupported => _isIos();

  @override
  Stream<AppleIapTransaction> get transactionUpdates {
    if (!isPlatformSupported) {
      return const Stream<AppleIapTransaction>.empty();
    }
    return _updates ??= (_transactionEventStream ??
            _eventChannel.receiveBroadcastStream())
        .map<AppleIapTransaction>(_parseTransaction)
        .asBroadcastStream();
  }

  @override
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) {
      return false;
    }
    final Map<String, Object?> data = _requireMap(
      await _invoke('availability', const <String, Object?>{}),
      'StoreKit 可用性',
    );
    final String state = _requiredString(data['state'], 'state').toLowerCase();
    return state == 'available';
  }

  @override
  Future<List<AppleIapStoreProduct>> fetchProducts(
    Set<String> storeProductIds,
  ) async {
    if (!isPlatformSupported) {
      return const <AppleIapStoreProduct>[];
    }
    if (storeProductIds.isEmpty ||
        storeProductIds.length > _maximumProductCount) {
      throw ArgumentError.value(
        storeProductIds,
        'storeProductIds',
        '数量需为 1～100',
      );
    }
    final List<String> normalized = storeProductIds
        .map((String id) => _identifier(id, 'storeProductId'))
        .toList(growable: false)
      ..sort();
    final Object? raw = await _invoke('loadProducts', <String, Object?>{
      'productIds': normalized,
    });
    if (raw is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 商品响应不是数组',
      );
    }
    final List<AppleIapStoreProduct> products = raw
        .map<AppleIapStoreProduct>((Object? item) {
          final Map<String, Object?> data = _requireMap(item, 'StoreKit 商品');
          final String type = _requiredString(
            data['productType'],
            'productType',
          ).toLowerCase();
          if (type != 'consumable') {
            throw const ApiException(
              kind: ApiFailureKind.protocol,
              message: 'StoreKit 返回了非消耗型充值商品',
            );
          }
          return AppleIapStoreProduct(
            storeProductId: _identifier(data['id'], 'id'),
            displayName: _requiredString(data['displayName'], 'displayName'),
            description: _requiredString(data['description'], 'description'),
            displayPrice: _requiredString(data['displayPrice'], 'displayPrice'),
          );
        })
        .toList(growable: false);
    if (products
            .map((AppleIapStoreProduct item) => item.storeProductId)
            .toSet()
            .length !=
        products.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 商品响应包含重复标识',
      );
    }
    return products;
  }

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String storeProductId,
    required String appAccountToken,
  }) async {
    if (!isPlatformSupported) {
      return const AppleIapPurchaseResult(
        state: AppleIapPurchaseState.unavailable,
      );
    }
    final Object? raw = await _invoke('purchase', <String, Object?>{
      'productId': _identifier(storeProductId, 'storeProductId'),
      'appAccountToken': _canonicalUuid(
        appAccountToken,
        'appAccountToken',
      ),
    });
    final Map<String, Object?> data = _requireMap(raw, 'StoreKit 购买');
    final String outcome = _requiredString(
      data['outcome'],
      'outcome',
    ).toLowerCase();
    if (outcome == 'transaction') {
      final AppleIapTransaction transaction = _parseTransaction(
        data['transaction'],
      );
      return AppleIapPurchaseResult(
        state: transaction.locallyVerified
            ? AppleIapPurchaseState.verified
            : AppleIapPurchaseState.unverified,
        transaction: transaction,
      );
    }
    return switch (outcome) {
      'pending' => const AppleIapPurchaseResult(
        state: AppleIapPurchaseState.pending,
      ),
      'user_cancelled' => const AppleIapPurchaseResult(
        state: AppleIapPurchaseState.canceled,
      ),
      'failed' => const AppleIapPurchaseResult(
        state: AppleIapPurchaseState.failed,
      ),
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 返回了未知购买状态',
      ),
    };
  }

  @override
  Future<List<AppleIapTransaction>> unfinishedTransactions() async {
    if (!isPlatformSupported) {
      return const <AppleIapTransaction>[];
    }
    final Object? raw = await _invoke(
      'recoverUnfinished',
      const <String, Object?>{'synchronizeStore': false},
    );
    if (raw is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 未完成交易响应不是数组',
      );
    }
    final List<AppleIapTransaction> transactions = raw
        .map<AppleIapTransaction>(_parseTransaction)
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

  @override
  Future<void> synchronize() async {
    if (!isPlatformSupported) {
      return;
    }
    await _invoke(
      'recoverUnfinished',
      const <String, Object?>{'synchronizeStore': true},
      timeout: const Duration(seconds: 90),
    );
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> arguments, {
    Duration? timeout,
  }) async {
    try {
      final AppleIapMethodInvoker? invoker = _invoker;
      final Future<Object?> request = invoker != null
          ? invoker(method, arguments)
          : _methodChannel.invokeMethod<Object?>(method, arguments);
      return await request.timeout(timeout ?? _nativeTimeout);
    } on TimeoutException {
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'StoreKit 操作超时，交易保持未完成并等待恢复',
      );
    } on MissingPluginException {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: 'StoreKit 2 原生桥未注册',
      );
    } on PlatformException catch (error) {
      throw ApiException(
        kind: error.code == 'unsupported_os'
            ? ApiFailureKind.configuration
            : ApiFailureKind.business,
        message: switch (error.code) {
          'unsupported_os' => '当前 iOS 版本不支持 StoreKit 2 充值',
          'payments_disabled' => '系统已禁止 App 内购买',
          'product_not_found' => 'Apple 充值商品暂不可用',
          'invalid_request' => 'Apple 充值请求无效',
          _ => 'Apple IAP 暂不可用，交易不会被客户端认定为成功',
        },
      );
    }
  }

  static AppleIapTransaction _parseTransaction(Object? raw) {
    final Map<String, Object?> data = _requireMap(raw, 'StoreKit 交易');
    final String verification = _requiredString(
      data['verification'],
      'verification',
    ).toLowerCase();
    if (verification != 'verified' && verification != 'unverified') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 交易验证状态无效',
      );
    }
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
    final Object? rawToken = data['appAccountToken'];
    return AppleIapTransaction(
      transactionId: _transactionId(data['transactionId']),
      originalTransactionId: switch (data['originalTransactionId']) {
        null => null,
        final Object value => _transactionId(value),
      },
      storeProductId: _identifier(data['productId'], 'productId'),
      appAccountToken: rawToken == null
          ? null
          : _canonicalUuid(rawToken, 'appAccountToken'),
      signedTransaction: signedTransaction,
      locallyVerified: verification == 'verified',
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

  static String _requiredString(Object? raw, String field) {
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'StoreKit 响应缺少有效 $field',
      );
    }
    return raw;
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

  static String _canonicalUuid(Object? raw, String field) {
    final String value = _requiredString(raw, field).toLowerCase();
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
