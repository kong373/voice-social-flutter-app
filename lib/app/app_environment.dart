enum BackendMode { mock, live }

enum DeploymentEnvironment { local, development, staging, production }

extension DeploymentEnvironmentLabel on DeploymentEnvironment {
  String get label => switch (this) {
        DeploymentEnvironment.local => '本地',
        DeploymentEnvironment.development => '开发',
        DeploymentEnvironment.staging => '预发布',
        DeploymentEnvironment.production => '生产',
      };

  bool get requiresSecureTransport =>
      this == DeploymentEnvironment.staging ||
      this == DeploymentEnvironment.production;
}

class AppEnvironment {
  const AppEnvironment({
    required this.backendMode,
    required this.apiBaseUrl,
    required this.clientType,
    required this.clientInnerVersion,
    required this.oauthClientId,
    required this.oauthClientSecret,
    required this.realtimeEndpoint,
    this.deploymentEnvironment = DeploymentEnvironment.local,
    this.apiTimeout = const Duration(seconds: 15),
    this.liveProbePath = '/',
    this.allowInsecureHttp = false,
  });

  factory AppEnvironment.fromDefines() {
    const String modeValue = String.fromEnvironment(
      'BACKEND_MODE',
      defaultValue: 'mock',
    );
    const String deploymentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'local',
    );
    const String timeoutValue = String.fromEnvironment(
      'API_TIMEOUT_SECONDS',
      defaultValue: '15',
    );
    final int timeoutSeconds = int.tryParse(timeoutValue) ?? 15;
    return AppEnvironment(
      backendMode: modeValue == 'live' ? BackendMode.live : BackendMode.mock,
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
      clientType: const String.fromEnvironment(
        'CLIENT_TYPE',
        defaultValue: 'Android',
      ),
      clientInnerVersion: const String.fromEnvironment(
        'CLIENT_INNER_VERSION',
        defaultValue: '1',
      ),
      oauthClientId: const String.fromEnvironment('OAUTH_CLIENT_ID'),
      oauthClientSecret: const String.fromEnvironment('OAUTH_CLIENT_SECRET'),
      realtimeEndpoint: const String.fromEnvironment('ROOM_REALTIME_ENDPOINT'),
      deploymentEnvironment: _parseDeploymentEnvironment(deploymentValue),
      apiTimeout: Duration(seconds: timeoutSeconds),
      liveProbePath: const String.fromEnvironment(
        'LIVE_PROBE_PATH',
        defaultValue: '/',
      ),
      allowInsecureHttp: const bool.fromEnvironment('ALLOW_INSECURE_HTTP'),
    );
  }

  factory AppEnvironment.mock() => const AppEnvironment(
        backendMode: BackendMode.mock,
        apiBaseUrl: '',
        clientType: 'Android',
        clientInnerVersion: '1',
        oauthClientId: 'mock-client',
        oauthClientSecret: 'mock-secret',
        realtimeEndpoint: '',
      );

  final BackendMode backendMode;
  final String apiBaseUrl;
  final String clientType;
  final String clientInnerVersion;
  final String oauthClientId;
  final String oauthClientSecret;
  final String realtimeEndpoint;
  final DeploymentEnvironment deploymentEnvironment;
  final Duration apiTimeout;
  final String liveProbePath;
  final bool allowInsecureHttp;

  bool get isLive => backendMode == BackendMode.live;

  Uri? get apiBaseUri {
    final String normalized = apiBaseUrl.trim();
    return normalized.isEmpty ? null : Uri.tryParse(normalized);
  }

  String get redactedApiOrigin {
    final Uri? uri = apiBaseUri;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '未配置';
    }
    final String port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Map<String, Object?> get redactedSummary => <String, Object?>{
        'backendMode': backendMode.name,
        'deploymentEnvironment': deploymentEnvironment.name,
        'apiOrigin': redactedApiOrigin,
        'clientType': clientType,
        'clientInnerVersion': clientInnerVersion,
        'apiTimeoutSeconds': apiTimeout.inSeconds,
        'liveProbePath': liveProbePath,
        'oauthClientIdConfigured': oauthClientId.trim().isNotEmpty,
        'oauthClientSecretConfigured': oauthClientSecret.trim().isNotEmpty,
        'realtimeEndpointConfigured': realtimeEndpoint.trim().isNotEmpty,
        'allowInsecureHttp': allowInsecureHttp,
      };

  void validateLiveConfiguration() {
    if (!isLive) {
      return;
    }
    final List<String> issues = <String>[
      if (apiBaseUrl.trim().isEmpty) '缺少 API_BASE_URL',
      if (clientType.trim().isEmpty) '缺少 CLIENT_TYPE',
      if (clientInnerVersion.trim().isEmpty) '缺少 CLIENT_INNER_VERSION',
      if (oauthClientId.trim().isEmpty) '缺少 OAUTH_CLIENT_ID',
      if (oauthClientSecret.trim().isEmpty) '缺少 OAUTH_CLIENT_SECRET',
    ];

    final Uri? uri = apiBaseUri;
    if (apiBaseUrl.trim().isNotEmpty) {
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        issues.add('API_BASE_URL 不是有效的绝对地址');
      } else {
        final String scheme = uri.scheme.toLowerCase();
        if (scheme != 'https' && scheme != 'http') {
          issues.add('API_BASE_URL 只允许 http 或 https');
        }
        if (uri.userInfo.isNotEmpty) {
          issues.add('API_BASE_URL 不得内嵌账号或密码');
        }
        if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
          issues.add('API_BASE_URL 不得包含 query 或 fragment');
        }
        if (scheme == 'http') {
          if (deploymentEnvironment.requiresSecureTransport) {
            issues.add('预发布和生产环境必须使用 HTTPS');
          } else if (!allowInsecureHttp) {
            issues.add('HTTP 仅可在显式启用 ALLOW_INSECURE_HTTP 时用于本地或开发环境');
          }
        }
      }
    }

    if (apiTimeout.inSeconds < 5 || apiTimeout.inSeconds > 60) {
      issues.add('API_TIMEOUT_SECONDS 必须在 5～60 秒之间');
    }
    if (!liveProbePath.trim().startsWith('/')) {
      issues.add('LIVE_PROBE_PATH 必须以 / 开头');
    }

    if (issues.isNotEmpty) {
      throw StateError('实时联调配置无效：${issues.join('；')}');
    }
  }
}

DeploymentEnvironment _parseDeploymentEnvironment(String value) {
  return switch (value.trim().toLowerCase()) {
    'development' || 'dev' => DeploymentEnvironment.development,
    'staging' || 'stage' || 'preproduction' =>
      DeploymentEnvironment.staging,
    'production' || 'prod' => DeploymentEnvironment.production,
    _ => DeploymentEnvironment.local,
  };
}
