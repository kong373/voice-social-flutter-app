import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  test('private messages remain scoped to the selected conversation', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final List<ConversationSummary> conversations =
        await repository.fetchConversations();
    final ConversationSummary first = conversations.firstWhere(
      (ConversationSummary item) => item.available,
    );
    final ConversationSummary second = conversations.firstWhere(
      (ConversationSummary item) =>
          item.available && item.id != first.id,
    );
    final int secondCount =
        (await repository.fetchPrivateMessages(second)).length;

    final ChatMessage sent = await repository.sendPrivateMessage(
      conversation: first,
      content: '这条消息只属于当前会话',
    );
    expect(sent.conversationId, first.id);
    expect(
      (await repository.fetchPrivateMessages(first)).last.content,
      '这条消息只属于当前会话',
    );
    expect(
      (await repository.fetchPrivateMessages(second)).length,
      secondCount,
    );

    final ConversationSummary unavailable = conversations.firstWhere(
      (ConversationSummary item) => !item.available,
    );
    await expectLater(
      repository.fetchPrivateMessages(unavailable),
      throwsA(isA<ApiException>()),
    );
  });

  test('notification read and clear actions target exact categories', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final List<AppNotification> system =
        await repository.fetchNotifications(NotificationCategory.system);
    final List<AppNotification> interaction =
        await repository.fetchNotifications(NotificationCategory.interaction);
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

  test('notification permission stays unknown until an adapter action succeeds', () async {
    final MockMessageRepository repository = MockMessageRepository();
    final MessageRecoverySnapshot before =
        await repository.fetchRecoverySnapshot();
    expect(
      before.notificationPermission,
      NativeNotificationPermissionState.unknown,
    );

    final MessageRecoverySnapshot after =
        await repository.requestNotificationPermission();
    expect(
      after.notificationPermission,
      NativeNotificationPermissionState.allowed,
    );
  });
}
