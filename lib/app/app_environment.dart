import 'package:flutter/foundation.dart' show kReleaseMode;

enum BackendMode { mock, live }

enum DeploymentEnvironment {
  local,
  development,
  staging,
  production;

  String get label => switch (this) {
    DeploymentEnvironment.local => '本地',
    DeploymentEnvironment.development => '开发',
    DeploymentEnvironment.staging => '预发布',
    DeploymentEnvironment.production => '生产',
  };

  bool get requiresSecureTransport =>
      this == DeploymentEnvironment.staging ||
      this == DeploymentEnvironment.production;

  bool get allowsDevelopmentTools =>
      this == DeploymentEnvironment.local ||
      this == DeploymentEnvironment.development;
}

/// Runtime configuration for the Flutter client.
///
/// The mobile application is an OAuth public client. It carries only a public
/// client identifier; vendor and OAuth secrets stay on the backend. Local
/// development SMS codes may be included in the profile-gated first-party
/// challenge response, never fetched with a confidential client credential.
class AppEnvironment {
  const AppEnvironment({
    required this.backendMode,
    required this.apiBaseUrl,
    required this.clientType,
    required this.clientInnerVersion,
    required this.oauthClientId,
    required this.realtimeEndpoint,
    this.deploymentEnvironment = DeploymentEnvironment.local,
    this.deploymentEnvironmentConfigured = true,
    this.apiTimeout = const Duration(seconds: 15),
    this.liveProbePath = '/',
    this.allowInsecureHttp = false,
    this.enableAgoraRtc = false,
    this.enableAlipayAppPay = false,
    @Deprecated('Mobile clients are public clients and never carry a secret.')
    String oauthClientSecret = '',
  });

  factory AppEnvironment.fromDefines() {
    const String modeValue = String.fromEnvironment('BACKEND_MODE');
    const String deploymentValue = String.fromEnvironment('APP_ENV');
    const String timeoutValue = String.fromEnvironment(
      'API_TIMEOUT_SECONDS',
      defaultValue: '15',
    );
    return AppEnvironment.fromResolvedValues(
      backendModeValue: modeValue,
      deploymentValue: deploymentValue,
      timeoutValue: timeoutValue,
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
      realtimeEndpoint: const String.fromEnvironment('ROOM_REALTIME_ENDPOINT'),
      liveProbePath: const String.fromEnvironment(
        'LIVE_PROBE_PATH',
        defaultValue: '/',
      ),
      allowInsecureHttp: const bool.fromEnvironment('ALLOW_INSECURE_HTTP'),
      enableAgoraRtc: const bool.fromEnvironment('ENABLE_AGORA_RTC'),
      enableAlipayAppPay: const bool.fromEnvironment('ENABLE_ALIPAY_APP_PAY'),
    );
  }

  factory AppEnvironment.fromResolvedValues({
    required String backendModeValue,
    required String deploymentValue,
    required String timeoutValue,
    required String apiBaseUrl,
    required String clientType,
    required String clientInnerVersion,
    required String oauthClientId,
    required String realtimeEndpoint,
    required String liveProbePath,
    required bool allowInsecureHttp,
    bool enableAgoraRtc = false,
    bool enableAlipayAppPay = false,
    bool releaseBuild = kReleaseMode,
  }) {
    final DeploymentEnvironment deploymentEnvironment =
        _parseDeploymentEnvironment(deploymentValue);
    final bool deploymentEnvironmentConfigured = _isValidDeploymentEnvironment(
      deploymentValue,
    );
    final String normalizedBackendMode = backendModeValue.trim().toLowerCase();
    if (releaseBuild &&
        (!deploymentEnvironmentConfigured || normalizedBackendMode != 'live')) {
      throw StateError(
        'Release 构建要求显式配置合法 APP_ENV 和 BACKEND_MODE=live；'
        '缺失或 Mock 后端会被拒绝。',
      );
    }
    if ((deploymentEnvironment == DeploymentEnvironment.staging ||
            deploymentEnvironment == DeploymentEnvironment.production) &&
        normalizedBackendMode != 'live') {
      throw StateError(
        'APP_ENV=${deploymentEnvironment.name} 发布构建要求显式 '
        'BACKEND_MODE=live；缺失或非 live 会被拒绝。',
      );
    }

    final int timeoutSeconds = int.tryParse(timeoutValue) ?? 15;
    return AppEnvironment(
      backendMode: normalizedBackendMode == 'live'
          ? BackendMode.live
          : BackendMode.mock,
      apiBaseUrl: apiBaseUrl,
      clientType: clientType,
      clientInnerVersion: clientInnerVersion,
      oauthClientId: oauthClientId,
      realtimeEndpoint: realtimeEndpoint,
      deploymentEnvironment: deploymentEnvironment,
      deploymentEnvironmentConfigured: deploymentEnvironmentConfigured,
      apiTimeout: Duration(seconds: timeoutSeconds),
      liveProbePath: liveProbePath,
      allowInsecureHttp: allowInsecureHttp,
      enableAgoraRtc: enableAgoraRtc,
      enableAlipayAppPay: enableAlipayAppPay,
    );
  }

  factory AppEnvironment.mock() => const AppEnvironment(
    backendMode: BackendMode.mock,
    apiBaseUrl: '',
    clientType: 'Android',
    clientInnerVersion: '1',
    oauthClientId: 'mock-client',
    realtimeEndpoint: '',
  );

  final BackendMode backendMode;
  final String apiBaseUrl;
  final String clientType;
  final String clientInnerVersion;
  final String oauthClientId;
  final String realtimeEndpoint;
  final DeploymentEnvironment deploymentEnvironment;

  /// Whether APP_ENV was explicitly present and recognized by the build.
  /// Directly constructed test environments default to configured for
  /// backwards compatibility; compile-time live builds set this from the raw
  /// define and therefore fail closed when it is missing or misspelled.
  final bool deploymentEnvironmentConfigured;
  final Duration apiTimeout;
  final String liveProbePath;
  final bool allowInsecureHttp;

  /// Explicit opt-in for the live Agora transport. It is false by default;
  /// the adapter is only wired when live mode also receives complete,
  /// server-issued RTC credentials from the authenticated token endpoint.
  final bool enableAgoraRtc;

  /// Explicit opt-in for the first-party Android Alipay bridge. The default
  /// is disabled; enabling it still requires a server-issued order string and
  /// the native official SDK host plugin. No payment credential is read by
  /// the Flutter client.
  final bool enableAlipayAppPay;

  /// Compatibility getter for older callers. The value is deliberately empty.
  @Deprecated('Mobile clients are public clients and never carry a secret.')
  String get oauthClientSecret => '';

  /// Compatibility getter retained for old diagnostics. Confidential outbox
  /// credentials are never loaded by the mobile application.
  @Deprecated('Development codes come from a profile-gated challenge response.')
  bool get canReadDevelopmentSmsOutbox => false;

  bool get isLive => backendMode == BackendMode.live;

  /// Numeric version code sent to the first-party version policy endpoint.
  /// Invalid build metadata is represented as zero so the live gate can fail
  /// closed instead of silently skipping the policy check.
  int get currentVersion => int.tryParse(clientInnerVersion.trim()) ?? 0;

  /// The backend contract uses 1 for Android and 2 for iOS.
  int get platformType => clientType.trim().toLowerCase() == 'ios' ? 2 : 1;

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
    'deploymentEnvironmentConfigured': deploymentEnvironmentConfigured,
    'apiOrigin': redactedApiOrigin,
    'clientType': clientType,
    'clientInnerVersion': clientInnerVersion,
    'apiTimeoutSeconds': apiTimeout.inSeconds,
    'liveProbePath': liveProbePath,
    'oauthClientIdConfigured': oauthClientId.trim().isNotEmpty,
    'oauthClientSecretConfigured': false,
    'developmentOutboxConfigured': false,
    'realtimeEndpointConfigured': realtimeEndpoint.trim().isNotEmpty,
    'allowInsecureHttp': allowInsecureHttp,
    'enableAgoraRtc': enableAgoraRtc,
    'enableAlipayAppPay': enableAlipayAppPay,
  };

  void validateLiveConfiguration() {
    if (!isLive) {
      return;
    }
    final List<String> issues = <String>[
      if (apiBaseUrl.trim().isEmpty) '缺少 API_BASE_URL',
      if (clientType.trim().isEmpty) '缺少 CLIENT_TYPE',
      if (clientInnerVersion.trim().isEmpty) '缺少 CLIENT_INNER_VERSION',
      if (clientInnerVersion.trim().isNotEmpty &&
          (int.tryParse(clientInnerVersion.trim()) == null ||
              int.parse(clientInnerVersion.trim()) <= 0))
        'CLIENT_INNER_VERSION 必须为正整数',
      if (oauthClientId.trim().isEmpty) '缺少 OAUTH_CLIENT_ID',
      if (!deploymentEnvironmentConfigured) 'APP_ENV 必须显式配置为合法环境',
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
    'staging' || 'stage' || 'preproduction' => DeploymentEnvironment.staging,
    'production' || 'prod' => DeploymentEnvironment.production,
    _ => DeploymentEnvironment.local,
  };
}

bool _isValidDeploymentEnvironment(String value) {
  return switch (value.trim().toLowerCase()) {
    'local' ||
    'development' ||
    'dev' ||
    'staging' ||
    'stage' ||
    'preproduction' ||
    'production' ||
    'prod' => true,
    _ => false,
  };
}
