import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';

void main() {
  testWidgets(
    'permission center renders unavailable and does not invoke a grant action',
    (WidgetTester tester) async {
      final _UnavailablePermissionRepository repository =
          _UnavailablePermissionRepository();
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        accountComplianceRepository: repository,
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const SystemPermissionCenterPage(
              account: 'user-1',
              currentVersion: 6,
              platformType: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('适配器未接入'), findsNWidgets(3));
      expect(find.textContaining('不会把未知状态伪装成尚未请求'), findsOneWidget);
      await tester.tap(find.text('通知'));
      await tester.pumpAndSettle();
      expect(repository.permissionCalls, 0);
      expect(find.text('已允许'), findsNothing);
    },
  );

  testWidgets(
    'permanently denied permission exposes a settings recovery action',
    (WidgetTester tester) async {
      final _PermanentPermissionRepository repository =
          _PermanentPermissionRepository();
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        accountComplianceRepository: repository,
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const SystemPermissionCenterPage(
              account: 'user-1',
              currentVersion: 6,
              platformType: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已永久拒绝'), findsOneWidget);
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      expect(repository.openSettingsCalls, 1);
    },
  );
}

class _UnavailablePermissionRepository extends MockAccountComplianceRepository {
  int permissionCalls = 0;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  }) async {
    return AccountComplianceSnapshot(
      account: account,
      nickname: '用户',
      verificationState: VerificationState.unverified,
      youthModeEnabled: false,
      restriction: const AccountRestriction(
        kind: RestrictionKind.none,
        reason: '',
      ),
      cancellation: const CancellationEligibility(
        allowed: true,
        message: '可申请',
        mobile: '',
        requiresSmsCode: false,
      ),
      versionInfo: const VersionUpdateInfo(
        hasUpdate: false,
        forceUpdate: false,
        versionName: '',
        releaseNotes: '',
        packageUrl: '',
      ),
      sessions: const <DeviceSession>[],
      permissions: const <PermissionSetting>[
        PermissionSetting(
          kind: PermissionKind.microphone,
          state: PermissionState.unavailable,
          title: '麦克风',
          purpose: '语音',
          managedByPlatform: null,
        ),
        PermissionSetting(
          kind: PermissionKind.notifications,
          state: PermissionState.unavailable,
          title: '通知',
          purpose: '提醒',
          managedByPlatform: null,
        ),
        PermissionSetting(
          kind: PermissionKind.photos,
          state: PermissionState.unavailable,
          title: '照片',
          purpose: '图片',
          managedByPlatform: null,
        ),
      ],
    );
  }

  @override
  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  }) async {
    permissionCalls++;
  }
}

class _PermanentPermissionRepository extends _UnavailablePermissionRepository {
  int openSettingsCalls = 0;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  }) async {
    return AccountComplianceSnapshot(
      account: account,
      nickname: '用户',
      verificationState: VerificationState.unverified,
      youthModeEnabled: false,
      restriction: const AccountRestriction(
        kind: RestrictionKind.none,
        reason: '',
      ),
      cancellation: const CancellationEligibility(
        allowed: true,
        message: '可申请',
        mobile: '',
        requiresSmsCode: false,
      ),
      versionInfo: const VersionUpdateInfo(
        hasUpdate: false,
        forceUpdate: false,
        versionName: '',
        releaseNotes: '',
        packageUrl: '',
      ),
      sessions: const <DeviceSession>[],
      permissions: const <PermissionSetting>[
        PermissionSetting(
          kind: PermissionKind.microphone,
          state: PermissionState.permanentlyDenied,
          title: '麦克风',
          purpose: '语音',
          managedByPlatform: true,
        ),
      ],
    );
  }

  @override
  Future<void> openPermissionSettings() async {
    openSettingsCalls++;
  }
}
