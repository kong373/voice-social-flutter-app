import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/video_ui_components.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('video runtime UI pilot keeps every interaction in context',
      (WidgetTester tester) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lobby(),
          builder: (BuildContext context, Widget? child) => LobbyBackdrop(
            child: child ?? const SizedBox.shrink(),
          ),
          home: MainShell(
            dependencies: dependencies,
            onSignOut: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-01-light-social-home',
    );
    await announceQaEvidence(tester, 'M33_HOME_READY');

    await tester.ensureVisible(find.text('进入').first);
    await tester.tap(find.text('进入').first.hitTestable());
    await _waitFor(
      tester,
      () => find.byType(RoomPage).evaluate().isNotEmpty &&
          find.text('实时公屏').evaluate().isNotEmpty,
      description: 'immersive room',
    );
    expect(find.text('1 号麦'), findsWidgets);
    expect(find.text('8 号麦'), findsWidgets);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-02-dark-eight-seat-room',
    );
    await announceQaEvidence(tester, 'M33_ROOM_READY');

    final Finder composer = find.byKey(const Key('room-message-composer'));
    await tester.ensureVisible(composer);
    await tester.tap(composer);
    await tester.enterText(composer, '今晚也要好好聊天');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(RoomPage), findsOneWidget);
    expect(find.text('实时公屏'), findsOneWidget);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-03-room-keyboard-context',
    );
    await announceQaEvidence(tester, 'M33_KEYBOARD_CONTEXT_READY');
    await dismissQaImeAndWait(tester);

    final Finder giftAction = find.text('礼物').last;
    await tester.ensureVisible(giftAction);
    await tester.tap(giftAction.hitTestable());
    await _waitFor(
      tester,
      () => find.textContaining('赠送').evaluate().isNotEmpty ||
          find.textContaining('余额').evaluate().isNotEmpty,
      description: 'in-room gift sheet',
    );
    expect(find.byType(RoomPage), findsOneWidget);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-04-in-room-gift-sheet',
    );
    await announceQaEvidence(tester, 'M33_GIFT_SHEET_READY');
    Navigator.of(tester.element(find.byType(RoomPage))).pop();
    await tester.pumpAndSettle();

    final Finder moreAction = find.text('更多').last;
    await tester.ensureVisible(moreAction);
    await tester.tap(moreAction.hitTestable());
    await _waitFor(
      tester,
      () => find.byType(BottomSheet).evaluate().isNotEmpty ||
          find.byType(ModalBarrier).evaluate().isNotEmpty,
      description: 'in-room tool sheet',
    );
    expect(find.byType(RoomPage), findsOneWidget);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-05-in-room-tools',
    );
    await announceQaEvidence(tester, 'M33_TOOLS_READY');
    Navigator.of(tester.element(find.byType(RoomPage))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('最小化房间').hitTestable());
    await _waitFor(
      tester,
      () => find.byKey(const Key('minimized-room-pill')).evaluate().isNotEmpty,
      description: 'minimized room pill',
    );
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('房间仍在继续 · 点击恢复'), findsOneWidget);
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-06-minimized-room',
    );
    await announceQaEvidence(tester, 'M33_MINIMIZED_ROOM_READY');

    await tester.tap(find.byKey(const Key('minimized-room-pill')).hitTestable());
    await _waitFor(
      tester,
      () => find.byType(RoomPage).evaluate().isNotEmpty &&
          find.text('实时公屏').evaluate().isNotEmpty,
      description: 'restored room',
    );
    await captureQaScreenshot(
      tester,
      binding,
      'm33-${qaAvdId.toLowerCase()}-07-restored-room',
    );
    await announceQaEvidence(tester, 'M33_RESTORE_READY');

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['m33VideoRuntimeUi'] = <String, Object?>{
      'avd': qaAvdId,
      'rootNavigation': '首页/发现/消息/我的',
      'fixedSeatCount': 8,
      'keyboardKeepsRoomContext': true,
      'giftStaysInRoomContext': true,
      'toolsStayInRoomContext': true,
      'minimizeRestore': true,
      'providerCallsMade': false,
      'result': 'PASS',
    };
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 300; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('Timed out waiting for $description.');
}
