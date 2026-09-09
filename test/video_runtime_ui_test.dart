import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  for (final String area in <String>['public-screen', 'seat-grid']) {
    testWidgets('iOS outside tap dismisses composer on $area', (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = AppDependencies.mock();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social().copyWith(platform: TargetPlatform.iOS),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-room-880217')));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('video-room-composer'));
      await tester.tap(composer);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
      final rect = tester.getRect(find.byKey(Key('video-room-$area')));
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isFalse);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('更多').hitTestable(), findsOneWidget);
      expect(find.text('成员').hitTestable(), findsOneWidget);

      await tester.tap(composer);
      await tester.pumpAndSettle();
      await tester.enterText(composer, 'outside tap regression');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
      expect(find.textContaining('outside tap regression'), findsWidgets);
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
      await tester.tap(find.byKey(const Key('room-expression-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-expression-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('room-expression-晚安')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(composer).controller!.text, '[晚安]');
      final outside = tester.getRect(find.byKey(Key('video-room-$area')));
      await tester.tapAt(outside.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('礼物').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(GiftSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final double keyboardHeight in <double>[260, 300]) {
    testWidgets(
      'SE room keeps public screen usable with $keyboardHeight keyboard',
      (WidgetTester tester) async {
        await loadGoldenFonts();
        tester.view.physicalSize = const Size(750, 1334);
        tester.view.devicePixelRatio = 2;
        tester.view.padding = const FakeViewPadding(top: 40);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        final AppDependencies dependencies = AppDependencies.mock();
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.social(fontFamily: kGoldenFontFamily),
              home: MainShell(
                dependencies: dependencies,
                onSignOut: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('live-room-880217')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('video-room-composer')));
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final Finder publicScreen = find.byKey(
          const Key('video-room-public-screen'),
        );
        expect(tester.getSize(publicScreen).height, greaterThanOrEqualTo(90));
        expect(find.byTooltip('发送').hitTestable(), findsOneWidget);
        await tester.drag(
          find.byKey(const Key('video-room-seat-grid')),
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();
        // The fixture's eighth seat is occupied by 暖光.
        expect(find.text('暖光').hitTestable(), findsOneWidget);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    await loadGoldenFonts();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          builder: _captureRoot,
          theme: AppTheme.social(fontFamily: kGoldenFontFamily),
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
    await _captureRoomEvidence(tester, 'room-390x844');
    _expectNineSeatLayout(tester);

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
    await _captureRoomEvidence(tester, 'minimized-390x844');
    await tester.tap(find.byKey(const Key('minimized-room-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    _expectNineSeatLayout(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              builder: _captureRoot,
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
      await _captureRoomEvidence(tester, 'room-360x764-text130');
      _expectNineSeatLayout(tester);
      expect(
        MediaQuery.textScalerOf(tester.element(publicScreen)).scale(10),
        13,
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
      final sheet = find.byType(GiftSheet);
      final targets = tester.widget<GiftSheet>(sheet).targets;
      expect(targets.length, greaterThanOrEqualTo(2));
      final before =
          (await dependencies.commerceRepository.fetchWalletSummary())
              .giftCoins!
              .tenths;
      await tester.tap(
        find.descendant(of: sheet, matching: find.text(targets[1].name)),
      );
      await tester.pump();
      final sendGift = find
          .descendant(
            of: sheet,
            matching: find.textContaining(RegExp(r'^赠送(?: ·)? 20$')),
          )
          .hitTestable();
      expect(sendGift, findsOneWidget);
      await tester.tap(sendGift);
      await tester.pumpAndSettle();
      // S09: separate confirmed receipts, not one synthetic batch success.
      final plan = dependencies.giftSendCoordinator.plan!;
      expect(plan.succeeded, 2);
      expect(plan.terminal, isTrue);
      expect(plan.entries.map((e) => e.command.receiverUserId), [
        targets[0].userId,
        targets[1].userId,
      ]);
      expect(
        plan.entries.map((e) => e.command.requestId).toSet(),
        hasLength(2),
      );
      expect(plan.entries.map((e) => e.transferId).toSet(), hasLength(2));
      expect(plan.entries.every((e) => e.command.quantity == 1), isTrue);
      expect(find.text('已送出（已确认）'), findsNWidgets(2));
      final feedback = find.byKey(const Key('gift-success-feedback'));
      expect(
        find.descendant(of: feedback, matching: find.text('玫瑰 ×1 已送达')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: feedback,
          matching: find.text('送给 ${targets[0].name}'),
        ),
        findsOneWidget,
      );
      expect(find.text('晚星 送出星河心意'), findsNothing);
      expect(
        sheet,
        findsOneWidget,
      ); // The result page stays until explicit dismissal.
      await _captureRoomEvidence(tester, 'gift-results-360x764-text130');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.descendant(
          of: feedback,
          matching: find.text('送给 ${targets[1].name}'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(feedback, findsNothing);
      expect(
        (await dependencies.commerceRepository.fetchWalletSummary())
            .giftCoins!
            .tenths,
        before - BigInt.from(200),
      );
      await tester.ensureVisible(find.text('完成查看，重新选择礼物'));
      await tester.pumpAndSettle();
      expect(find.text('完成查看，重新选择礼物').hitTestable(), findsOneWidget);
      await _captureRoomEvidence(
        tester,
        'gift-results-complete-360x764-text130',
      );
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GiftSheet), findsNothing);

      expect(find.byTooltip('更多'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('更多').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('互动玩法'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      await _captureRoomEvidence(tester, 'tools-360x764-text130');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('互动玩法'), findsNothing);
      _expectNineSeatLayout(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

const _captureKey = Key('nine-seat-layout-evidence');

void _expectNineSeatLayout(WidgetTester tester) {
  // Q06-01 + S02 frozen layout: one visibly distinct centered seat ABOVE the
  // other eight seats in two four-column rows. Never bless an observed height.
  final stage = find.byKey(const Key('video-room-seat-grid'));
  final stageRect = tester.getRect(stage);
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          RegExp(r'^\d+ 号麦，').hasMatch(widget.properties.label ?? ''),
    ),
    findsNWidgets(9),
  );
  Finder seat(int n) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label?.startsWith('$n 号麦，') ?? false),
  );
  final rects = <Rect>[];
  for (var n = 1; n <= 9; n++) {
    expect(seat(n), findsOneWidget);
    // The seat cell includes transparent spacing below its avatar at 1.3x;
    // check the painted avatar, not the empty center of that layout box.
    expect(
      find
          .descendant(of: seat(n), matching: find.byType(AnimatedContainer))
          .first
          .hitTestable(),
      findsOneWidget,
      reason: 'seat $n avatar must remain visible',
    );
    final rect = tester.getRect(seat(n));
    expect(rect.top, greaterThanOrEqualTo(stageRect.top));
    expect(rect.bottom, lessThanOrEqualTo(stageRect.bottom));
    rects.add(rect);
  }
  expect(rects[0].center.dx, closeTo(stageRect.center.dx, 0.01));
  expect(rects[0].bottom, lessThanOrEqualTo(rects[1].top));
  for (var column = 0; column < 4; column++) {
    expect(rects[1 + column].top, closeTo(rects[1].top, 0.01));
    expect(rects[5 + column].top, closeTo(rects[5].top, 0.01));
    expect(rects[1 + column].left, closeTo(rects[5 + column].left, 0.01));
    expect(rects[1 + column].bottom, lessThan(rects[5 + column].top));
    if (column < 3) {
      expect(rects[1 + column].right, lessThan(rects[2 + column].left));
      expect(rects[5 + column].right, lessThan(rects[6 + column].left));
    }
  }
  final special = tester.widget<AnimatedContainer>(
    find
        .descendant(of: seat(1), matching: find.byType(AnimatedContainer))
        .first,
  );
  final ordinary = tester.widget<AnimatedContainer>(
    find
        .descendant(of: seat(2), matching: find.byType(AnimatedContainer))
        .first,
  );
  expect(
    special.constraints!.maxWidth,
    greaterThan(ordinary.constraints!.maxWidth),
  );
  expect(
    ((special.decoration! as BoxDecoration).border! as Border).top.color,
    RoomColors.gold,
  );
  expect(find.textContaining('1 号特殊麦 · '), findsOneWidget);

  final screen = find.byKey(const Key('video-room-public-screen'));
  final screenRect = tester.getRect(screen);
  final layout = find.ancestor(
    of: stage,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Column &&
          widget.children.any(
            (child) => child is SizedBox && child.child is CustomScrollView,
          ),
    ),
  );
  expect(layout, findsOneWidget);
  // Conserve the shared layout budget: seat viewport + public screen + its
  // existing four-pixel bottom padding. Width preserves ten-pixel gutters.
  expect(screenRect.top, closeTo(stageRect.bottom, 0.01));
  expect(screenRect.width, closeTo(stageRect.width - 20, 0.01));
  expect(
    screenRect.height + stageRect.height + 4,
    closeTo(tester.getSize(layout).height, 0.01),
  );
  expect(
    screenRect.bottom,
    lessThanOrEqualTo(
      tester.getRect(find.byKey(const Key('video-room-composer'))).top,
    ),
  );
  expect(find.textContaining('欢迎进入房间，请友善交流。').hitTestable(), findsOneWidget);
  // Both approved nine-seat fixture viewports now use the existing <420
  // responsive branch. The compact stage must remain IN the scrolling feed.
  expect(screenRect.height, lessThan(420));
  final compact = find.byKey(const Key('video-room-mood-stage-compact'));
  expect(compact, findsOneWidget);
  expect(find.byKey(const Key('video-room-mood-stage-standard')), findsNothing);
  expect(
    find.ancestor(of: compact, matching: find.byType(Scrollable)),
    findsOneWidget,
  );
  expect(find.text('礼物').hitTestable(), findsOneWidget);
  expect(find.text('成员').hitTestable(), findsOneWidget);
  expect(find.byTooltip('更多').hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Widget _captureRoot(BuildContext context, Widget? child) =>
    RepaintBoundary(key: _captureKey, child: child!);

Future<void> _captureRoomEvidence(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('ROOM_LAYOUT_EVIDENCE_DIR');
  if (directory.isEmpty) return;
  final context = tester.element(find.byKey(_captureKey));
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
