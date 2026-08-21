import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

import 'support/golden_font_gate.dart';

void main() {
  late GoldenFileComparator originalGoldenComparator;

  setUpAll(() async {
    originalGoldenComparator = goldenFileComparator;
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.file(
        '${Directory.current.path}/test/video_runtime_visual_golden_test.dart',
      ),
      precisionTolerance: 0.0002,
    );
    await loadGoldenFonts();
  });

  tearDownAll(() {
    goldenFileComparator = originalGoldenComparator;
  });

  testWidgets('M3.3 video-runtime visual states at 390x844', (
    WidgetTester tester,
  ) async {
    _configureGoldenView(tester);

    const Key captureKey = Key('video-runtime-golden-boundary');
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );
    await tester.pumpWidget(_goldenApp(captureKey, dependencies));
    await tester.pumpAndSettle();
    await _precacheGoldenAssets(tester, captureKey);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_home_390x844.png'),
    );

    await tester.tap(find.byKey(const Key('live-room-880217')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_room_390x844.png'),
    );

    await tester.tap(find.byKey(const Key('room-expression-button')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_expression_390x844.png'),
    );
    Navigator.of(
      tester.element(find.byKey(const Key('room-expression-sheet'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(GiftSheet), findsOneWidget);
    expect(find.text('背包'), findsNothing);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_gift_390x844.png'),
    );
  });

  testWidgets('M3.3 root tabs and pure decoration states at 390x844', (
    WidgetTester tester,
  ) async {
    _configureGoldenView(tester);

    const Key captureKey = Key('video-runtime-account-golden-boundary');
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );
    await tester.pumpWidget(_goldenApp(captureKey, dependencies));
    await tester.pumpAndSettle();
    await _precacheGoldenAssets(tester, captureKey);
    await tester.pumpAndSettle();

    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_discovery_390x844.png'),
    );

    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_messages_390x844.png'),
    );

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('个性装扮'), findsOneWidget);
    expect(find.textContaining('会员'), findsNothing);
    expect(find.textContaining('背包'), findsNothing);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_account_390x844.png'),
    );

    await tester.tap(find.text('装扮'));
    await tester.pumpAndSettle();
    expect(find.byType(DecorationPage), findsOneWidget);
    expect(find.text('装扮中心'), findsOneWidget);
    expect(find.textContaining('会员'), findsNothing);
    expect(find.textContaining('背包'), findsNothing);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/m3_3_decoration_390x844.png'),
    );
  });

  testWidgets('M3.3 secondary flows at 390x844', (WidgetTester tester) async {
    _configureGoldenView(tester);

    const Key captureKey = Key('video-runtime-secondary-golden-boundary');
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 20, 18, 12),
    );

    Future<void> capture(Widget page, String golden) async {
      await tester.pumpWidget(_goldenPageApp(captureKey, dependencies, page));
      await tester.pumpAndSettle();
      await _precacheGoldenAssets(tester, captureKey);
      await tester.pumpAndSettle();
      await expectLater(find.byKey(captureKey), matchesGoldenFile(golden));
    }

    await capture(
      const DynamicDetailPage(postId: 'dynamic-1001'),
      'goldens/m3_3_dynamic_detail_390x844.png',
    );
    await capture(
      PrivateChatPage(
        conversation: ConversationSummary(
          id: 'conversation-20001',
          kind: ConversationKind.privateChat,
          title: '晚星',
          lastMessage: '今晚房间的话题很温柔。',
          updatedAt: DateTime(2026, 8, 20, 18, 4),
          unreadCount: 2,
          targetUserId: 20001,
        ),
      ),
      'goldens/m3_3_private_chat_390x844.png',
    );
    await capture(
      const NotificationCenterPage(),
      'goldens/m3_3_notifications_390x844.png',
    );
    await capture(
      const PublicProfilePage(userId: 20001),
      'goldens/m3_3_public_profile_390x844.png',
    );
    await capture(
      const RoomMembersPage(
        roomId: '9527',
        currentUserId: 10001,
        currentRole: RoomRole.owner,
        seats: <MicSeat>[
          MicSeat(
            number: 1,
            backendIndex: 1,
            state: MicSeatState.occupied,
            userId: 20001,
            userName: '房主 · 鹿屿',
            userRole: RoomRole.owner,
          ),
          MicSeat(
            number: 2,
            backendIndex: 2,
            state: MicSeatState.occupiedMuted,
            userId: 20002,
            userName: '南风',
            userRole: RoomRole.speaker,
          ),
        ],
      ),
      'goldens/m3_3_room_members_390x844.png',
    );
    await capture(
      const RoomManagementPage(
        roomId: '9527',
        currentUserId: 10001,
        currentRole: RoomRole.owner,
        seats: <MicSeat>[
          MicSeat(
            number: 1,
            backendIndex: 1,
            state: MicSeatState.occupied,
            userId: 20001,
            userName: '房主 · 鹿屿',
            userRole: RoomRole.owner,
          ),
          MicSeat(
            number: 2,
            backendIndex: 2,
            state: MicSeatState.occupiedMuted,
            userId: 20002,
            userName: '南风',
            userRole: RoomRole.speaker,
          ),
        ],
      ),
      'goldens/m3_3_room_management_390x844.png',
    );
  });

  test(
    'M3.3 video-runtime golden font gate fails closed when the baseline font is absent',
    () async {
      final Directory emptyFontDirectory = await Directory.systemTemp
          .createTemp('m33-empty-video-golden-fonts-');
      addTearDown(() => emptyFontDirectory.delete(recursive: true));

      await expectLater(
        loadGoldenFonts(goldenFontDirectory: emptyFontDirectory),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('M3.3 golden font gate failed'),
          ),
        ),
      );
    },
  );
}

void _configureGoldenView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _goldenApp(Key captureKey, AppDependencies dependencies) {
  return RepaintBoundary(
    key: captureKey,
    child: AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.social(fontFamily: kGoldenFontFamily),
        home: MainShell(dependencies: dependencies, onSignOut: () async {}),
      ),
    ),
  );
}

Widget _goldenPageApp(
  Key captureKey,
  AppDependencies dependencies,
  Widget page,
) {
  return RepaintBoundary(
    key: captureKey,
    child: AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.social(fontFamily: kGoldenFontFamily),
        home: page,
      ),
    ),
  );
}

Future<void> _precacheGoldenAssets(WidgetTester tester, Key captureKey) async {
  final BuildContext assetContext = tester.element(find.byKey(captureKey));
  const List<String> assetPaths = <String>[
    'assets/runtime/social-sky.png',
    'assets/runtime/room-cosmos.png',
    'assets/runtime/room-cover-ruby.png',
    'assets/runtime/room-cover-island.png',
    'assets/runtime/room-cover-festival.png',
    'assets/runtime/room-cover-moon.png',
    'assets/runtime/avatar-rose.png',
    'assets/runtime/avatar-night.png',
    'assets/runtime/avatar-copper.png',
    'assets/runtime/avatar-silver.png',
    'assets/runtime/gift-blossom.png',
    'assets/runtime/gift-ticket.png',
    'assets/runtime/gift-whale.png',
    'assets/runtime/gift-celebration-banner.png',
  ];
  await tester.runAsync(
    () => Future.wait<void>(
      assetPaths.map(
        (String path) => precacheImage(AssetImage(path), assetContext),
      ),
    ),
  );
}

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         precisionTolerance >= 0 && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final bool passed =
        result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
