import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  for (final double width in <double>[375, 402]) {
    testWidgets('related dynamic comment heading is readable at $width', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 874);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: DynamicDetailPage(
            postId: 'dynamic-1002',
            currentUserId: 10001,
            repository: MockDynamicRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(DynamicDetailPage))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      final Finder heading = find.text('评论 1');
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: heading, matching: find.byType(RichText)),
      );
      final Color foreground = paragraph.text.style!.color!;
      // The heading sits directly on the social page, outside the white card.
      final double contrast = _contrast(foreground, SocialColors.page);
      expect(
        contrast,
        greaterThanOrEqualTo(4.5),
        reason: '评论 1 computed color $foreground: $contrast:1',
      );
      expect(foreground, SocialColors.textPrimary);
      expect(paragraph.didExceedMaxLines, isFalse);
      final Rect bounds = tester.getRect(heading);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(width));
    });
    for (final String label in <String>['动态收到评论', '9月7日']) {
      testWidgets('$label is readable under inherited dark theme at $width', (
        WidgetTester tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 874);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: AppDependencies.forTestEnvironment(
              environment: AppEnvironment.mock(),
              mockNow: DateTime(2026, 9, 9),
              messageRepository: _NotificationRepository(),
            ),
            child: MaterialApp(
              // Match the ordinary app root; a social theme here masks the bug.
              theme: AppTheme.dark(),
              home: const NotificationDetailPage(notificationId: 'comment'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(
            tester.element(find.byType(NotificationDetailPage)),
          ).brightness,
          Brightness.dark,
        );
        expect(find.text('m4-ios-0907-a 评论了你的动态'), findsNWidgets(2));
        expect(find.text('查看相关内容'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final Finder text = find.text(label);
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        final Color foreground = paragraph.text.style!.color!;
        final DecoratedBox card = tester.widget<DecoratedBox>(
          find.ancestor(of: text, matching: find.byType(DecoratedBox)).first,
        );
        final Color cardColor = (card.decoration as BoxDecoration).color!;
        final Color background = Color.alphaBlend(cardColor, SocialColors.page);
        final double contrast = _contrast(foreground, background);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason:
              '$label computed color $foreground on $background: $contrast:1',
        );
        expect(
          foreground,
          label == '动态收到评论'
              ? SocialColors.textPrimary
              : SocialColors.textSecondary,
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final Rect bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
      });
    }
  }
}

double _contrast(Color foreground, Color background) {
  final double foregroundLuminance = Color.alphaBlend(
    foreground,
    background,
  ).computeLuminance();
  final double backgroundLuminance = background.computeLuminance();
  return foregroundLuminance > backgroundLuminance
      ? (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05)
      : (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
}

class _NotificationRepository extends MockMessageRepository {
  @override
  Future<AppNotification> fetchNotification(String notificationId) async {
    return AppNotification(
      id: notificationId,
      category: NotificationCategory.interaction,
      title: '动态收到评论',
      summary: 'm4-ios-0907-a 评论了你的动态',
      details: 'm4-ios-0907-a 评论了你的动态',
      createdAt: DateTime(2026, 9, 7),
      unread: true,
      targetType: NotificationTargetType.dynamicPost,
      targetId: 'post',
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {}
}
