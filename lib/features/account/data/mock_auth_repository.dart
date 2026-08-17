import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  const MockAuthRepository();

  @override
  Future<void> sendSmsCode(String phone) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_isPhoneValid(phone)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        code: 404,
        message: '请输入正确的手机号码',
      );
    }
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
    return AuthOutcome.authenticated(_session(phone));
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
    return _session(phone);
  }

  static AuthSession _session(String phone) => AuthSession(
        accessToken: 'mock-access-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        userId: 10001,
        mobile: phone,
        roles: 'USER',
      );

  static bool _isPhoneValid(String phone) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(phone);
}
