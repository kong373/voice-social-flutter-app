import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_pages.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<AppDependencies> mountMine(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    Future<void> Function()? onSignOut,
    void Function(AppDependencies)? configure,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = AppDependencies.mock();
    configure?.call(dependencies);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    });
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.room(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: MainShell(
            dependencies: dependencies,
            onSignOut: onSignOut ?? () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last.hitTestable());
    await tester.pumpAndSettle();
    return dependencies;
  }

  Finder mineScroll() => find.descendant(
    of: find.byKey(const Key('video-runtime-account')),
    matching: find.byType(Scrollable),
  );

  Future<void> showTool(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      150,
      scrollable: mineScroll().first,
    );
    await tester.pumpAndSettle();
  }

  void expectOnlyRoot(WidgetTester tester) {
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(VideoRuntimeAccountPage), findsOneWidget);
    expect(
      find.byType(PersonalCenterPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const Key('video-runtime-account')), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(const Key('open-personal-center')), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(PersonalCenterPage))).canPop(),
      isFalse,
    );
    expect(find.text('首页').hitTestable(), findsOneWidget);
    expect(find.text('我的').last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets('mine tab is the sole personal-center root above the dock', (
    tester,
  ) async {
    await mountMine(tester);
    expectOnlyRoot(tester);
    expect(find.text('个性装扮陈列'), findsOneWidget);
  });

  testWidgets('profile shortcut opens editor and pageBack returns to root', (
    tester,
  ) async {
    await mountMine(tester);
    await tester.tap(find.text('资料').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(EditProfilePage), findsOneWidget);
    expect(
      find.byType(PersonalCenterPage, skipOffstage: false),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EditProfilePage), findsNothing);
    expectOnlyRoot(tester);
  });

  testWidgets('top account action opens compliance hub directly', (
    tester,
  ) async {
    await mountMine(tester);
    await tester.tap(find.byTooltip('账号与安全').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(AccountComplianceHubPage), findsOneWidget);
    expect(
      find.byType(PersonalCenterPage, skipOffstage: false),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expectOnlyRoot(tester);
  });

  testWidgets('notification tool remains reachable and opens its center', (
    tester,
  ) async {
    await mountMine(tester);
    await showTool(tester, '通知中心');
    await tester.tap(find.text('通知中心').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(NotificationCenterPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PersonalCenterPage), findsOneWidget);
    expect(find.text('首页').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wallet shortcut lands in CommerceHub with its ordinary-role gate',
    (tester) async {
      await mountMine(
        tester,
        configure: (dependencies) {
          (dependencies.commerceRepository as MockCommerceRepository)
                  .incomeRole =
              IncomeRole.ordinary;
        },
      );
      expect(find.text('钱包'), findsOneWidget);
      await tester.tap(find.text('钱包').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(CommerceHubPage), findsOneWidget);
      expect(find.text('钱包与商城'), findsOneWidget);
      expect(find.text('主播收益'), findsNothing);
      expect(find.text('历史提现记录'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expectOnlyRoot(tester);
    },
  );

  testWidgets('mine has one saved-room entry and no fabricated recent room', (
    tester,
  ) async {
    await mountMine(tester);
    expect(find.text('我的房间'), findsOneWidget);
    expect(find.text('收藏房间'), findsOneWidget);
    expect(find.text('最近进房'), findsNothing);
    expect(find.text('我的收藏'), findsNothing);
    expect(find.text('继续上次的听房时光'), findsNothing);
    await showTool(tester, '收藏房间');
    await tester.tap(find.text('收藏房间').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(SavedRoomsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expectOnlyRoot(tester);
  });

  testWidgets(
    'all eight tools scroll above dock and final tool remains tappable at 360x640 text 1.3',
    (tester) async {
      var signOutCalls = 0;
      await mountMine(
        tester,
        size: const Size(360, 640),
        textScale: 1.3,
        onSignOut: () async {
          signOutCalls += 1;
        },
      );
      for (final label in <String>[
        '编辑个人资料',
        '关注与粉丝',
        '访客记录',
        '通知中心',
        '隐私与黑名单',
        '帮助与客服',
        '账号安全',
        '退出登录',
      ]) {
        await showTool(tester, label);
        expect(find.text(label), findsOneWidget);
      }

      final lastTool = find.text('退出登录');
      final shortcut = find
          .ancestor(of: lastTool, matching: find.byType(InkWell))
          .first;
      final shellScaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byType(MainShell),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      final dock = find.byWidget(shellScaffold.bottomNavigationBar!);
      for (
        var attempt = 0;
        attempt < 10 &&
            tester.getRect(shortcut).bottom >= tester.getRect(dock).top;
        attempt += 1
      ) {
        await tester.drag(mineScroll().first, const Offset(0, -100));
        await tester.pumpAndSettle();
      }
      expect(lastTool.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(shortcut).bottom,
        lessThan(tester.getRect(dock).top),
      );
      await tester.tap(lastTool);
      await tester.pumpAndSettle();
      expect(signOutCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
