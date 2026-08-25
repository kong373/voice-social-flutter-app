import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  test('mock friend request state is authoritative and idempotent', () async {
    final MockSocialRepository repository = MockSocialRepository();

    final first = await repository.sendFriendRequest(
      userId: 20004,
      message: '一起聊聊',
    );
    final second = await repository.sendFriendRequest(
      userId: 20004,
      message: '重复点击不应创建第二条',
    );

    expect(first.requestId, isNotEmpty);
    expect(first.status, FriendRequestStatus.pending);
    expect(second.requestId, first.requestId);
    expect(repository.friendRequestSendCount, 1);
  });

  testWidgets('public profile sends one friend request while the CTA is busy', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    final MockSocialRepository repository =
        dependencies.socialRepository as MockSocialRepository;
    repository.friendRequestSendDelay = const Duration(milliseconds: 120);

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

    final Finder requestButton = find.text('申请好友');
    expect(requestButton, findsOneWidget);
    await tester.tap(requestButton);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('申请中…'), findsOneWidget);

    // The second tap lands while the first request is in flight.
    await tester.tap(find.text('申请中…'));
    await tester.pumpAndSettle();

    expect(repository.friendRequestSendCount, 1);
    expect(find.text('好友申请已发送'), findsOneWidget);
    expect(find.text('已发送申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
