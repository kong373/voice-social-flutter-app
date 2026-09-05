import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/data/backend_apple_iap_port.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

void main() {
  test(
    'financial request keeps its initial principal while transport opens',
    () async {
      final requests = <_Request>[];
      final server = await _serve(
        requests,
        (_) => _response(401, 40101, 'unauthorized', null),
      );
      addTearDown(() => server.close(force: true));
      String authorization = 'Bearer session-a';
      final port = BackendAppleIapPort(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'iOS',
          clientInnerVersion: '6',
          authorizationProvider: () => authorization,
        ),
        routes: const BackendRouteCatalog(),
      );
      final request = port.createOrder(
        productId: '00000000-0000-0000-0000-000000001101',
        requestId: 'principal-bound-before-transport',
      );
      authorization = 'Bearer session-b';
      await expectLater(request, throwsA(isA<ApiException>()));
      expect(requests.single.authorization, 'Bearer session-a');
    },
  );
  test(
    'Apple financial POST never refreshes and replays under another session',
    () async {
      final requests = <_Request>[];
      final server = await _serve(
        requests,
        (_) => _response(401, 40101, 'unauthorized', null),
      );
      addTearDown(() => server.close(force: true));
      int refreshCalls = 0;
      final port = BackendAppleIapPort(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'iOS',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
          unauthorizedRecovery: () async {
            refreshCalls += 1;
            return true;
          },
        ),
        routes: const BackendRouteCatalog(),
      );
      await expectLater(
        port.createOrder(
          productId: '00000000-0000-0000-0000-000000001101',
          requestId: 'no-cross-session-create',
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        port.deliverTransaction(
          orderNo: 'vs_apple_order_1',
          transaction: _transaction,
          requestId: 'no-cross-session-deliver',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0);
      expect(requests, hasLength(2));
    },
  );
  test('Apple backend port sends minimal authenticated contracts', () async {
    final List<_Request> requests = <_Request>[];
    final HttpServer server = await _serve(requests, (_Request request) {
      return switch (request.path) {
        '/app-economy-api/pay/apple/order' => _ok(<String, Object?>{
          'orderNo': 'vs_apple_order_1',
          'productId': '00000000-0000-0000-0000-000000001101',
          'storeProductId': 'com.kong373.voiceSocialApp.recharge.60',
          'appAccountToken': '11111111-1111-4111-8111-111111111111',
          'amountMinor': 600,
          'giftCoinAmount': 60,
          'status': 'CONFIRMING',
        }),
        '/app-economy-api/pay/apple/transaction' => _ok(<String, Object?>{
          'orderNo': 'vs_apple_order_1',
          'transactionId': '100000000000001',
          'deliveryState': 'DELIVERED',
          'creditedGiftCoins': 60,
          'finishAllowed': true,
        }),
        '/app-economy-api/pay/apple/order/status' => _ok(<String, Object?>{
          'orderNo': 'vs_apple_order_1',
          'status': 'SUCCEEDED',
          'creditedGiftCoins': 60,
          'transactionId': '100000000000001',
          'finishAllowed': true,
        }),
        _ => _response(404, 404, 'not found', null),
      };
    });
    addTearDown(() => server.close(force: true));
    final BackendAppleIapPort port = _port(server);

    final AppleIapOrderBinding order = await port.createOrder(
      productId: '00000000-0000-0000-0000-000000001101',
      requestId: 'apple-order-request-1',
    );
    final AppleIapDeliveryAck ack = await port.deliverTransaction(
      orderNo: order.orderNo,
      transaction: _transaction,
      requestId: 'apple-transaction-request-1',
    );
    final AppleIapOrderStatus status = await port.readOrderStatus(
      order.orderNo,
    );

    expect(order.storeProductId, 'com.kong373.voiceSocialApp.recharge.60');
    expect(order.amountMinor, 600);
    expect(ack.deliveryState, AppleIapDeliveryState.delivered);
    expect(status.status, 'SUCCEEDED');
    expect(requests, hasLength(3));
    expect(requests[0].method, 'POST');
    expect(requests[0].requestId, 'apple-order-request-1');
    expect(requests[0].authorization, 'Bearer contract-test');
    expect(requests[0].body, <String, Object?>{
      'productId': '00000000-0000-0000-0000-000000001101',
    });
    expect(requests[1].body, <String, Object?>{
      'orderNo': 'vs_apple_order_1',
      'signedTransaction': 'header.payload.signature',
    });
    expect(requests[2].method, 'GET');
    expect(requests[2].query, <String, String>{'orderNo': 'vs_apple_order_1'});
  });

  test('Apple backend port rejects contradictory finish authority', () async {
    final HttpServer server = await _serve(<_Request>[], (_) {
      return _ok(<String, Object?>{
        'orderNo': 'vs_apple_order_1',
        'transactionId': '100000000000001',
        'deliveryState': 'PENDING',
        'creditedGiftCoins': 0,
        'finishAllowed': true,
      });
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      _port(server).deliverTransaction(
        orderNo: 'vs_apple_order_1',
        transaction: _transaction,
        requestId: 'apple-transaction-request-1',
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('Apple backend port rejects catalog binding drift', () async {
    final HttpServer server = await _serve(<_Request>[], (_) {
      return _ok(<String, Object?>{
        'orderNo': 'vs_apple_order_1',
        'productId': '00000000-0000-0000-0000-000000001999',
        'storeProductId': 'com.kong373.voiceSocialApp.recharge.60',
        'appAccountToken': '11111111-1111-4111-8111-111111111111',
        'amountMinor': 600,
        'giftCoinAmount': 60,
        'status': 'CONFIRMING',
      });
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      _port(server).createOrder(
        productId: '00000000-0000-0000-0000-000000001101',
        requestId: 'apple-order-request-1',
      ),
      throwsA(isA<ApiException>()),
    );
  });
}

final AppleIapTransaction _transaction = AppleIapTransaction(
  transactionId: '100000000000001',
  originalTransactionId: '100000000000001',
  productId: 'com.kong373.voiceSocialApp.recharge.60',
  appAccountToken: '11111111-1111-4111-8111-111111111111',
  purchaseDate: DateTime.utc(2026, 9, 4),
  signedTransaction: 'header.payload.signature',
  verification: AppleIapVerification.verified,
  source: AppleIapTransactionSource.purchase,
);

BackendAppleIapPort _port(HttpServer server) => BackendAppleIapPort(
  apiClient: ApiClient(
    baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
    clientType: 'iOS',
    clientInnerVersion: '6',
    authorizationProvider: () => 'Bearer contract-test',
  ),
  routes: const BackendRouteCatalog(),
);

Future<HttpServer> _serve(
  List<_Request> requests,
  FutureOr<_Response> Function(_Request request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String body = await utf8.decoder.bind(request).join();
    final _Request record = _Request(
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      requestId: request.headers.value('X-Request-Id'),
      body: body.isEmpty
          ? null
          : Map<String, Object?>.from(jsonDecode(body) as Map),
    );
    requests.add(record);
    final _Response response = await handler(record);
    request.response.statusCode = response.httpStatus;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
        'code': response.code,
        'message': response.message,
        'data': response.data,
      }),
    );
    await request.response.close();
  });
  return server;
}

class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String? authorization;
  final String? requestId;
  final Map<String, Object?>? body;
}

class _Response {
  const _Response(this.httpStatus, this.code, this.message, this.data);

  final int httpStatus;
  final int code;
  final String message;
  final Object? data;
}

_Response _ok(Object? data) => _response(200, 200, 'OK', data);

_Response _response(int status, int code, String message, Object? data) =>
    _Response(status, code, message, data);
