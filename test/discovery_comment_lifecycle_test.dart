import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

void main() {
  testWidgets('discovery comment sheet opens and closes without hard errors', (
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
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('发现').last.hitTestable());
    await tester.pumpAndSettle();

    await tester.tap(find.text('18').first.hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('回复 晚星…'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '发现页评论草稿');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('回复 晚星…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamic detail releases a focused comment editor safely', (
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
          home: const DiscoveryFeedPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder firstCommentAction = find.descendant(
      of: find.byType(DynamicPostCard).first,
      matching: find.byIcon(Icons.chat_bubble_outline_rounded),
    );
    await tester.tap(firstCommentAction);
    await tester.pumpAndSettle();

    expect(find.byType(DynamicDetailPage), findsOneWidget);
    await tester.enterText(find.byType(TextField), '还没有发送的评论');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(DynamicDetailPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
