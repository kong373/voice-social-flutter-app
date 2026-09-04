import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel productionChannel = MethodChannel(
    'voice_social_app/alipay_production_contract_test',
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(productionChannel, null);
  });

  test('production environment selects online Alipay mode', () {
    final AppEnvironment environment = AppEnvironment.fromResolvedValues(
      backendModeValue: 'live',
      deploymentValue: 'production',
      timeoutValue: '15',
      apiBaseUrl: 'https://api.example.invalid/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      liveProbePath: '/',
      allowInsecureHttp: false,
      enableAlipayAppPay: true,
      releaseBuild: true,
    );

    environment.validateLiveConfiguration();
    expect(environment.isLive, isTrue);
    expect(environment.enableAlipayAppPay, isTrue);
    expect(environment.useAlipaySandbox, isFalse);
    expect(environment.redactedSummary['useAlipaySandbox'], isFalse);

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: environment,
    );
    final MethodChannelAlipayAppPayAdapter adapter =
        dependencies.alipayAppPayAdapter as MethodChannelAlipayAppPayAdapter;
    expect(adapter.isAvailable, isTrue);
    expect(adapter.sandboxMode, isFalse);
  });

  test('debug formal acceptance selects online mode only for development', () {
    final AppEnvironment environment = AppEnvironment.fromResolvedValues(
      backendModeValue: 'live',
      deploymentValue: 'development',
      timeoutValue: '15',
      apiBaseUrl: 'http://10.0.2.2:18080/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      liveProbePath: '/',
      allowInsecureHttp: true,
      enableAlipayAppPay: true,
      alipayFormalAcceptance: true,
      releaseBuild: false,
    );

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: environment,
    );
    final MethodChannelAlipayAppPayAdapter adapter =
        dependencies.alipayAppPayAdapter as MethodChannelAlipayAppPayAdapter;
    expect(environment.useAlipaySandbox, isFalse);
    expect(adapter.sandboxMode, isFalse);
  });

  test('production bridge sends a typed sandbox=false flag', () async {
    Map<String, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(productionChannel, (MethodCall call) async {
          expect(call.method, 'pay');
          arguments = Map<String, Object?>.from(call.arguments as Map);
          return <String, Object?>{
            'sdkCompleted': true,
            'resultStatus': '9000',
            'bridgeOutcome': 'pay_task_returned',
          };
        });

    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: productionChannel,
          enabled: true,
          sandbox: false,
          isAndroid: () => true,
          consentChecker: () async => true,
        );
    final AlipayAppPayResult result = await adapter.pay(
      orderNo: 'formal-order-1',
      orderString: 'server-signed-formal-order',
    );

    expect(arguments, <String, Object?>{
      'orderStr': 'server-signed-formal-order',
      'sandbox': false,
    });
    expect(result.sdkCompleted, isTrue);
    expect(result.resultStatus, '9000');
    expect(result.isSdkSuccess, isTrue);
    expect(result.isProvisional, isTrue);
    expect(result.vendorStatus, isNull);
  });

  test(
    'native 9000 remains provisional until the backend status is succeeded',
    () async {
      final _AuthorityHttpClient transport = _AuthorityHttpClient();
      final _FakeAlipayAdapter adapter = _FakeAlipayAdapter();
      final BackendCommerceCatalogRepository repository =
          BackendCommerceCatalogRepository(
            apiClient: ApiClient(
              baseUri: Uri.parse('http://authority.invalid/'),
              clientType: 'Android',
              clientInnerVersion: '6',
              authorizationProvider: () => 'Bearer test-session',
              httpClient: transport,
            ),
            routes: const BackendRouteCatalog(),
            alipayAppPayAdapter: adapter,
          );
      const RechargeProduct product = RechargeProduct(
        id: '00000000-0000-0000-0000-000000001001',
        giftCoins: 60,
        priceCny: 6,
      );

      await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      final RechargeOrder created = await repository.createRechargeOrder(
        account: 'current-user-account',
        product: product,
        channel: PaymentChannelType.alipay,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );

      final RechargeOrder provisional = await repository.invokePayment(created);
      expect(adapter.invocations, 1);
      expect(provisional.isNativeSdkSuccess, isTrue);
      expect(provisional.state, RechargeOrderState.confirming);
      expect(provisional.message, '服务端仍在确认订单');
      expect(transport.paths, <String>[
        '/app-mini-api/mini/v1/recharge/products',
        '/app-economy-api/pay/ali/order',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
      ]);

      transport.status = 'SUCCEEDED';
      final RechargeOrder authoritative = await repository.queryRechargeOrder(
        provisional,
      );
      expect(authoritative.state, RechargeOrderState.succeeded);
      expect(authoritative.message, '服务端已确认到账');
      expect(transport.paths, <String>[
        '/app-mini-api/mini/v1/recharge/products',
        '/app-economy-api/pay/ali/order',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
        '/app-economy-api/pay/ali/order/reconcile',
        '/app-economy-api/pay/ali/order/status',
      ]);
    },
  );

  test('formal and sandbox wallet packages stay explicitly separated', () {
    final String bridge = File(
      'packages/alipay_app_pay/android/src/main/kotlin/'
      'com/kong373/alipay_app_pay/AlipayAppPayPlugin.kt',
    ).readAsStringSync();
    final String productionGuide = File(
      'docs/alipay-app-pay-production.md',
    ).readAsStringSync();
    final String sandboxRunner = File(
      'tool/qa/run_alipay_focused_smoke.sh',
    ).readAsStringSync();

    expect(bridge, contains('AlipaySdkEnvironment.setForPay(sandbox)'));
    expect(bridge, contains('EnvUtils.EnvEnum.ONLINE'));
    expect(bridge, contains('EnvUtils.EnvEnum.SANDBOX'));
    expect(bridge, isNot(contains('com.eg.android.AlipayGphoneRC')));
    expect(productionGuide, contains('com.eg.android.AlipayGphone'));
    expect(productionGuide, contains('com.eg.android.AlipayGphoneRC'));
    expect(productionGuide, contains('sandbox: false'));
    expect(productionGuide, contains('sandbox: true'));
    expect(
      sandboxRunner,
      contains("TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'"),
    );
  });
}

class _FakeAlipayAdapter implements AlipayAppPayAdapter {
  int invocations = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  }) async {
    invocations += 1;
    return const AlipayAppPayResult(
      outcome: AlipayAppPayOutcome.sdkCompleted,
      reason: AlipayAppPayReason.processing,
      sdkCompleted: true,
      resultStatus: '9000',
      bridgeOutcome: AlipayAppPayBridgeOutcome.payTaskReturned,
    );
  }
}

class _AuthorityHttpClient implements HttpClient {
  final List<String> paths = <String>[];
  String status = 'CONFIRMING';

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    paths.add(url.path);
    return _AuthorityHttpClientRequest(this, url);
  }

  Object? responseData(Uri url) {
    final Map<String, Object?> data;
    if (url.path.endsWith('/recharge/products')) {
      data = <String, Object?>{
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
      };
    } else if (url.path.endsWith('/ali/order')) {
      data = <String, Object?>{
        'orderNo': 'formal-recharge-order-1',
        'orderStr': 'server-signed-formal-order',
        'productId': '00000000-0000-0000-0000-000000001001',
        'amountMinor': 600,
        'giftCoinAmount': 60,
        'channel': 'ALIPAY',
        'platform': 'ANDROID',
        'status': 'CREATED',
      };
    } else if (url.path.endsWith('/ali/order/status')) {
      data = <String, Object?>{
        'orderNo': 'formal-recharge-order-1',
        'bool': status == 'SUCCEEDED',
        'status': status,
      };
    } else {
      data = <String, Object?>{};
    }
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthorityHttpClientRequest implements HttpClientRequest {
  _AuthorityHttpClientRequest(this.owner, this.url);

  final _AuthorityHttpClient owner;
  final Uri url;

  @override
  final HttpHeaders headers = _AuthorityHttpHeaders();

  @override
  void write(Object? object) {}

  @override
  Future<HttpClientResponse> close() async =>
      _AuthorityHttpClientResponse(owner.responseData(url));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthorityHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthorityHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _AuthorityHttpClientResponse(Object? data)
    : super(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': data,
            }),
          ),
        ),
      );

  @override
  int get statusCode => 200;

  @override
  final HttpHeaders headers = _AuthorityHttpHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
