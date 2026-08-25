import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  testWidgets('an older profile refresh cannot replace the newest response', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    final _ControlledSocialRepository repository =
        _ControlledSocialRepository();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: VideoRuntimeAccountPage(
              dependencies: dependencies,
              profileRepository: repository,
              onOpenRoom: (_) {},
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );

    expect(repository.requests, hasLength(1));
    repository.complete(0, _profile(name: '初始用户'));
    await tester.pumpAndSettle();
    expect(find.text('初始用户'), findsOneWidget);

    await tester.tap(find.text('初始用户').hitTestable());
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('用户号 10001'))).pop();
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));

    await tester.tap(find.text('初始用户').hitTestable());
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('用户号 10001'))).pop();
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(3));

    repository.complete(2, _profile(name: '最新用户'));
    await tester.pumpAndSettle();
    expect(find.text('最新用户'), findsOneWidget);

    repository.complete(1, _profile(name: '过期用户'));
    await tester.pumpAndSettle();

    expect(find.text('最新用户'), findsOneWidget);
    expect(find.text('过期用户'), findsNothing);

    await tester.tap(find.text('最新用户').hitTestable());
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('用户号 10001'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('最新用户').hitTestable());
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('用户号 10001'))).pop();
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(5));

    repository.complete(4, _profile(name: '稳定用户'));
    await tester.pumpAndSettle();
    repository.fail(3, StateError('过期请求失败'));
    await tester.pumpAndSettle();

    expect(find.text('稳定用户'), findsOneWidget);
    expect(find.text('个人资料加载失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ControlledSocialRepository extends MockSocialRepository {
  final List<Completer<SocialProfile>> requests = <Completer<SocialProfile>>[];

  @override
  Future<SocialProfile> fetchMyProfile() {
    final Completer<SocialProfile> completer = Completer<SocialProfile>();
    requests.add(completer);
    return completer.future;
  }

  void complete(int index, SocialProfile profile) {
    requests[index].complete(profile);
  }

  void fail(int index, Object error) {
    requests[index].completeError(error);
  }
}

SocialProfile _profile({required String name}) {
  return SocialProfile(
    user: SocialUser(
      userId: 10001,
      name: name,
      signature: '同一账户的资料更新',
      avatarUrl: '',
      isFollowing: false,
      isFollower: false,
      isFriend: false,
      isBlocked: false,
      isOnline: true,
    ),
    account: '10001',
    sex: 2,
    birthday: '2000-06-18',
    city: '武汉',
    coverUrl: '',
    followingCount: 2,
    followerCount: 3,
    friendCount: 1,
    postCount: 4,
    level: 8,
  );
}
