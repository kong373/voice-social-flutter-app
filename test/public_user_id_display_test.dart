import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/public_user_id_label.dart';

void main() {
  testWidgets('display and copy the business user id instead of login UUID', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: VideoRuntimeAccountPage(
              dependencies: dependencies,
              profileRepository: _UuidLoginProfileRepository(),
              onOpenRoom: (_) {},
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ID 20004'), findsOneWidget);
    expect(find.textContaining(_loginUuid), findsNothing);
    await tester.tap(find.byTooltip('复制用户 ID'));
    await tester.pumpAndSettle();
    expect(copied, '20004');
    expect(find.text('用户 ID 已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable user identity cannot be copied as a real target', (
    WidgetTester tester,
  ) async {
    int clipboardWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites += 1;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PublicUserIdLabel(userId: 0))),
    );
    await tester.tap(find.text('用户 ID 暂不可用'));
    await tester.pumpAndSettle();
    expect(clipboardWrites, 0);
    expect(find.text('ID 0'), findsNothing);
  });

  testWidgets('clipboard failure offers retry and never reports success', (
    WidgetTester tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PublicUserIdLabel(userId: 20004))),
    );
    await tester.tap(find.byTooltip('复制用户 ID'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法复制用户 ID，请重试'), findsOneWidget);
    expect(find.text('用户 ID 已复制'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const String _loginUuid = 'ce32cbc5-a3f7-4560-a77f-da07c3dad228';

class _UuidLoginProfileRepository extends MockSocialRepository {
  @override
  Future<SocialProfile> fetchMyProfile() async {
    final SocialProfile original = await super.fetchPublicProfile(20004);
    return SocialProfile(
      user: original.user,
      account: _loginUuid,
      sex: original.sex,
      birthday: original.birthday,
      city: original.city,
      coverUrl: original.coverUrl,
      followingCount: original.followingCount,
      followerCount: original.followerCount,
      friendCount: original.friendCount,
      postCount: original.postCount,
      level: original.level,
    );
  }
}
