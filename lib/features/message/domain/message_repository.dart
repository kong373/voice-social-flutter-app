import 'package:voice_social_app/features/message/domain/message_models.dart';

abstract interface class MessageRepository {
  bool get supportsConversationList;
  bool get supportsPrivateHistory;
  bool get supportsPrivateSend;
  bool get supportsPrivateRealtime;
  bool get supportsSystemNotificationList;
  bool get supportsNativeNotificationPermission;

  Future<List<ConversationSummary>> fetchConversations();

  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  );

  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  });

  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  );

  Future<AppNotification> fetchNotification(String notificationId);

  Future<void> markNotificationRead(String notificationId);

  Future<void> clearInteractionNotifications();

  Future<MessageRecoverySnapshot> fetchRecoverySnapshot();

  Future<MessageRecoverySnapshot> requestNotificationPermission();
}
