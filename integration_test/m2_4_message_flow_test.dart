import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

import 'm2_4_test_support.dart';

const bool _qaCriticalOnly = bool.fromEnvironment('QA_CRITICAL_ONLY');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _installLinuxSecureStorageTestStub();

  testWidgets(
    'FLOW-010 public profile relation, block, report, and list lifecycle',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);

      await tester.tap(find.text('消息').last);
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('南风'));
      await tester.tap(find.text('南风'));
      await tester.pumpAndSettle();
      expect(find.byType(PrivateChatPage), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看公开主页'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('用户号 20002'));
      expect(find.byType(PublicProfilePage), findsOneWidget);
      expect(find.text('南风'), findsOneWidget);

      // The fixture starts with user 20002 followed. Normalize it, then run
      // the requested follow -> unfollow lifecycle through the real buttons.
      expect(find.widgetWithText(FilledButton, '取消关注'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
      await tester.pumpAndSettle();
      expect(
        (await dependencies.socialRepository.fetchPublicProfile(
          20002,
        )).user.isFollowing,
        isFalse,
      );

      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pumpAndSettle();
      expect(
        (await dependencies.socialRepository.fetchPublicProfile(
          20002,
        )).user.isFollowing,
        isTrue,
      );
      expect(find.widgetWithText(FilledButton, '取消关注'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
      await tester.pumpAndSettle();
      expect(
        (await dependencies.socialRepository.fetchPublicProfile(
          20002,
        )).user.isFollowing,
        isFalse,
      );

      // Blocking is high-risk and must confirm. It also clears any relation;
      // unblocking must not silently restore the previous follow state.
      await tester.tap(find.widgetWithText(OutlinedButton, '加入黑名单'));
      await tester.pumpAndSettle();
      expect(find.text('加入黑名单？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      SocialProfile target = await dependencies.socialRepository
          .fetchPublicProfile(20002);
      expect(target.user.isBlocked, isTrue);
      expect(target.user.isFollowing, isFalse);
      expect(find.widgetWithText(OutlinedButton, '移出黑名单'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '移出黑名单'));
      await tester.pumpAndSettle();
      expect(find.text('移出黑名单？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      target = await dependencies.socialRepository.fetchPublicProfile(20002);
      expect(target.user.isBlocked, isFalse);
      expect(target.user.isFollowing, isFalse);
      expect(find.widgetWithText(OutlinedButton, '加入黑名单'), findsOneWidget);

      // Verify the precise report object before submitting through the form.
      await _scrollToAndTap(
        tester,
        find.widgetWithText(OutlinedButton, '举报用户'),
      );
      await pumpUntilVisible(tester, find.text('举报南风'));
      final ReportPage reportPage = tester.widget<ReportPage>(
        find.byType(ReportPage),
      );
      expect(reportPage.targetType, ReportTargetType.user);
      expect(reportPage.targetId, '20002');
      expect(reportPage.targetName, '南风');
      await tester.enterText(
        find.widgetWithText(TextFormField, '补充说明'),
        'FLOW-010 精确对象举报回归说明',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _scrollToAndTap(tester, find.text('提交举报'));
      expect(find.text('举报已提交'), findsOneWidget);
      expect(find.textContaining('回执编号：report-'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfilePage), findsOneWidget);

      // Return through the same route stack, then enter the normal personal
      // center relation list. The canceled follow must still be absent.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PrivateChatPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MessageCenterPage), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('个人与关系'));
      await _scrollToAndTap(tester, find.text('关注、粉丝与好友'));
      await pumpUntilVisible(tester, find.text('鹿屿'));
      expect(find.byType(RelationsPage), findsOneWidget);
      expect(find.text('南风'), findsNothing);
      expect(find.text('鹿屿'), findsOneWidget);

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-010-social-relations-$qaAvdId',
      );
    },
    skip: _qaCriticalOnly,
  );

  testWidgets(
    'FLOW-013 ordinary messaging, notification detail, unavailable target, and recovery',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);

      // Open the ordinary root message destination and prove that reading a
      // conversation clears its unread count and a real send updates both the
      // message history and the conversation summary in one repository.
      await tester.tap(find.text('消息').last);
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.byType(MessageCenterPage));
      expect(find.text('晚星'), findsOneWidget);
      expect(find.text('青禾'), findsOneWidget);
      await tester.tap(find.text('晚星'));
      await pumpUntilVisible(tester, find.byType(PrivateChatPage));
      expect(
        find.descendant(
          of: find.byType(PrivateChatPage),
          matching: find.text('今晚房间的话题很温柔。'),
        ),
        findsOneWidget,
      );

      const String sentText = 'FLOW-013 Android 模拟器私聊消息';
      final Finder messageField = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.hintText == '输入消息…',
        description: 'enabled private message field',
      );
      await tester.enterText(messageField, sentText);
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final Finder sendMessage = find.byTooltip('发送消息');
      expect(sendMessage, findsOneWidget);
      await tester.ensureVisible(sendMessage);
      await tester.tap(sendMessage);
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text(sentText));
      final List<ConversationSummary> conversationsAfterSend =
          await dependencies.messageRepository.fetchConversations();
      final ConversationSummary sentConversation = conversationsAfterSend
          .singleWhere(
            (ConversationSummary item) => item.targetUserId == 20001,
          );
      expect(sentConversation.lastMessage, sentText);
      expect(sentConversation.unreadCount, 0);
      final List<ChatMessage> persistedMessages = await dependencies
          .messageRepository
          .fetchPrivateMessages(sentConversation);
      expect(
        persistedMessages.where(
          (ChatMessage message) =>
              message.isMine && message.content == sentText,
        ),
        hasLength(1),
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-013-01-private-send-$qaAvdId',
      );

      await _popPage(tester, find.byType(PrivateChatPage));
      expect(find.byType(MessageCenterPage), findsOneWidget);
      expect(find.text(sentText), findsOneWidget);

      // An unavailable conversation must route to an explicit recovery page,
      // never a blank chat or a fabricated send surface.
      await tester.tap(find.text('青禾'));
      await pumpUntilVisible(
        tester,
        find.byType(NotificationTargetUnavailablePage),
      );
      expect(find.text('会话不可用'), findsWidgets);
      expect(find.text('用户已注销或当前关系不可用'), findsOneWidget);
      await tester.tap(find.text('返回消息'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageCenterPage), findsOneWidget);

      // Read a concrete system notification and verify the authoritative read
      // marker before returning to the category list.
      await tester.tap(find.byTooltip('系统与互动通知'));
      await pumpUntilVisible(tester, find.byType(NotificationCenterPage));
      expect(find.text('账号安全提醒'), findsOneWidget);
      await tester.tap(find.text('账号安全提醒'));
      await pumpUntilVisible(tester, find.byType(NotificationDetailPage));
      const String systemSummary = '你的账号在新设备上完成登录。';
      const String systemDetails =
          '设备：Android 测试设备\n时间：今天 09:20\n如非本人操作，请前往账号与安全检查登录设备。';
      await pumpUntilVisible(tester, find.text(systemSummary));
      await pumpUntilVisible(tester, find.text(systemDetails));
      expect(find.text('通知详情'), findsOneWidget);
      expect(find.text(systemSummary), findsOneWidget);
      expect(find.text(systemDetails), findsOneWidget);
      final AppNotification readNotification = await dependencies
          .messageRepository
          .fetchNotification('notification-system-1');
      expect(readNotification.unread, isFalse);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-013-02-system-notification-detail-$qaAvdId',
      );
      await _popPage(tester, find.byType(NotificationDetailPage));

      // Preserve a deleted-target notification, show its details, and route
      // the action to the explicit unavailable reason.
      await tester.tap(find.text('互动通知'));
      await pumpUntilVisible(tester, find.text('动态收到一条评论'));
      await tester.tap(find.text('动态收到一条评论'));
      await pumpUntilVisible(tester, find.byType(NotificationDetailPage));
      const String unavailableSummary = '目标动态已被作者删除。';
      const String unavailableDetails = '该通知保留，但目标内容已经不可用。';
      await pumpUntilVisible(tester, find.text(unavailableSummary));
      await pumpUntilVisible(tester, find.text(unavailableDetails));
      expect(find.text(unavailableSummary), findsOneWidget);
      expect(find.text(unavailableDetails), findsOneWidget);
      await tester.tap(find.text('查看不可用原因'));
      await pumpUntilVisible(
        tester,
        find.byType(NotificationTargetUnavailablePage),
      );
      expect(find.text('动态已删除或不可见'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-013-03-unavailable-notification-target-$qaAvdId',
      );
      await tester.tap(find.text('返回消息'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDetailPage), findsOneWidget);
      await _popPage(tester, find.byType(NotificationDetailPage));
      expect(find.byType(NotificationCenterPage), findsOneWidget);

      // Clear interaction notifications only after the required confirmation.
      await tester.tap(find.byTooltip('清空互动通知'));
      await tester.pumpAndSettle();
      expect(find.text('清空互动通知？'), findsOneWidget);
      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();
      expect(find.text('暂无互动通知'), findsOneWidget);
      expect(
        await dependencies.messageRepository.fetchNotifications(
          NotificationCategory.interaction,
        ),
        isEmpty,
      );

      // Return to the message root and use its ordinary recovery entry. The
      // permission state and the last server notification sync are both
      // repository-backed; recovery explicitly refuses to invent history.
      await _popPage(tester, find.byType(NotificationCenterPage));
      expect(find.byType(MessageCenterPage), findsOneWidget);
      await tester.tap(find.byTooltip('通知权限与消息恢复'));
      await pumpUntilVisible(
        tester,
        find.byType(MessagePermissionRecoveryPage),
      );
      expect(find.textContaining('不会编造断线期间私聊'), findsOneWidget);
      expect(find.text('尚未请求'), findsOneWidget);
      await _scrollToAndTap(tester, find.text('请求系统通知权限'));
      expect(find.text('已允许'), findsOneWidget);
      MessageRecoverySnapshot recovery = await dependencies.messageRepository
          .fetchRecoverySnapshot();
      expect(
        recovery.notificationPermission,
        NativeNotificationPermissionState.allowed,
      );
      expect(recovery.lastNotificationSyncAt, isNotNull);
      await _scrollToAndTap(tester, find.text('刷新恢复状态'));
      recovery = await dependencies.messageRepository.fetchRecoverySnapshot();
      expect(recovery.privateRealtimeAvailable, isTrue);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-013-04-permission-recovery-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _scrollToAndTap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _popPage(WidgetTester tester, Finder page) async {
  expect(page, findsOneWidget);
  Navigator.of(tester.element(page)).pop();
  await tester.pumpAndSettle();
}

void _installLinuxSecureStorageTestStub() {
  if (!Platform.isLinux) {
    return;
  }
  final Map<String, String> values = <String, String>{};
  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        final Map<Object?, Object?> arguments =
            (call.arguments as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};
        final String? key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return key == null ? null : values[key];
          case 'write':
            if (key != null) {
              values[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              values.remove(key);
            }
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(values);
          case 'containsKey':
            return key != null && values.containsKey(key);
        }
        throw MissingPluginException('Unsupported secure storage test call');
      });
}
