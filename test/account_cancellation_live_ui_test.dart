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

void main() {
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
