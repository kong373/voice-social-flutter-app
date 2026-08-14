import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

void main() {
  test('auth controller persists an authenticated SMS session', () async {
    final MemoryKeyValueStore store = MemoryKeyValueStore();
    final AuthSessionManager sessionManager = AuthSessionManager(store);
    final AuthController controller = AuthController(
      repository: const MockAuthRepository(),
      sessionManager: sessionManager,
      deviceIdentityProvider: DeviceIdentityProvider(
        environment: AppEnvironment.mock(),
        sessionManager: sessionManager,
      ),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.stage, AuthFlowStage.consentRequired);

    await controller.acceptConsent();
    expect(controller.stage, AuthFlowStage.signedOut);

    final bool signedIn = await controller.signInWithSms(
      phone: '13800138000',
      smsCode: '123456',
    );
    expect(signedIn, isTrue);
    expect(controller.stage, AuthFlowStage.signedIn);
    expect(controller.session?.userId, 10001);

    final AuthSession? restored = await sessionManager.restore();
    expect(restored?.mobile, '13800138000');

    await controller.signOut();
    expect(controller.stage, AuthFlowStage.signedOut);
    expect(sessionManager.session, isNull);
  });

  test('unregistered phone enters profile completion and registers', () async {
    final AuthSessionManager sessionManager =
        AuthSessionManager(MemoryKeyValueStore());
    final AuthController controller = AuthController(
      repository: const MockAuthRepository(),
      sessionManager: sessionManager,
      deviceIdentityProvider: DeviceIdentityProvider(
        environment: AppEnvironment.mock(),
        sessionManager: sessionManager,
      ),
    );
    addTearDown(controller.dispose);

    await controller.acceptConsent();
    await controller.signInWithSms(
      phone: '13900000000',
      smsCode: '123456',
    );
    expect(controller.stage, AuthFlowStage.registrationRequired);

    final bool registered = await controller.completeRegistration(
      const RegistrationProfile(nickname: '新朋友', sex: 2),
    );
    expect(registered, isTrue);
    expect(controller.stage, AuthFlowStage.signedIn);
  });
}
