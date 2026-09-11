import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

void main() {
  _Binding();

  for (final scenario in [
    'open-switch',
    '401-switch',
    'refresh-switch',
    'refresh-same',
    'response-switch',
  ]) {
    test(
      'Alipay create is bound to the initiating identity: $scenario',
      () async {
        final f = await _Fixture.create();
        final entered = Completer<void>();
        final release = Completer<void>();
        if (scenario == 'open-switch') {
          f.transport.beforeOpen = (method, uri) async {
            if (uri.path.endsWith('/ali/order')) {
              entered.complete();
              await release.future;
            }
          };
        }
        f.onRequest = (request) async {
          if (request.uri.path.endsWith('/ali/order') && f.orders.length == 1) {
            if (scenario == '401-switch' || scenario == 'response-switch') {
              f.switchIdentity();
            }
            if (scenario.contains('401') || scenario.startsWith('refresh-')) {
              return 401;
            }
          }
          return 200;
        };
        f.onRecovery = () async {
          if (scenario == 'refresh-switch') f.switchIdentity();
          if (scenario == 'refresh-same') f.token = 'Bearer A-refreshed';
          return true;
        };
        final result = _outcome(f.createOrder());
        if (scenario == 'open-switch') {
          await entered.future;
          f.switchIdentity();
          release.complete();
        }
        final outcome = await result;
        if (scenario == 'refresh-same') {
          expect(outcome, isA<RechargeOrder>());
          expect(f.orders.map((r) => r.authorization), [
            'Bearer A',
            'Bearer A-refreshed',
          ]);
          expect(f.orders[0].requestId, f.orders[1].requestId);
          expect(f.orders[0].body, f.orders[1].body);
        } else {
          expect(outcome, _identityFailure);
          expect(
            f.orders.map((r) => r.authorization),
            scenario == 'open-switch' ? isEmpty : ['Bearer A'],
          );
        }
        expect(f.recoveryCalls, scenario.startsWith('refresh-') ? 1 : 0);
        expect(f.nativeCalls, 0);
      },
    );
  }

  for (final sameUser in [false, true]) {
    test(
      'consent wait cannot launch an old identity payment; sameUser=$sameUser',
      () async {
        final entered = Completer<void>();
        final consent = Completer<bool>();
        final f = await _Fixture.create(
          consent: () {
            entered.complete();
            return consent.future;
          },
        );
        final order = await f.createOrder();
        final result = _outcome(f.repository.invokePayment(order));
        await entered.future;
        f.switchIdentity(sameUser: sameUser);
        consent.complete(true);
        expect(await result, _identityFailure);
        expect(f.nativeCalls, 0);
        expect(f.recoveryRequests, isEmpty);
      },
    );
  }

  test(
    'an order created before logout cannot launch after another login',
    () async {
      final f = await _Fixture.create();
      final order = await f.createOrder();
      f.switchIdentity(sameUser: true);
      expect(
        await _outcome(f.repository.invokePayment(order)),
        _identityFailure,
      );
      expect(f.nativeCalls, 0);
      expect(f.recoveryRequests, isEmpty);
    },
  );

  test(
    'same-user relogin does not inherit a pending create or idempotency key',
    () async {
      final f = await _Fixture.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.onRequest = (request) async {
        if (request.uri.path.endsWith('/ali/order') && f.orders.length == 1) {
          entered.complete();
          await release.future;
        }
        return 200;
      };
      final old = _outcome(f.createOrder());
      await entered.future;
      f.switchIdentity(sameUser: true);
      final current = _outcome(f.createOrder());
      release.complete();
      expect(await old, _identityFailure);
      expect(await current, isA<RechargeOrder>());
      expect(f.orders.length, 2);
      expect(f.orders[0].requestId, isNot(f.orders[1].requestId));
    },
  );

  test(
    'late native success after logout cannot reconcile or publish old result',
    () async {
      final native = Completer<Object?>();
      final entered = Completer<void>();
      final f = await _Fixture.create(
        native: () {
          entered.complete();
          return native.future;
        },
      );
      final order = await f.createOrder();
      final result = _outcome(f.repository.invokePayment(order));
      await entered.future;
      f.switchIdentity();
      native.complete(_nativeSuccess);
      expect(await result, _identityFailure);
      expect(f.nativeCalls, 1);
      expect(f.recoveryRequests, isEmpty);
    },
  );

  for (final route in [
    '/ali/order/reconcile',
    '/ali/order/cancel',
    '/ali/order/status',
  ]) {
    test(
      'Alipay recovery remains identity-bound across $route connection wait',
      () async {
        final f = await _Fixture.create();
        var order = await f.createOrder();
        if (route.endsWith('/cancel')) {
          order = order.withNativeBridgeResult(
            sdkCompleted: false,
            resultStatus: '6001',
            outcome: 'userCanceled',
            reason: 'userCanceled',
            bridgeOutcome: 'pay_task_returned',
          );
        } else if (route.endsWith('/status')) {
          order = order.copyWith(state: RechargeOrderState.succeeded);
        }
        final entered = Completer<void>();
        final release = Completer<void>();
        f.transport.beforeOpen = (method, uri) async {
          if (uri.path.endsWith(route)) {
            entered.complete();
            await release.future;
          }
        };
        final result = _outcome(f.repository.queryRechargeOrder(order));
        await entered.future;
        f.switchIdentity();
        release.complete();
        expect(await result, _identityFailure);
        expect(f.recoveryRequests, isEmpty);
      },
    );
  }

  test(
    'unchanged identity reaches native then authoritative reconciliation',
    () async {
      final f = await _Fixture.create();
      final order = await f.createOrder();
      final result = await f.repository.invokePayment(order);
      expect(f.nativeCalls, 1);
      expect(result.state, RechargeOrderState.succeeded);
      expect(f.recoveryRequests.map((r) => r.path), [
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
      ]);
      expect(
        f.recoveryRequests.every((r) => r.authorization == 'Bearer A'),
        isTrue,
      );
    },
  );
}

const _nativeSuccess = <String, Object?>{
  'sdkCompleted': true,
  'resultStatus': '9000',
  'bridgeOutcome': 'pay_task_returned',
};
final _identityFailure = isA<ApiException>().having(
  (error) => error.kind,
  'kind',
  ApiFailureKind.unauthorized,
);
Future<Object> _outcome(Future<RechargeOrder> future) =>
    future.then<Object>((value) => value, onError: (Object error) => error);

class _Fixture {
  _Fixture(this.server, this.transport);
  final HttpServer server;
  final _Transport transport;
  late final BackendCommerceCatalogRepository repository;
  int? userId = 1;
  int generation = 1;
  String token = 'Bearer A';
  int nativeCalls = 0;
  int recoveryCalls = 0;
  final orders = <_Request>[];
  final recoveryRequests = <_Request>[];
  Future<int> Function(HttpRequest)? onRequest;
  Future<bool> Function()? onRecovery;
  void switchIdentity({bool sameUser = false}) {
    userId = null;
    generation++;
    userId = sameUser ? 1 : 2;
    generation++;
    token = sameUser ? 'Bearer A-relogin' : 'Bearer B';
  }

  static Future<_Fixture> create({
    Future<bool> Function()? consent,
    Future<Object?> Function()? native,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = _Fixture(server, _Transport());
    const channel = MethodChannel('voice_social_app/alipay_identity_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          f.nativeCalls++;
          return native == null ? _nativeSuccess : await native();
        });
    addTearDown(() async {
      f.transport.close(force: true);
      await server.close(force: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final observed = _Request(
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        request.headers.value('X-Request-Id'),
        body,
      );
      final isOrder = request.uri.path.endsWith('/ali/order');
      if (isOrder) f.orders.add(observed);
      if (request.uri.path.contains('/ali/order/'))
        f.recoveryRequests.add(observed);
      final status = await f.onRequest?.call(request) ?? 200;
      final data = request.uri.path.endsWith('/recharge/products')
          ? <String, Object?>{
              'platform': 'ANDROID',
              'list': <Object?>[],
              'total': 0,
              'orderCreationStatus': 'READY',
              'providerInvocation': false,
            }
          : isOrder
          ? <String, Object?>{
              'orderNo': 'fixture_order_${f.orders.length}',
              'orderStr': 'local-test-placeholder',
              'productId': 'product-1',
              'amountMinor': 600,
              'giftCoinAmount': 60,
              'channel': 'ALIPAY',
              'platform': 'ANDROID',
              'status': 'CREATED',
            }
          : <String, Object?>{
              'orderNo': 'fixture_order_1',
              'status': 'SUCCEEDED',
              'bool': true,
            };
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({'code': status, 'message': 'fixture', 'data': data}),
        );
      await request.response.close();
    });
    f.repository = BackendCommerceCatalogRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'Android',
        clientInnerVersion: '6',
        httpClient: f.transport,
        authorizationProvider: () => f.token,
        unauthorizedRecovery: () async {
          f.recoveryCalls++;
          return await f.onRecovery?.call() ?? false;
        },
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => f.userId,
      identityGeneration: () => f.generation,
      alipayAppPayAdapter: MethodChannelAlipayAppPayAdapter(
        enabled: true,
        sandbox: true,
        channel: channel,
        isAndroid: () => true,
        consentChecker: consent ?? () async => true,
      ),
    );
    await f.repository.fetchRechargeProducts(
      platform: ClientStorePlatform.android,
    );
    return f;
  }

  Future<RechargeOrder> createOrder() => repository.createRechargeOrder(
    account: 'account-A',
    product: const RechargeProduct(id: 'product-1', giftCoins: 60, priceCny: 6),
    channel: PaymentChannelType.alipay,
    platform: ClientStorePlatform.android,
    youthModeEnabled: false,
  );
}

class _Request {
  _Request(this.path, this.authorization, this.requestId, this.body);
  final String path;
  final String? authorization;
  final String? requestId;
  final String body;
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _Transport implements HttpClient {
  final HttpClient delegate = HttpClient();
  Future<void> Function(String, Uri)? beforeOpen;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    await beforeOpen?.call(method, url);
    return delegate.openUrl(method, url);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
