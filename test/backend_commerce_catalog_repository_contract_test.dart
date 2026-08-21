import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

void main() {
  test('catalog capability flags and platform channels are explicit', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);
    final BackendCommerceCatalogRepository repository = harness.repository;
    expect(repository.supportsRechargeCatalog, isFalse);
    expect(repository.supportsPaymentChannelInvocation, isFalse);
    expect(
      repository.availableChannels(ClientStorePlatform.android),
      <PaymentChannelType>[
        PaymentChannelType.wechat,
        PaymentChannelType.alipay,
      ],
    );
    expect(
      repository.availableChannels(ClientStorePlatform.ios),
      <PaymentChannelType>[PaymentChannelType.appleIap],
    );
    await expectLater(
      repository.fetchRechargeProducts(platform: ClientStorePlatform.android),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
    expect(harness.requests, isEmpty);
  });

  test(
    'catalog recharge precheck and order preserve query/body contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/pay/check' => _Response.ok(<String, Object?>{}),
          '/app-economy-api/pay/v1/wechat/order' => _Response.ok(
            <String, Object?>{'outTradeNo': 'recharge-1'},
          ),
          '/app-economy-api/pay/isOrderSuccess' => _Response.ok(true),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository = harness.repository;
      final RechargeEligibility eligible = await repository
          .checkRechargeEligibility(youthModeEnabled: false);
      expect(eligible.allowed, isTrue);
      final RechargeProduct product = const RechargeProduct(
        id: 'p-1',
        giftCoins: 100,
        priceCny: 6,
      );
      final RechargeOrder order = await repository.createRechargeOrder(
        account: '  user-1 ',
        product: product,
        channel: PaymentChannelType.wechat,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );
      expect(order.orderNo, 'recharge-1');
      expect(order.account, 'user-1');
      expect(order.state, RechargeOrderState.created);
      final RechargeOrder confirmed = await repository.queryRechargeOrder(
        order,
      );
      expect(confirmed.state, RechargeOrderState.succeeded);
      expect(harness.requests, hasLength(4));
      expect(harness.requests[0].method, 'POST');
      expect(harness.requests[0].body, isNull);
      expect(harness.requests[1].path, '/app-economy-api/pay/check');
      expect(harness.requests[2].query, <String, String>{'amount': '6.00'});
      expect(harness.requests[3].query, <String, String>{
        'orderNo': 'recharge-1',
      });
    },
  );

  test(
    'catalog youth/platform/sdk guards fail closed before network writes',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository = harness.repository;
      final RechargeEligibility blocked = await repository
          .checkRechargeEligibility(youthModeEnabled: true);
      expect(blocked.allowed, isFalse);
      expect(blocked.message, contains('青少年模式'));
      const RechargeProduct product = RechargeProduct(
        id: 'p-1',
        giftCoins: 100,
        priceCny: 6,
      );
      await expectLater(
        repository.createRechargeOrder(
          account: 'user-1',
          product: product,
          channel: PaymentChannelType.appleIap,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.createRechargeOrder(
          account: 'user-1',
          product: product,
          channel: PaymentChannelType.appleIap,
          platform: ClientStorePlatform.ios,
          youthModeEnabled: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      await expectLater(
        repository.invokePayment(
          RechargeOrder(
            orderNo: 'recharge-1',
            account: 'user-1',
            product: product,
            channel: PaymentChannelType.wechat,
            state: RechargeOrderState.created,
            createdAt: DateTime(2026),
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      expect(harness.requests, hasLength(2));
      expect(
        harness.requests.map((RequestRecord item) => item.path),
        everyElement('/app-economy-api/pay/check'),
      );
    },
  );

  test(
    'catalog gift and decoration list filters retired/disabled records',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-mini-api/mini/v1/gift/list' => _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'giftId': 1,
                'giftName': '玫瑰',
                'price': 10,
                'categoryName': '热门',
              },
              <String, Object?>{'giftId': 2, 'giftName': '盲盒', 'price': 99},
              <String, Object?>{
                'giftId': 3,
                'giftName': '隐藏礼物',
                'price': 1,
                'status': 0,
              },
            ],
          }),
          '/app-api/user/userDecorations/getList' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'id': 'dec-1',
                  'decorationName': '月光头像框',
                  'type': 1,
                  'ncoin': 88,
                  'userDecorationId': 'owned-1',
                  'isPutOn': 1,
                },
                <String, Object?>{
                  'id': 'dec-2',
                  'name': '资料卡',
                  'type': 5,
                  'owned': false,
                  'equipped': false,
                },
              ],
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository = harness.repository;
      final List<GiftCatalogItem> gifts = await repository.fetchGiftCatalog();
      expect(gifts, hasLength(1));
      expect(gifts.single.name, '玫瑰');
      expect(gifts.single.category, GiftCatalogCategory.popular);
      final List<DecorationItem> decorations = await repository
          .fetchDecorations();
      expect(decorations, hasLength(2));
      expect(decorations.first.kind, DecorationKind.avatarFrame);
      expect(decorations.first.owned, isTrue);
      expect(decorations.first.equipped, isTrue);
      expect(decorations.last.kind, DecorationKind.profileCard);
      expect(harness.requests[1].body, <String, Object?>{
        'pageNum': 1,
        'pageSize': 100,
      });
    },
  );

  test(
    'catalog decoration purchase/equip use mutation then authoritative refetch',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/mall/userBuyOrGiveGoods' => _Response.ok(
            <String, Object?>{},
          ),
          '/app-api/user/userDecorations/putOn' => _Response.ok(
            <String, Object?>{},
          ),
          '/app-api/user/userDecorations/getList' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'id': '9',
                  'name': '月光头像框',
                  'type': 1,
                  'owned': true,
                  'isPutOn': 1,
                },
              ],
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository = harness.repository;
      final DecorationItem purchased = await repository.purchaseDecoration('9');
      expect(purchased.id, '9');
      expect(purchased.owned, isTrue);
      final DecorationItem equipped = await repository.setDecorationEquipped(
        decorationId: '9',
        equipped: true,
      );
      expect(equipped.equipped, isTrue);
      expect(harness.requests[0].method, 'POST');
      expect(harness.requests[0].body, <String, Object?>{
        'goodsId': 9,
        'buyNum': 1,
      });
      expect(harness.requests[1].path, '/app-api/user/userDecorations/getList');
      expect(harness.requests[2].method, 'PATCH');
      expect(harness.requests[2].body, <String, Object?>{
        'id': 9,
        'isPutOn': 1,
      });
      expect(harness.requests[3].path, '/app-api/user/userDecorations/getList');
    },
  );

  test('catalog error envelope maps HTTP/business failure', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return const _Response(
        statusCode: 409,
        code: 409,
        message: '礼物目录已下线',
        data: null,
      );
    });
    addTearDown(harness.close);
    await expectLater(
      harness.repository.fetchGiftCatalog(),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.kind, 'kind', ApiFailureKind.conflict)
            .having((ApiException e) => e.httpStatus, 'httpStatus', 409)
            .having((ApiException e) => e.message, 'message', '礼物目录已下线'),
      ),
    );
  });
}

class _Harness {
  _Harness._(this.server, this.requests)
    : repository = BackendCommerceCatalogRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
        ),
        routes: const BackendRouteCatalog(),
      );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommerceCatalogRepository repository;

  static Future<_Harness> start(
    FutureOr<_Response> Function(RequestRecord) handler,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final _Harness harness = _Harness._(server, requests);
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Response response = await handler(record);
      request.response.statusCode = response.statusCode;
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
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
}

class _Response {
  const _Response({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Response.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}
