import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets('My rereads the profile after unfollowing the last relation', (
    tester,
  ) async {
    final (dependencies, reads) = await _showMy(tester);
    _expectFollowing('1');
    await _openRelations(tester);
    await tester.tap(find.text('南风'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicProfilePage), findsOneWidget);
    final unfollow = find.widgetWithText(FilledButton, '取消关注');
    await tester.ensureVisible(unfollow);
    await tester.tap(unfollow);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('当前没有符合条件的用户'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reads.requests, hasLength(2));
    // Returning does not guess a decrement while the authoritative read waits.
    _expectFollowing('1');
    final current = await dependencies.socialRepository.fetchMyProfile();
    expect(current.followingCount, 0);
    reads.requests[1].complete(current);
    await tester.pumpAndSettle();
    _expectFollowing('0');

    await _openRelations(tester);
    expect(find.text('当前没有符合条件的用户'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reads.requests, hasLength(3));
    reads.requests[2].complete(current);
    await tester.pumpAndSettle();
    _expectFollowing('0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('older relation-return profile cannot replace the latest count', (
    tester,
  ) async {
    final (dependencies, reads) = await _showMy(tester);
    await _returnFromRelations(tester);
    expect(reads.requests, hasLength(2));
    final older = await dependencies.socialRepository.fetchMyProfile();
    await dependencies.socialRepository.setFollowing(
      userId: 20002,
      following: false,
    );
    await _returnFromRelations(tester);
    expect(reads.requests, hasLength(3));
    reads.requests[2].complete(
      await dependencies.socialRepository.fetchMyProfile(),
    );
    await tester.pumpAndSettle();
    _expectFollowing('0');
    reads.requests[1].complete(older);
    await tester.pumpAndSettle();
    _expectFollowing('0');
    expect(tester.takeException(), isNull);
  });

  for (final lateError in [false, true]) {
    testWidgets(
      'relation-return ${lateError ? "error" : "response"} is ignored after identity ABA',
      (tester) async {
        final (dependencies, reads) = await _showMy(tester);
        await _returnFromRelations(tester);
        expect(reads.requests, hasLength(2));
        final old = await dependencies.socialRepository.fetchMyProfile();
        await dependencies.sessionManager.save(_session(20003));
        await dependencies.sessionManager.save(_session(10001));
        if (lateError) {
          reads.requests[1].completeError(StateError('STALE-PROFILE'));
        } else {
          reads.requests[1].complete(old.copyWith(followingCount: 99));
        }
        await tester.pumpAndSettle();
        _expectFollowing('1');
        expect(find.text('99'), findsNothing);
        expect(find.textContaining('STALE-PROFILE'), findsNothing);

        // A fresh return remains usable after the obsolete response is ignored.
        await dependencies.socialRepository.setFollowing(
          userId: 20002,
          following: false,
        );
        await _returnFromRelations(tester);
        expect(reads.requests, hasLength(3));
        reads.requests[2].complete(
          await dependencies.socialRepository.fetchMyProfile(),
        );
        await tester.pumpAndSettle();
        _expectFollowing('0');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<(AppDependencies, _ProfileReads)> _showMy(WidgetTester tester) async {
  final dependencies = AppDependencies.mock();
  final reads = _ProfileReads();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    dependencies.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await dependencies.sessionManager.save(_session(10001));
  await dependencies.socialRepository.setFollowing(
    userId: 20001,
    following: false,
  );
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.social(),
        home: Scaffold(
          body: VideoRuntimeAccountPage(
            dependencies: dependencies,
            profileRepository: reads,
            onOpenRoom: (_) {},
            onSignOut: () async {},
          ),
        ),
      ),
    ),
  );
  expect(reads.requests, hasLength(1));
  reads.requests.single.complete(
    await dependencies.socialRepository.fetchMyProfile(),
  );
  await tester.pumpAndSettle();
  return (dependencies, reads);
}

Future<void> _openRelations(WidgetTester tester) async {
  final entry = find.text('关注与粉丝');
  await tester.scrollUntilVisible(
    entry,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(RelationsPage), findsOneWidget);
}

Future<void> _returnFromRelations(WidgetTester tester) async {
  await _openRelations(tester);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void _expectFollowing(String value) {
  final stat = find
      .ancestor(of: find.text('关注'), matching: find.byType(Column))
      .first;
  expect(find.descendant(of: stat, matching: find.text(value)), findsOneWidget);
}

AuthSession _session(int id) => AuthSession(
  accessToken: 'widget-test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: id,
  mobile: '',
  roles: 'USER',
);

class _ProfileReads extends MockSocialRepository {
  final requests = <Completer<SocialProfile>>[];

  @override
  Future<SocialProfile> fetchMyProfile() {
    final request = Completer<SocialProfile>();
    requests.add(request);
    return request.future;
  }
}
