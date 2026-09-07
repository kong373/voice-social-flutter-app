import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  testWidgets('dynamic post card renders server ISO time in local time', (
    WidgetTester tester,
  ) async {
    final DateTime createdAt = DateTime(2026, 9, 6, 10, 0, 4).toUtc();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      mockNow: DateTime(2026, 9, 6, 10, 2),
    );
    final DynamicPost post = DynamicPost(
      id: 'dynamic-time-test',
      author: const DynamicAuthor(userId: 20001, nickname: '测试用户'),
      content: '动态时间测试',
      createdAt: createdAt.toIso8601String(),
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: DynamicPostCard(
              post: post,
              onOpen: () {},
              onLike: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('10:00'), findsOneWidget);
    expect(find.text(createdAt.toIso8601String()), findsNothing);
  });
}
