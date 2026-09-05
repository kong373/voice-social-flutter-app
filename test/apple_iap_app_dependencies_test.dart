import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

void main() {
  test('Apple IAP is an explicit iOS live runtime capability', () {
    final AppEnvironment enabled = AppEnvironment.fromResolvedValues(
      backendModeValue: 'live',
      deploymentValue: 'development',
      timeoutValue: '15',
      apiBaseUrl: 'https://development.example.test',
      clientType: 'iOS',
      clientInnerVersion: '6',
      oauthClientId: 'mobile-public',
      realtimeEndpoint: '',
      liveProbePath: '/health',
      allowInsecureHttp: false,
      enableAppleIap: true,
      releaseBuild: false,
    );

    expect(enabled.enableAppleIap, isTrue);
    expect(enabled.redactedSummary['enableAppleIap'], isTrue);
  });

  test(
    'dependencies wire StoreKit only for explicitly enabled iOS live mode',
    () {
      final _StoreKit storeKit = _StoreKit();
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: _environment(clientType: 'iOS', enableAppleIap: true),
        appleIapStoreKit2Adapter: storeKit,
      );
      addTearDown(dependencies.dispose);

      expect(dependencies.appleIapStoreKit2Adapter, same(storeKit));
      expect(dependencies.appleIapPurchaseCoordinator, isNotNull);
      expect(
        dependencies.commerceCatalogRepository.supportsPaymentChannelInvocation,
        isFalse,
        reason: 'the authenticated iOS catalog must still report READY first',
      );
    },
  );

  test('Android remains fail-closed even when Apple flag is supplied', () {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: _environment(clientType: 'Android', enableAppleIap: true),
      appleIapStoreKit2Adapter: _StoreKit(),
    );
    addTearDown(dependencies.dispose);

    expect(
      dependencies.appleIapStoreKit2Adapter,
      isA<DisabledAppleIapStoreKit2Adapter>(),
    );
    expect(dependencies.appleIapPurchaseCoordinator, isNull);
  });

  test('signed-in app gate starts unfinished transaction recovery', () {
    final String source = File('lib/app/app_gate.dart').readAsStringSync();

    expect(source, contains('recoverAppleIapAfterAuthentication'));
  });
}

AppEnvironment _environment({
  required String clientType,
  required bool enableAppleIap,
}) => AppEnvironment(
  backendMode: BackendMode.live,
  apiBaseUrl: 'https://development.example.test',
  clientType: clientType,
  clientInnerVersion: '6',
  oauthClientId: 'mobile-public',
  realtimeEndpoint: '',
  deploymentEnvironment: DeploymentEnvironment.development,
  enableAppleIap: enableAppleIap,
);

class _StoreKit implements AppleIapStoreKit2Adapter {
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
      const <AppleStoreProduct>[];

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async => const AppleIapPurchaseResult(
    outcome: AppleIapPurchaseOutcome.unavailable,
  );

  @override
  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  }) async => const <AppleIapTransaction>[];

  @override
  Future<bool> finish(String transactionId) async => false;
}
