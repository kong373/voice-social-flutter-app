import 'package:voice_social_app/features/account/domain/auth_models.dart';

abstract interface class AuthRepository {
  Future<void> sendSmsCode(String phone);

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
}
