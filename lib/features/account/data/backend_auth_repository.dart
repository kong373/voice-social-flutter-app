import 'dart:math';

import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';

class BackendAuthRepository implements AuthRepository {
  BackendAuthRepository({
    required ApiClient apiClient,
    required AppEnvironment environment,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _environment = environment,
       _routes = routes;

  static const int _mobileNotRegisteredCode = 10201;
  static const String _refreshPath =
      '/app-register-api/userAccount/v1/refreshSession';
  static const String _logoutPath = '/app-register-api/userAccount/v1/logout';
  static const Duration _refreshRecoveryWindow = Duration(seconds: 30);
  static final Random _requestIdRandom = Random.secure();
  static const int _requestIdEntropyLength = 32;
  static final RegExp _requestIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
  );

  final ApiClient _apiClient;
  final AppEnvironment _environment;
  final BackendRouteCatalog _routes;

  Map<String, String> get _publicClientHeaders => <String, String>{
    'Client-Id': _environment.oauthClientId,
  };

  @override
  Future<SmsChallenge> sendSmsCode({
    required String phone,
    required ClientDevice device,
  }) async {
    final ApiResponse response = await _apiClient.put(
      _routes.sendSmsCode,
      query: <String, String>{'mobileNumber': phone, 'type': '1'},
      headers: <String, String>{
        ..._publicClientHeaders,
        'X-Device-Id': device.deviceId,
      },
      authenticated: false,
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String challengeId = _string(data['challengeId']);
    final int expiresIn = _asInt(data['expiresIn']) ?? 0;
    final int retryAfter = _asInt(data['retryAfter']) ?? 60;
    final String developmentCode = _string(data['developmentCode']);
    if (challengeId.isEmpty || expiresIn <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '短信挑战响应字段不完整',
      );
    }
    return SmsChallenge(
      challengeId: challengeId,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      retryAfter: retryAfter < 1 ? 1 : retryAfter,
      developmentCode: RegExp(r'^\d{6}$').hasMatch(developmentCode)
          ? developmentCode
          : null,
    );
  }

  @override
  Future<AuthOutcome> signInWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  }) async {
    try {
      final ApiResponse response = await _apiClient.put(
        _routes.loginBySms,
        headers: _publicClientHeaders,
        body: _loginPayload(phone: phone, smsCode: smsCode, device: device),
        authenticated: false,
      );
      return AuthOutcome.authenticated(
        _parseSession(response.data, deviceId: device.deviceId),
      );
    } on ApiException catch (error) {
      if (error.code == _mobileNotRegisteredCode) {
        return const AuthOutcome.registrationRequired();
      }
      rethrow;
    }
  }

  @override
  Future<AuthSession> registerWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
    required RegistrationProfile profile,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.registerByMobile,
      headers: _publicClientHeaders,
      body: <String, Object?>{
        'phone': phone,
        'smsCode': smsCode,
        'sex': profile.sex,
        'labelIds': <int>[],
        'inviteCode': profile.inviteCode,
        'appInviteCode': '',
        'deviceType': device.deviceType,
        'deviceId': device.deviceId,
        'mobileKind': device.mobileKind,
        'appMarketType': device.appMarketType,
        'clientId': _environment.oauthClientId,
        'isEmulator': device.isEmulator,
        'nickname': profile.nickname,
        'birthday': profile.birthday,
        'smDeviceId': device.smDeviceId,
        'sensorsAnonymousId': device.deviceId,
      },
      authenticated: false,
    );
    return _parseSession(response.data, deviceId: device.deviceId);
  }

  @override
  Future<AuthSession> refreshSession(AuthSession session) async {
    if (!session.canRefresh || session.deviceId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        code: 401,
        httpStatus: 401,
        message: '刷新会话已失效，请重新登录',
      );
    }
    final String requestId = _newRefreshRequestId();
    final Stopwatch stopwatch = Stopwatch()..start();
    ApiException? firstAmbiguousFailure;
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        final ApiResponse response = await _apiClient.post(
          _refreshPath,
          headers: <String, String>{
            ..._refreshClientHeaders(session),
            'X-Request-Id': requestId,
          },
          body: <String, Object?>{
            'refreshToken': session.refreshToken,
            'deviceId': session.deviceId,
          },
          authenticated: false,
        );
        return _parseSession(
          response.data,
          deviceId: session.deviceId,
          clientId: _refreshClientHeaders(session)['Client-Id'],
        );
      } on ApiException catch (error) {
        if (attempt != 0 ||
            !_isRefreshRecoveryCandidate(error) ||
            stopwatch.elapsed >= _refreshRecoveryWindow) {
          rethrow;
        }
        firstAmbiguousFailure = error;
      }
    }
    // The loop either returns or rethrows. This guard keeps the method total
    // if the retry policy changes without accidentally returning a fake token.
    throw firstAmbiguousFailure ??
        const ApiException(kind: ApiFailureKind.protocol, message: '刷新响应无法确认');
  }

  @override
  Future<void> logout(AuthSession session) async {
    if (session.refreshToken.isEmpty) {
      return;
    }
    await _apiClient.post(
      _logoutPath,
      body: <String, Object?>{'refreshToken': session.refreshToken},
    );
  }

  Map<String, Object?> _loginPayload({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  }) => <String, Object?>{
    'phone': phone,
    'smsCode': smsCode,
    'deviceType': device.deviceType,
    'deviceId': device.deviceId,
    'mobileKind': device.mobileKind,
    'clientId': _environment.oauthClientId,
    'isEmulator': device.isEmulator,
    'isSSO': true,
    'smDeviceId': device.smDeviceId,
    'sensorsAnonymousId': device.deviceId,
  };

  AuthSession _parseSession(
    Object? data, {
    required String deviceId,
    String? clientId,
  }) {
    final Map<String, Object?> map = _asMap(data);
    final String accessToken = _string(map['access_token']);
    final int expiresIn = _asInt(map['expires_in']) ?? 0;
    final String refreshToken = _string(map['refresh_token']);
    final int refreshExpiresIn = _asInt(map['refresh_expires_in']) ?? 0;
    final int userId = _asInt(map['userId']) ?? 0;
    if (accessToken.isEmpty ||
        expiresIn <= 0 ||
        refreshToken.isEmpty ||
        refreshExpiresIn <= 0 ||
        userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '登录响应中的会话字段不完整',
      );
    }
    final DateTime now = DateTime.now();
    return AuthSession(
      accessToken: accessToken,
      tokenType: _string(map['token_type'], fallback: 'Bearer'),
      expiresAt: now.add(Duration(seconds: expiresIn)),
      refreshToken: refreshToken,
      refreshExpiresAt: now.add(Duration(seconds: refreshExpiresIn)),
      deviceId: deviceId,
      clientId: clientId ?? _environment.oauthClientId,
      userId: userId,
      mobile: _string(map['mobile']),
      roles: _string(map['roles']),
      boundRoomId: _nullableString(map['roomId']),
    );
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  Map<String, String> _refreshClientHeaders(AuthSession session) {
    final String clientId = session.clientId.trim();
    return <String, String>{
      'Client-Id': clientId.isEmpty ? _environment.oauthClientId : clientId,
    };
  }

  static String _newRefreshRequestId() {
    final String entropy = List<String>.generate(
      _requestIdEntropyLength,
      (_) => _requestIdRandom.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
    final String requestId = 'flutter-auth-refresh-$entropy';
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('刷新请求幂等 ID 格式无效');
    }
    return requestId;
  }

  static bool _isRefreshRecoveryCandidate(ApiException error) =>
      switch (error.kind) {
        ApiFailureKind.network ||
        ApiFailureKind.timeout ||
        ApiFailureKind.protocol ||
        ApiFailureKind.server => true,
        ApiFailureKind.unauthorized ||
        ApiFailureKind.forbidden ||
        ApiFailureKind.conflict ||
        ApiFailureKind.validation ||
        ApiFailureKind.configuration ||
        ApiFailureKind.business => false,
      };

  static String? _nullableString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
