import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

import 'support/golden_font_gate.dart';

void main() {
  test('video runtime uses separate light lobby and immersive room themes', () {
    expect(AppTheme.social().brightness, Brightness.light);
    expect(AppTheme.room().brightness, Brightness.dark);
    expect(
      AppTheme.social().bottomNavigationBarTheme.type,
      BottomNavigationBarType.fixed,
    );
  });

  testWidgets('home enters room, opens gift sheet and minimizes the session', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    final Finder roomCard = find.byKey(const Key('live-room-880217'));
    expect(roomCard, findsOneWidget);
    await tester.tap(roomCard);
    await tester.pumpAndSettle();

    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(find.text('礼物'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.byKey(const Key('video-room-composer')), findsOneWidget);
    expect(
      find.byKey(const Key('video-room-mood-stage-standard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('video-room-mood-stage-compact')),
      findsNothing,
    );

    expect(find.byKey(const Key('room-follow-host')), findsNothing);
    expect(find.text('关注房主'), findsNothing);
    expect(find.text('已关注'), findsNothing);
    expect(find.text('我要点歌'), findsNothing);

    await tester.tap(find.byKey(const Key('room-expression-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-expression-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('room-expression-晚安')));
    await tester.pumpAndSettle();
    final TextField composer = tester.widget<TextField>(
      find.byKey(const Key('video-room-composer')),
    );
    expect(composer.controller?.text, '[晚安]');
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(GiftSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(GiftSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('离开房间').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('收起房间'), findsOneWidget);
    await tester.tap(find.text('收起房间').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
    await tester.tap(find.byKey(const Key('minimized-room-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lobby tabs, discovery publishing and private chat are routed', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('电台').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-room-520906')), findsOneWidget);
    expect(find.byKey(const Key('live-room-880217')), findsNothing);

    await tester.tap(find.text('发现').last.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发布动态'));
    await tester.pumpAndSettle();
    expect(find.byType(PublishDynamicPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('消息').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚星').first.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(PrivateChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account recent room restores a real room route', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recent-room-880217')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light lobby remains stable at 360x800 and 1.3 text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(864, 1920);
    tester.view.devicePixelRatio = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('正在发生'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room sheets remain stable at 360x800 and 1.3 text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(864, 1920);
    tester.view.devicePixelRatio = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-room-880217')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('room-expression-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-expression-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('贴图').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-expression-星河鲸鱼')), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(
      tester.element(find.byKey(const Key('room-expression-sheet'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(GiftSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'room gift to tools remains stable at cloud-constrained 360 width and 1.3x text',
    (WidgetTester tester) async {
      await loadGoldenFonts();
      tester.view.physicalSize = const Size(900, 1910);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AppDependencies dependencies = AppDependencies.mock();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.social(fontFamily: kGoldenFontFamily),
              home: MainShell(
                dependencies: dependencies,
                onSignOut: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('live-room-880217')));
      await tester.pumpAndSettle();
      final Finder publicScreen = find.byKey(
        const Key('video-room-public-screen'),
      );
      expect(tester.getSize(publicScreen), const Size(340, 395));
      expect(
        MediaQuery.textScalerOf(tester.element(publicScreen)).scale(10),
        13,
      );
      expect(
        find.byKey(const Key('video-room-mood-stage-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('video-room-mood-stage-standard')),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('video-room-mood-stage-compact')),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final Finder composer = find.byKey(const Key('video-room-composer'));
      await tester.tap(composer.hitTestable());
      await tester.enterText(composer, '晚上好，刚刚进来听听');
      await tester.pump(const Duration(milliseconds: 400));
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('room-expression-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-expression-晚安')));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tester.tap(find.text('礼物').hitTestable());
      await tester.pumpAndSettle();
      final Finder sendGift = find.textContaining('赠送').hitTestable();
      expect(sendGift, findsWidgets);
      await tester.tap(sendGift.first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('gift-celebration-overlay')), findsOneWidget);
      for (int attempt = 0; attempt < 10; attempt += 1) {
        if (find.byType(GiftSheet).evaluate().isEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GiftSheet), findsNothing);

      expect(find.byTooltip('更多'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('更多').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('互动玩法'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('互动玩法'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
