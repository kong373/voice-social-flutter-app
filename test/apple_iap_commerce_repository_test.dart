import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

final Object _testSession = Object();

void main() {
  test(
    'iOS catalog, purchase, delivery, finish and status use Apple authority',
    () async {
      final HttpServer server = await _catalogServer(
        storeProductId: 'com.kong373.voiceSocialApp.recharge.60',
      );
      addTearDown(() => server.close(force: true));
      final _StoreKit storeKit = _StoreKit();
      final _Backend backend = _Backend();
      final AppleIapPurchaseCoordinator coordinator =
          AppleIapPurchaseCoordinator(
            purchaseStore: MemoryKeyValueStore(),
            authenticatedAccount: () => 'test-account',
            authenticatedSession: () => _testSession,
            storeKit: storeKit,
            backend: backend,
          );
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: _client(server),
            routes: const BackendRouteCatalog(),
            appleIapCoordinator: coordinator,
            appleCreateRequestIdGenerator: () => 'apple-create-fixed',
          );

      final List<RechargeProduct> products = await repository
          .fetchRechargeProducts(platform: ClientStorePlatform.ios);

      expect(repository.supportsPaymentChannelInvocation, isTrue);
      expect(
        repository.availableChannels(ClientStorePlatform.ios),
        const <PaymentChannelType>[PaymentChannelType.appleIap],
      );
      expect(products.single.storeProductId, storeKit.storeProductId);
      expect(products.single.storeDisplayPrice, '¥6.00');
      RechargeOrder order = await repository.createRechargeOrder(
        account: 'masked-user',
        product: products.single,
        channel: PaymentChannelType.appleIap,
        platform: ClientStorePlatform.ios,
        youthModeEnabled: false,
      );
      expect(backend.createdProductIds, <String>[products.single.id]);
      expect(backend.createRequestIds, <String>['apple-create-fixed']);
      expect(order.appleAppAccountToken, _appAccountToken);
      expect(order.appleStoreProductId, storeKit.storeProductId);

      order = await repository.invokePayment(order);
      expect(order.state, RechargeOrderState.succeeded);
      expect(storeKit.finished, <String>[_transactionId]);
      expect(backend.deliveryCalls, 1);

      order = await repository.queryRechargeOrder(order);
      expect(order.state, RechargeOrderState.succeeded);
      expect(order.message, contains('服务端'));
      await coordinator.dispose();
    },
  );

  test(
    'iOS READY catalog without a valid store product fails closed',
    () async {
      final HttpServer server = await _catalogServer(storeProductId: null);
      addTearDown(() => server.close(force: true));
      final AppleIapPurchaseCoordinator coordinator =
          AppleIapPurchaseCoordinator(
            purchaseStore: MemoryKeyValueStore(),
            authenticatedAccount: () => 'test-account',
            authenticatedSession: () => _testSession,
            storeKit: _StoreKit(),
            backend: _Backend(),
          );
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: _client(server),
            routes: const BackendRouteCatalog(),
            appleIapCoordinator: coordinator,
          );

      await expectLater(
        repository.fetchRechargeProducts(platform: ClientStorePlatform.ios),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(repository.supportsPaymentChannelInvocation, isFalse);
      await coordinator.dispose();
    },
  );
  for (final scenario in <String>[
    'missing',
    'wrong-id',
    'wrong-price',
    'wrong-currency',
    'non-consumable',
  ]) {
    test(
      'IAP catalog rejects $scenario before any order or native purchase',
      () async {
        final server = await _catalogServer(storeProductId: _storeProductId);
        addTearDown(() => server.close(force: true));
        final storeKit = _StoreKit(
          productLoader: (_) async => scenario == 'missing'
              ? <AppleStoreProduct>[]
              : <AppleStoreProduct>[
                  _catalogStoreProduct(
                    id: scenario == 'wrong-id'
                        ? 'example.unexpected'
                        : _storeProductId,
                    price: scenario == 'wrong-price' ? 5000 : 6000,
                    currency: scenario == 'wrong-currency' ? 'USD' : 'CNY',
                    type: scenario == 'non-consumable'
                        ? 'nonConsumable'
                        : 'consumable',
                  ),
                ],
        );
        final backend = _Backend();
        final coordinator = _catalogCoordinator(storeKit, backend);
        addTearDown(coordinator.dispose);
        final repository = BackendCommerceCatalogRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          appleIapCoordinator: coordinator,
        );
        await expectLater(
          repository
              .fetchRechargeProducts(platform: ClientStorePlatform.ios)
              .timeout(const Duration(seconds: 3)),
          throwsA(isA<ApiException>()),
        );
        expect(repository.supportsPaymentChannelInvocation, isFalse);
        expect(repository.availableChannels(ClientStorePlatform.ios), isEmpty);
        expect(backend.createdProductIds, isEmpty);
        expect(backend.deliveryCalls, 0);
        expect(storeKit.purchaseCalls, 0);
        expect(storeKit.finished, isEmpty);
      },
    );
  }

  test(
    'IAP catalog matches multiple products by identifier, not return order',
    () async {
      const secondId = '00000000-0000-0000-0000-000000001102';
      const secondStoreId = 'com.kong373.voiceSocialApp.recharge.300';
      final server = await _catalogServer(
        storeProductId: _storeProductId,
        productRows: <Map<String, Object?>>[
          _catalogRow(_productId, _storeProductId, 600, 60),
          _catalogRow(secondId, secondStoreId, 3000, 300),
        ],
      );
      addTearDown(() => server.close(force: true));
      final storeKit = _StoreKit(
        productLoader: (ids) async {
          expect(ids, <String>[_storeProductId, secondStoreId]);
          return <AppleStoreProduct>[
            _catalogStoreProduct(
              id: secondStoreId,
              price: 30000,
              display: 'fixture-30',
            ),
            _catalogStoreProduct(display: 'fixture-6'),
          ];
        },
      );
      final backend = _Backend();
      final coordinator = _catalogCoordinator(storeKit, backend);
      addTearDown(coordinator.dispose);
      final repository = BackendCommerceCatalogRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        appleIapCoordinator: coordinator,
      );
      final products = await repository
          .fetchRechargeProducts(platform: ClientStorePlatform.ios)
          .timeout(const Duration(seconds: 3));
      expect(products.map((p) => p.id), <String>[_productId, secondId]);
      expect(products.map((p) => p.storeDisplayPrice), <String>[
        'fixture-6',
        'fixture-30',
      ]);
      expect(repository.supportsPaymentChannelInvocation, isTrue);
      expect(backend.createdProductIds, isEmpty);
      expect(storeKit.purchaseCalls, 0);
    },
  );

  test('IAP blocked refresh clears prior catalog readiness', () async {
    var status = 'READY';
    final server = await _catalogServer(
      storeProductId: _storeProductId,
      statusProvider: () => status,
    );
    addTearDown(() => server.close(force: true));
    final storeKit = _StoreKit();
    final backend = _Backend();
    final coordinator = _catalogCoordinator(storeKit, backend);
    addTearDown(coordinator.dispose);
    final repository = BackendCommerceCatalogRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      appleIapCoordinator: coordinator,
    );
    await repository
        .fetchRechargeProducts(platform: ClientStorePlatform.ios)
        .timeout(const Duration(seconds: 3));
    expect(repository.supportsPaymentChannelInvocation, isTrue);
    status = 'VENDOR_BLOCKED';
    await repository
        .fetchRechargeProducts(platform: ClientStorePlatform.ios)
        .timeout(const Duration(seconds: 3));
    expect(repository.supportsPaymentChannelInvocation, isFalse);
    expect(repository.availableChannels(ClientStorePlatform.ios), isEmpty);
    expect(backend.createdProductIds, isEmpty);
    expect(storeKit.purchaseCalls, 0);
  });

  test(
    'IAP-CAT-P2-01 late READY must not overwrite newer blocked catalog',
    () async {
      // Diagnostic regression: the exported ff06e9a implementation is expected
      // to violate the final assertion. Do not weaken it or mark it skipped.
      var status = 'READY';
      final productsRequested = Completer<void>();
      final productReply = Completer<List<AppleStoreProduct>>();
      final server = await _catalogServer(
        storeProductId: _storeProductId,
        statusProvider: () => status,
      );
      addTearDown(() => server.close(force: true));
      final storeKit = _StoreKit(
        productLoader: (_) {
          if (!productsRequested.isCompleted) productsRequested.complete();
          return productReply.future;
        },
      );
      final backend = _Backend();
      final coordinator = _catalogCoordinator(storeKit, backend);
      addTearDown(coordinator.dispose);
      final repository = BackendCommerceCatalogRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        appleIapCoordinator: coordinator,
      );
      final oldRead = repository
          .fetchRechargeProducts(platform: ClientStorePlatform.ios)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              // Discarding a stale read may return or reject; either is safe if
              // it cannot restore readiness from its superseded response.
              if (error is! ApiException)
                Error.throwWithStackTrace(error, stack);
            },
          );
      addTearDown(() async {
        if (!productReply.isCompleted) {
          productReply.complete(<AppleStoreProduct>[_catalogStoreProduct()]);
        }
        await oldRead.timeout(const Duration(seconds: 3));
      });
      await productsRequested.future.timeout(const Duration(seconds: 3));
      status = 'VENDOR_BLOCKED';
      await repository
          .fetchRechargeProducts(platform: ClientStorePlatform.ios)
          .timeout(const Duration(seconds: 3));
      expect(repository.supportsPaymentChannelInvocation, isFalse);
      productReply.complete(<AppleStoreProduct>[_catalogStoreProduct()]);
      await oldRead.timeout(const Duration(seconds: 3));
      expect(repository.supportsPaymentChannelInvocation, isFalse);
      expect(repository.availableChannels(ClientStorePlatform.ios), isEmpty);
      expect(backend.createdProductIds, isEmpty);
      expect(storeKit.purchaseCalls, 0);
    },
  );

  test(
    'late HTTP catalog cannot start StoreKit after a newer blocked reply',
    () async {
      var status = 'READY';
      final firstRequest = Completer<void>();
      final firstReply = Completer<void>();
      final server = await _catalogServer(
        storeProductId: _storeProductId,
        statusProvider: () => status,
        beforeReply: (requestNumber) async {
          if (requestNumber == 1) {
            firstRequest.complete();
            await firstReply.future;
          }
        },
      );
      addTearDown(() => server.close(force: true));
      var productLoads = 0;
      final storeKit = _StoreKit(
        productLoader: (_) async {
          productLoads++;
          return <AppleStoreProduct>[_catalogStoreProduct()];
        },
      );
      final coordinator = _catalogCoordinator(storeKit, _Backend());
      addTearDown(coordinator.dispose);
      final repository = BackendCommerceCatalogRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        appleIapCoordinator: coordinator,
      );
      final oldRead = repository.fetchRechargeProducts(
        platform: ClientStorePlatform.ios,
      );
      final rejected = expectLater(
        oldRead,
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await firstRequest.future.timeout(const Duration(seconds: 3));
      status = 'VENDOR_BLOCKED';
      await repository.fetchRechargeProducts(platform: ClientStorePlatform.ios);
      firstReply.complete();
      await rejected.timeout(const Duration(seconds: 3));
      expect(productLoads, 0);
      expect(repository.supportsPaymentChannelInvocation, isFalse);
      expect(storeKit.purchaseCalls, 0);
    },
  );

  test('older StoreKit failure cannot clear a newer valid catalog', () async {
    final requested = Completer<void>();
    final oldProducts = Completer<List<AppleStoreProduct>>();
    var loads = 0;
    final server = await _catalogServer(storeProductId: _storeProductId);
    addTearDown(() => server.close(force: true));
    final storeKit = _StoreKit(
      productLoader: (_) async {
        if (++loads == 1) {
          requested.complete();
          return oldProducts.future;
        }
        return <AppleStoreProduct>[_catalogStoreProduct()];
      },
    );
    final coordinator = _catalogCoordinator(storeKit, _Backend());
    addTearDown(coordinator.dispose);
    final repository = BackendCommerceCatalogRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      appleIapCoordinator: coordinator,
    );
    final oldRead = repository.fetchRechargeProducts(
      platform: ClientStorePlatform.ios,
    );
    final rejected = expectLater(oldRead, throwsA(isA<ApiException>()));
    await requested.future.timeout(const Duration(seconds: 3));
    await repository.fetchRechargeProducts(platform: ClientStorePlatform.ios);
    expect(repository.supportsPaymentChannelInvocation, isTrue);
    oldProducts.completeError(
      const ApiException(
        kind: ApiFailureKind.network,
        message: 'Old fixture request failed',
      ),
    );
    await rejected.timeout(const Duration(seconds: 3));
    expect(repository.supportsPaymentChannelInvocation, isTrue);
    expect(
      repository.availableChannels(ClientStorePlatform.ios),
      <PaymentChannelType>[PaymentChannelType.appleIap],
    );
    expect(storeKit.purchaseCalls, 0);
  });

  for (final mismatch in <String>['store-id', 'amount', 'coins']) {
    test('IAP order $mismatch drift never reaches native purchase', () async {
      final server = await _catalogServer(storeProductId: _storeProductId);
      addTearDown(() => server.close(force: true));
      final storeKit = _StoreKit();
      final backend = _Backend(
        orderOverride: AppleIapOrderBinding(
          orderNo: 'vs_apple_order_1',
          productId: _productId,
          storeProductId: mismatch == 'store-id'
              ? 'example.other-product'
              : _storeProductId,
          appAccountToken: _appAccountToken,
          amountMinor: mismatch == 'amount' ? 700 : 600,
          giftCoinAmount: mismatch == 'coins' ? 70 : 60,
          environment: 'Sandbox',
          status: 'CONFIRMING',
          createdAt: null,
        ),
      );
      final coordinator = _catalogCoordinator(storeKit, backend);
      addTearDown(coordinator.dispose);
      final repository = BackendCommerceCatalogRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        appleIapCoordinator: coordinator,
      );
      final products = await repository
          .fetchRechargeProducts(platform: ClientStorePlatform.ios)
          .timeout(const Duration(seconds: 3));
      await expectLater(
        repository
            .createRechargeOrder(
              account: 'test-account',
              product: products.single,
              channel: PaymentChannelType.appleIap,
              platform: ClientStorePlatform.ios,
              youthModeEnabled: false,
            )
            .timeout(const Duration(seconds: 3)),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(backend.createdProductIds, <String>[_productId]);
      expect(storeKit.purchaseCalls, 0);
      expect(backend.deliveryCalls, 0);
      expect(storeKit.finished, isEmpty);
    });
  }
}

const String _productId = '00000000-0000-0000-0000-000000001101';
const String _storeProductId = 'com.kong373.voiceSocialApp.recharge.60';
const String _appAccountToken = '11111111-1111-4111-8111-111111111111';
const String _transactionId = '100000000000001';

ApiClient _client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'iOS',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);

Future<HttpServer> _catalogServer({
  required String? storeProductId,
  String Function()? statusProvider,
  List<Map<String, Object?>>? productRows,
  Future<void> Function(int)? beforeReply,
}) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  var requestNumber = 0;
  server.listen((HttpRequest request) async {
    await request.drain<void>();
    final status = statusProvider?.call() ?? 'READY';
    await beforeReply?.call(++requestNumber);
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'code': 200,
        'message': 'OK',
        'data': <String, Object?>{
          'platform': 'IOS',
          'list':
              productRows ??
              <Object?>[
                <String, Object?>{
                  'productId': _productId,
                  'title': '60礼物币',
                  'amountMinor': 600,
                  'amount': 6.0,
                  'giftCoinAmount': 60,
                  'bonusGiftCoin': 0,
                  if (storeProductId != null) 'storeProductId': storeProductId,
                },
              ],
          'total': productRows?.length ?? 1,
          'orderCreationStatus': status,
          'providerInvocation': false,
        },
      }),
    );
    await request.response.close();
  });
  return server;
}

class _StoreKit implements AppleIapStoreKit2Adapter {
  _StoreKit({this.productLoader});

  final Future<List<AppleStoreProduct>> Function(List<String>)? productLoader;
  int purchaseCalls = 0;
  final String storeProductId = _storeProductId;
  final List<String> finished = <String>[];

  @override
  bool get isPlatformSupported => true;

  @override
  Stream<AppleIapTransaction> get transactionUpdates =>
      const Stream<AppleIapTransaction>.empty();

  @override
  Future<AppleIapAvailabilityStatus> availability() async =>
      const AppleIapAvailabilityStatus(state: AppleIapAvailability.available);

  @override
  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds) async {
    if (productLoader != null) return productLoader!(productIds);
    return const <AppleStoreProduct>[
      AppleStoreProduct(
        id: _storeProductId,
        displayName: '60 Gift Coins',
        description: 'Consumable',
        displayPrice: '¥6.00',
        priceMilliunits: 6000,
        currencyCode: 'CNY',
        productType: 'consumable',
      ),
    ];
  }

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async {
    purchaseCalls += 1;
    return AppleIapPurchaseResult(
      outcome: AppleIapPurchaseOutcome.transaction,
      transaction: AppleIapTransaction(
        transactionId: _transactionId,
        originalTransactionId: _transactionId,
        productId: productId,
        appAccountToken: appAccountToken,
        purchaseDate: DateTime.utc(2026, 9, 4),
        signedTransaction: 'header.payload.signature',
        verification: AppleIapVerification.verified,
        source: AppleIapTransactionSource.purchase,
      ),
    );
  }

  @override
  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  }) async => const <AppleIapTransaction>[];

  @override
  Future<bool> finish(String transactionId) async {
    finished.add(transactionId);
    return true;
  }
}

class _Backend implements AppleIapBackendPort {
  _Backend({this.orderOverride});

  final AppleIapOrderBinding? orderOverride;
  final List<String> createdProductIds = <String>[];
  final List<String> createRequestIds = <String>[];
  int deliveryCalls = 0;

  @override
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  }) async {
    createdProductIds.add(productId);
    createRequestIds.add(requestId);
    return orderOverride ??
        const AppleIapOrderBinding(
          orderNo: 'vs_apple_order_1',
          productId: _productId,
          storeProductId: _storeProductId,
          appAccountToken: _appAccountToken,
          amountMinor: 600,
          giftCoinAmount: 60,
          environment: 'Sandbox',
          status: 'CONFIRMING',
          createdAt: null,
        );
  }

  @override
  Future<AppleIapDeliveryAck> deliverTransaction({
    required String? orderNo,
    required AppleIapTransaction transaction,
    required String requestId,
  }) async {
    deliveryCalls += 1;
    return const AppleIapDeliveryAck(
      orderNo: 'vs_apple_order_1',
      transactionId: _transactionId,
      deliveryState: AppleIapDeliveryState.delivered,
      creditedGiftCoins: 60,
      finishAllowed: true,
    );
  }

  @override
  Future<AppleIapOrderStatus> readOrderStatus(String orderNo) async =>
      const AppleIapOrderStatus(
        orderNo: 'vs_apple_order_1',
        status: 'SUCCEEDED',
        creditedGiftCoins: 60,
        transactionId: _transactionId,
        finishAllowed: true,
      );
}

AppleIapPurchaseCoordinator _catalogCoordinator(
  _StoreKit storeKit,
  _Backend backend,
) => AppleIapPurchaseCoordinator(
  purchaseStore: MemoryKeyValueStore(),
  authenticatedAccount: () => 'test-account',
  authenticatedSession: () => _testSession,
  storeKit: storeKit,
  backend: backend,
);

AppleStoreProduct _catalogStoreProduct({
  String id = _storeProductId,
  int price = 6000,
  String currency = 'CNY',
  String type = 'consumable',
  String display = 'fixture-6',
}) => AppleStoreProduct(
  id: id,
  displayName: 'Fixture coins',
  description: 'Synthetic test product',
  displayPrice: display,
  priceMilliunits: price,
  currencyCode: currency,
  productType: type,
);

Map<String, Object?> _catalogRow(
  String id,
  String storeId,
  int amount,
  int coins,
) => <String, Object?>{
  'productId': id,
  'storeProductId': storeId,
  'title': 'Fixture coins',
  'amountMinor': amount,
  'amount': amount / 100,
  'giftCoinAmount': coins,
  'bonusGiftCoin': 0,
};
