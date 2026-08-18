import 'dart:convert';
import 'dart:io';

import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';

Future<void> main() async {
  final Map<String, String> values = Platform.environment;
  final AppEnvironment environment = AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: values['M3_API_BASE_URL'] ?? '',
    clientType: values['M3_CLIENT_TYPE'] ?? 'Android',
    clientInnerVersion: values['M3_CLIENT_INNER_VERSION'] ?? '1',
    oauthClientId: values['M3_OAUTH_CLIENT_ID'] ?? '',
    oauthClientSecret: values['M3_OAUTH_CLIENT_SECRET'] ?? '',
    realtimeEndpoint: '',
    deploymentEnvironment: _deployment(values['M3_APP_ENV'] ?? 'development'),
    apiTimeout: Duration(
      seconds: int.tryParse(values['M3_API_TIMEOUT_SECONDS'] ?? '') ?? 15,
    ),
    liveProbePath: values['M3_PROBE_PATH'] ?? '/',
    allowInsecureHttp:
        (values['M3_ALLOW_INSECURE_HTTP'] ?? '').toLowerCase() == 'true',
  );
  final LiveBackendReadinessSnapshot snapshot =
      await LiveBackendReadinessService(environment: environment).check();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(snapshot.toRedactedJson()),
  );
  exitCode = snapshot.canAttemptAuthentication ? 0 : 2;
}

DeploymentEnvironment _deployment(String value) {
  return switch (value.trim().toLowerCase()) {
    'staging' || 'stage' => DeploymentEnvironment.staging,
    'production' || 'prod' => DeploymentEnvironment.production,
    'local' => DeploymentEnvironment.local,
    _ => DeploymentEnvironment.development,
  };
}
