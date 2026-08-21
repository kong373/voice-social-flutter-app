import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester, {ThemeData? outerTheme}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: outerTheme ?? AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('production message tab is the reviewed message center root', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('消息').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byType(MessageCenterPage), findsOneWidget);
    expect(find.byKey(const Key('video-runtime-messages')), findsOneWidget);
    expect(find.text('官方消息'), findsOneWidget);
    expect(find.text('系统通知'), findsOneWidget);
    expect(find.text('打招呼'), findsOneWidget);
    expect(find.text('互动消息'), findsOneWidget);
    expect(find.text('好友请求'), findsOneWidget);
    expect(find.byTooltip('搜索消息'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(MessageCenterPage))).canPop(),
      isFalse,
    );

    await tester.tap(find.text('好友请求').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byType(RelationsPage), findsOneWidget);
    expect(find.text('关注、粉丝与好友'), findsOneWidget);
  });

  testWidgets('mine root and account detail use one repository profile', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('晚星'), findsOneWidget);
    expect(find.textContaining('ID 10001'), findsOneWidget);
    expect(find.text('星河漫游者'), findsNothing);

    await tester.tap(find.text('晚星').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('晚星'), findsOneWidget);
    expect(find.text('用户号 10001'), findsOneWidget);
    expect(find.text('星河漫游者'), findsNothing);
  });

  testWidgets('decoration remains readable through the real shell navigator', (
    WidgetTester tester,
  ) async {
    // App routes are pushed above MainShell's local social Theme. A dark outer
    // theme reproduces the actual nested-route contrast regression.
    await pumpShell(tester, outerTheme: AppTheme.room());

    await tester.tap(find.text('我的').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('装扮').first.hitTestable());
    await tester.pumpAndSettle();

    final Text title = tester.widget<Text>(find.text('装扮中心'));
    final Text summary = tester.widget<Text>(find.text('个性装扮'));
    final Text subtitle = tester.widget<Text>(find.text('头像框、进场效果与声波样式'));

    expect(title.style?.color, SocialColors.textPrimary);
    expect(summary.style?.color, SocialColors.textPrimary);
    expect(subtitle.style?.color, SocialColors.textSecondary);
    expect(tester.takeException(), isNull);
  });
}
