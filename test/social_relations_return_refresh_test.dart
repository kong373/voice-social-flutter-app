import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  for (final type in [
    SocialRelationList.following,
    SocialRelationList.friends,
  ]) {
    testWidgets('$type reloads after unfollow in the real public profile', (
      tester,
    ) async {
      final dependencies = AppDependencies.mock();
      addTearDown(dependencies.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final name = type == SocialRelationList.following ? '南风' : '鹿屿';
      final userId = type == SocialRelationList.following ? 20002 : 20001;
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: RelationsPage(initialType: type),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfilePage), findsOneWidget);
      final unfollow = find.widgetWithText(FilledButton, '取消关注');
      await tester.ensureVisible(unfollow);
      await tester.tap(unfollow);
      await tester.pumpAndSettle();
      expect(
        (await dependencies.socialRepository.fetchPublicProfile(
          userId,
        )).user.isFollowing,
        isFalse,
      );

      // Normal back, with no synthetic success result or manual list refresh.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RelationsPage), findsOneWidget);
      expect(find.byType(PublicProfilePage), findsNothing);
      expect(find.text(name), findsNothing);
      if (type == SocialRelationList.friends) {
        expect(find.text('当前没有符合条件的用户'), findsOneWidget);
      } else {
        expect(find.text('鹿屿'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
