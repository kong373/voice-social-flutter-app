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
  testWidgets(
    'account initial 403/409/422/500 failures render retry instead of a spinner',
    (WidgetTester tester) async {
      const List<int> statuses = <int>[403, 409, 422, 500];
      final List<Widget Function()> pages = <Widget Function()>[
        () => const AccountRestrictionPage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
        () => const AccountAppealPage(account: 'user-1'),
        () => const AccountCancellationPage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
        () => const VersionUpgradePage(currentVersion: 1, platformType: 1),
        () => const YouthModePage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
        () => const RealNamePage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
        () => const DeviceSessionsPage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
        () => const SystemPermissionCenterPage(
          account: 'user-1',
          currentVersion: 1,
          platformType: 1,
        ),
      ];

      for (final int status in statuses) {
        for (final Widget Function() page in pages) {
          final _FailingAccountRepository repository =
              _FailingAccountRepository(status);
          final AppDependencies dependencies =
              AppDependencies.forTestEnvironment(
                environment: AppEnvironment.mock(),
                accountComplianceRepository: repository,
              );
          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(theme: AppTheme.dark(), home: page()),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('HTTP $status'), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        }
      }
    },
  );

  testWidgets(
    'account cancellation mutation surfaces recoverable 403/409/422/500 errors',
    (WidgetTester tester) async {
      for (final int status in <int>[403, 409, 422, 500]) {
        final _FailingCancellationRepository repository =
            _FailingCancellationRepository(status);
        final AppDependencies dependencies = AppDependencies.forTestEnvironment(
          environment: AppEnvironment.mock(),
          accountComplianceRepository: repository,
        );
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              key: ValueKey<int>(status),
              theme: AppTheme.dark(),
              home: AccountCancellationPage(
                key: ValueKey<int>(status),
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
        expect(find.text('HTTP $status'), findsOneWidget);
      }
    },
  );
}

class _FailingAccountRepository extends MockAccountComplianceRepository {
  _FailingAccountRepository(this.status);

  final int status;

  ApiException get _failure => ApiException(
    kind: switch (status) {
      403 => ApiFailureKind.forbidden,
      409 => ApiFailureKind.conflict,
      422 => ApiFailureKind.validation,
      _ => ApiFailureKind.server,
    },
    httpStatus: status,
    message: 'HTTP $status',
  );

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) => Future<AccountComplianceSnapshot>.error(_failure);

  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) => Future<AppealCase>.error(_failure);

  @override
  Future<CancellationEligibility> queryCancellationEligibility() =>
      Future<CancellationEligibility>.error(_failure);

  @override
  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  }) => Future<VersionUpdateInfo>.error(_failure);
}

class _FailingCancellationRepository extends MockAccountComplianceRepository {
  _FailingCancellationRepository(this.status);

  final int status;

  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    return const CancellationEligibility(
      allowed: true,
      message: '账号满足注销条件',
      mobile: '',
      requiresSmsCode: false,
    );
  }

  @override
  Future<void> requestCancellation({required String smsCode}) {
    return Future<void>.error(
      ApiException(
        kind: switch (status) {
          403 => ApiFailureKind.forbidden,
          409 => ApiFailureKind.conflict,
          422 => ApiFailureKind.validation,
          _ => ApiFailureKind.server,
        },
        httpStatus: status,
        message: 'HTTP $status',
      ),
    );
  }
}
