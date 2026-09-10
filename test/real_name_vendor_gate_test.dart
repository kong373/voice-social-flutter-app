import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';

void main() {
  testWidgets(
    'R02 identity evidence has its own prompt and permits resubmission without age flag',
    (tester) async {
      final dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.mock,
          apiBaseUrl: 'https://example.invalid',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
        ),
        accountComplianceRepository: _IdentityEvidenceRepository(),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: const MaterialApp(
            home: RealNamePage(
              account: 'fixture',
              currentVersion: 6,
              platformType: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('请补充实名认证资料后绑定收款账户'), findsOneWidget);
      expect(find.textContaining('原实名记录缺少年龄资料'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('提交认证'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'live real-name page exposes first-party manual review and submits',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://example.invalid',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
          deploymentEnvironment: DeploymentEnvironment.production,
        ),
        accountComplianceRepository: MockAccountComplianceRepository(),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: const MaterialApp(
            home: RealNamePage(
              account: '13800138000',
              currentVersion: 6,
              platformType: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('FIRST_PARTY_MANUAL_REVIEW'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('提交认证'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '张三');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '42010619960820123X',
      );
      await tester.tap(find.text('提交认证'));
      await tester.pumpAndSettle();
      expect(find.text('已认证'), findsOneWidget);
    },
  );
}

class _IdentityEvidenceRepository extends MockAccountComplianceRepository {
  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async =>
      (await super.fetchSnapshot(
        account: account,
        expectedUserId: expectedUserId,
        currentVersion: currentVersion,
        platformType: platformType,
      )).copyWith(
        verificationState: VerificationState.verified,
        needsAgeResubmission: false,
        needsIdentityResubmission: true,
      );
}
