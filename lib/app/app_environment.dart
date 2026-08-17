enum BackendMode { mock, live }

class AppEnvironment {
  const AppEnvironment({
    required this.backendMode,
    required this.apiBaseUrl,
    required this.clientType,
    required this.clientInnerVersion,
    required this.oauthClientId,
    required this.oauthClientSecret,
    required this.realtimeEndpoint,
  });

  factory AppEnvironment.fromDefines() {
    const String modeValue = String.fromEnvironment(
      'BACKEND_MODE',
      defaultValue: 'mock',
    );
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

  bool get isLive => backendMode == BackendMode.live;

  void validateLiveConfiguration() {
    if (!isLive) {
      return;
    }
    final List<String> missing = <String>[
      if (apiBaseUrl.trim().isEmpty) 'API_BASE_URL',
      if (oauthClientId.trim().isEmpty) 'OAUTH_CLIENT_ID',
      if (oauthClientSecret.trim().isEmpty) 'OAUTH_CLIENT_SECRET',
    ];
    if (missing.isNotEmpty) {
      throw StateError('缺少运行参数：${missing.join(', ')}');
    }
  }
}
