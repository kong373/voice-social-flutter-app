import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets(
    'live report page disables UUID room submissions with canonical-id copy',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://example.test',
          clientType: 'Android',
          clientInnerVersion: '1',
          oauthClientId: 'test-client',
          realtimeEndpoint: '',
        ),
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const ReportPage(
              targetType: ReportTargetType.room,
              targetId: 'room-01HX7W6M2Y7Y8D7NQ2V9A5C1KZ',
              targetName: '实时房间',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('当前第一方举报接口只接受数字房间 ID；该房间使用 UUID/public_id，暂不能提交举报。'),
        findsOneWidget,
      );
      final Finder submitButton = find.widgetWithText(FilledButton, '提交举报');
      expect(submitButton, findsOneWidget);
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);
    },
  );

  testWidgets('mock report page keeps UUID room submissions usable', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const ReportPage(
            targetType: ReportTargetType.room,
            targetId: 'room-01HX7W6M2Y7Y8D7NQ2V9A5C1KZ',
            targetName: '模拟房间',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('当前第一方举报接口只接受数字房间 ID；该房间使用 UUID/public_id，暂不能提交举报。'),
      findsNothing,
    );
    final Finder submitButton = find.widgetWithText(FilledButton, '提交举报');
    expect(submitButton, findsOneWidget);
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
  });
}
