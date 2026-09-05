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

Future<HttpServer> _catalogServer({required String? storeProductId}) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    await request.drain<void>();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'code': 200,
        'message': 'OK',
        'data': <String, Object?>{
          'platform': 'IOS',
          'list': <Object?>[
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
          'total': 1,
          'orderCreationStatus': 'READY',
          'providerInvocation': false,
        },
      }),
    );
    await request.response.close();
  });
  return server;
}

class _StoreKit implements AppleIapStoreKit2Adapter {
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
  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds) async =>
      <AppleStoreProduct>[
        const AppleStoreProduct(
          id: _storeProductId,
          displayName: '60 Gift Coins',
          description: 'Consumable',
          displayPrice: '¥6.00',
          priceMilliunits: 6000,
          currencyCode: 'CNY',
          productType: 'consumable',
        ),
      ];

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async => AppleIapPurchaseResult(
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
    return const AppleIapOrderBinding(
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
