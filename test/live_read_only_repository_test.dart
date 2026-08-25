import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';

void main() {
  test(
    'live repository parses user wallet orders and vendor readiness',
    () async {
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
      final VendorReadinessOverview readiness = await repository
          .fetchVendorReadiness();

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
      expect(
        readiness.capabilities.keys,
        containsAll(<String>['SMS', 'RTC', 'IM', 'PAYMENT']),
      );
      expect(readiness.capabilities['SMS']?.boundaryReady, isTrue);
      expect(readiness.capabilities['SMS']?.runtimeReady, isFalse);
      expect(
        readiness.capabilities['SMS']?.missingConfiguration,
        contains('app.vendor.sms.adapter-enabled=true'),
      );
      expect(readiness.toString(), isNot(contains('actual-secret-value')));
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
    },
  );

  test('wallet payloads must be objects', () async {
    final LiveReadOnlyRepository giftCoinRepository = LiveReadOnlyRepository(
      _StubApiClient(
        getResponses: <String, ApiResponse>{
          _giftCoinPath: _ok(<Object?>[]),
          _walletPath: _ok(_validWallet()),
        },
      ),
    );
    final LiveReadOnlyRepository walletRepository = LiveReadOnlyRepository(
      _StubApiClient(
        getResponses: <String, ApiResponse>{
          _giftCoinPath: _ok(_validGiftCoin()),
          _walletPath: _ok(<Object?>[]),
        },
      ),
    );

    await expectLater(
      giftCoinRepository.fetchWallet(),
      throwsA(_protocolFailure),
    );
    await expectLater(
      walletRepository.fetchWallet(),
      throwsA(_protocolFailure),
    );
  });

  test('wallet balances are required, typed, and non-negative', () async {
    final List<Map<String, Object?>> invalidGiftCoins = <Map<String, Object?>>[
      <String, Object?>{},
      <String, Object?>{'integer': '8800'},
      <String, Object?>{'integer': -1},
      <String, Object?>{'integer': 8800, 'value': '8800'},
      <String, Object?>{'integer': 8800, 'value': 8801},
    ];
    for (final Map<String, Object?> giftCoin in invalidGiftCoins) {
      await expectLater(
        LiveReadOnlyRepository(
          _StubApiClient(
            getResponses: <String, ApiResponse>{
              _giftCoinPath: _ok(giftCoin),
              _walletPath: _ok(_validWallet()),
            },
          ),
        ).fetchWallet(),
        throwsA(_protocolFailure),
      );
    }

    final List<Map<String, Object?>> invalidWallets = <Map<String, Object?>>[
      <String, Object?>{'frozenBalance': 5.67},
      <String, Object?>{'balance': '12.34', 'frozenBalance': 5.67},
      <String, Object?>{'balance': -1, 'frozenBalance': 5.67},
      <String, Object?>{'balance': 12.34},
      <String, Object?>{'balance': 12.34, 'frozenBalance': '5.67'},
      <String, Object?>{'balance': 12.34, 'frozenBalance': -1},
    ];
    for (final Map<String, Object?> wallet in invalidWallets) {
      await expectLater(
        LiveReadOnlyRepository(
          _StubApiClient(
            getResponses: <String, ApiResponse>{
              _giftCoinPath: _ok(_validGiftCoin()),
              _walletPath: _ok(wallet),
            },
          ),
        ).fetchWallet(),
        throwsA(_protocolFailure),
      );
    }
  });

  test('order list and records aliases must agree', () async {
    final Map<String, Object?> order = _validOrder();
    final LiveReadOnlyRepository matchingRepository = LiveReadOnlyRepository(
      _StubApiClient(
        getResponses: <String, ApiResponse>{
          _ordersPath: _ok(<String, Object?>{
            'list': <Object?>[order],
            'records': <Object?>[
              <String, Object?>{...order},
            ],
            'total': 1,
          }),
        },
      ),
    );
    final LiveReadOnlyRepository conflictingRepository = LiveReadOnlyRepository(
      _StubApiClient(
        getResponses: <String, ApiResponse>{
          _ordersPath: _ok(<String, Object?>{
            'list': <Object?>[order],
            'records': <Object?>[
              <String, Object?>{...order, 'orderNo': 'P-CONFLICT'},
            ],
            'total': 1,
          }),
        },
      ),
    );

    expect(await matchingRepository.fetchOrders(), hasLength(1));
    await expectLater(
      conflictingRepository.fetchOrders(),
      throwsA(_protocolFailure),
    );
  });

  test('orders require total and reject invalid total aliases', () async {
    final Map<String, Object?> order = _validOrder();
    final List<Map<String, Object?>> invalidResponses = <Map<String, Object?>>[
      <String, Object?>{
        'list': <Object?>[order],
      },
      <String, Object?>{
        'list': <Object?>[order],
        'total': '1',
      },
      <String, Object?>{
        'list': <Object?>[order],
        'total': -1,
      },
      <String, Object?>{
        'list': <Object?>[order],
        'total': 0,
      },
    ];
    for (final Map<String, Object?> data in invalidResponses) {
      await expectLater(
        LiveReadOnlyRepository(
          _StubApiClient(
            getResponses: <String, ApiResponse>{_ordersPath: _ok(data)},
          ),
        ).fetchOrders(),
        throwsA(_protocolFailure),
      );
    }
  });

  test('orders reject malformed authoritative fields', () async {
    final List<Map<String, Object?>> invalidOrders = <Map<String, Object?>>[
      <String, Object?>{..._validOrder(), 'orderNo': ''},
      <String, Object?>{..._validOrder(), 'amount': '6.00'},
      <String, Object?>{..._validOrder(), 'amount': -1},
      <String, Object?>{..._validOrder(), 'ncoin': '600'},
      <String, Object?>{..._validOrder(), 'ncoin': -1},
      <String, Object?>{..._validOrder(), 'status': 'UNKNOWN'},
      <String, Object?>{..._validOrder(), 'createDate': ''},
      <String, Object?>{..._validOrder(), 'createDate': 'not-a-time'},
    ];
    for (final Map<String, Object?> order in invalidOrders) {
      await expectLater(
        LiveReadOnlyRepository(
          _StubApiClient(
            getResponses: <String, ApiResponse>{
              _ordersPath: _ok(<String, Object?>{
                'list': <Object?>[order],
                'total': 1,
              }),
            },
          ),
        ).fetchOrders(),
        throwsA(_protocolFailure),
      );
    }
  });
}

const String _giftCoinPath = '/app-economy-api/ncoin';
const String _walletPath = '/app-mini-api/mini/v1/wallet/overview';
const String _ordersPath = '/app-economy-api/pay/getOrders';

final Matcher _protocolFailure = isA<ApiException>().having(
  (ApiException error) => error.kind,
  'kind',
  ApiFailureKind.protocol,
);

ApiResponse _ok(Object? data) =>
    ApiResponse(code: 200, message: 'OK', data: data);

Map<String, Object?> _validGiftCoin() => <String, Object?>{
  'integer': 8800,
  'value': 8800,
};

Map<String, Object?> _validWallet() => <String, Object?>{
  'balance': 12.34,
  'frozenBalance': 5.67,
};

Map<String, Object?> _validOrder() => <String, Object?>{
  'orderNo': 'P202608180001',
  'amount': 6,
  'ncoin': 600,
  'payType': 'WECHAT',
  'status': 'SUCCEEDED',
  'createDate': '2026-08-18T12:00:00Z',
};

class _StubApiClient extends ApiClient {
  _StubApiClient({required this.getResponses})
    : super(
        baseUri: Uri.parse('http://stub.invalid/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: _authorization,
      );

  final Map<String, ApiResponse> getResponses;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final ApiResponse? response = getResponses[path];
    if (response == null) {
      throw StateError('Unexpected GET $path');
    }
    return response;
  }

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final ApiResponse? response = getResponses[path];
    if (response == null) {
      throw StateError('Unexpected POST $path');
    }
    return response;
  }
}

String? _authorization() => 'Bearer test-token';

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
    'total': 1,
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
