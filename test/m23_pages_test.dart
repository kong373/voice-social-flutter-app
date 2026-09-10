import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  Future<void> pumpScoped(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(theme: AppTheme.dark(), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('DS-004 feed reaches DS-005, DS-006, DS-007, and community hub', (
    WidgetTester tester,
  ) async {
    await pumpScoped(tester, const DiscoveryFeedPage());
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('下班后终于松下来。今晚想听听大家最近遇到的温柔小事。'), findsOneWidget);
    expect(find.byTooltip('发布动态'), findsOneWidget);
    expect(find.byTooltip('排行榜'), findsOneWidget);
    expect(find.byTooltip('社交经营'), findsOneWidget);

    await tester.tap(find.text('下班后终于松下来。今晚想听听大家最近遇到的温柔小事。'));
    await tester.pumpAndSettle();
    expect(find.text('动态详情'), findsOneWidget);
  });

  testWidgets(
    'DS-006 validates text content and keeps image capability explicit',
    (WidgetTester tester) async {
      await pumpScoped(tester, const PublishDynamicPage());
      expect(find.text('发布动态'), findsWidgets);
      expect(find.textContaining('当前环境仅可发布文字'), findsOneWidget);

      final Finder publishButton = find.widgetWithText(FilledButton, '发布动态');
      expect(publishButton, findsOneWidget);
      await tester.ensureVisible(publishButton);
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      expect(find.text('请输入动态内容或选择图片'), findsOneWidget);
    },
  );

  testWidgets('DS-007 exposes user and room ranking boards', (
    WidgetTester tester,
  ) async {
    await pumpScoped(tester, const RankingPage());
    expect(find.text('魅力榜'), findsWidgets);
    expect(find.text('晚星'), findsOneWidget);
    await tester.tap(find.text('房间榜').first);
    await tester.pumpAndSettle();
    expect(find.text('深夜温柔陪伴'), findsOneWidget);
  });

  testWidgets('SC-001 through SC-003 are reachable from community hub', (
    WidgetTester tester,
  ) async {
    await pumpScoped(tester, const CommunityHubPage());
    for (final String title in <String>['公会主页', '公会加入与主播管理', '邀请与渠道归属']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('guild page renders retained business state', (
    WidgetTester tester,
  ) async {
    await pumpScoped(tester, const GuildHomePage());
    expect(find.text('晚风陪伴社'), findsOneWidget);
  });
}
