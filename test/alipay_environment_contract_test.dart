import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';

void main() {
  test('Alipay App Pay is disabled by default and opt-in is redacted', () {
    const AppEnvironment defaults = AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://development.example.test/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
    );
    expect(defaults.enableAlipayAppPay, isFalse);
    expect(defaults.useAlipaySandbox, isFalse);
    expect(defaults.redactedSummary['enableAlipayAppPay'], isFalse);
    expect(defaults.redactedSummary['useAlipaySandbox'], isFalse);

    final AppEnvironment enabled = AppEnvironment.fromResolvedValues(
      backendModeValue: 'live',
      deploymentValue: 'development',
      timeoutValue: '15',
      apiBaseUrl: 'https://development.example.test/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      liveProbePath: '/',
      allowInsecureHttp: false,
      enableAlipayAppPay: true,
      releaseBuild: false,
    );
    expect(enabled.enableAlipayAppPay, isTrue);
    expect(enabled.useAlipaySandbox, isTrue);
    expect(enabled.redactedSummary.toString(), isNot(contains('secret')));
    expect(enabled.redactedSummary.toString(), isNot(contains('private')));
  });

  test(
    'Alipay sandbox mode is restricted to live local/development builds',
    () {
      for (final DeploymentEnvironment environment in <DeploymentEnvironment>[
        DeploymentEnvironment.local,
        DeploymentEnvironment.development,
      ]) {
        final AppEnvironment enabled = AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'http://127.0.0.1:18080/',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
          deploymentEnvironment: environment,
          enableAlipayAppPay: true,
        );
        expect(enabled.useAlipaySandbox, isTrue, reason: environment.name);
      }

      for (final DeploymentEnvironment environment in <DeploymentEnvironment>[
        DeploymentEnvironment.staging,
        DeploymentEnvironment.production,
      ]) {
        final AppEnvironment enabled = AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://example.test/',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
          deploymentEnvironment: environment,
          enableAlipayAppPay: true,
        );
        expect(enabled.useAlipaySandbox, isFalse, reason: environment.name);
      }
    },
  );

  test('Alipay opt-in does not bypass production live configuration gates', () {
    expect(
      () => AppEnvironment.fromResolvedValues(
        backendModeValue: 'mock',
        deploymentValue: 'production',
        timeoutValue: '15',
        apiBaseUrl: 'https://production.example.test/',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'public-client',
        realtimeEndpoint: '',
        liveProbePath: '/',
        allowInsecureHttp: false,
        enableAlipayAppPay: true,
        releaseBuild: false,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
