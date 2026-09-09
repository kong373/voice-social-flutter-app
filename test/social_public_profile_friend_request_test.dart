import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets('public profile cannot submit removed friend requests', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    final MockSocialRepository repository =
        dependencies.socialRepository as MockSocialRepository;

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const PublicProfilePage(userId: 20004),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('申请好友'), findsNothing);
    expect(repository.supportsFriendRequestWorkflow, isFalse);
    expect(tester.takeException(), isNull);
  });
}
