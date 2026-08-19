import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';

void main() {
  AppEnvironment liveEnvironment({
    String apiBaseUrl = 'https://dev.example.com:8443/gateway/',
    DeploymentEnvironment deployment = DeploymentEnvironment.development,
    bool allowInsecureHttp = false,
    String liveProbePath = '/',
    String developmentOutboxKey = '',
  }) {
    return AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: apiBaseUrl,
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'client-id-value',
      realtimeEndpoint: '',
      developmentOutboxKey: developmentOutboxKey,
      deploymentEnvironment: deployment,
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

  test('mobile public client never loads an OAuth secret', () {
    final AppEnvironment environment = liveEnvironment();
    expect(environment.oauthClientSecret, isEmpty);
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

  test('development outbox key is forbidden in staging and production', () {
    final AppEnvironment environment = liveEnvironment(
      deployment: DeploymentEnvironment.staging,
      developmentOutboxKey: 'development-only-key',
    );
    expect(
      environment.validateLiveConfiguration,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('DEVELOPMENT_OUTBOX_KEY'),
        ),
      ),
    );
  });

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
}
