import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

const AppEnvironment liveEnvironment = AppEnvironment(
  backendMode: BackendMode.live,
  apiBaseUrl: 'https://example.invalid',
  clientType: 'Android',
  clientInnerVersion: '6',
  oauthClientId: 'public-client',
  realtimeEndpoint: '',
  deploymentEnvironment: DeploymentEnvironment.production,
);

void main() {
  for (final deployment in DeploymentEnvironment.values) {
    testWidgets('login diagnostic visibility in ${deployment.name}', (
      tester,
    ) async {
      final dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://example.invalid',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
          deploymentEnvironment: deployment,
        ),
        initialStorage: <String, String>{
          AuthSessionManager.consentStorageKey:
              AuthSessionManager.consentStorageValue,
        },
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(home: AppGate(dependencies: dependencies)),
        ),
      );
      await _pumpUntil(tester, find.text('登录 / 注册'));
      expect(
        find.byKey(const Key('live-backend-readiness-entry')),
        deployment.allowsDevelopmentTools ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets(
    'live account restriction blocks MainShell with appeal and exit',
    (WidgetTester tester) async {
      final _GateComplianceRepository repository = _GateComplianceRepository(
        _snapshot(
          accountUsable: false,
          restriction: const AccountRestriction(
            kind: RestrictionKind.account,
            reason: '账号因安全策略暂时受限',
          ),
        ),
      );
      final AppDependencies dependencies = _dependencies(
        repository,
        sessionMobile: '13800138000',
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(home: AppGate(dependencies: dependencies)),
        ),
      );
      await _pumpUntil(
        tester,
        find.byKey(const Key('live-account-restricted')),
      );

      expect(find.byKey(const Key('live-home-ready')), findsNothing);
      expect(find.text('账号因安全策略暂时受限'), findsOneWidget);
      expect(
        find.byKey(const Key('account-access-gate-appeal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('account-access-gate-signout')),
        findsOneWidget,
      );
      expect(repository.calls, 1);
    },
  );

  testWidgets('live account status network failure stays fail-closed', (
    WidgetTester tester,
  ) async {
    final _GateComplianceRepository repository = _GateComplianceRepository(
      null,
      error: const ApiException(
        kind: ApiFailureKind.timeout,
        message: '状态检查超时',
      ),
    );
    final AppDependencies dependencies = _dependencies(repository);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: AppGate(dependencies: dependencies)),
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const Key('account-access-gate-error')),
    );

    expect(find.byKey(const Key('live-home-ready')), findsNothing);
    expect(find.text('状态检查超时'), findsOneWidget);
    expect(find.textContaining('不会默认放行'), findsOneWidget);
  });

  testWidgets(
    'changing the session principal clears the old compliance snapshot first',
    (WidgetTester tester) async {
      final _SwitchingGateComplianceRepository repository =
          _SwitchingGateComplianceRepository(_snapshot());
      final AppDependencies dependencies = _dependencies(repository);
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(home: AppGate(dependencies: dependencies)),
        ),
      );
      await _pumpUntil(tester, find.byKey(const Key('live-home-ready')));

      final AuthSession nextSession = AuthSession(
        accessToken: 'next-access-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        refreshToken: 'next-refresh-token',
        refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
        deviceId: 'next-device',
        clientId: 'public-client',
        userId: 10002,
        mobile: '13900000000',
        roles: 'USER',
      );
      await dependencies.sessionManager.save(nextSession);
      dependencies.authController.notifyListeners();
      await tester.pump();

      expect(find.byKey(const Key('live-home-ready')), findsNothing);
      expect(find.byKey(const Key('live-account-preflight')), findsOneWidget);
      expect(repository.calls, 2);

      repository.secondSnapshot.complete(_snapshot());
      await _pumpUntil(tester, find.byKey(const Key('live-home-ready')));
    },
  );

  for (final outcome in <String>['allowed', 'restricted', 'network-error']) {
    testWidgets(
      'same identity rotation preserves shell while rechecking $outcome',
      (tester) async {
        final repository = _SwitchingGateComplianceRepository(_snapshot());
        final dependencies = _dependencies(repository);
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(home: AppGate(dependencies: dependencies)),
          ),
        );
        await _pumpUntil(tester, find.byKey(const Key('live-home-ready')));
        final previousShell = tester.element(find.byType(MainShell));
        await tester.tap(find.text('我的').hitTestable());
        await tester.pump();
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
        final current = dependencies.authController.session!;
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'rotated-access',
            refreshToken: 'rotated-refresh',
            tokenType: current.tokenType,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            refreshExpiresAt: current.refreshExpiresAt,
            deviceId: current.deviceId,
            clientId: current.clientId,
            userId: current.userId,
            mobile: current.mobile,
            roles: current.roles,
          ),
        );
        dependencies.authController.notifyListeners();
        await tester.pump();
        expect(repository.calls, 2);
        expect(previousShell.mounted, isTrue);
        expect(tester.element(find.byType(MainShell)), same(previousShell));
        expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
        if (outcome == 'network-error') {
          repository.secondSnapshot.completeError(
            const ApiException(kind: ApiFailureKind.timeout, message: '状态检查超时'),
          );
          await _pumpUntil(
            tester,
            find.byKey(const Key('account-access-gate-error')),
          );
          expect(find.byType(MainShell), findsNothing);
        } else {
          repository.secondSnapshot.complete(
            outcome == 'allowed'
                ? _snapshot()
                : _snapshot(accountUsable: false),
          );
          if (outcome == 'allowed') {
            await tester.pump();
            expect(tester.element(find.byType(MainShell)), same(previousShell));
            expect(
              tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
              3,
            );
          } else {
            await _pumpUntil(
              tester,
              find.byKey(const Key('live-account-restricted')),
            );
            expect(find.byType(MainShell), findsNothing);
          }
        }
        await tester.pumpWidget(const SizedBox());
        dependencies.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('same optional update deferral survives normal rotation', (
    tester,
  ) async {
    const policy = VersionUpdateInfo(
      hasUpdate: true,
      forceUpdate: false,
      versionName: '7.0.0',
      releaseNotes: '安全更新',
      packageUrl: 'https://updates.example.invalid/app.apk',
    );
    final repository = _SwitchingGateComplianceRepository(
      _snapshot(versionInfo: policy),
    );
    final dependencies = _dependencies(repository);
    await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
    await _pumpUntil(tester, find.byKey(const Key('app-version-gate-later')));
    await tester.tap(find.byKey(const Key('app-version-gate-later')));
    await _pumpUntil(tester, find.byKey(const Key('live-home-ready')));
    await tester.tap(find.text('我的').hitTestable());
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    final shell = tester.element(find.byType(MainShell));
    await _rotate(dependencies);
    await tester.pump();
    repository.secondSnapshot.complete(_snapshot(versionInfo: policy));
    await tester.pump();
    expect(shell.mounted, isTrue);
    expect(tester.element(find.byType(MainShell)), same(shell));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(find.byKey(const Key('live-version-policy')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['restricted', 'network-error', 'mandatory-update']) {
    testWidgets('fresh $outcome removes pushed pages and dialog', (
      tester,
    ) async {
      final repository = _SwitchingGateComplianceRepository(_snapshot());
      final dependencies = _dependencies(repository);
      await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
      await _pumpUntil(tester, find.byKey(const Key('live-home-ready')));
      final gateState = tester.state(find.byType(AppGate));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('old protected page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldContext = tester.element(find.text('old protected page'));
      final delayed = Completer<void>();
      final lateNavigation = delayed.future.then((_) {
        if (oldContext.mounted) {
          unawaited(
            Navigator.of(oldContext).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('late reopened page')),
              ),
            ),
          );
        }
      });
      unawaited(
        showDialog<void>(
          context: oldContext,
          builder: (_) =>
              const AlertDialog(content: Text('old protected dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await _rotate(dependencies);
      await tester.pump();
      expect(oldContext.mounted, isTrue);
      if (outcome == 'network-error') {
        repository.secondSnapshot.completeError(
          const ApiException(kind: ApiFailureKind.timeout, message: '状态检查超时'),
        );
      } else {
        repository.secondSnapshot.complete(
          outcome == 'restricted'
              ? _snapshot(accountUsable: false)
              : _snapshot(
                  versionInfo: const VersionUpdateInfo(
                    hasUpdate: true,
                    forceUpdate: true,
                    versionName: '8.0.0',
                    releaseNotes: '必须升级',
                    packageUrl: 'https://updates.example.invalid/app.apk',
                  ),
                ),
        );
      }
      // Complete an in-flight page operation before an animated pop finishes.
      await tester.pump();
      delayed.complete();
      await lateNavigation;
      await tester.pumpAndSettle();
      expect(oldContext.mounted, isFalse);
      expect(find.text('old protected page'), findsNothing);
      expect(find.text('old protected dialog'), findsNothing);
      expect(find.text('late reopened page'), findsNothing);
      expect(
        find.byKey(
          Key(switch (outcome) {
            'restricted' => 'live-account-restricted',
            'network-error' => 'account-access-gate-error',
            _ => 'live-version-policy',
          }),
        ),
        findsOneWidget,
      );
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
      expect(tester.state(find.byType(AppGate)), same(gateState));
      expect(repository.calls, 2);
      await dependencies.authController.discardSessionAndSignOut();
      await tester.pumpAndSettle();
      expect(find.text('登录 / 注册'), findsWidgets);
      expect(find.byKey(const Key('live-version-policy')), findsNothing);
      expect(find.byKey(const Key('live-account-restricted')), findsNothing);
      expect(repository.calls, 2);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'optional version policy offers later and then enters MainShell',
    (WidgetTester tester) async {
      final AppDependencies dependencies = _dependencies(
        _GateComplianceRepository(
          _snapshot(
            versionInfo: const VersionUpdateInfo(
              hasUpdate: true,
              forceUpdate: false,
              versionName: '7.0.0',
              releaseNotes: '安全更新',
              packageUrl: 'https://updates.example.invalid/app.apk',
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(home: AppGate(dependencies: dependencies)),
        ),
      );
      await _pumpUntil(tester, find.byKey(const Key('live-version-policy')));

      expect(find.byKey(const Key('app-version-gate-later')), findsOneWidget);
      await tester.tap(find.byKey(const Key('app-version-gate-later')));
      await tester.pump();
      expect(find.byKey(const Key('live-home-ready')), findsOneWidget);
    },
  );

  testWidgets(
    'mandatory version policy has no later bypass and fails closed on URL',
    (WidgetTester tester) async {
      final AppDependencies dependencies = _dependencies(
        _GateComplianceRepository(
          _snapshot(
            versionInfo: const VersionUpdateInfo(
              hasUpdate: true,
              forceUpdate: true,
              versionName: '7.0.0',
              releaseNotes: '必须升级',
              packageUrl: 'https://updates.example.invalid/app.apk',
            ),
          ),
        ),
        externalUrlOpener: _FailingUrlOpener(),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(home: AppGate(dependencies: dependencies)),
        ),
      );
      await _pumpUntil(tester, find.byKey(const Key('live-version-policy')));

      expect(find.byKey(const Key('app-version-gate-later')), findsNothing);
      expect(find.byKey(const Key('live-home-ready')), findsNothing);
      await tester.tap(find.byKey(const Key('app-version-gate-open')));
      await _pumpUntil(tester, find.byKey(const Key('app-version-gate-error')));
      expect(find.textContaining('升级地址未能打开'), findsOneWidget);
      expect(find.byKey(const Key('live-home-ready')), findsNothing);
    },
  );

  testWidgets('version gate reports navigation without claiming installation', (
    WidgetTester tester,
  ) async {
    final _RecordingUrlOpener opener = _RecordingUrlOpener();
    final AppDependencies dependencies = _dependencies(
      _GateComplianceRepository(
        _snapshot(
          versionInfo: const VersionUpdateInfo(
            hasUpdate: true,
            forceUpdate: true,
            versionName: '7.0.0',
            releaseNotes: '必须升级',
            packageUrl: 'https://updates.example.invalid/app.apk',
          ),
        ),
      ),
      externalUrlOpener: opener,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: AppGate(dependencies: dependencies)),
      ),
    );
    await _pumpUntil(tester, find.byKey(const Key('live-version-policy')));

    await tester.tap(find.byKey(const Key('app-version-gate-open')));
    await _pumpUntil(tester, find.byKey(const Key('app-version-gate-status')));

    expect(opener.opened, Uri.parse('https://updates.example.invalid/app.apk'));
    expect(find.textContaining('不等于已安装更新'), findsOneWidget);
    expect(find.byKey(const Key('live-home-ready')), findsNothing);
  });
}

Future<void> _rotate(AppDependencies dependencies) async {
  final current = dependencies.authController.session!;
  await dependencies.sessionManager.save(
    AuthSession(
      accessToken: 'rotated-access',
      refreshToken: 'rotated-refresh',
      tokenType: current.tokenType,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshExpiresAt: current.refreshExpiresAt,
      deviceId: current.deviceId,
      clientId: current.clientId,
      userId: current.userId,
      mobile: current.mobile,
      roles: current.roles,
    ),
  );
  dependencies.authController.notifyListeners();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 40; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for ${finder.description}.');
}

AppDependencies _dependencies(
  MockAccountComplianceRepository repository, {
  String sessionMobile = '13800138000',
  ExternalUrlOpener? externalUrlOpener,
}) {
  final AuthSession session = AuthSession(
    accessToken: 'access-token',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshToken: 'refresh-token',
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    deviceId: 'device-id',
    clientId: 'public-client',
    userId: 10001,
    mobile: sessionMobile,
    roles: 'USER',
  );
  return AppDependencies.forTestEnvironment(
    environment: liveEnvironment,
    accountComplianceRepository: repository,
    externalUrlOpener: externalUrlOpener,
    initialStorage: <String, String>{
      AuthSessionManager.consentStorageKey:
          AuthSessionManager.consentStorageValue,
      'auth.session.v2': session.encode(),
    },
  );
}

AccountComplianceSnapshot _snapshot({
  bool accountUsable = true,
  AccountRestriction restriction = const AccountRestriction(
    kind: RestrictionKind.none,
    reason: '',
  ),
  VersionUpdateInfo versionInfo = const VersionUpdateInfo(
    hasUpdate: false,
    forceUpdate: false,
    versionName: '',
    releaseNotes: '',
    packageUrl: '',
  ),
}) => AccountComplianceSnapshot(
  account: '13800138000',
  nickname: '测试用户',
  accountUsable: accountUsable,
  verificationState: VerificationState.unavailable,
  youthModeEnabled: false,
  restriction: restriction,
  cancellation: const CancellationEligibility(
    allowed: false,
    message: '',
    mobile: '',
    requiresSmsCode: false,
  ),
  versionInfo: versionInfo,
  sessions: const <DeviceSession>[],
  permissions: const <PermissionSetting>[],
);

class _GateComplianceRepository extends MockAccountComplianceRepository {
  _GateComplianceRepository(this.snapshot, {this.error});

  final AccountComplianceSnapshot? snapshot;
  final Object? error;
  int calls = 0;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async {
    calls += 1;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return snapshot!;
  }
}

class _SwitchingGateComplianceRepository
    extends MockAccountComplianceRepository {
  _SwitchingGateComplianceRepository(this.snapshot);

  final AccountComplianceSnapshot snapshot;
  final Completer<AccountComplianceSnapshot> secondSnapshot =
      Completer<AccountComplianceSnapshot>();
  int calls = 0;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) {
    calls += 1;
    return calls == 1
        ? Future<AccountComplianceSnapshot>.value(snapshot)
        : secondSnapshot.future;
  }
}

class _RecordingUrlOpener implements ExternalUrlOpener {
  Uri? opened;

  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    return true;
  }
}

class _FailingUrlOpener implements ExternalUrlOpener {
  @override
  Future<bool> open(Uri uri) async => false;
}
