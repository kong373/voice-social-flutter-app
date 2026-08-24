import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';

void main() {
  AppEnvironment liveEnvironment({
    String apiBaseUrl = 'https://dev.example.com:8443/gateway/',
    String clientInnerVersion = '6',
    DeploymentEnvironment deployment = DeploymentEnvironment.development,
    bool deploymentEnvironmentConfigured = true,
    bool allowInsecureHttp = false,
    String liveProbePath = '/',
  }) {
    return AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: apiBaseUrl,
      clientType: 'Android',
      clientInnerVersion: clientInnerVersion,
      oauthClientId: 'client-id-value',
      realtimeEndpoint: '',
      deploymentEnvironment: deployment,
      deploymentEnvironmentConfigured: deploymentEnvironmentConfigured,
      allowInsecureHttp: allowInsecureHttp,
      liveProbePath: liveProbePath,
    );
  }

  test('redacted summary never exposes client id or gateway path', () {
    final AppEnvironment environment = liveEnvironment();
    final String summary = environment.redactedSummary.toString();

    expect(environment.redactedApiOrigin, 'https://dev.example.com:8443');
    expect(summary, isNot(contains('client-id-value')));
    expect(summary, isNot(contains('/gateway/')));
    expect(environment.redactedSummary['oauthClientIdConfigured'], isTrue);
    expect(environment.redactedSummary['oauthClientSecretConfigured'], isFalse);
  });

  test('mobile public client never loads confidential credentials', () {
    final AppEnvironment environment = liveEnvironment();
    expect(environment.oauthClientSecret, isEmpty);
    expect(environment.canReadDevelopmentSmsOutbox, isFalse);
    expect(environment.redactedSummary['developmentOutboxConfigured'], isFalse);
  });

  test('development tools are limited to local and development', () {
    expect(DeploymentEnvironment.local.allowsDevelopmentTools, isTrue);
    expect(DeploymentEnvironment.development.allowsDevelopmentTools, isTrue);
    expect(DeploymentEnvironment.staging.allowsDevelopmentTools, isFalse);
    expect(DeploymentEnvironment.production.allowsDevelopmentTools, isFalse);
  });

  test('development HTTP requires an explicit insecure override', () {
    final AppEnvironment blocked = liveEnvironment(
      apiBaseUrl: 'http://10.0.2.2:8080/',
    );
    expect(
      blocked.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('ALLOW_INSECURE_HTTP'),
        ),
      ),
    );

    final AppEnvironment allowed = liveEnvironment(
      apiBaseUrl: 'http://10.0.2.2:8080/',
      allowInsecureHttp: true,
    );
    expect(allowed.validateLiveConfiguration, returnsNormally);
  });

  test('production always rejects insecure HTTP', () {
    final AppEnvironment environment = liveEnvironment(
      apiBaseUrl: 'http://production.example.com/',
      deployment: DeploymentEnvironment.production,
      allowInsecureHttp: true,
    );
    expect(
      environment.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('HTTPS'),
        ),
      ),
    );
  });

  test('mobile client never exposes development outbox configuration', () {
    final AppEnvironment environment = liveEnvironment(
      deployment: DeploymentEnvironment.staging,
    );
    expect(environment.canReadDevelopmentSmsOutbox, isFalse);
    expect(environment.redactedSummary['developmentOutboxConfigured'], isFalse);
  });

  test(
    'development tools are limited to local and development environments',
    () {
      expect(DeploymentEnvironment.local.allowsDevelopmentTools, isTrue);
      expect(DeploymentEnvironment.development.allowsDevelopmentTools, isTrue);
      expect(DeploymentEnvironment.staging.allowsDevelopmentTools, isFalse);
      expect(DeploymentEnvironment.production.allowsDevelopmentTools, isFalse);
    },
  );

  test('probe path must be absolute and timeout must be bounded', () {
    final AppEnvironment invalidPath = liveEnvironment(liveProbePath: 'health');
    expect(
      invalidPath.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('LIVE_PROBE_PATH'),
        ),
      ),
    );

    final AppEnvironment invalidTimeout = AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://dev.example.com/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'client',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
      apiTimeout: const Duration(seconds: 2),
    );
    expect(
      invalidTimeout.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('5～60'),
        ),
      ),
    );
  });

  test('live version code must be a positive integer', () {
    for (final String value in <String>['0', '-1', '6.1', 'six']) {
      final AppEnvironment environment = liveEnvironment(
        clientInnerVersion: value,
      );
      expect(
        environment.validateLiveConfiguration,
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('CLIENT_INNER_VERSION'),
          ),
        ),
        reason: value,
      );
    }
  });

  test('live mode rejects missing or misspelled APP_ENV', () {
    final AppEnvironment environment = liveEnvironment(
      deploymentEnvironmentConfigured: false,
    );
    expect(
      environment.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('APP_ENV'),
        ),
      ),
    );
  });
}
