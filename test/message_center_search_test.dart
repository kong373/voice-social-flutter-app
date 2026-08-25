import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets('message search filters conversations and opens the real chat', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const MessageCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索消息'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '晚星');
    await tester.pumpAndSettle();

    final Finder conversationTitle = find.byWidgetPredicate(
      (Widget widget) => widget is Text && widget.data == '晚星',
      description: 'conversation title 晚星',
    );
    expect(conversationTitle, findsOneWidget);
    await tester.tap(conversationTitle);
    await tester.pumpAndSettle();

    expect(find.byType(PrivateChatPage), findsOneWidget);
  });

  testWidgets('friend request shortcut opens the dedicated requests page', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const MessageCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('好友请求').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byType(FriendRequestsPage), findsOneWidget);
    expect(find.text('关注、粉丝与好友'), findsNothing);
  });
}
