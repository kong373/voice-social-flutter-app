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
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';

void main() {
  Future<void> mount(WidgetTester tester, _SessionsRepository repo) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: AppDependencies.forTestEnvironment(
          environment: AppEnvironment.mock(),
          accountComplianceRepository: repo,
        ),
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const DeviceSessionsPage(
            account: 'user',
            currentVersion: 6,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same installation retains separate logins and one current badge',
    (tester) async {
      final repo = _SessionsRepository();
      await mount(tester, repo);
      expect(find.text('同一台测试设备'), findsNWidgets(2));
      expect(find.text('当前登录'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);
      expect(find.text('2 个登录会话'), findsOneWidget);
      expect(repo.revokeIds, isEmpty);
    },
  );

  testWidgets(
    'removal is single-flight and re-reads server list before success',
    (tester) async {
      final repo = _SessionsRepository()..pending = Completer<void>();
      await mount(tester, repo);
      await tester.tap(find.text('移除'));
      await tester.pump();
      expect(repo.revokeIds, ['other-login']);
      expect(find.text('移除中…'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '移除中…'),
      );
      expect(button.onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '刷新登录会话',
              ),
            )
            .onPressed,
        isNull,
      );
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(find.text('1 个登录会话'), findsOneWidget);
      expect(find.text('移除'), findsNothing);
      expect(find.text('当前登录'), findsOneWidget);
    },
  );

  testWidgets(
    'post-removal read failure exposes retry and disables stale actions',
    (tester) async {
      final repo = _SessionsRepository()..failReload = true;
      await mount(tester, repo);
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(find.text('会话列表读取失败'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '移除'))
            .onPressed,
        isNull,
      );
      expect(repo.revokeIds, ['other-login']);
      repo.failReload = false;
      await tester.tap(find.byTooltip('刷新登录会话'));
      await tester.pumpAndSettle();
      expect(find.text('会话列表读取失败'), findsNothing);
      expect(find.text('1 个登录会话'), findsOneWidget);
      expect(repo.revokeIds, ['other-login']);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SessionsRepository extends MockAccountComplianceRepository {
  final List<String> revokeIds = [];
  Completer<void>? pending;
  int reads = 0;
  bool failReload = false;
  bool removed = false;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async {
    reads++;
    if (reads > 1 && failReload) {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: '会话列表读取失败',
      );
    }
    final snapshot = await super.fetchSnapshot(
      account: account,
      currentVersion: currentVersion,
      platformType: platformType,
    );
    return snapshot.copyWith(
      sessions: [
        DeviceSession(
          id: 'current-login',
          deviceName: '同一台测试设备',
          location: '',
          lastActiveAt: DateTime.utc(2026, 9, 9),
          isCurrent: true,
          canRevoke: false,
        ),
        if (!removed)
          DeviceSession(
            id: 'other-login',
            deviceName: '同一台测试设备',
            location: '',
            lastActiveAt: DateTime.utc(2026, 9, 8),
            isCurrent: false,
            canRevoke: true,
          ),
      ],
    );
  }

  @override
  Future<void> revokeDeviceSession(String sessionId) async {
    revokeIds.add(sessionId);
    if (pending != null) await pending!.future;
    removed = true;
  }
}
