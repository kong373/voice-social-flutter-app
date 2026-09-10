import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/login_page.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<AppDependencies> start(WidgetTester tester) async {
    final dependencies = AppDependencies.mock();
    await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await dependencies.authController.acceptConsent();
    final login = dependencies.authController.signInWithSms(
      phone: '13800138000',
      smsCode: '123456',
    );
    await tester.pumpAndSettle();
    await login;
    await tester.pumpAndSettle();
    return dependencies;
  }

  Future<BuildContext> push(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('old identity route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.element(find.text('old identity route'));
  }

  testWidgets('expired session removes pushed routes and nested dialog', (
    tester,
  ) async {
    final dependencies = await start(tester);
    await push(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceSessionsPage(
            account: '13800138000',
            currentVersion: 6,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final oldContext = tester.element(find.byType(DeviceSessionsPage));
    unawaited(
      showDialog<void>(
        context: oldContext,
        builder: (_) => const AlertDialog(content: Text('old identity dialog')),
      ),
    );
    await tester.pumpAndSettle();
    await dependencies.sessionManager.clear();
    expect(await dependencies.authController.refreshSession(), isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('old identity route'), findsNothing);
    expect(find.byType(DeviceSessionsPage), findsNothing);
    expect(find.text('old identity dialog'), findsNothing);
    expect(oldContext.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same principal rotation keeps pushed route', (tester) async {
    final dependencies = await start(tester);
    final oldContext = await push(tester);
    final refresh = dependencies.authController.refreshSession();
    await tester.pumpAndSettle();
    expect(await refresh, isTrue);
    await tester.pumpAndSettle();
    expect(oldContext.mounted, isTrue);
    expect(find.text('old identity route'), findsOneWidget);
  });

  testWidgets('explicit logout removes dialog and stale async route context', (
    tester,
  ) async {
    final dependencies = await start(tester);
    final oldContext = await push(tester);
    final delayed = Completer<void>();
    final lateResult = delayed.future.then((_) {
      if (oldContext.mounted) {
        Navigator.of(oldContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('resurrected')),
          ),
        );
      }
    });
    unawaited(
      showDialog<void>(
        context: oldContext,
        builder: (_) => const AlertDialog(content: Text('old identity dialog')),
      ),
    );
    await tester.pumpAndSettle();
    final logout = dependencies.authController.signOut();
    await tester.pumpAndSettle();
    await logout;
    await tester.pumpAndSettle();
    delayed.complete();
    await lateResult;
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('resurrected'), findsNothing);
    expect(oldContext.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('different principal removes old routes', (tester) async {
    final dependencies = await start(tester);
    final oldContext = await push(tester);
    final session = dependencies.authController.session!;
    await dependencies.sessionManager.save(
      AuthSession(
        accessToken: session.accessToken,
        tokenType: session.tokenType,
        expiresAt: session.expiresAt,
        refreshToken: session.refreshToken,
        refreshExpiresAt: session.refreshExpiresAt,
        deviceId: session.deviceId,
        clientId: session.clientId,
        userId: 20002,
        mobile: '13800138001',
        roles: session.roles,
      ),
    );
    // A public controller notification observes the new principal.
    final notification = dependencies.authController.sendSmsCode('13800138001');
    await tester.pumpAndSettle();
    await notification;
    expect(oldContext.mounted, isFalse);
    expect(dependencies.authController.stage, AuthFlowStage.signedIn);
  });

  testWidgets('personal center logout popUntil coexists with navigator reset', (
    tester,
  ) async {
    final dependencies = await start(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PersonalCenterPage(
            session: dependencies.authController.session,
            onSignOut: dependencies.authController.signOut,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(PersonalCenterPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final failErase in [false, true]) {
    testWidgets(
      '401 replay rejection reaches auth gate; erase failure=$failErase',
      (tester) async {
        final store = _EraseStore();
        final manager = AuthSessionManager(store);
        await manager.acceptConsent();
        await manager.save(
          AuthSession(
            accessToken: 'test-access',
            tokenType: 'Bearer',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            refreshToken: 'test-refresh',
            refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
            deviceId: 'test-device',
            userId: 10,
            mobile: '13800138000',
            roles: 'USER',
          ),
        );
        final controller = AuthController(
          repository: _RejectedRefresh(),
          sessionManager: manager,
          deviceIdentityProvider: DeviceIdentityProvider(
            environment: AppEnvironment.mock(),
            sessionManager: manager,
          ),
        );
        await controller.initialize();
        await tester.pumpWidget(
          AuthNavigationBoundary(
            controller: controller,
            builder: (key) => MaterialApp(
              navigatorKey: key,
              home: ListenableBuilder(
                listenable: controller,
                builder: (_, _) =>
                    controller.stage == AuthFlowStage.recoveryRequired
                    ? SessionRecoveryPage(
                        busy: controller.busy,
                        message: controller.errorMessage,
                        onRetry: controller.retrySessionRecovery,
                        onSignOut: controller.discardSessionAndSignOut,
                      )
                    : controller.stage == AuthFlowStage.signedOut
                    ? LoginPage(controller: controller)
                    : const Scaffold(body: Text('signed in')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final oldContext = await push(tester);
        store.failErase = failErase;
        expect(await controller.refreshSession(), isFalse);
        await tester.pumpAndSettle();
        expect(oldContext.mounted, isFalse);
        expect(find.textContaining('REFRESH_TOKEN_REPLAYED'), findsNothing);
        if (failErase) {
          expect(find.byType(SessionRecoveryPage), findsOneWidget);
          store.failErase = false;
          await controller.retrySessionRecovery();
          await tester.pumpAndSettle();
        } else {
          expect(find.text('登录已失效，请重新登录'), findsOneWidget);
        }
        expect(find.byType(LoginPage), findsOneWidget);
        expect(controller.session, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        manager.dispose();
      },
    );
  }

  testWidgets(
    'consent and registration notifications preserve ordinary routes',
    (tester) async {
      final dependencies = AppDependencies.mock();
      await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      final context = await push(tester);
      await dependencies.authController.acceptConsent();
      final sendCode = dependencies.authController.sendSmsCode('13900000000');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(await sendCode, isTrue);
      final login = dependencies.authController.signInWithSms(
        phone: '13900000000',
        smsCode: '123456',
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await login;
      expect(
        dependencies.authController.stage,
        AuthFlowStage.registrationRequired,
      );
      expect(context.mounted, isTrue);
      dependencies.authController.cancelRegistration();
      await tester.pumpAndSettle();
      expect(context.mounted, isTrue);
    },
  );
}

class _RejectedRefresh extends MockAuthRepository {
  @override
  Future<AuthSession> refreshSession(AuthSession session) async =>
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        httpStatus: 401,
        message: 'REFRESH_TOKEN_REPLAYED',
      );

  @override
  Future<void> logout(AuthSession session) async {}
}

class _EraseStore extends MemoryKeyValueStore {
  bool failErase = false;

  @override
  Future<void> delete(String key) async {
    if (failErase) throw StateError('test erase failure');
    await super.delete(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failErase && value.isEmpty) throw StateError('test erase failure');
    await super.write(key, value);
  }
}
