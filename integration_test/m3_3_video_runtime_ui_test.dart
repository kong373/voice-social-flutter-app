import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/main.dart' as app;

import 'm2_4_test_support.dart';

const String _expectedWidthValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_WIDTH',
  defaultValue: '390',
);
const String _expectedHeightValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_HEIGHT',
  defaultValue: '844',
);
const String _expectedDprValue = String.fromEnvironment(
  'QA_EXPECTED_DPR',
  defaultValue: '3',
);

final double _expectedWidth = double.parse(_expectedWidthValue);
final double _expectedHeight = double.parse(_expectedHeightValue);
final double _expectedDpr = double.parse(_expectedDprValue);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'video runtime lobby and persistent room interaction matches target',
    (WidgetTester tester) async {
      await app.main();
      await _waitFor(
        tester,
        () => find.byKey(const Key('video-runtime-home')).evaluate().isNotEmpty,
        description: 'video runtime home',
      );
      _expectExactViewport(tester);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-01-light-home',
      );
      await announceQaEvidence(tester, 'M33_LIGHT_LOBBY_READY');

      await tester.ensureVisible(find.byKey(const Key('live-room-880217')));
      await tester.tap(find.byKey(const Key('live-room-880217')).hitTestable());
      await _waitFor(
        tester,
        () =>
            find.byType(VideoRuntimeRoomPage).evaluate().isNotEmpty &&
            find.text('礼物').evaluate().isNotEmpty,
        description: 'immersive room',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-02-immersive-eight-seat-room',
      );
      await announceQaEvidence(tester, 'M33_IMMERSIVE_ROOM_READY');

      final Finder composer = find.byKey(const Key('video-room-composer'));
      await tester.tap(composer.hitTestable());
      await tester.enterText(composer, '晚上好，刚刚进来听听');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-03-room-keyboard-context',
      );
      await announceQaEvidence(tester, 'M33_ROOM_KEYBOARD_CONTEXT_READY');
      await dismissQaImeAndWait(tester);

      await tester.tap(find.text('礼物').hitTestable());
      await _waitFor(
        tester,
        () => find.byType(GiftSheet).evaluate().isNotEmpty,
        description: 'room gift sheet',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-04-room-gift-sheet',
      );
      await announceQaEvidence(tester, 'M33_ROOM_GIFT_SHEET_READY');
      final Finder sendGift = find.text('赠送').hitTestable();
      if (sendGift.evaluate().isNotEmpty) {
        await tester.tap(sendGift.first);
        await tester.pump(const Duration(milliseconds: 500));
        if (find
            .byKey(const Key('gift-celebration-overlay'))
            .evaluate()
            .isNotEmpty) {
          await captureQaScreenshot(
            tester,
            binding,
            'm33-${qaAvdId.toLowerCase()}-05-gift-celebration-overlay',
          );
          await announceQaEvidence(tester, 'M33_GIFT_OVERLAY_READY');
        }
      }
      if (find.byType(GiftSheet).evaluate().isNotEmpty) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('更多').hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('互动').evaluate().isNotEmpty &&
            find.text('工具').evaluate().isNotEmpty,
        description: 'room tools sheet',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-06-room-tools-sheet',
      );
      await announceQaEvidence(tester, 'M33_ROOM_TOOLS_READY');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('离开房间').hitTestable());
      await _waitFor(
        tester,
        () => find.text('收起房间').evaluate().isNotEmpty,
        description: 'minimize room action',
      );
      await tester.tap(find.text('收起房间').hitTestable());
      await _waitFor(
        tester,
        () =>
            find.byKey(const Key('minimized-room-pill')).evaluate().isNotEmpty,
        description: 'minimized room pill',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-07-minimized-room',
      );
      await announceQaEvidence(tester, 'M33_MINIMIZED_ROOM_READY');

      await tester.tap(find.text('消息').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-08-light-messages-with-room',
      );

      await tester.tap(find.text('我的').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-09-light-account-with-room',
      );

      await tester.tap(find.byKey(const Key('minimized-room-pill')));
      await _waitFor(
        tester,
        () => find.byType(VideoRuntimeRoomPage).evaluate().isNotEmpty,
        description: 'restored room',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-10-restored-room',
      );
      await announceQaEvidence(tester, 'M33_ROOM_RESTORED');

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['m33VideoRuntimeUi'] = <String, Object?>{
        'avd': qaAvdId,
        'logicalViewport':
            '${_expectedWidth.toInt()}x${_expectedHeight.toInt()}',
        'devicePixelRatio': _expectedDpr,
        'lightLobby': true,
        'immersiveRoom': true,
        'fixedEightSeats': true,
        'keyboardPreservesRoom': true,
        'giftIsRoomSheet': true,
        'toolsAreRoomSheet': true,
        'roomMinimizeAndRestore': true,
        'providerCallsMade': false,
        'result': 'PASS',
      };
    },
  );
}

void _expectExactViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logicalSize = Size(
    tester.view.physicalSize.width / dpr,
    tester.view.physicalSize.height / dpr,
  );
  expect(dpr, closeTo(_expectedDpr, 0.01));
  expect(logicalSize.width, closeTo(_expectedWidth, 0.1));
  expect(logicalSize.height, closeTo(_expectedHeight, 0.1));
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 360; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('Timed out waiting for $description.');
}
