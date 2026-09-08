import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  for (final (Size size, double safeTop, double safeBottom)
      in <(Size, double, double)>[
        (const Size(375, 667), 20, 0),
        (const Size(402, 874), 62, 34),
      ]) {
    for (final bool embedded in <bool>[false, true]) {
      testWidgets(
        'message header avoids system inset ${size.width} embedded=$embedded',
        (WidgetTester tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = FakeViewPadding(
            top: safeTop,
            bottom: safeBottom,
          );
          tester.view.viewPadding = FakeViewPadding(
            top: safeTop,
            bottom: safeBottom,
          );
          addTearDown(tester.view.reset);
          final AppDependencies dependencies = AppDependencies.mock();
          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: AppTheme.social(),
                home: embedded
                    ? MainShell(
                        dependencies: dependencies,
                        onSignOut: () async {},
                      )
                    : const MessageCenterPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (embedded) {
            await tester.tap(find.text('消息').hitTestable());
            await tester.pumpAndSettle();
          }
          final Finder page = find.byType(MessageCenterPage);
          final Finder list = find.descendant(
            of: page,
            matching: find.byType(ListView),
          );
          expect(tester.getTopLeft(list).dy, safeTop);
          expect(
            tester.getTopLeft(find.byTooltip('搜索消息')).dy,
            greaterThanOrEqualTo(safeTop),
          );
          await tester.tap(find.byTooltip('搜索消息'));
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
