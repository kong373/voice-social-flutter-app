import 'package:voice_social_app/features/account/domain/auth_models.dart';

abstract interface class AuthRepository {
  Future<SmsChallenge> sendSmsCode({
    required String phone,
    required ClientDevice device,
  });

  Future<String?> readDevelopmentSmsCode(String challengeId);

  Future<AuthOutcome> signInWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  });

  Future<AuthSession> registerWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
    required RegistrationProfile profile,
  });

  Future<AuthSession> refreshSession(AuthSession session);

  Future<void> logout(AuthSession session);
}
