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
  })  : _apiClient = apiClient,
        _environment = environment,
        _routes = routes;

  static const int _mobileNotRegisteredCode = 10201;

  final ApiClient _apiClient;
  final AppEnvironment _environment;
  final BackendRouteCatalog _routes;

  @override
  Future<void> sendSmsCode(String phone) async {
    await _apiClient.put(
      _routes.sendSmsCode,
      query: <String, String>{'mobileNumber': phone, 'type': '1'},
      authenticated: false,
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
        body: _loginPayload(
          phone: phone,
          smsCode: smsCode,
          device: device,
        ),
        authenticated: false,
      );
      return AuthOutcome.authenticated(_parseSession(response.data));
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
        'clientSecret': _environment.oauthClientSecret,
        'isEmulator': device.isEmulator,
        'nickname': profile.nickname,
        'birthday': profile.birthday,
        'smDeviceId': device.smDeviceId,
        'sensorsAnonymousId': device.deviceId,
      },
      authenticated: false,
    );
    return _parseSession(response.data);
  }

  Map<String, Object?> _loginPayload({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  }) =>
      <String, Object?>{
        'phone': phone,
        'smsCode': smsCode,
        'deviceType': device.deviceType,
        'deviceId': device.deviceId,
        'mobileKind': device.mobileKind,
        'clientId': _environment.oauthClientId,
        'clientSecret': _environment.oauthClientSecret,
        'isSSO': true,
        'smDeviceId': device.smDeviceId,
        'sensorsAnonymousId': device.deviceId,
      };

  AuthSession _parseSession(Object? data) {
    if (data is! Map<String, Object?>) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '登录响应缺少令牌信息',
      );
    }
    final String accessToken = data['access_token']?.toString() ?? '';
    final int expiresIn =
        int.tryParse(data['expires_in']?.toString() ?? '') ?? 0;
    final int userId = int.tryParse(data['userId']?.toString() ?? '') ?? 0;
    if (accessToken.isEmpty || expiresIn <= 0 || userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '登录响应中的令牌字段不完整',
      );
    }
    return AuthSession(
      accessToken: accessToken,
      tokenType: data['token_type']?.toString() ?? 'Bearer',
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: userId,
      mobile: data['mobile']?.toString() ?? '',
      roles: data['roles']?.toString() ?? '',
      boundRoomId: _nullableString(data['roomId']),
    );
  }

  static String? _nullableString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
