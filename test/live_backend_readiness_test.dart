import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';

void main() {
  AppEnvironment liveEnvironment({String apiBaseUrl = 'https://dev.example.com/'}) {
    return AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: apiBaseUrl,
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'client-id-value',
      oauthClientSecret: 'secret-value',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
    );
  }

  test('mock mode performs no network probe', () async {
    final _FakeGatewayProbe probe = _FakeGatewayProbe(
      GatewayProbeResult(
        status: LiveBackendReadinessStatus.gatewayReachable,
        message: 'unused',
        checkedAt: DateTime.utc(2026, 8, 17),
      ),
    );
    final LiveBackendReadinessSnapshot snapshot =
        await LiveBackendReadinessService(
      environment: AppEnvironment.mock(),
      gatewayProbe: probe,
    ).check();

    expect(snapshot.status, LiveBackendReadinessStatus.mockMode);
    expect(snapshot.canAttemptAuthentication, isFalse);
    expect(probe.callCount, 0);
  });

  test('invalid configuration fails before the network probe', () async {
    final _FakeGatewayProbe probe = _FakeGatewayProbe(
      GatewayProbeResult(
        status: LiveBackendReadinessStatus.gatewayReachable,
        message: 'unused',
        checkedAt: DateTime.utc(2026, 8, 17),
      ),
    );
    final LiveBackendReadinessSnapshot snapshot =
        await LiveBackendReadinessService(
      environment: liveEnvironment(apiBaseUrl: 'http://dev.example.com/'),
      gatewayProbe: probe,
    ).check();

    expect(
      snapshot.status,
      LiveBackendReadinessStatus.configurationInvalid,
    );
    expect(probe.callCount, 0);
  });

  test('reachable gateway allows the authentication phase to begin', () async {
    final _FakeGatewayProbe probe = _FakeGatewayProbe(
      GatewayProbeResult(
        status: LiveBackendReadinessStatus.gatewayReachable,
        message: 'HTTP 401 still proves the gateway is reachable',
        checkedAt: DateTime.utc(2026, 8, 17),
        latency: const Duration(milliseconds: 87),
        httpStatus: 401,
      ),
    );
    final LiveBackendReadinessSnapshot snapshot =
        await LiveBackendReadinessService(
      environment: liveEnvironment(),
      gatewayProbe: probe,
    ).check();

    expect(snapshot.canAttemptAuthentication, isTrue);
    expect(snapshot.httpStatus, 401);
    expect(snapshot.apiOrigin, 'https://dev.example.com');
    expect(probe.callCount, 1);
    expect(snapshot.toRedactedText(), isNot(contains('secret-value')));
    expect(snapshot.toRedactedText(), isNot(contains('client-id-value')));
  });

  test('network failure remains distinct from configuration failure', () async {
    final _FakeGatewayProbe probe = _FakeGatewayProbe(
      GatewayProbeResult(
        status: LiveBackendReadinessStatus.networkUnavailable,
        message: 'network unavailable',
        checkedAt: DateTime.utc(2026, 8, 17),
      ),
    );
    final LiveBackendReadinessSnapshot snapshot =
        await LiveBackendReadinessService(
      environment: liveEnvironment(),
      gatewayProbe: probe,
    ).check();

    expect(snapshot.status, LiveBackendReadinessStatus.networkUnavailable);
    expect(snapshot.canAttemptAuthentication, isFalse);
    expect(probe.callCount, 1);
  });
}

class _FakeGatewayProbe implements GatewayProbe {
  _FakeGatewayProbe(this.result);

  final GatewayProbeResult result;
  int callCount = 0;

  @override
  Future<GatewayProbeResult> probe(AppEnvironment environment) async {
    callCount += 1;
    return result;
  }
}
