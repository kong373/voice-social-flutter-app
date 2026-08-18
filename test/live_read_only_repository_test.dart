import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';

void main() {
  test('live repository parses user wallet orders and vendor readiness', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final List<String> requestedPaths = <String>[];

    server.listen((HttpRequest request) async {
      requestedPaths.add(request.uri.path);
      expect(request.headers.value('Client-Id'), 'mobile-public-client');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer access-token',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'OK',
          'data': _responseFor(request.uri.path),
        }),
      );
      await request.response.close();
    });

    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '6',
      authorizationProvider: () => 'Bearer access-token',
      requestHeadersProvider: () => const <String, String>{
        'Client-Id': 'mobile-public-client',
      },
    );
    final LiveReadOnlyRepository repository = LiveReadOnlyRepository(client);

    final LiveReadOnlyOverview overview = await repository.fetchOverview();
    final VendorReadinessOverview readiness =
        await repository.fetchVendorReadiness();

    expect(overview.user.userId, 10001);
    expect(overview.user.nickname, '测试用户');
    expect(overview.wallet.giftCoinBalance, 8800);
    expect(overview.wallet.cashBalance, 12.34);
    expect(overview.wallet.frozenBalance, 5.67);
    expect(overview.orders, hasLength(1));
    expect(overview.orders.single.orderNo, 'P202608180001');
    expect(readiness.contractVersion, 'vendor-boundary-v1');
    expect(readiness.integrationStatus, 'READY_FOR_PROVIDER_INTEGRATION');
    expect(readiness.runtimeStatus, 'VENDOR_BLOCKED');
    expect(readiness.allBoundariesReady, isTrue);
    expect(readiness.allRuntimeAdaptersReady, isFalse);
    expect(readiness.capabilities.keys, containsAll(<String>['SMS', 'RTC', 'IM', 'PAYMENT']));
    expect(readiness.capabilities['SMS']?.boundaryReady, isTrue);
    expect(readiness.capabilities['SMS']?.runtimeReady, isFalse);
    expect(
      readiness.capabilities['SMS']?.missingConfiguration,
      contains('app.vendor.sms.adapter-enabled=true'),
    );
    expect(
      readiness.toString(),
      isNot(contains('actual-secret-value')),
    );
    expect(
      requestedPaths,
      containsAll(<String>[
        '/app-register-api/userAccount/v1/current',
        '/app-economy-api/ncoin',
        '/app-mini-api/mini/v1/wallet/overview',
        '/app-economy-api/pay/getOrders',
        '/app-register-api/vendor/v1/readiness',
      ]),
    );
  });
}

Object _responseFor(String path) => switch (path) {
      '/app-register-api/userAccount/v1/current' => <String, Object?>{
          'userId': 10001,
          'loginName': 'account-10001',
          'nickName': '测试用户',
          'mobile': '13800138000',
          'roles': 'USER',
          'status': 'ACTIVE',
        },
      '/app-economy-api/ncoin' => <String, Object?>{'integer': 8800},
      '/app-mini-api/mini/v1/wallet/overview' => <String, Object?>{
          'balance': 12.34,
          'frozenBalance': 5.67,
        },
      '/app-economy-api/pay/getOrders' => <String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'orderNo': 'P202608180001',
              'amount': 6,
              'ncoin': 600,
              'payType': 'WECHAT',
              'status': 'PAID',
              'createDate': '2026-08-18T12:00:00Z',
            },
          ],
        },
      '/app-register-api/vendor/v1/readiness' => <String, Object?>{
          'contractVersion': 'vendor-boundary-v1',
          'integrationStatus': 'READY_FOR_PROVIDER_INTEGRATION',
          'runtimeStatus': 'VENDOR_BLOCKED',
          'allBoundariesReady': true,
          'allRuntimeAdaptersReady': false,
          'capabilities': <String, Object?>{
            for (final String capability in <String>['SMS', 'RTC', 'IM', 'PAYMENT'])
              capability: <String, Object?>{
                'capability': capability,
                'boundaryStatus': 'READY',
                'runtimeStatus': 'VENDOR_BLOCKED',
                'provider': 'UNCONFIGURED',
                'missingConfiguration': <String>[
                  'app.vendor.${capability.toLowerCase()}.adapter-enabled=true',
                ],
                'serverOnlySecretProperties': <String>[
                  'app.vendor.${capability.toLowerCase()}.server-secret',
                ],
                'adapterContract': 'VendorPorts.${capability}Port',
                'securityBoundary':
                    'All secret values remain server-side and are never returned.',
              },
          },
        },
      _ => <String, Object?>{},
    };
