import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  test('private messages remain scoped to the selected conversation', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final List<ConversationSummary> conversations = await repository
        .fetchConversations();
    final ConversationSummary first = conversations.firstWhere(
      (ConversationSummary item) => item.available,
    );
    final ConversationSummary second = conversations.firstWhere(
      (ConversationSummary item) => item.available && item.id != first.id,
    );
    final int secondCount = (await repository.fetchPrivateMessages(
      second,
    )).length;

    final ChatMessage sent = await repository.sendPrivateMessage(
      conversation: first,
      content: '这条消息只属于当前会话',
    );
    expect(sent.conversationId, first.id);
    expect(
      (await repository.fetchPrivateMessages(first)).last.content,
      '这条消息只属于当前会话',
    );
    expect((await repository.fetchPrivateMessages(second)).length, secondCount);

    final ConversationSummary unavailable = conversations.firstWhere(
      (ConversationSummary item) => !item.available,
    );
    await expectLater(
      repository.fetchPrivateMessages(unavailable),
      throwsA(isA<ApiException>()),
    );
  });

  test('draft histories stay isolated by target user', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final ConversationSummary first = ConversationSummary.draft(
      kind: ConversationKind.privateChat,
      title: '草稿一',
      lastMessage: '',
      unreadCount: 0,
      targetUserId: 31001,
    );
    final ConversationSummary second = ConversationSummary.draft(
      kind: ConversationKind.privateChat,
      title: '草稿二',
      lastMessage: '',
      unreadCount: 0,
      targetUserId: 31002,
    );

    final ChatMessage firstMessage = await repository.sendPrivateMessage(
      conversation: first,
      content: '只给草稿一',
    );
    final ChatMessage secondMessage = await repository.sendPrivateMessage(
      conversation: second,
      content: '只给草稿二',
    );

    expect(firstMessage.conversationId, isNull);
    expect(secondMessage.conversationId, isNull);
    expect(
      (await repository.fetchPrivateMessages(
        first,
      )).map((ChatMessage item) => item.content),
      <String>['只给草稿一'],
    );
    expect(
      (await repository.fetchPrivateMessages(
        second,
      )).map((ChatMessage item) => item.content),
      <String>['只给草稿二'],
    );
  });

  test(
    'a draft targeting an existing session reads and updates formal history',
    () async {
      final MockMessageRepository repository = MockMessageRepository();
      final ConversationSummary draft = ConversationSummary.draft(
        kind: ConversationKind.privateChat,
        title: '晚星',
        lastMessage: '',
        unreadCount: 0,
        targetUserId: 20001,
      );

      final ChatMessage sent = await repository.sendPrivateMessage(
        conversation: draft,
        content: '从草稿进入正式会话',
      );
      expect(sent.conversationId, 'conversation-20001');

      final List<ChatMessage> formalHistory = await repository
          .fetchPrivateMessages(
            (await repository.fetchConversations()).firstWhere(
              (ConversationSummary item) => item.id == 'conversation-20001',
            ),
          );
      expect(formalHistory.last.content, '从草稿进入正式会话');
      expect(
        (await repository.fetchPrivateMessages(draft)).last.content,
        '从草稿进入正式会话',
      );
      expect(
        (await repository.fetchConversations())
            .firstWhere(
              (ConversationSummary item) => item.id == 'conversation-20001',
            )
            .lastMessage,
        '从草稿进入正式会话',
      );
    },
  );

  test('notification read and clear actions target exact categories', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final List<AppNotification> system = await repository.fetchNotifications(
      NotificationCategory.system,
    );
    final List<AppNotification> interaction = await repository
        .fetchNotifications(NotificationCategory.interaction);
    expect(system, isNotEmpty);
    expect(interaction, isNotEmpty);

    final AppNotification target = interaction.first;
    await repository.markNotificationRead(target.id);
    expect((await repository.fetchNotification(target.id)).unread, isFalse);

    await repository.clearInteractionNotifications();
    expect(
      await repository.fetchNotifications(NotificationCategory.interaction),
      isEmpty,
    );
    expect(
      await repository.fetchNotifications(NotificationCategory.system),
      isNotEmpty,
    );
  });

  test(
    'notification permission stays unknown until an adapter action succeeds',
    () async {
      final MockMessageRepository repository = MockMessageRepository();
      final MessageRecoverySnapshot before = await repository
          .fetchRecoverySnapshot();
      expect(
        before.notificationPermission,
        NativeNotificationPermissionState.unknown,
      );

      final MessageRecoverySnapshot after = await repository
          .requestNotificationPermission();
      expect(
        after.notificationPermission,
        NativeNotificationPermissionState.allowed,
      );
    },
  );
}
