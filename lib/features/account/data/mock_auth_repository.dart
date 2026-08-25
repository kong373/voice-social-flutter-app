import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  const MockAuthRepository();

  @override
  Future<SmsChallenge> sendSmsCode({
    required String phone,
    required ClientDevice device,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_isPhoneValid(phone)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        code: 404,
        message: '请输入正确的手机号码',
      );
    }
    return SmsChallenge(
      challengeId: 'mock-${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      retryAfter: 60,
      developmentCode: '123456',
    );
  }

  @override
  Future<AuthOutcome> signInWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!_isPhoneValid(phone) || smsCode.length != 6) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        code: 404,
        message: '手机号或验证码格式不正确',
      );
    }
    if (phone == '13900000000') {
      return const AuthOutcome.registrationRequired();
    }
    return AuthOutcome.authenticated(_session(phone, device.deviceId));
  }

  @override
  Future<AuthSession> registerWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
    required RegistrationProfile profile,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (profile.nickname.trim().length < 2) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        code: 404,
        message: '昵称至少需要 2 个字',
      );
    }
    return _session(phone, device.deviceId);
  }

  @override
  Future<AuthSession> refreshSession(AuthSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!session.canRefresh) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        code: 401,
        httpStatus: 401,
        message: '刷新会话已失效',
      );
    }
    return _session(session.mobile, session.deviceId);
  }

  @override
  Future<void> logout(AuthSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  static AuthSession _session(String phone, String deviceId) {
    final DateTime now = DateTime.now();
    return AuthSession(
      accessToken: 'mock-access-token',
      tokenType: 'Bearer',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshToken: 'mock-refresh-token',
      refreshExpiresAt: now.add(const Duration(days: 30)),
      deviceId: deviceId,
      clientId: 'mock-client',
      userId: 10001,
      mobile: phone,
      roles: 'USER',
    );
  }

  static bool _isPhoneValid(String phone) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(phone);
}
