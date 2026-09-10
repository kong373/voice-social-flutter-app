import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

import 'support/media_http_fakes.dart';

const _upgradeMessage = '充值需要 iOS 15 或更高版本';
const _storeProductId = 'com.kong373.voiceSocialApp.recharge.60';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native unsupported_os is not reduced to an empty product catalog',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);

      await expectLater(
        fixture.coordinator.validateProducts([_storeProductId]),
        throwsA(_requiresIos15),
      );

      expect(fixture.nativeCalls, ['availability']);
      expect(fixture.backend.calls, isEmpty);
    },
  );

  for (final state in [
    'payments_disabled',
    'unsupported_platform',
    'unavailable',
    'unknown_native_state',
  ]) {
    test(
      '$state stays unavailable without an incorrect OS upgrade error',
      () async {
        final fixture = _Fixture(state: state);
        addTearDown(fixture.coordinator.dispose);

        expect(
          await fixture.coordinator.validateProducts([_storeProductId]),
          isEmpty,
        );
        expect(fixture.nativeCalls, ['availability']);
        expect(fixture.backend.calls, isEmpty);
      },
    );
  }

  test(
    'READY backend catalog propagates unsupported OS and opens no payment channel',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);

      await expectLater(
        fixture.repository.fetchRechargeProducts(
          platform: ClientStorePlatform.ios,
        ),
        throwsA(_requiresIos15),
      );

      fixture.expectReadOnly(attempts: 1);
    },
  );

  testWidgets(
    'recharge page shows iOS 15 requirement and retry never buys or offers a payment bypass',
    (tester) async {
      final fixture = _Fixture();
      final dependencies = _Dependencies(fixture.repository);
      addTearDown(fixture.coordinator.dispose);
      addTearDown(dependencies.sessionManager.dispose);

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: const MaterialApp(home: RechargeCatalogPage()),
        ),
      );
      await _waitForCatalog(tester, fixture);

      void expectUpgradeOnly() {
        expect(find.text(_upgradeMessage), findsOneWidget);
        expect(find.textContaining('当前充值暂不可用'), findsNothing);
        expect(find.text('选择支付方式'), findsNothing);
        expect(find.textContaining('支付宝'), findsNothing);
        expect(find.textContaining('微信支付'), findsNothing);
        expect(find.text('重试'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      expectUpgradeOnly();
      fixture.expectReadOnly(attempts: 1);
      await tester.tap(find.text('重试'));
      await _waitForCatalog(tester, fixture);
      expectUpgradeOnly();
      fixture.expectReadOnly(attempts: 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Matcher get _requiresIos15 => isA<ApiException>()
    .having((error) => error.kind, 'kind', ApiFailureKind.configuration)
    .having((error) => error.message, 'message', _upgradeMessage);

Future<void> _waitForCatalog(WidgetTester tester, _Fixture fixture) async {
  for (var i = 0; i < 100; i++) {
    // Drain HTTP stream completion as well as widget frames, without waiting
    // for the whole page's animation schedule to become idle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail(
    'Catalog did not leave loading state: native=${fixture.nativeCalls}, HTTP=${fixture.http.requests.length}',
  );
}

class _Fixture {
  _Fixture({String state = 'unsupported_os'}) {
    final session = Object();
    coordinator = AppleIapPurchaseCoordinator(
      storeKit: MethodChannelAppleIapStoreKit2Adapter(
        isIos: () => true,
        transactionEventStream: const Stream<Object?>.empty(),
        invoker: (method, arguments) async {
          nativeCalls.add(method);
          if (method == 'availability') {
            // Exact AppDelegate wire contract on iOS 13/14; not a fake product list.
            return {'state': state, 'minimumOsVersion': '15.0'};
          }
          if (method == 'recoverUnfinished') {
            throw PlatformException(
              code: 'unsupported_os',
              message: 'StoreKit 2 requires iOS 15 or later',
            );
          }
          throw StateError('Unexpected native call: $method');
        },
      ),
      backend: backend,
      authenticatedSession: () => session,
      authenticatedAccount: () => 'contract-account',
      purchaseStore: MemoryKeyValueStore(),
    );
    http = MediaFakeHttp((request) {
      expect(request.method, 'GET');
      expect(request.uri.path, const BackendRouteCatalog().rechargeProducts);
      expect(request.uri.queryParameters, {'platform': 'IOS'});
      return MediaFakeResponse.json({
        'platform': 'IOS',
        'list': [
          {
            'productId': '00000000-0000-0000-0000-000000001101',
            'title': '60礼物币',
            'amountMinor': 600,
            'amount': 6.0,
            'giftCoinAmount': 60,
            'bonusGiftCoin': 0,
            'storeProductId': _storeProductId,
          },
        ],
        'total': 1,
        'orderCreationStatus': 'READY',
        'providerInvocation': false,
      });
    });
    repository = BackendCommerceCatalogRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('https://configured.backend.test'),
        clientType: 'iOS',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer contract-test',
        httpClient: http,
      ),
      routes: const BackendRouteCatalog(),
      appleIapCoordinator: coordinator,
    );
  }

  final nativeCalls = <String>[];
  final backend = _UnexpectedBackend();
  late final AppleIapPurchaseCoordinator coordinator;
  late final BackendCommerceCatalogRepository repository;
  late final MediaFakeHttp http;

  void expectReadOnly({required int attempts}) {
    expect(repository.supportsPaymentChannelInvocation, isFalse);
    expect(repository.availableChannels(ClientStorePlatform.ios), isEmpty);
    expect(repository.availableChannels(ClientStorePlatform.android), isEmpty);
    expect(http.requests, hasLength(attempts));
    expect(http.requests.map((request) => request.method), everyElement('GET'));
    expect(nativeCalls, [
      for (var i = 0; i < attempts; i++) ...[
        'recoverUnfinished',
        'availability',
      ],
    ]);
    expect(backend.calls, isEmpty);
  }
}

class _UnexpectedBackend implements AppleIapBackendPort {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Unsupported OS must not create or deliver an order');
  }
}

class _Dependencies implements AppDependencies {
  _Dependencies(this.commerceCatalogRepository);

  @override
  final BackendCommerceCatalogRepository commerceCatalogRepository;
  @override
  final commerceRepository = MockCommerceRepository();
  @override
  final accountComplianceRepository = MockAccountComplianceRepository();
  @override
  final sessionManager = AuthSessionManager(MemoryKeyValueStore());
  @override
  final environment = const AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'https://configured.backend.test',
    clientType: 'iOS',
    clientInnerVersion: '6',
    oauthClientId: 'mobile-public',
    realtimeEndpoint: '',
    deploymentEnvironment: DeploymentEnvironment.development,
    enableAppleIap: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
