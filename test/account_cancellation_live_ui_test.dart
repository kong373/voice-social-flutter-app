import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_pages.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

void main() {
  testWidgets(
    'confirmed application submits once then displays fresh cooling authority',
    (tester) async {
      final repository = _SubmitRepository();
      final dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        accountComplianceRepository: repository,
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AccountCancellationPage(
              account: 'user-1',
              currentVersion: 1,
              platformType: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('申请注销'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(repository.submits, 1);
      expect(repository.reads, greaterThanOrEqualTo(3));
      expect(find.text('撤销注销'), findsOneWidget);
      expect(find.text('申请注销'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'near deadline schedules authority reread before normal polling interval',
    (tester) async {
      final repository = _AuthorityRepository()
        ..deadline = DateTime.now()
            .toUtc()
            .add(const Duration(milliseconds: 900))
            .toIso8601String();
      await _openAuthorityPage(tester, repository);
      repository.mayCancel = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repository.reads, greaterThan(1));
      expect(find.text('撤销注销'), findsNothing);
      expect(find.text('注销申请处理中'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hidden in-flight read is discarded and return reads fresh authority',
    (tester) async {
      final repository = _AuthorityRepository();
      await _openAuthorityPage(tester, repository);
      repository.pending = Completer<CancellationEligibility>();
      await tester.pump(const Duration(seconds: 2));
      expect(repository.reads, 2);
      final navigator = Navigator.of(
        tester.element(find.byType(AccountCancellationPage)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repository.pending!.complete(repository.value);
      repository.pending = null;
      repository.mayCancel = false;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.reads, 2);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(repository.reads, 3);
      expect(find.text('撤销注销'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'expired cooling snapshot retains application without any write action',
    (tester) async {
      final repository = _AuthorityRepository()..mayCancel = false;
      await _openAuthorityPage(tester, repository);
      expect(find.text('注销申请处理中'), findsOneWidget);
      expect(find.text('当前不可撤销'), findsOneWidget);
      expect(find.text('撤销注销'), findsNothing);
      expect(find.text('申请注销'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'open cancellation page refreshes expiry and fails closed on read error',
    (tester) async {
      final repository = _AuthorityRepository();
      await _openAuthorityPage(tester, repository);
      expect(find.text('撤销注销'), findsOneWidget);
      repository.mayCancel = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(repository.reads, greaterThan(1));
      expect(find.text('撤销注销'), findsNothing);
      repository.failReads = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('状态查询失败'), findsOneWidget);
      expect(find.text('申请注销'), findsNothing);
      expect(find.text('撤销注销'), findsNothing);
      repository.failReads = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('注销申请处理中'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'foreground resume and route return refresh while hidden pages do not poll',
    (tester) async {
      final repository = _AuthorityRepository();
      await _openAuthorityPage(tester, repository);
      final context = tester.element(find.byType(AccountCancellationPage));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final calls = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, calls);
      repository.mayCancel = false;
      Navigator.of(tester.element(find.text('covered'))).pop();
      await tester.pumpAndSettle();
      expect(repository.reads, greaterThan(calls));
      expect(find.text('撤销注销'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pausedCalls = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, pausedCalls);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.reads, greaterThan(pausedCalls));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'server expiry rejection invalidates old revoke snapshot before retry',
    (tester) async {
      final repository = _AuthorityRepository()..rejectRevoke = true;
      await _openAuthorityPage(tester, repository);
      await tester.tap(find.text('撤销注销'));
      await tester.pumpAndSettle();
      expect(repository.cancels, 1);
      expect(repository.reads, greaterThan(1));
      expect(find.text('注销申请已撤销'), findsNothing);
      expect(find.text('撤销注销'), findsNothing);
      expect(find.text('注销申请处理中'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'old in-flight eligibility cannot restore action after account switch',
    (tester) async {
      final repository = _AuthorityRepository();
      final dependencies = await _openAuthorityPage(tester, repository);
      repository.pending = Completer<CancellationEligibility>();
      await tester.pump(const Duration(seconds: 2));
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'synthetic',
          tokenType: 'Bearer',
          expiresAt: DateTime(2030),
          userId: 2,
          mobile: '',
          roles: 'USER',
        ),
      );
      repository.pending!.complete(repository.value);
      await tester.pumpAndSettle();
      expect(find.text('登录状态已改变，请重新进入账号注销页。'), findsOneWidget);
      expect(find.text('撤销注销'), findsNothing);
      final calls = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, calls);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('live cancellation without SMS still exposes explicit submit', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: _ConfirmationOnlyRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AccountCancellationPage(
            account: 'user-1',
            currentVersion: 1,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认注销申请'), findsOneWidget);
    expect(find.text('申请注销'), findsOneWidget);
    expect(find.text('短信验证码'), findsNothing);
    expect(find.textContaining('7 天冷静期'), findsOneWidget);
  });

  testWidgets('cooling-off cancellation exposes revoke and hides new request', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: _CoolingOffRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AccountCancellationPage(
            account: 'user-1',
            currentVersion: 1,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('撤销注销'), findsOneWidget);
    expect(find.text('申请注销'), findsNothing);
    expect(find.text('注销冷静期中'), findsOneWidget);
  });

  testWidgets('blocked cancellation shows no submit, revoke or SMS action', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: _BlockedRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AccountCancellationPage(
            account: 'user-1',
            currentVersion: 1,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂不能申请注销'), findsOneWidget);
    expect(find.text('当前暂不满足注销条件'), findsOneWidget);
    expect(find.text('申请注销'), findsNothing);
    expect(find.text('撤销注销'), findsNothing);
    expect(find.text('短信验证码'), findsNothing);
    expect(find.text('注销冷静期中'), findsNothing);
  });

  testWidgets('revoke action does not double-submit and recovers HTTP errors', (
    WidgetTester tester,
  ) async {
    final _FailingCancellationRepository repository =
        _FailingCancellationRepository();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: repository,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AccountCancellationPage(
            account: 'user-1',
            currentVersion: 1,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销注销'));
    await tester.pump();
    expect(repository.cancelCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    expect(find.text('撤销注销'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(repository.cancelCalls, 1);

    repository.release();
    await tester.pumpAndSettle();
    expect(repository.cancelCalls, 1);
    expect(find.text('撤销注销'), findsOneWidget);
    expect(find.text('申请注销'), findsNothing);
    expect(find.text('注销状态已变化，请刷新后重试'), findsOneWidget);
  });
}

Future<AppDependencies> _openAuthorityPage(
  WidgetTester tester,
  _AuthorityRepository repository,
) async {
  final dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    accountComplianceRepository: repository,
  );
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const AccountCancellationPage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return dependencies;
}

class _AuthorityRepository extends MockAccountComplianceRepository {
  int reads = 0;
  int cancels = 0;
  bool mayCancel = true;
  bool failReads = false;
  bool rejectRevoke = false;
  String deadline = '2030-01-01T08:00:00Z';
  Completer<CancellationEligibility>? pending;
  CancellationEligibility get value => CancellationEligibility(
    allowed: false,
    canCancel: mayCancel,
    status: 'COOLING_OFF',
    message: '账户已进入注销冷静期',
    mobile: '',
    requiresSmsCode: false,
    coolingEndsAt: deadline,
  );
  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    reads++;
    if (pending != null) return pending!.future;
    if (failReads)
      throw const ApiException(kind: ApiFailureKind.network, message: '状态查询失败');
    return value;
  }

  @override
  Future<CancellationEligibility> cancelDeletion() async {
    cancels++;
    if (rejectRevoke) {
      mayCancel = false;
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40925,
        httpStatus: 409,
        message: '注销冷静期已结束，无法取消',
      );
    }
    return const CancellationEligibility(
      allowed: true,
      message: '',
      mobile: '',
      requiresSmsCode: false,
    );
  }
}

class _SubmitRepository extends _AuthorityRepository {
  int submits = 0;
  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    if (submits > 0) return super.queryCancellationEligibility();
    reads++;
    return const CancellationEligibility(
      allowed: true,
      message: '账号满足注销条件',
      mobile: '',
      requiresSmsCode: false,
    );
  }

  @override
  Future<void> requestCancellation({required String smsCode}) async {
    submits++;
  }
}

class _ConfirmationOnlyRepository extends MockAccountComplianceRepository {
  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    return const CancellationEligibility(
      allowed: true,
      message: '账号满足注销条件',
      mobile: '',
      requiresSmsCode: false,
    );
  }
}

class _CoolingOffRepository extends MockAccountComplianceRepository {
  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    return const CancellationEligibility(
      allowed: false,
      canCancel: true,
      status: 'COOLING_OFF',
      message: '账户已进入注销冷静期',
      mobile: '',
      requiresSmsCode: false,
      coolingEndsAt: '2026-08-29T08:00:00Z',
    );
  }
}

class _BlockedRepository extends MockAccountComplianceRepository {
  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    return const CancellationEligibility(
      allowed: false,
      status: 'BLOCKED',
      canCancel: false,
      message: '当前暂不满足注销条件',
      mobile: '',
      requiresSmsCode: false,
    );
  }
}

class _FailingCancellationRepository extends _CoolingOffRepository {
  final Completer<CancellationEligibility> _completer =
      Completer<CancellationEligibility>();
  int cancelCalls = 0;

  @override
  Future<CancellationEligibility> cancelDeletion() {
    cancelCalls++;
    return _completer.future;
  }

  void release() {
    _completer.completeError(
      const ApiException(
        kind: ApiFailureKind.conflict,
        httpStatus: 409,
        message: '注销状态已变化，请刷新后重试',
      ),
    );
  }
}
