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
    realtimeEndpoint: '',
    deploymentEnvironment: _deployment(values['M3_APP_ENV'] ?? 'development'),
    apiTimeout: Duration(
      seconds: int.tryParse(values['M3_API_TIMEOUT_SECONDS'] ?? '') ?? 15,
    ),
    liveProbePath: values['M3_PROBE_PATH'] ?? '/',
    allowInsecureHttp:
        (values['M3_ALLOW_INSECURE_HTTP'] ?? '').toLowerCase() == 'true',
  );
  _validatePreflightTransportPolicy(
    environment,
    allowPrivateHttpOnly:
        (values['M3_ALLOW_PRIVATE_HTTP_ONLY'] ?? '').toLowerCase() == 'true',
  );
  final LiveBackendReadinessSnapshot snapshot =
      await LiveBackendReadinessService(environment: environment).check();
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(snapshot.toRedactedJson()),
  );
  exitCode = snapshot.canAttemptAuthentication ? 0 : 2;
}

void _validatePreflightTransportPolicy(
  AppEnvironment environment, {
  required bool allowPrivateHttpOnly,
}) {
  final Uri? uri = environment.apiBaseUri;
  if (uri == null) {
    return;
  }
  if (uri.scheme.toLowerCase() != 'http' || !environment.allowInsecureHttp) {
    return;
  }
  if (!allowPrivateHttpOnly) {
    return;
  }
  final String host = uri.host.trim().toLowerCase();
  if (_isLoopbackHost(host) || _isPrivateDevelopmentHost(host)) {
    return;
  }
  throw StateError(
    '实时联调配置无效：HTTP 仅允许 loopback 或 private development host；公网地址必须使用 HTTPS。',
  );
}

bool _isLoopbackHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    return true;
  }
  final InternetAddressType? type = InternetAddress.tryParse(host)?.type;
  if (type == null) {
    return false;
  }
  return InternetAddress.tryParse(host)?.isLoopback ?? false;
}

bool _isPrivateDevelopmentHost(String host) {
  final InternetAddress? address = InternetAddress.tryParse(host);
  if (address == null) {
    return host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan');
  }
  if (address.type != InternetAddressType.IPv4) {
    final String normalized = address.address.toLowerCase();
    return normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe80:');
  }
  final List<int> octets = address.rawAddress;
  return octets[0] == 10 ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] == 192 && octets[1] == 168) ||
      (octets[0] == 169 && octets[1] == 254);
}

DeploymentEnvironment _deployment(String value) {
  return switch (value.trim().toLowerCase()) {
    'staging' || 'stage' => DeploymentEnvironment.staging,
    'production' || 'prod' => DeploymentEnvironment.production,
    'local' => DeploymentEnvironment.local,
    _ => DeploymentEnvironment.development,
  };
}
