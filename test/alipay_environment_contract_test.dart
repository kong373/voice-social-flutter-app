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
    expect(defaults.redactedSummary['enableAlipayAppPay'], isFalse);

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
    expect(enabled.redactedSummary.toString(), isNot(contains('secret')));
    expect(enabled.redactedSummary.toString(), isNot(contains('private')));
  });

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
