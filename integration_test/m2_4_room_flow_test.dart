import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'room entry, fixed eight seats, gift sheet, leave, and ten re-entries work',
    (WidgetTester tester) async {
      await launchAndAuthenticate(tester);

      for (int iteration = 1; iteration <= 10; iteration += 1) {
        await tester.tap(find.text('进入房间').first);
        await pumpUntilVisible(tester, find.text('实时公屏'));

        const List<String> expectedSeatLabels = <String>[
          '1 号麦，房主 · 鹿屿',
          '2 号麦，南风',
          '3 号麦，晚星',
          '4 号麦，空闲',
          '5 号麦，已锁定',
          '6 号麦，空闲',
          '7 号麦，空麦且闭麦',
          '8 号麦，空闲',
        ];
        expect(
          find.bySemanticsLabel(RegExp(r'^\d+ 号麦，')),
          findsNWidgets(8),
          reason: 'RM-004 must expose exactly eight numbered mic seats',
        );
        for (final String label in expectedSeatLabels) {
          expect(
            find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
            findsOneWidget,
            reason: 'RM-004 must expose the fixed seat state: $label',
          );
        }
        expect(
          find.bySemanticsLabel(RegExp(r'^9 号麦，')),
          findsNothing,
          reason: 'the owner must occupy seat 1, not an extra ninth seat',
        );

        if (iteration == 1) {
          await captureQaScreenshot(
            tester,
            binding,
            'FLOW-004-room-entry-fixed-eight-seats-$qaAvdId',
          );
          expect(find.text('礼物'), findsOneWidget);
          await tester.tap(find.text('礼物'));
          await tester.pumpAndSettle();
          expect(find.text('送礼物'), findsOneWidget);
          expect(find.text('普通礼物'), findsOneWidget);
          expectNoRetiredFeatureText(reason: 'room gift sheet');
          await tester.tap(find.text('赠送 · 10'));
          await tester.pumpAndSettle();
          expect(find.text('礼物已送出'), findsOneWidget);
          await captureQaScreenshot(
            tester,
            binding,
            'FLOW-005-room-gift-bottom-sheet-$qaAvdId',
          );
        }

        await tester.tap(find.byTooltip('离开房间'));
        await tester.pumpAndSettle();
        expect(find.text('离开房间？'), findsOneWidget);
        await tester.tap(find.text('确认离开'));
        await pumpUntilVisible(tester, find.text('此刻适合你的房间'));
        expect(find.text('实时公屏'), findsNothing);
        if (iteration == 10) {
          await captureQaScreenshot(
            tester,
            binding,
            'FLOW-015-ten-room-reentries-returned-home-$qaAvdId',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'FLOW-005 ordinary room entry completes the authoritative room core flow',
    (WidgetTester tester) async {
      await launchAndAuthenticate(tester);
      await tester.tap(find.text('进入房间').first);
      await pumpUntilVisible(tester, find.text('实时公屏'));
      expect(find.textContaining('房间号 880217'), findsOneWidget);

      expect(find.text('申请上麦'), findsOneWidget);
      await tester.tap(find.text('申请上麦'));
      await pumpUntilVisible(tester, find.text('选择麦位'));
      await tester.pumpAndSettle();
      final Finder seatFour = find.widgetWithText(FilledButton, '4 号麦');
      expect(seatFour, findsOneWidget);
      await tester.ensureVisible(seatFour);
      await tester.tap(seatFour);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'^4 号麦，我')),
        findsOneWidget,
        reason:
            'selecting an available seat must produce an authoritative on-mic '
            'state instead of stopping at a pending request',
      );
      expect(find.text('闭麦'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-up-mic-seat-4-$qaAvdId',
      );

      await tester.tap(find.text('闭麦'));
      await tester.pumpAndSettle();
      expect(find.text('开麦'), findsOneWidget);
      expect(find.text('闭麦'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-microphone-closed-$qaAvdId',
      );

      await tester.tap(find.text('开麦'));
      await tester.pumpAndSettle();
      expect(find.text('闭麦'), findsOneWidget);
      expect(find.text('开麦'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-microphone-open-$qaAvdId',
      );

      const String publicMessage = 'FLOW-005 房间公屏权威消息';
      final Finder composer = find.widgetWithText(TextField, '说点什么…');
      expect(composer, findsOneWidget);
      await tester.enterText(composer, publicMessage);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(publicMessage, findRichText: true),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-public-screen-message-$qaAvdId',
      );

      await tester.tap(find.text('成员'));
      await pumpUntilVisible(tester, find.text('在线成员与听众席'));
      await tester.pumpAndSettle();
      final Finder exactMember = find.widgetWithText(ListTile, '南风');
      expect(exactMember, findsOneWidget);
      expect(
        find.descendant(
          of: exactMember,
          matching: find.textContaining('2 号麦 · 已闭麦'),
        ),
        findsOneWidget,
      );
      await tester.tap(exactMember);
      await tester.pumpAndSettle();
      expect(find.text('查看主页'), findsOneWidget);
      await tester.tap(find.text('查看主页'));
      await pumpUntilVisible(tester, find.text('个人主页'));
      await tester.pumpAndSettle();
      expect(find.text('南风'), findsOneWidget);
      expect(find.text('下班后只聊轻松的事。'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-online-member-20002-profile-$qaAvdId',
      );
      await tester.tap(find.byType(BackButton).last);
      await pumpUntilVisible(tester, find.text('在线成员与听众席'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton).last);
      await pumpUntilVisible(tester, find.text('实时公屏'));

      await tester.tap(find.text('礼物'));
      await pumpUntilVisible(tester, find.text('送礼物'));
      await tester.pumpAndSettle();
      expect(find.text('实时公屏'), findsOneWidget);
      expect(find.textContaining('房间号 880217'), findsOneWidget);
      expect(find.text('礼物目录与赠送面板'), findsNothing);
      final Finder targetSelector = find.byType(
        DropdownButtonFormField<GiftTarget>,
      );
      expect(targetSelector, findsOneWidget);
      await tester.tap(targetSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('晚星').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: targetSelector, matching: find.text('晚星')),
        findsOneWidget,
      );

      await tester.tap(find.text('陪伴'));
      await tester.pumpAndSettle();
      expect(find.text('玫瑰'), findsOneWidget);
      await tester.tap(find.text('玫瑰'));
      await tester.tap(find.widgetWithText(ChoiceChip, '×10'));
      await tester.pumpAndSettle();
      expect(find.text('赠送 · 100'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-gift-target-item-quantity-$qaAvdId',
      );

      await tester.tap(find.text('赠送 · 100'));
      await tester.pumpAndSettle();
      expect(find.text('送礼物'), findsNothing);
      expect(
        find.textContaining('我送给 晚星 玫瑰 ×10', findRichText: true),
        findsOneWidget,
        reason: 'the room public screen must show the accepted gift receipt',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-gift-public-screen-result-$qaAvdId',
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('礼物'));
      await pumpUntilVisible(tester, find.text('送礼物'));
      await tester.pumpAndSettle();
      expect(find.text('余额 1100'), findsOneWidget);
      expect(find.text('实时公屏'), findsOneWidget);
      expect(find.textContaining('房间号 880217'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-gift-authoritative-balance-$qaAvdId',
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('实时公屏'));

      await tester.tap(find.byTooltip('离开房间'));
      await pumpUntilVisible(tester, find.text('离开房间？'));
      expect(find.text('离开后将同时下麦，并结束本次房间会话。'), findsOneWidget);
      await tester.tap(find.text('确认离开'));
      await pumpUntilVisible(tester, find.text('此刻适合你的房间'));
      expect(find.text('实时公屏'), findsNothing);
      expect(find.text('正在离开房间…'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-005-left-room-home-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'FLOW-006 home search opens a valid room number directly',
    (WidgetTester tester) async {
      await launchAndAuthenticate(tester);
      await _openGlobalSearch(tester);
      await _openDirectRoom(tester, '880217');

      expect(find.text('实时公屏'), findsOneWidget);
      expect(find.textContaining('房间号 880217'), findsOneWidget);
      expect(find.text('房间直达'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-006-search-valid-room-direct-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'FLOW-006 invalid room recovery accepts a corrected valid room number',
    (WidgetTester tester) async {
      await launchAndAuthenticate(tester);
      await _openGlobalSearch(tester);
      await _openUnavailableDirectRoom(tester, '999999');

      expect(find.text('房间直达'), findsOneWidget);
      expect(find.text('目标房间不可用'), findsOneWidget);
      expect(find.text('目标房间不存在、已失效或暂不可进入'), findsOneWidget);
      expect(find.text('重新校验'), findsOneWidget);
      expect(find.text('返回上一页'), findsOneWidget);

      final Finder recoveryInput = find.widgetWithText(TextField, '房间号或完整链接');
      expect(recoveryInput, findsOneWidget);
      await tester.enterText(recoveryInput, '660318');
      await tester.pump();
      expect(
        tester.widget<TextField>(recoveryInput).controller?.text,
        '660318',
      );
      final Finder retry = find.widgetWithText(FilledButton, '重新校验');
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      await pumpUntilVisible(tester, find.text('实时公屏'));
      expect(find.textContaining('房间号 660318'), findsOneWidget);

      await _leaveRoom(tester, find.text('搜索说明'));
      await _openUnavailableDirectRoom(tester, '999999');
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-006-search-invalid-room-recovery-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'FLOW-007 owner mutes and unmutes the exact room member',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _openOwnerRoomManagement(tester);

      final Finder target = _managementMemberTile('晚星');
      expect(target, findsOneWidget);
      expect(
        find.descendant(of: target, matching: find.text('3 号麦')),
        findsOneWidget,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('禁言用户'), findsOneWidget);
      await tester.tap(find.text('禁言用户'));
      await tester.pumpAndSettle();

      final Finder mutedTarget = _managementMemberTile('晚星');
      expect(
        find.descendant(of: mutedTarget, matching: find.text('已禁言')),
        findsOneWidget,
      );
      final mutedMembers = await dependencies.roomOperationsRepository
          .fetchMutedUsers('880217');
      expect(
        mutedMembers.map((member) => member.userId),
        contains(20003),
        reason: 'the authoritative muted-user list must contain 晚星 only by ID',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-member-muted-$qaAvdId',
      );

      await tester.tap(mutedTarget);
      await tester.pumpAndSettle();
      expect(find.text('解除禁言'), findsOneWidget);
      await tester.tap(find.text('解除禁言'));
      await tester.pumpAndSettle();

      final Finder unmutedTarget = _managementMemberTile('晚星');
      expect(
        find.descendant(of: unmutedTarget, matching: find.text('已禁言')),
        findsNothing,
      );
      final unmutedMembers = await dependencies.roomOperationsRepository
          .fetchMutedUsers('880217');
      expect(
        unmutedMembers.map((member) => member.userId),
        isNot(contains(20003)),
        reason: 'the authoritative muted-user list must remove 晚星 by ID',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-member-unmuted-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'FLOW-007 owner takes the exact member off mic with authoritative UI',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _openOwnerRoomManagement(tester);

      final Finder target = _managementMemberTile('晚星');
      expect(
        find.descendant(of: target, matching: find.text('3 号麦')),
        findsOneWidget,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('移下麦位'), findsOneWidget);
      await tester.tap(find.text('移下麦位'));
      await pumpUntilVisible(tester, find.text('移下麦位？'));
      expect(find.text('晚星 将停止发言并回到听众席。'), findsOneWidget);
      await tester.tap(find.text('确认移下麦'));
      await tester.pumpAndSettle();

      final authoritativePage = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: '880217', page: 1, pageSize: 100);
      final authoritativeTarget = authoritativePage.items.singleWhere(
        (member) => member.userId == 20003,
      );
      expect(authoritativeTarget.isOnMic, isFalse);
      expect(authoritativeTarget.seatNumber, isNull);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-member-taken-off-mic-$qaAvdId',
      );

      final Finder refreshedTarget = _managementMemberTile('晚星');
      expect(
        find.descendant(of: refreshedTarget, matching: find.text('听众席')),
        findsOneWidget,
        reason:
            'after the authoritative move, the management UI must not restore '
            '晚星 to stale seat 3',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'FLOW-007 owner removes the exact listener from the room',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _openOwnerRoomManagement(tester);

      final Finder target = _managementMemberTile('阿岚');
      expect(
        find.descendant(of: target, matching: find.text('听众席')),
        findsOneWidget,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('移出房间'), findsOneWidget);
      await tester.tap(find.text('移出房间'));
      await pumpUntilVisible(tester, find.text('移出房间？'));
      expect(find.text('阿岚 将立即离开当前房间。本次操作不会自动加入永久黑名单。'), findsOneWidget);
      await tester.tap(find.text('确认移出'));
      await tester.pumpAndSettle();

      final authoritativePage = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: '880217', page: 1, pageSize: 100);
      expect(
        authoritativePage.items.map((member) => member.userId),
        isNot(contains(20005)),
      );
      expect(_managementMemberTile('阿岚'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-member-removed-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'FLOW-007 owner locks and unlocks the exact mic seat',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _openOwnerRoomManagement(tester);
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();

      Finder target = _managementSeatCard(4);
      expect(
        find.descendant(of: target, matching: find.text('空闲')),
        findsOneWidget,
      );
      final Finder lockAction = find.descendant(
        of: target,
        matching: find.widgetWithText(ActionChip, '锁定'),
      );
      expect(lockAction, findsOneWidget);
      await tester.tap(lockAction);
      await tester.pumpAndSettle();

      target = _managementSeatCard(4);
      expect(
        find.descendant(of: target, matching: find.text('已锁定')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: target,
          matching: find.widgetWithText(ActionChip, '解锁'),
        ),
        findsOneWidget,
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-seat-4-locked-$qaAvdId',
      );

      final Finder unlockAction = find.descendant(
        of: target,
        matching: find.widgetWithText(ActionChip, '解锁'),
      );
      await tester.tap(unlockAction);
      await tester.pumpAndSettle();
      target = _managementSeatCard(4);
      expect(
        find.descendant(of: target, matching: find.text('空闲')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: target,
          matching: find.widgetWithText(ActionChip, '锁定'),
        ),
        findsOneWidget,
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-seat-4-unlocked-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'FLOW-007 owner saves a room announcement and sees authoritative UI',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _openOwnerRoom(tester);

      const String initialTopic = '今晚话题：最近让你觉得被治愈的一件小事';
      expect(find.text(initialTopic), findsOneWidget);
      await tester.tap(find.text(initialTopic));
      await pumpUntilVisible(tester, find.text('编辑房间公告'));

      const String updatedTitle = 'FLOW-007 房主公告';
      const String updatedContent = 'FLOW-007 公告内容已由权威状态刷新';
      await tester.enterText(
        find.widgetWithText(TextFormField, '公告标题'),
        updatedTitle,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '公告内容'),
        updatedContent,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final Finder saveAnnouncement = find.text('保存公告');
      await tester.ensureVisible(saveAnnouncement);
      await tester.pumpAndSettle();
      await tester.tap(saveAnnouncement);
      await pumpUntilVisible(tester, find.text('实时公屏'));
      await tester.pumpAndSettle();

      final authoritativeTopic = await dependencies.roomOperationsRepository
          .fetchTopic('880217');
      expect(authoritativeTopic.title, updatedTitle);
      expect(authoritativeTopic.content, updatedContent);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-007-announcement-authoritative-$qaAvdId',
      );
      expect(
        find.text(updatedContent),
        findsOneWidget,
        reason:
            'after a successful authoritative save, the room topic card must '
            'render the saved announcement content',
      );
      expect(find.text(initialTopic), findsNothing);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'FLOW-008 owner ordinary entry completes a server-authoritative room PK',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      seedQaRoomEntryRole(dependencies, RoomRole.owner);

      await tester.tap(find.text('进入房间').first);
      await pumpUntilVisible(tester, find.text('实时公屏'));
      expect(find.textContaining('房间号 880217'), findsOneWidget);

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('房间 PK'), findsOneWidget);
      await tester.tap(find.text('房间 PK'));
      await pumpUntilVisible(tester, find.text('PK 邀请与准备'));

      final Finder opponent = find.widgetWithText(ListTile, '下班后的松弛时刻');
      expect(opponent, findsOneWidget);
      await tester.ensureVisible(opponent);
      await tester.tap(opponent);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      final Finder sendInvitation = find.text('发送 PK 邀请');
      await tester.ensureVisible(sendInvitation);
      await tester.tap(sendInvitation);
      await pumpUntilVisible(tester, find.text('已邀请 下班后的松弛时刻'));
      expect(find.text('等待对方确认'), findsOneWidget);

      final Finder refreshInvitation = find.byTooltip('刷新邀请状态');
      await tester.ensureVisible(refreshInvitation);
      await tester.tap(refreshInvitation);
      await tester.pumpAndSettle();
      expect(find.text('等待对方确认'), findsOneWidget);

      await tester.tap(refreshInvitation);
      await pumpUntilVisible(tester, find.text('PK 对战与结算'));
      await tester.pumpAndSettle();
      expect(find.text('05:00'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新比分'));
      await tester.pumpAndSettle();
      expect(find.text('04:00'), findsOneWidget);
      expect(find.text('135'), findsOneWidget);
      expect(find.text('117'), findsOneWidget);

      for (int refresh = 0; refresh < 4; refresh += 1) {
        await tester.tap(find.byTooltip('刷新比分'));
        await tester.pumpAndSettle();
      }
      expect(find.text('已结束'), findsOneWidget);
      expect(find.text('本房获胜'), findsOneWidget);
      expect(find.text('825 : 705'), findsOneWidget);
      await tester.ensureVisible(find.text('本房获胜'));
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-008-room-pk-settlement-$qaAvdId',
      );

      await tester.scrollUntilVisible(
        find.text('返回房间'),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('返回房间'));
      await tester.tap(find.text('返回房间'));
      await pumpUntilVisible(tester, find.text('实时公屏'));
      await tester.pumpAndSettle();
      expect(find.text('PK 邀请与准备'), findsNothing);
      expect(find.textContaining('房间号 880217'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-008-room-pk-returned-to-room-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _openGlobalSearch(WidgetTester tester) async {
  expect(find.byType(TextField), findsOneWidget);
  final Finder searchEntry = find
      .ancestor(of: find.byType(TextField), matching: find.byType(InkWell))
      .first;
  await tester.tap(searchEntry);
  await tester.pumpAndSettle();
  expect(find.text('搜索说明'), findsOneWidget);
  expect(find.text('搜索房间、用户或房间号'), findsOneWidget);
}

Future<void> _openDirectRoom(WidgetTester tester, String roomId) async {
  await tester.enterText(find.byType(TextField).first, roomId);
  await tester.pump();
  final Finder directEntry = find.text('直达房间 $roomId');
  expect(directEntry, findsOneWidget);
  await tester.tap(directEntry);
  await pumpUntilVisible(tester, find.text('实时公屏'));
}

Future<void> _openUnavailableDirectRoom(
  WidgetTester tester,
  String roomId,
) async {
  await tester.enterText(find.byType(TextField).first, roomId);
  await tester.pump();
  final Finder directEntry = find.text('直达房间 $roomId');
  expect(directEntry, findsOneWidget);
  await tester.tap(directEntry);
  await pumpUntilVisible(tester, find.text('目标房间不可用'));
}

Future<void> _leaveRoom(WidgetTester tester, Finder destination) async {
  await tester.tap(find.byTooltip('离开房间'));
  await pumpUntilVisible(tester, find.text('离开房间？'));
  await tester.tap(find.text('确认离开'));
  await pumpUntilVisible(tester, destination);
}

Future<void> _openOwnerRoom(WidgetTester tester) async {
  await tester.tap(find.text('进入房间').first);
  await pumpUntilVisible(tester, find.text('实时公屏'));
  expect(find.textContaining('房间号 880217'), findsOneWidget);
  expect(find.byTooltip('更多'), findsOneWidget);
}

Future<void> _openOwnerRoomManagement(WidgetTester tester) async {
  await _openOwnerRoom(tester);
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  expect(find.text('房间管理'), findsOneWidget);
  await tester.tap(find.text('房间管理'));
  await pumpUntilVisible(tester, find.text('成员治理'));
  await tester.pumpAndSettle();
  expect(find.text('房间管理'), findsOneWidget);
}

Finder _managementMemberTile(String name) =>
    find.widgetWithText(ListTile, name);

Finder _managementSeatCard(int seatNumber) =>
    find.ancestor(of: find.text('$seatNumber 号麦'), matching: find.byType(Card));
