import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
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
      allowsDevelopmentTools: true,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.stage, AuthFlowStage.consentRequired);

    await controller.acceptConsent();
    expect(controller.stage, AuthFlowStage.signedOut);

    final bool sent = await controller.sendSmsCode('13800138000');
    expect(sent, isTrue);
    expect(controller.lastSmsChallenge?.challengeId, isNotEmpty);
    expect(controller.developmentSmsCode, '123456');

    final bool signedIn = await controller.signInWithSms(
      phone: '13800138000',
      smsCode: '123456',
    );
    expect(signedIn, isTrue);
    expect(controller.stage, AuthFlowStage.signedIn);
    expect(controller.session?.userId, 10001);
    expect(controller.session?.refreshToken, isNotEmpty);

    final AuthSession? restored = await sessionManager.restore();
    expect(restored?.mobile, '13800138000');

    await controller.signOut();
    expect(controller.stage, AuthFlowStage.signedOut);
    expect(sessionManager.session, isNull);
  });

  test(
    'auth controller drops development OTP outside an allowed environment',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      final AuthController controller = AuthController(
        repository: const MockAuthRepository(),
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      await controller.sendSmsCode('13800138000');

      expect(controller.lastSmsChallenge?.developmentCode, isNull);
      expect(controller.developmentSmsCode, isNull);
    },
  );

  test('expired access token is refreshed during startup', () async {
    final AuthSessionManager sessionManager = AuthSessionManager(
      MemoryKeyValueStore(),
    );
    await sessionManager.acceptConsent();
    await sessionManager.save(
      AuthSession(
        accessToken: 'expired-access',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshToken: 'valid-refresh',
        refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
        deviceId: 'device-1',
        userId: 10001,
        mobile: '13800138000',
        roles: 'USER',
      ),
    );
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

    expect(controller.stage, AuthFlowStage.signedIn);
    expect(controller.session?.accessToken, 'mock-access-token');
  });

  test('unregistered phone enters profile completion and registers', () async {
    final AuthSessionManager sessionManager = AuthSessionManager(
      MemoryKeyValueStore(),
    );
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
    await controller.signInWithSms(phone: '13900000000', smsCode: '123456');
    expect(controller.stage, AuthFlowStage.registrationRequired);

    final bool registered = await controller.completeRegistration(
      const RegistrationProfile(nickname: '新朋友', sex: 2),
    );
    expect(registered, isTrue);
    expect(controller.stage, AuthFlowStage.signedIn);
  });

  test(
    'ambiguous refresh outcome clears the one-time token and fails closed',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      await sessionManager.acceptConsent();
      await sessionManager.save(_expiredRefreshableSession());
      final _RefreshFailureAuthRepository repository =
          _RefreshFailureAuthRepository(
            const ApiException(kind: ApiFailureKind.timeout, message: '刷新响应超时'),
          );
      final AuthController controller = AuthController(
        repository: repository,
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(repository.refreshCalls, 1);
      expect(controller.stage, AuthFlowStage.signedOut);
      expect(controller.session, isNull);
      expect(await sessionManager.restore(), isNull);
      expect(controller.errorMessage, contains('刷新结果无法确认'));
    },
  );

  test(
    'refresh conflict is fail-closed and clears the local session',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      await sessionManager.acceptConsent();
      await sessionManager.save(_expiredRefreshableSession());
      final AuthController controller = AuthController(
        repository: _RefreshFailureAuthRepository(
          const ApiException(
            kind: ApiFailureKind.conflict,
            httpStatus: 409,
            code: 40901,
            message: 'refresh request already committed',
          ),
        ),
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.stage, AuthFlowStage.signedOut);
      expect(controller.session, isNull);
      expect(await sessionManager.restore(), isNull);
    },
  );

  test(
    'preflight configuration failure preserves a refreshable local session',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      await sessionManager.acceptConsent();
      final AuthSession original = _expiredRefreshableSession();
      await sessionManager.save(original);
      final AuthController controller = AuthController(
        repository: _RefreshFailureAuthRepository(
          const ApiException(
            kind: ApiFailureKind.configuration,
            message: '后端地址尚未配置',
          ),
        ),
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.stage, AuthFlowStage.recoveryRequired);
      expect(controller.session?.refreshToken, original.refreshToken);
      expect(controller.errorMessage, '后端地址尚未配置');
    },
  );

  test('concurrent refresh calls remain a single rotation attempt', () async {
    final AuthSessionManager sessionManager = AuthSessionManager(
      MemoryKeyValueStore(),
    );
    final AuthSession original = _expiredRefreshableSession();
    await sessionManager.save(original);
    final _DelayedRefreshAuthRepository repository =
        _DelayedRefreshAuthRepository();
    final AuthController controller = AuthController(
      repository: repository,
      sessionManager: sessionManager,
      deviceIdentityProvider: DeviceIdentityProvider(
        environment: AppEnvironment.mock(),
        sessionManager: sessionManager,
      ),
    );
    addTearDown(controller.dispose);

    final Future<bool> first = controller.refreshSession();
    final Future<bool> duplicate = controller.refreshSession();
    await repository.started.future;
    expect(repository.refreshCalls, 1);
    repository.result.complete(_refreshedSession());

    expect(await Future.wait(<Future<bool>>[first, duplicate]), <bool>[
      true,
      true,
    ]);
    expect(repository.refreshCalls, 1);
    expect(controller.session?.refreshToken, 'rotated-refresh');
  });

  test(
    'late refresh response cannot restore a locally signed-out session',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      final AuthSession original = _expiredRefreshableSession();
      await sessionManager.save(original);
      final _DelayedRefreshAuthRepository repository =
          _DelayedRefreshAuthRepository();
      final AuthController controller = AuthController(
        repository: repository,
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      final Future<bool> refresh = controller.refreshSession();
      await repository.started.future;
      await controller.discardSessionAndSignOut();
      repository.result.complete(_refreshedSession());

      expect(await refresh, isFalse);
      expect(controller.stage, AuthFlowStage.signedOut);
      expect(controller.session, isNull);
      expect(await sessionManager.restore(), isNull);
    },
  );

  test(
    'signOut invalidates an in-flight refresh before clearing credentials',
    () async {
      final AuthSessionManager sessionManager = AuthSessionManager(
        MemoryKeyValueStore(),
      );
      await sessionManager.save(_expiredRefreshableSession());
      final _DelayedRefreshAuthRepository repository =
          _DelayedRefreshAuthRepository();
      final AuthController controller = AuthController(
        repository: repository,
        sessionManager: sessionManager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: sessionManager,
        ),
      );
      addTearDown(controller.dispose);

      final Future<bool> refresh = controller.refreshSession();
      await repository.started.future;
      await controller.signOut();
      repository.result.complete(_refreshedSession());

      expect(await refresh, isFalse);
      expect(controller.stage, AuthFlowStage.signedOut);
      expect(controller.session, isNull);
      expect(await sessionManager.restore(), isNull);
    },
  );
}

AuthSession _expiredRefreshableSession() => AuthSession(
  accessToken: 'expired-access',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
  refreshToken: 'one-time-refresh',
  refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  deviceId: 'device-1',
  clientId: 'voice-social-mobile-public',
  userId: 10001,
  mobile: '13800138000',
  roles: 'USER',
);

AuthSession _refreshedSession() => AuthSession(
  accessToken: 'rotated-access',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  refreshToken: 'rotated-refresh',
  refreshExpiresAt: DateTime.now().add(const Duration(days: 30)),
  deviceId: 'device-1',
  clientId: 'voice-social-mobile-public',
  userId: 10001,
  mobile: '13800138000',
  roles: 'USER',
);

class _RefreshFailureAuthRepository extends MockAuthRepository {
  _RefreshFailureAuthRepository(this.failure);

  final Object failure;
  int refreshCalls = 0;

  @override
  Future<AuthSession> refreshSession(AuthSession session) async {
    refreshCalls += 1;
    throw failure;
  }
}

class _DelayedRefreshAuthRepository extends MockAuthRepository {
  final Completer<void> started = Completer<void>();
  final Completer<AuthSession> result = Completer<AuthSession>();
  int refreshCalls = 0;

  @override
  Future<AuthSession> refreshSession(AuthSession session) {
    refreshCalls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
  }
}
