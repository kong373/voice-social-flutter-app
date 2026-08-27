import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

void main() {
  test(
    'native cancellation evidence is strict and survives only safe copies',
    () {
      final RechargeOrder created = RechargeOrder(
        orderNo: 'recharge-order-evidence',
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        state: RechargeOrderState.confirming,
        createdAt: DateTime(2026),
      );

      final RechargeOrder trusted = created.withNativeBridgeResult(
        sdkCompleted: false,
        resultStatus: '6001',
        outcome: 'userCanceled',
        reason: 'userCanceled',
      );
      expect(
        trusted.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.trustedUserCanceled6001,
      );
      expect(trusted.hasTrustedNativeCancellationEvidence, isTrue);

      // Refresh/status copies retain the normalized evidence needed for a
      // recovery retry, while any native-field rewrite fails closed.
      final RechargeOrder stateCopy = trusted.copyWith(
        state: RechargeOrderState.confirming,
        message: '仍在确认',
      );
      expect(stateCopy.hasTrustedNativeCancellationEvidence, isTrue);
      final RechargeOrder nativeFieldsCopy = trusted.copyWith(
        nativeSdkCompleted: false,
        nativeResultStatus: '6001',
      );
      expect(
        nativeFieldsCopy.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.none,
      );
      expect(nativeFieldsCopy.hasTrustedNativeCancellationEvidence, isFalse);

      final RechargeOrder contradictory = created.withNativeBridgeResult(
        sdkCompleted: false,
        resultStatus: '6001',
        outcome: 'userCanceled',
        reason: 'processing',
      );
      expect(
        contradictory.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.none,
      );
      expect(contradictory.hasTrustedNativeCancellationEvidence, isFalse);
    },
  );

  test(
    'Alipay order string comes from backend and native result is provisional',
    () async {
      final List<_Request> requests = <_Request>[];
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Object? decoded = body.trim().isEmpty ? null : jsonDecode(body);
        requests.add(
          _Request(
            method: request.method,
            path: request.uri.path,
            query: request.uri.queryParameters,
            requestId: request.headers.value('X-Request-Id'),
            body: decoded is Map ? Map<String, Object?>.from(decoded) : decoded,
          ),
        );
        final Object? data = request.uri.path.endsWith('/recharge/products')
            ? <String, Object?>{
                'platform': 'ANDROID',
                'list': <Object?>[
                  <String, Object?>{
                    'productId': '00000000-0000-0000-0000-000000001001',
                    'title': '60礼物币',
                    'amountMinor': 600,
                    'amount': 6.00,
                    'giftCoinAmount': 60,
                    'bonusGiftCoin': 0,
                  },
                ],
                'total': 1,
                'orderCreationStatus': 'READY',
                'providerInvocation': false,
              }
            : request.uri.path.endsWith('/ali/order')
            ? <String, Object?>{
                'orderNo': 'recharge-order-1',
                'orderStr': 'server-signed-order-string',
                'productId': 'product-1',
                'amountMinor': 600,
                'giftCoinAmount': 60,
                'channel': 'ALIPAY',
                'platform': 'ANDROID',
                'status': 'CREATED',
              }
            : <String, Object?>{
                'orderNo': 'recharge-order-1',
                'bool': true,
                'status': 'SUCCEEDED',
              };
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': data,
            }),
          );
        await request.response.close();
      });

      final _FakeAlipayAdapter adapter = _FakeAlipayAdapter();
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
            ),
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: adapter,
          );
      const RechargeProduct product = RechargeProduct(
        id: 'product-1',
        giftCoins: 60,
        priceCny: 6,
      );

      expect(repository.supportsPaymentChannelInvocation, isFalse);
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      expect(repository.supportsPaymentChannelInvocation, isTrue);
      expect(
        repository.availableChannels(ClientStorePlatform.android),
        const <PaymentChannelType>[PaymentChannelType.alipay],
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: product,
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );
      expect(created.orderNo, 'recharge-order-1');
      expect(created.paymentOrderString, 'server-signed-order-string');
      expect(requests[1].path, '/app-economy-api/pay/ali/order');
      expect(requests[1].body, <String, Object?>{
        'account': 'current-user-account',
        'productId': 'product-1',
        'channel': 'ALIPAY',
        'platform': 'ANDROID',
      });

      final RechargeOrder provisional = await repository.invokePayment(created);
      // The native result is provisional, but invokePayment immediately runs
      // reconcile POST followed by the authoritative read-only GET.
      expect(provisional.state, RechargeOrderState.succeeded);
      expect(provisional.message, '服务端已确认到账');
      expect(adapter.orderStrings, <String>['server-signed-order-string']);
      expect(requests, hasLength(4));
      expect(requests[2].method, 'POST');
      expect(requests[2].path, '/app-economy-api/pay/ali/order/reconcile');
      expect(requests[2].query, <String, String>{
        'orderNo': 'recharge-order-1',
      });
      expect(requests[2].requestId, startsWith('alipay-reconcile-'));
      expect(requests[3].method, 'GET');
      expect(requests[3].path, '/app-economy-api/pay/ali/order/status');
      expect(requests[3].query, <String, String>{
        'orderNo': 'recharge-order-1',
      });

      final RechargeOrder authoritative = await repository.queryRechargeOrder(
        provisional,
      );
      expect(authoritative.state, RechargeOrderState.succeeded);
      expect(requests, hasLength(5));
      expect(requests[4].path, '/app-economy-api/pay/ali/order/status');
      expect(provisional.nativeSdkCompleted, isTrue);
      expect(provisional.nativeResultStatus, '9000');
      expect(provisional.isNativeSdkSuccess, isTrue);
    },
  );

  test(
    'only trusted 6001 cancellation skips reconcile for native outcomes',
    () async {
      final List<AlipayAppPayResult> nativeResults = <AlipayAppPayResult>[
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.processing,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: false,
          resultStatus: '8000',
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.processing,
          reason: AlipayAppPayReason.timeout,
          sdkCompleted: false,
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.sdkCompleted,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: true,
          resultStatus: '9000',
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.networkError,
          reason: AlipayAppPayReason.network,
          sdkCompleted: false,
          resultStatus: '6002',
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.processing,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: false,
          resultStatus: '6004',
        ),
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.failed,
          reason: AlipayAppPayReason.vendorFailed,
          sdkCompleted: false,
          resultStatus: '4000',
        ),
        // A contradictory bridge payload must not be allowed to enter the
        // cancel mutation merely because it contains the 6001 token.
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: true,
          resultStatus: '6001',
        ),
      ];

      for (final AlipayAppPayResult nativeResult in nativeResults) {
        final _ServerHarness harness = await _ServerHarness.start(
          nativeResult: nativeResult,
        );
        try {
          final BackendCommerceCatalogRepository repository =
              BackendCommerceCatalogRepository(
                apiClient: harness.client,
                routes: const BackendRouteCatalog(),
                alipayAppPayAdapter: harness.adapter,
              );
          await repository.fetchRechargeProducts(
            platform: ClientStorePlatform.android,
          );
          final RechargeOrder created = await repository.createRechargeOrder(
            account: 'current-user-account',
            product: const RechargeProduct(
              id: 'product-1',
              giftCoins: 60,
              priceCny: 6,
            ),
            channel: PaymentChannelType.alipay,
            platform: ClientStorePlatform.android,
            youthModeEnabled: false,
          );

          final RechargeOrder result = await repository.invokePayment(created);

          // The backend may truthfully report a previously settled order; the
          // native evidence is retained separately and never authorizes it.
          expect(result.state, RechargeOrderState.succeeded);
          expect(result.nativeSdkCompleted, nativeResult.sdkCompleted);
          expect(result.nativeResultStatus, nativeResult.resultStatus);
          expect(
            result.isNativeSdkSuccess,
            nativeResult.sdkCompleted && nativeResult.resultStatus == '9000',
          );
          expect(result.message, '服务端已确认到账');
          expect(harness.requests, hasLength(4));
          final bool trustedCancellation =
              nativeResult.sdkCompleted == false &&
              nativeResult.outcome == AlipayAppPayOutcome.userCanceled &&
              nativeResult.reason == AlipayAppPayReason.userCanceled &&
              nativeResult.resultStatus == '6001';
          expect(
            harness.requests[2].path,
            trustedCancellation
                ? '/app-economy-api/pay/ali/order/cancel'
                : '/app-economy-api/pay/ali/order/reconcile',
          );
          expect(harness.requests[2].method, 'POST');
          expect(harness.requests[2].query, <String, String>{
            'orderNo': 'recharge-order-1',
          });
          expect(
            harness.requests[2].requestId,
            startsWith(
              trustedCancellation ? 'alipay-cancel-' : 'alipay-reconcile-',
            ),
          );
          expect(harness.requests[3].method, 'GET');
          expect(
            harness.requests[3].path,
            '/app-economy-api/pay/ali/order/status',
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'trusted local Alipay cancellation writes once per request id then reads DB status',
    () async {
      final _ServerHarness harness = await _ServerHarness.start(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        status: 'CANCELLED',
      );
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: harness.client,
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: harness.adapter,
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder first = await repository.invokePayment(created);
      expect(
        first.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.trustedUserCanceled6001,
      );
      expect(first.hasTrustedNativeCancellationEvidence, isTrue);

      // The order is already terminal, so a later refresh must not replay the
      // close-capable cancel mutation even though trusted evidence is retained.
      final RechargeOrder terminalRefresh = await repository.queryRechargeOrder(
        first,
      );
      expect(terminalRefresh.state, RechargeOrderState.canceled);
      final RechargeOrder second = await repository.invokePayment(created);

      expect(first.state, RechargeOrderState.canceled);
      expect(second.state, RechargeOrderState.canceled);
      expect(harness.requests, hasLength(7));
      expect(
        harness.requests
            .where(
              (_Request request) =>
                  request.path == '/app-economy-api/pay/ali/order/cancel',
            )
            .length,
        2,
      );
      final List<_Request> cancelRequests = harness.requests
          .where(
            (_Request request) =>
                request.path == '/app-economy-api/pay/ali/order/cancel',
          )
          .toList();
      expect(cancelRequests[0].method, 'POST');
      expect(cancelRequests[0].query, <String, String>{
        'orderNo': 'recharge-order-1',
      });
      expect(cancelRequests[0].requestId, startsWith('alipay-cancel-'));
      expect(cancelRequests[1].requestId, cancelRequests[0].requestId);
      expect(
        harness.requests.any(
          (_Request request) =>
              request.path == '/app-economy-api/pay/ali/order/reconcile',
        ),
        isFalse,
      );
      expect(
        harness.requests
            .where(
              (_Request request) =>
                  request.path == '/app-economy-api/pay/ali/order/status',
            )
            .length,
        3,
      );
      expect(
        harness.requests.last.path,
        '/app-economy-api/pay/ali/order/status',
      );
      expect(
        harness.requests.where(
          (_Request request) =>
              request.path == '/app-economy-api/pay/ali/order/reconcile',
        ),
        isEmpty,
      );
    },
  );

  test(
    'trusted cancellation still forces DB status when cancel write is unavailable',
    () async {
      final _ServerHarness harness = await _ServerHarness.start(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        status: 'CONFIRMING',
        cancelStatusCode: 503,
      );
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: harness.client,
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: harness.adapter,
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder result = await repository.invokePayment(created);

      expect(result.state, RechargeOrderState.confirming);
      expect(harness.requests, hasLength(4));
      expect(harness.requests[2].path, '/app-economy-api/pay/ali/order/cancel');
      expect(harness.requests[2].method, 'POST');
      expect(harness.requests[3].path, '/app-economy-api/pay/ali/order/status');
      expect(
        harness.requests.any(
          (_Request request) =>
              request.path == '/app-economy-api/pay/ali/order/reconcile',
        ),
        isFalse,
      );
    },
  );

  test(
    'query recovery retries cancel after the initial cancel request is unavailable',
    () async {
      final _ServerHarness harness = await _ServerHarness.start(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        statusSequence: <String>['CONFIRMING', 'CANCELLED'],
        cancelStatusSequence: <int>[503, 200],
      );
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: harness.client,
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: harness.adapter,
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder first = await repository.invokePayment(created);
      expect(first.state, RechargeOrderState.confirming);
      expect(
        first.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.trustedUserCanceled6001,
      );
      expect(first.hasTrustedNativeCancellationEvidence, isTrue);

      final RechargeOrder recovered = await repository.queryRechargeOrder(
        first,
      );

      expect(recovered.state, RechargeOrderState.canceled);
      expect(harness.requests, hasLength(7));
      expect(harness.requests.map((_Request request) => request.path), <String>[
        '/app-mini-api/mini/v1/recharge/products',
        '/app-economy-api/pay/ali/order',
        '/app-economy-api/pay/ali/order/cancel',
        '/app-economy-api/pay/ali/order/status',
        '/app-economy-api/pay/ali/order/cancel',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
      ]);
      expect(harness.requests[2].requestId, harness.requests[4].requestId);
    },
  );

  test(
    'query recovery replays stable cancel after an UNKNOWN cancellation result',
    () async {
      final _ServerHarness harness = await _ServerHarness.start(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        statusSequence: <String>['CONFIRMING', 'CANCELLED'],
        // The first response represents a backend-cached UNKNOWN outcome;
        // the replay must retain the same request id before reconciliation.
        cancelStatusSequence: <int>[200, 200],
        cancelOutcomeSequence: <String>['UNKNOWN', 'UNKNOWN'],
      );
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: harness.client,
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: harness.adapter,
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder first = await repository.invokePayment(created);
      expect(first.state, RechargeOrderState.confirming);
      expect(
        first.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.trustedUserCanceled6001,
      );
      expect(first.hasTrustedNativeCancellationEvidence, isTrue);

      final RechargeOrder recovered = await repository.queryRechargeOrder(
        first,
      );

      expect(recovered.state, RechargeOrderState.canceled);
      final List<_Request> cancelRequests = harness.requests
          .where(
            (_Request request) =>
                request.path == '/app-economy-api/pay/ali/order/cancel',
          )
          .toList();
      expect(cancelRequests, hasLength(2));
      expect(cancelRequests[1].requestId, cancelRequests[0].requestId);
      expect(
        harness.requests.any(
          (_Request request) =>
              request.path == '/app-economy-api/pay/ali/order/reconcile',
        ),
        isTrue,
      );
    },
  );

  test(
    'contradictory 6001 evidence never replays cancel during query recovery',
    () async {
      final _ServerHarness harness = await _ServerHarness.start(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: false,
          resultStatus: '6001',
        ),
        status: 'CONFIRMING',
      );
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: harness.client,
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: harness.adapter,
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder first = await repository.invokePayment(created);
      final RechargeOrder recovered = await repository.queryRechargeOrder(
        first,
      );

      expect(first.state, RechargeOrderState.confirming);
      expect(first.nativeSdkCompleted, isFalse);
      expect(first.nativeResultStatus, '6001');
      expect(
        first.nativeCancellationEvidence,
        RechargeNativeCancellationEvidence.none,
      );
      expect(first.hasTrustedNativeCancellationEvidence, isFalse);
      expect(recovered.state, RechargeOrderState.confirming);
      expect(harness.requests.map((_Request request) => request.path), <String>[
        '/app-mini-api/mini/v1/recharge/products',
        '/app-economy-api/pay/ali/order',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
      ]);
      expect(
        harness.requests.any(
          (_Request request) =>
              request.path == '/app-economy-api/pay/ali/order/cancel',
        ),
        isFalse,
      );
    },
  );

  test(
    'contradictory native completion payload never shows completed wording',
    () async {
      final _FakeAlipayAdapter adapter = _FakeAlipayAdapter(
        nativeResult: const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.sdkCompleted,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: false,
          resultStatus: '9000',
        ),
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        final Object? data = request.uri.path.endsWith('/recharge/products')
            ? <String, Object?>{
                'platform': 'ANDROID',
                'list': <Object?>[
                  <String, Object?>{
                    'productId': '00000000-0000-0000-0000-000000001001',
                    'title': '60礼物币',
                    'amountMinor': 600,
                    'amount': 6.00,
                    'giftCoinAmount': 60,
                    'bonusGiftCoin': 0,
                  },
                ],
                'total': 1,
                'orderCreationStatus': 'READY',
                'providerInvocation': false,
              }
            : request.uri.path.endsWith('/ali/order')
            ? <String, Object?>{
                'orderNo': 'recharge-order-1',
                'orderStr': 'server-signed-order-string',
                'productId': 'product-1',
                'amountMinor': 600,
                'giftCoinAmount': 60,
                'channel': 'ALIPAY',
                'platform': 'ANDROID',
                'status': 'CREATED',
              }
            : <String, Object?>{};
        final bool statusRequest = request.uri.path.endsWith(
          '/ali/order/status',
        );
        request.response
          ..statusCode = statusRequest ? 500 : 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': statusRequest ? 500 : 200,
              'message': statusRequest ? 'FAIL' : 'OK',
              'data': data,
            }),
          );
        await request.response.close();
      });
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
            ),
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: adapter,
          );

      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder provisional = await repository.invokePayment(created);

      expect(provisional.state, RechargeOrderState.confirming);
      expect(provisional.message, '支付宝处理中，正在等待服务端确认');
      expect(provisional.nativeSdkCompleted, isFalse);
      expect(provisional.nativeResultStatus, '9000');
      expect(provisional.isNativeSdkSuccess, isFalse);
    },
  );

  test('unavailable native bridge leaves backend order unmodified', () async {
    final _FakeAlipayAdapter adapter = _FakeAlipayAdapter(available: false);
    final _ServerHarness harness = await _ServerHarness.start();
    addTearDown(harness.close);
    final BackendCommerceCatalogRepository repository =
        BackendCommerceCatalogRepository(
          apiClient: harness.client,
          routes: const BackendRouteCatalog(),
          alipayAppPayAdapter: adapter,
        );
    const RechargeProduct product = RechargeProduct(
      id: 'product-1',
      giftCoins: 60,
      priceCny: 6,
    );

    expect(repository.supportsPaymentChannelInvocation, isFalse);
    await expectLater(
      repository.createRechargeOrder(
        account: 'current-user-account',
        product: product,
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      ),
      throwsA(isA<Exception>()),
    );
    expect(harness.requests, isEmpty);
  });

  test(
    'retries an ambiguous Alipay order creation with one stable request id',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> requestIds = <String?>[];
      var calls = 0;
      server.listen((HttpRequest request) async {
        await utf8.decoder.bind(request).join();
        if (request.uri.path.endsWith('/recharge/products')) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 200,
                'message': 'OK',
                'data': <String, Object?>{
                  'platform': 'ANDROID',
                  'list': <Object?>[
                    <String, Object?>{
                      'productId': '00000000-0000-0000-0000-000000001001',
                      'title': '60礼物币',
                      'amountMinor': 600,
                      'amount': 6.00,
                      'giftCoinAmount': 60,
                      'bonusGiftCoin': 0,
                    },
                  ],
                  'total': 1,
                  'orderCreationStatus': 'READY',
                  'providerInvocation': false,
                },
              }),
            );
          await request.response.close();
          return;
        }
        requestIds.add(request.headers.value('X-Request-Id'));
        calls += 1;
        if (calls == 1) {
          request.response
            ..statusCode = 500
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 500,
                'message': 'temporary backend failure',
                'data': <String, Object?>{},
              }),
            );
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{
                'orderNo': 'recharge-order-retried',
                'orderStr': 'server-signed-order-string',
                'productId': 'product-1',
                'amountMinor': 600,
                'giftCoinAmount': 60,
                'channel': 'ALIPAY',
                'platform': 'ANDROID',
                'status': 'CREATED',
              },
            }),
          );
        await request.response.close();
      });

      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
            ),
            routes: const BackendRouteCatalog(),
            alipayCreateRequestIdGenerator: () =>
                'fixed-alipay-create-request-id',
            alipayAppPayAdapter: _FakeAlipayAdapter(),
          );
      const RechargeProduct product = RechargeProduct(
        id: 'product-1',
        giftCoins: 60,
        priceCny: 6,
      );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );

      await expectLater(
        repository.createRechargeOrder(
          account: 'current-user-account',
          product: product,
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      final RechargeOrder retried = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: product,
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      expect(retried.orderNo, 'recharge-order-retried');
      expect(calls, 2);
      expect(requestIds, <String?>[
        'fixed-alipay-create-request-id',
        'fixed-alipay-create-request-id',
      ]);
    },
  );

  test(
    'result refresh reconciles Alipay before a read and keeps DB authority',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<_Request> requests = <_Request>[];
      server.listen((HttpRequest request) async {
        await utf8.decoder.bind(request).join();
        requests.add(
          _Request(
            method: request.method,
            path: request.uri.path,
            query: request.uri.queryParameters,
            requestId: request.headers.value('X-Request-Id'),
            body: null,
          ),
        );
        if (request.method == 'POST') {
          request.response
            ..statusCode = 503
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 503,
                'message': 'provider temporarily unavailable',
                'data': <String, Object?>{},
              }),
            );
        } else {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 200,
                'message': 'OK',
                'data': <String, Object?>{
                  'orderNo': 'recharge-order-recovery',
                  'bool': false,
                  'status': 'CONFIRMING',
                },
              }),
            );
        }
        await request.response.close();
      });

      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
            ),
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: _FakeAlipayAdapter(),
          );
      final RechargeOrder order = RechargeOrder(
        orderNo: 'recharge-order-recovery',
        account: 'current-user-account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 60,
          priceCny: 6,
        ),
        channel: PaymentChannelType.alipay,
        state: RechargeOrderState.confirming,
        createdAt: DateTime(2026),
      );

      final RechargeOrder first = await repository.queryRechargeOrder(order);
      final RechargeOrder second = await repository.queryRechargeOrder(first);

      expect(first.state, RechargeOrderState.confirming);
      expect(second.state, RechargeOrderState.confirming);
      expect(requests, hasLength(4));
      expect(requests[0].method, 'POST');
      expect(requests[0].path, '/app-economy-api/pay/ali/order/reconcile');
      expect(requests[1].method, 'GET');
      expect(requests[1].path, '/app-economy-api/pay/ali/order/status');
      expect(requests[2].method, 'POST');
      expect(requests[2].path, '/app-economy-api/pay/ali/order/reconcile');
      expect(requests[3].method, 'GET');
      expect(requests[3].path, '/app-economy-api/pay/ali/order/status');
      expect(requests[0].requestId, startsWith('alipay-reconcile-'));
      expect(requests[2].requestId, requests[0].requestId);
    },
  );

  test('terminal Alipay and non-Alipay status reads never reconcile', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final List<_Request> requests = <_Request>[];
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      requests.add(
        _Request(
          method: request.method,
          path: request.uri.path,
          query: request.uri.queryParameters,
          requestId: request.headers.value('X-Request-Id'),
          body: null,
        ),
      );
      final bool isAlipay = request.uri.path.endsWith('/ali/order/status');
      final String orderNo = isAlipay
          ? 'recharge-order-terminal'
          : 'recharge-order-wechat';
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': <String, Object?>{
              'orderNo': orderNo,
              'bool': isAlipay,
              'status': isAlipay ? 'SUCCEEDED' : 'CONFIRMING',
            },
          }),
        );
      await request.response.close();
    });

    final BackendCommerceCatalogRepository repository =
        BackendCommerceCatalogRepository(
          apiClient: ApiClient(
            baseUri: Uri.parse(
              'http://${server.address.address}:${server.port}/',
            ),
            clientType: 'Android',
            clientInnerVersion: '6',
            authorizationProvider: () => 'Bearer test-session',
          ),
          routes: const BackendRouteCatalog(),
          alipayAppPayAdapter: _FakeAlipayAdapter(),
        );
    final RechargeProduct product = const RechargeProduct(
      id: 'product-1',
      giftCoins: 60,
      priceCny: 6,
    );
    final RechargeOrder terminalAlipay = RechargeOrder(
      orderNo: 'recharge-order-terminal',
      account: 'current-user-account',
      product: product,
      channel: PaymentChannelType.alipay,
      state: RechargeOrderState.succeeded,
      createdAt: DateTime(2026),
    );
    final RechargeOrder confirmingWechat = RechargeOrder(
      orderNo: 'recharge-order-wechat',
      account: 'current-user-account',
      product: product,
      channel: PaymentChannelType.wechat,
      state: RechargeOrderState.confirming,
      createdAt: DateTime(2026),
    );

    expect(
      (await repository.queryRechargeOrder(terminalAlipay)).state,
      RechargeOrderState.succeeded,
    );
    expect(
      (await repository.queryRechargeOrder(confirmingWechat)).state,
      RechargeOrderState.confirming,
    );
    expect(requests, hasLength(2));
    expect(requests[0].method, 'GET');
    expect(requests[0].path, '/app-economy-api/pay/ali/order/status');
    expect(requests[1].method, 'GET');
    expect(requests[1].path, '/app-economy-api/pay/isOrderSuccess');
  });

  test(
    'reuses the stable request id after an ambiguous create timeout',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<void> releaseFirstRequest = Completer<void>();
      final List<String?> requestIds = <String?>[];
      var calls = 0;
      server.listen((HttpRequest request) async {
        await utf8.decoder.bind(request).join();
        if (request.uri.path.endsWith('/recharge/products')) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 200,
                'message': 'OK',
                'data': <String, Object?>{
                  'platform': 'ANDROID',
                  'list': <Object?>[
                    <String, Object?>{
                      'productId': '00000000-0000-0000-0000-000000001001',
                      'title': '60礼物币',
                      'amountMinor': 600,
                      'amount': 6.00,
                      'giftCoinAmount': 60,
                      'bonusGiftCoin': 0,
                    },
                  ],
                  'total': 1,
                  'orderCreationStatus': 'READY',
                  'providerInvocation': false,
                },
              }),
            );
          await request.response.close();
          return;
        }
        calls += 1;
        requestIds.add(request.headers.value('X-Request-Id'));
        if (calls == 1) {
          // Keep the first request ambiguous until the client-side timeout
          // has fired. The second request must still be able to arrive while
          // this handler is waiting.
          await releaseFirstRequest.future;
          try {
            await request.response.close();
          } catch (_) {
            // The client has already abandoned this timed-out response.
          }
          return;
        }
        if (!releaseFirstRequest.isCompleted) {
          releaseFirstRequest.complete();
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{
                'orderNo': 'recharge-order-timeout-retried',
                'orderStr': 'server-signed-order-string',
                'productId': 'product-1',
                'amountMinor': 600,
                'giftCoinAmount': 60,
                'channel': 'ALIPAY',
                'platform': 'ANDROID',
                'status': 'CREATED',
              },
            }),
          );
        await request.response.close();
      });

      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
              timeout: const Duration(milliseconds: 40),
            ),
            routes: const BackendRouteCatalog(),
            alipayCreateRequestIdGenerator: () =>
                'fixed-alipay-create-timeout-id',
            alipayAppPayAdapter: _FakeAlipayAdapter(),
          );
      const RechargeProduct product = RechargeProduct(
        id: 'product-1',
        giftCoins: 60,
        priceCny: 6,
      );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );

      await expectLater(
        repository.createRechargeOrder(
          account: 'current-user-account',
          product: product,
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );
      final RechargeOrder retried = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: product,
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      expect(retried.orderNo, 'recharge-order-timeout-retried');
      expect(calls, 2);
      expect(requestIds, <String?>[
        'fixed-alipay-create-timeout-id',
        'fixed-alipay-create-timeout-id',
      ]);
    },
  );

  test(
    'rejects an Alipay order whose server totals differ from the catalog',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        await utf8.decoder.bind(request).join();
        if (request.uri.path.endsWith('/recharge/products')) {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'code': 200,
                'message': 'OK',
                'data': <String, Object?>{
                  'platform': 'ANDROID',
                  'list': <Object?>[
                    <String, Object?>{
                      'productId': '00000000-0000-0000-0000-000000001001',
                      'title': '60礼物币',
                      'amountMinor': 600,
                      'amount': 6.00,
                      'giftCoinAmount': 60,
                      'bonusGiftCoin': 0,
                    },
                  ],
                  'total': 1,
                  'orderCreationStatus': 'READY',
                  'providerInvocation': false,
                },
              }),
            );
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{
                'orderNo': 'mismatched-order',
                'orderStr': 'server-signed-order-string',
                'productId': 'product-1',
                'amountMinor': 601,
                'giftCoinAmount': 60,
                'channel': 'ALIPAY',
                'platform': 'ANDROID',
                'status': 'CONFIRMING',
              },
            }),
          );
        await request.response.close();
      });
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse(
                'http://${server.address.address}:${server.port}/',
              ),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
            ),
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: _FakeAlipayAdapter(),
          );
      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );

      await expectLater(
        repository.createRechargeOrder(
          account: 'current-user-account',
          product: const RechargeProduct(
            id: 'product-1',
            giftCoins: 60,
            priceCny: 6,
          ),
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('configured Alipay bridge accepts only READY catalog status', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': <String, Object?>{
              'platform': 'ANDROID',
              'list': <Object?>[
                <String, Object?>{
                  'productId': '00000000-0000-0000-0000-000000009001',
                  'title': '60礼物币',
                  'amountMinor': 600,
                  'amount': 6.00,
                  'giftCoinAmount': 60,
                  'bonusGiftCoin': 0,
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
    final BackendCommerceCatalogRepository repository =
        BackendCommerceCatalogRepository(
          apiClient: ApiClient(
            baseUri: Uri.parse(
              'http://${server.address.address}:${server.port}/',
            ),
            clientType: 'Android',
            clientInnerVersion: '6',
            authorizationProvider: () => 'Bearer test-session',
          ),
          routes: const BackendRouteCatalog(),
          alipayAppPayAdapter: _FakeAlipayAdapter(),
        );

    final List<RechargeProduct> products = await repository
        .fetchRechargeProducts(platform: ClientStorePlatform.android);
    expect(products.single.id, '00000000-0000-0000-0000-000000009001');
  });
}

class _FakeAlipayAdapter implements AlipayAppPayAdapter {
  _FakeAlipayAdapter({
    this.available = true,
    this.nativeResult = const AlipayAppPayResult(
      outcome: AlipayAppPayOutcome.sdkCompleted,
      reason: AlipayAppPayReason.processing,
      sdkCompleted: true,
      resultStatus: '9000',
    ),
  });

  final bool available;
  final AlipayAppPayResult nativeResult;
  final List<String> orderStrings = <String>[];

  @override
  bool get isAvailable => available;

  @override
  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  }) async {
    orderStrings.add(orderString);
    return nativeResult;
  }
}

class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.query,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String? requestId;
  final Object? body;
}

class _ServerHarness {
  _ServerHarness._(this.server, this.requests)
    : client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer test-session',
      );

  final HttpServer server;
  final List<_Request> requests;
  final ApiClient client;

  static Future<_ServerHarness> start({
    AlipayAppPayResult? nativeResult,
    String status = 'SUCCEEDED',
    int cancelStatusCode = 200,
    List<String>? statusSequence,
    List<int>? cancelStatusSequence,
    List<String>? cancelOutcomeSequence,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<_Request> requests = <_Request>[];
    final _ServerHarness harness = _ServerHarness._(server, requests);
    final _FakeAlipayAdapter adapter = _FakeAlipayAdapter(
      nativeResult:
          nativeResult ??
          const AlipayAppPayResult(
            outcome: AlipayAppPayOutcome.sdkCompleted,
            reason: AlipayAppPayReason.processing,
            sdkCompleted: true,
            resultStatus: '9000',
          ),
    );
    final List<String> statuses = List<String>.from(
      statusSequence ?? <String>[status],
    );
    final List<int> cancelStatuses = List<int>.from(
      cancelStatusSequence ?? <int>[cancelStatusCode],
    );
    final List<String> cancelOutcomes = List<String>.from(
      cancelOutcomeSequence ?? <String>[status],
    );
    var statusIndex = 0;
    var cancelStatusIndex = 0;
    var cancelOutcomeIndex = 0;
    server.listen((HttpRequest request) async {
      requests.add(
        _Request(
          method: request.method,
          path: request.uri.path,
          query: request.uri.queryParameters,
          requestId: request.headers.value('X-Request-Id'),
          body: null,
        ),
      );
      final bool cancelRequest = request.uri.path.endsWith('/ali/order/cancel');
      final bool statusRequest = request.uri.path.endsWith('/ali/order/status');
      final int responseStatusCode = cancelRequest
          ? cancelStatuses[cancelStatusIndex < cancelStatuses.length
                ? cancelStatusIndex++
                : cancelStatuses.length - 1]
          : 200;
      final String cancelOutcome = cancelRequest
          ? cancelOutcomes[cancelOutcomeIndex < cancelOutcomes.length
                ? cancelOutcomeIndex++
                : cancelOutcomes.length - 1]
          : '';
      final String responseStatus = statusRequest
          ? statuses[statusIndex < statuses.length
                ? statusIndex++
                : statuses.length - 1]
          : status;
      request.response
        ..statusCode = responseStatusCode
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': responseStatusCode,
            'message': responseStatusCode == 200 ? 'OK' : 'FAIL',
            'data': request.uri.path.endsWith('/recharge/products')
                ? <String, Object?>{
                    'platform': 'ANDROID',
                    'list': <Object?>[
                      <String, Object?>{
                        'productId': '00000000-0000-0000-0000-000000001001',
                        'title': '60礼物币',
                        'amountMinor': 600,
                        'amount': 6.00,
                        'giftCoinAmount': 60,
                        'bonusGiftCoin': 0,
                      },
                    ],
                    'total': 1,
                    'orderCreationStatus': 'READY',
                    'providerInvocation': false,
                  }
                : request.uri.path.endsWith('/ali/order')
                ? <String, Object?>{
                    'orderNo': 'recharge-order-1',
                    'orderStr': 'server-signed-order-string',
                    'productId': 'product-1',
                    'amountMinor': 600,
                    'giftCoinAmount': 60,
                    'channel': 'ALIPAY',
                    'platform': 'ANDROID',
                    'status': 'CREATED',
                  }
                : cancelRequest
                ? <String, Object?>{
                    'orderNo': 'recharge-order-1',
                    'bool': false,
                    'status': status,
                    'cancelOutcome': cancelOutcome,
                  }
                : <String, Object?>{
                    'orderNo': 'recharge-order-1',
                    'bool': responseStatus == 'SUCCEEDED',
                    'status': responseStatus,
                  },
          }),
        );
      await request.response.close();
    });
    harness.adapter = adapter;
    return harness;
  }

  late final _FakeAlipayAdapter adapter;

  Future<void> close() => server.close(force: true);
}
