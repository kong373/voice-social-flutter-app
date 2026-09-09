import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';

class ControlledCompliance extends MockAccountComplianceRepository {
  bool failStatus = false;
  bool mismatchedDisable = false;
  bool mandatory = false;
  bool restricted = false;
  bool loseEnableResponse = false;
  Completer<bool>? disable;
  Completer<AccountComplianceSnapshot>? nextStatus;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async {
    final pending = nextStatus;
    nextStatus = null;
    if (pending != null) return pending.future;
    if (failStatus) throw StateError('unavailable');
    final snapshot = await super.fetchSnapshot(
      account: account,
      expectedUserId: expectedUserId,
      currentVersion: currentVersion,
      platformType: platformType,
    );
    return snapshot.copyWith(
      accountUsable: !restricted,
      versionInfo: mandatory
          ? const VersionUpdateInfo(
              hasUpdate: true,
              forceUpdate: true,
              versionName: '99',
              releaseNotes: 'mandatory',
              packageUrl: '',
            )
          : snapshot.versionInfo,
    );
  }

  @override
  Future<bool> setYouthMode({
    required bool enabled,
    required String pin,
  }) async {
    if (!enabled && disable != null) return disable!.future;
    if (!enabled && mismatchedDisable) return Future.value(true);
    final result = await super.setYouthMode(enabled: enabled, pin: pin);
    if (enabled && loseEnableResponse) throw StateError('response lost');
    return result;
  }
}

Future<AppDependencies> start(
  WidgetTester tester, {
  bool locked = false,
  ControlledCompliance? compliance,
}) async {
  final repository = compliance ?? ControlledCompliance();
  await repository.fetchSnapshot(
    account: '13800138000',
    currentVersion: 6,
    platformType: 1,
  );
  if (locked) await repository.setYouthMode(enabled: true, pin: '2468');
  final dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    accountComplianceRepository: repository,
  );
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

Future<void> unlock(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('youth-unlock-pin')), pin);
  await tester.tap(find.byKey(const Key('youth-unlock-submit')));
  await tester.pumpAndSettle();
}

void background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void foreground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets('stale unlocked status cannot overtake successful enable', (
    tester,
  ) async {
    final repository = ControlledCompliance();
    final dependencies = await start(tester, compliance: repository);
    final oldStatus = await repository.fetchSnapshot(
      account: '13800138000',
      currentVersion: 6,
      platformType: 1,
    );
    final pending = Completer<AccountComplianceSnapshot>();
    repository.nextStatus = pending;
    background(tester);
    foreground(tester);
    await dependencies.changeYouthMode(enabled: true, pin: '2468');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    pending.complete(oldStatus);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('enable replaces a root dialog without a pop animation', (
    tester,
  ) async {
    final dependencies = await start(tester);
    final context = tester.element(find.byType(MainShell));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('old dialog')),
      ),
    );
    await tester.pumpAndSettle();
    final oldContext = tester.element(find.text('old dialog'));
    await dependencies.changeYouthMode(enabled: true, pin: '2468');
    await tester.pump();
    expect(oldContext.mounted, isFalse);
    expect(find.text('old dialog'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
  });

  testWidgets(
    'lost enable response never returns to business before status confirmation',
    (tester) async {
      final repository = ControlledCompliance();
      final dependencies = await start(tester, compliance: repository);
      repository.loseEnableResponse = true;
      repository.failStatus = true;
      await expectLater(
        dependencies.changeYouthMode(enabled: true, pin: '2468'),
        throwsStateError,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsNothing);
      expect(find.byKey(const Key('live-account-preflight')), findsOneWidget);
      repository.failStatus = false;
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    },
  );

  testWidgets('stored authenticated session restores into lock before shell', (
    tester,
  ) async {
    final repository = ControlledCompliance();
    await repository.fetchSnapshot(
      account: '13800138000',
      currentVersion: 6,
      platformType: 1,
    );
    await repository.setYouthMode(enabled: true, pin: '2468');
    final session = AuthSession(
      accessToken: 'test-session',
      tokenType: 'Bearer',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: 10001,
      mobile: '13800138000',
      roles: 'USER',
    );
    final dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: repository,
      initialStorage: {
        AuthSessionManager.consentStorageKey:
            AuthSessionManager.consentStorageValue,
        'auth.session.v2': session.encode(),
      },
    );
    await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
    expect(find.byType(MainShell), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('only correct own PIN unlocks and restores IM access', (
    tester,
  ) async {
    final dependencies = await start(tester, locked: true);
    expect(dependencies.imSessionCoordinator.realtimeReady, isFalse);
    await unlock(tester, '1');
    expect(find.byType(MainShell), findsNothing);
    await unlock(tester, '1111');
    expect(find.byType(MainShell), findsNothing);
    await dependencies.imSessionCoordinator.ensureAuthenticated(
      dependencies.sessionManager.session!,
    );
    expect(dependencies.imSessionCoordinator.realtimeReady, isFalse);
    await unlock(tester, '2468');
    expect(find.byType(MainShell), findsOneWidget);
    expect(dependencies.imSessionCoordinator.realtimeReady, isTrue);
  });

  testWidgets('mismatched disable and unknown status cannot unlock', (
    tester,
  ) async {
    final repository = ControlledCompliance();
    await start(tester, locked: true, compliance: repository);
    repository.mismatchedDisable = true;
    await unlock(tester, '2468');
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    repository.mismatchedDisable = false;
    repository.failStatus = true;
    await unlock(tester, '2468');
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets(
    'foreground status removes deep business routes and releases room and IM',
    (tester) async {
      final repository = ControlledCompliance();
      final dependencies = await start(tester, compliance: repository);
      final room = dependencies.createRoomController(
        roomId: '1001',
        title: 'test',
      );
      final join = room.join();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await join;
      final rtc = dependencies.rtcAdapter as MockRtcAdapter;
      expect(rtc.joined, isTrue);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('deep business')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldContext = tester.element(find.text('deep business'));
      background(tester);
      await repository.setYouthMode(enabled: true, pin: '2468');
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
      expect(oldContext.mounted, isFalse);
      expect(rtc.joined, isFalse);
      expect(rtc.audioEnabled, isFalse);
      expect(dependencies.imSessionCoordinator.realtimeReady, isFalse);
      expect(
        () =>
            dependencies.createRoomController(roomId: '1001', title: 'blocked'),
        throwsStateError,
      );
      await room.join();
      expect(rtc.joined, isFalse);
      repository.failStatus = true;
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    },
  );

  testWidgets('late successful disable cannot resurrect expired account', (
    tester,
  ) async {
    final repository = ControlledCompliance();
    final dependencies = await start(
      tester,
      locked: true,
      compliance: repository,
    );
    repository.disable = Completer<bool>();
    final result = dependencies.changeYouthMode(enabled: false, pin: '2468');
    final rejected = expectLater(result, throwsStateError);
    await dependencies.authController.discardSessionAndSignOut();
    await tester.pumpAndSettle();
    repository.disable!.complete(false);
    await rejected;
    await tester.pumpAndSettle();
    expect(dependencies.youthModeResult, isNull);
    expect(find.byType(MainShell), findsNothing);
    expect(find.byKey(const Key('youth-mode-lock')), findsNothing);
  });

  testWidgets(
    'restriction and mandatory version retain priority over youth lock',
    (tester) async {
      final repository = ControlledCompliance()..mandatory = true;
      await start(tester, locked: true, compliance: repository);
      expect(find.byKey(const Key('live-version-policy')), findsOneWidget);
      expect(find.byKey(const Key('youth-mode-lock')), findsNothing);
      repository.restricted = true;
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-account-restricted')), findsOneWidget);
      expect(find.byKey(const Key('youth-mode-lock')), findsNothing);
    },
  );

  testWidgets('enabled account enters a non-dismissable global lock', (
    tester,
  ) async {
    await start(tester, locked: true);
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(find.textContaining('忘记'), findsNothing);
  });

  testWidgets('enable disposes settings and older business routes', (
    tester,
  ) async {
    await start(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('old business')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final oldContext = tester.element(find.text('old business'));
    final delayed = Completer<void>();
    final continuation = delayed.future.then((_) {
      if (oldContext.mounted) {
        unawaited(
          Navigator.of(oldContext).push(
            MaterialPageRoute<void>(
              builder: (_) => const Text('late business'),
            ),
          ),
        );
      }
    });
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const YouthModePage(
            account: '13800138000',
            currentVersion: 6,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2468');
    await tester.ensureVisible(find.text('开启青少年模式'));
    await tester.tap(find.text('开启青少年模式'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youth-mode-lock')), findsOneWidget);
    expect(oldContext.mounted, isFalse);
    delayed.complete();
    await continuation;
    await tester.pumpAndSettle();
    expect(find.text('late business'), findsNothing);
    expect(find.byType(YouthModePage), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
      isFalse,
    );
  });
}
