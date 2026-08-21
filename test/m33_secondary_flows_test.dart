import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<void> pumpScoped(
    WidgetTester tester,
    AppDependencies dependencies,
    Widget page, {
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(theme: AppTheme.social(), home: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('discovery detail submits a real local comment', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );
    await pumpScoped(
      tester,
      dependencies,
      const DynamicDetailPage(postId: 'dynamic-1001'),
    );

    expect(find.byType(SocialPageScaffold), findsOneWidget);
    await tester.enterText(find.byType(TextField), '这个房间的氛围很舒服');
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();

    expect(find.text('这个房间的氛围很舒服'), findsOneWidget);
    expect(find.text('评论 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public profile opens a functional private conversation', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );
    await pumpScoped(
      tester,
      dependencies,
      const PublicProfilePage(userId: 20001),
      textScale: 1.3,
    );

    await tester.tap(find.text('私聊'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivateChatPage), findsOneWidget);
    expect(find.text('今晚房间的话题很温柔。'), findsOneWidget);

    final Finder composer = find.byType(TextField);
    await tester.enterText(composer, '稍后房间见');
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();

    expect(find.text('稍后房间见'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary social pages keep forbidden commerce absent', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );
    await pumpScoped(tester, dependencies, const NotificationCenterPage());

    expect(find.text('系统通知'), findsOneWidget);
    expect(find.text('互动通知'), findsOneWidget);
    expect(find.textContaining('会员'), findsNothing);
    expect(find.textContaining('礼物背包'), findsNothing);
    expect(find.byType(SocialSkySurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
