import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  const AppEnvironment liveTestEnvironment = AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'https://example.invalid',
    clientType: 'Android',
    clientInnerVersion: '1',
    oauthClientId: 'public-client',
    realtimeEndpoint: 'wss://example.invalid/realtime',
    deploymentEnvironment: DeploymentEnvironment.development,
  );

  Future<AppDependencies> pumpLiveShell(
    WidgetTester tester, {
    required ThemeData outerTheme,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: liveTestEnvironment,
      messageRepository: _StoredOnlyMessageRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: outerTheme,
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return dependencies;
  }

  Future<void> pumpLiveAccountRoot(
    WidgetTester tester, {
    required ThemeData outerTheme,
    AppDependencies? scopeDependencies,
    Future<void> Function()? onSignOut,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: liveTestEnvironment,
    );
    final AppDependencies inheritedDependencies =
        scopeDependencies ?? dependencies;
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: inheritedDependencies,
        child: MaterialApp(
          theme: outerTheme,
          home: Scaffold(
            body: VideoRuntimeAccountPage(
              dependencies: dependencies,
              onOpenRoom: (_) {},
              onSignOut: onSignOut ?? () async {},
              profileRepository: _LiveProfileRepository(),
              liveReadOnlyRepository: _DeterministicLiveReadOnlyRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final ({String name, ThemeData theme}) themeCase
      in <({String name, ThemeData theme})>[
        (name: 'light', theme: AppTheme.social()),
        (name: 'dark', theme: AppTheme.room()),
      ]) {
    testWidgets(
      'live shell message root keeps real first-party message center in ${themeCase.name}',
      (WidgetTester tester) async {
        final AppDependencies dependencies = await pumpLiveShell(
          tester,
          outerTheme: themeCase.theme,
        );

        expect(dependencies.environment.isLive, isTrue);

        await tester.tap(find.text('消息').hitTestable());
        await tester.pumpAndSettle();

        expect(find.byType(MessageCenterPage), findsOneWidget);
        expect(find.byKey(const Key('video-runtime-messages')), findsOneWidget);
        expect(find.byKey(const Key('im-vendor-blocked')), findsNothing);
        expect(find.text('官方消息'), findsOneWidget);
        expect(find.text('系统通知'), findsOneWidget);
        expect(find.text('打招呼'), findsOneWidget);
        expect(find.text('互动消息'), findsOneWidget);
        expect(find.text('好友请求'), findsOneWidget);
        expect(find.textContaining('VENDOR_BLOCKED'), findsOneWidget);
      },
    );

    testWidgets(
      'live account root keeps real profile entry points in ${themeCase.name}',
      (WidgetTester tester) async {
        var signOutCalls = 0;
        await pumpLiveAccountRoot(
          tester,
          outerTheme: themeCase.theme,
          scopeDependencies: AppDependencies.mock(),
          onSignOut: () async => signOutCalls += 1,
        );

        expect(find.byType(VideoRuntimeAccountPage), findsOneWidget);
        expect(find.byKey(const Key('live-account-overview')), findsNothing);
        expect(find.text('Live旅客'), findsOneWidget);
        expect(find.text('晚星'), findsNothing);
        expect(find.text('活动中心'), findsOneWidget);
        expect(find.text('资料与设置'), findsWidgets);
        expect(find.text('通知中心'), findsOneWidget);
        expect(find.text('帮助与反馈'), findsOneWidget);
        expect(find.text('开发环境接入诊断'), findsOneWidget);
        expect(find.byKey(const Key('open-personal-center')), findsOneWidget);

        await tester.tap(find.byKey(const Key('open-personal-center')));
        await tester.pumpAndSettle();

        expect(find.byType(PersonalCenterPage), findsOneWidget);
        final Finder logout = find.text('退出登录');
        await tester.scrollUntilVisible(
          logout,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(logout.hitTestable());
        await tester.pumpAndSettle();

        expect(signOutCalls, 1);
        expect(find.byType(PersonalCenterPage), findsNothing);
        expect(find.byKey(const Key('video-runtime-account')), findsOneWidget);
      },
    );

    testWidgets(
      'live account developer diagnostics remains tappable above the bottom navigation in ${themeCase.name}',
      (WidgetTester tester) async {
        await pumpLiveAccountRoot(tester, outerTheme: themeCase.theme);

        final Finder vendorDiagnostics = find.byKey(
          const Key('open-vendor-diagnostics'),
        );
        await tester.scrollUntilVisible(
          vendorDiagnostics,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(vendorDiagnostics.hitTestable(), findsOneWidget);
        await tester.tap(find.text('开发环境接入诊断').hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(const Key('vendor-readiness-page')), findsOneWidget);
      },
    );

    testWidgets(
      'live account privacy entry opens the account compliance hub in ${themeCase.name}',
      (WidgetTester tester) async {
        await pumpLiveAccountRoot(tester, outerTheme: themeCase.theme);

        await tester.scrollUntilVisible(
          find.byKey(const Key('open-account-compliance')),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('隐私与安全').hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('账号与安全'), findsOneWidget);
      },
    );

    testWidgets(
      'live account restores the visible personal-center entry after compliance in ${themeCase.name}',
      (WidgetTester tester) async {
        await pumpLiveAccountRoot(tester, outerTheme: themeCase.theme);

        final Finder accountPage = find.byKey(
          const Key('video-runtime-account'),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('open-account-compliance')),
          240,
          scrollable: find
              .descendant(of: accountPage, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('隐私与安全').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('账号与安全'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        final Finder accountScrollable = find
            .descendant(of: accountPage, matching: find.byType(Scrollable))
            .first;
        final ScrollableState scrollable = tester.state<ScrollableState>(
          accountScrollable,
        );
        scrollable.position.jumpTo(scrollable.position.minScrollExtent);
        await tester.pumpAndSettle();

        final Finder personalCenter = find.byKey(
          const Key('open-personal-center'),
        );
        expect(personalCenter.hitTestable(), findsOneWidget);
        await tester.tap(personalCenter.hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(PersonalCenterPage), findsOneWidget);
      },
    );

    testWidgets(
      'live account root keeps safe commerce reads reachable in ${themeCase.name}',
      (WidgetTester tester) async {
        await pumpLiveAccountRoot(
          tester,
          outerTheme: themeCase.theme,
          scopeDependencies: AppDependencies.mock(),
        );

        expect(find.text('钱包'), findsOneWidget);
        expect(find.text('装扮'), findsOneWidget);
        expect(find.textContaining('正式支付渠道'), findsOneWidget);
        expect(find.textContaining('对象存储上传'), findsOneWidget);

        await tester.tap(find.text('钱包').hitTestable().first);
        await tester.pumpAndSettle();

        expect(find.byType(CommerceHubPage), findsOneWidget);
        expect(find.text('钱包与商城'), findsOneWidget);
        expect(find.text('钱包与流水'), findsOneWidget);
        expect(find.text('充值订单'), findsOneWidget);
        expect(find.textContaining('退款'), findsWidgets);
        expect(find.text('礼物'), findsOneWidget);
        expect(find.textContaining('尚在申请'), findsOneWidget);

        await tester.tap(find.text('礼物').hitTestable());
        await tester.pumpAndSettle();

        expect(find.byType(GiftCatalogPage), findsOneWidget);
        expect(find.text('礼物图鉴'), findsOneWidget);
        expect(find.text('红包'), findsNothing);
        expect(find.text('背包'), findsNothing);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.text('装扮').hitTestable().first);
        await tester.pumpAndSettle();

        expect(find.byType(DecorationPage), findsOneWidget);
        expect(find.text('装扮中心'), findsOneWidget);
        expect(find.text('个性装扮'), findsOneWidget);
        expect(find.textContaining('会员'), findsNothing);
        expect(find.textContaining('背包'), findsNothing);
      },
    );
  }
}

class _StoredOnlyMessageRepository extends MockMessageRepository {
  @override
  bool get supportsPrivateRealtime => false;
}

class _LiveProfileRepository extends MockSocialRepository {
  @override
  Future<SocialProfile> fetchMyProfile() async {
    return const SocialProfile(
      user: SocialUser(
        userId: 42001,
        name: 'Live旅客',
        signature: '真实资料来自 live 用户接口',
        avatarUrl: '',
        isFollowing: false,
        isFollower: false,
        isFriend: false,
        isBlocked: false,
        isOnline: true,
        roomId: '880217',
      ),
      account: 'live-user-42',
      sex: 1,
      birthday: '1999-04-02',
      city: '上海',
      coverUrl: '',
      followingCount: 8,
      followerCount: 16,
      friendCount: 4,
      postCount: 3,
      level: 12,
    );
  }
}

class _DeterministicLiveReadOnlyRepository extends LiveReadOnlyRepository {
  _DeterministicLiveReadOnlyRepository()
    : super(
        ApiClient(
          baseUri: Uri.parse('https://example.invalid'),
          clientType: 'Android',
          clientInnerVersion: '1',
          authorizationProvider: () => null,
          requestHeadersProvider: () => const <String, String>{},
        ),
      );

  @override
  Future<LiveReadOnlyOverview> fetchOverview() async {
    return const LiveReadOnlyOverview(
      user: LiveCurrentUser(
        userId: 42001,
        account: 'live-user-42',
        nickname: 'Live旅客',
        mobile: '138****4242',
        roles: 'USER',
        status: 'NORMAL',
      ),
      wallet: LiveWalletSnapshot(
        giftCoinBalance: 88,
        cashBalance: 12.5,
        frozenBalance: 0,
      ),
      orders: <LivePaymentOrder>[],
    );
  }
}
