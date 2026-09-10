import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

/// Opt-in contract: legacy text repositories and mocks need not support media.
abstract interface class MediaPrivateMessageRepository {
  /// Retry an unknown result with the same scope, requestId and reference.
  /// A token refresh may retain that scope; account ABA permanently invalidates it.
  Future<ChatMessage> sendPrivateMediaMessage({
    required ConversationSummary conversation,
    required MediaReference media,
    required MediaIdentityScope identity,
    required String requestId,
  });
}

/// A visible chat may become hidden or change accounts while HTTP is pending.
/// Check this lease before paging again or acknowledging the conversation read.
abstract interface class VisiblePrivateMessageRepository
    implements MessageRepository {
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessages(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    Set<String> knownMessageIds = const <String>{},
    String? resumeCursor,
  });
}

class PrivateMessageSyncBatch {
  const PrivateMessageSyncBatch(this.messages, {this.nextCursor});
  final List<ChatMessage> messages;

  /// A bounded batch is not a complete read. Continue before marking read or
  /// advancing the known-message boundary to the newest received messages.
  final String? nextCursor;
}

/// One validated cursor page per call, without implicitly marking history read.
/// Allows the visible controller to publish newest rows before scanning old
/// receipts, sharing a single flight and a two-page budget per polling turn.
abstract interface class PagedPrivateMessageRepository
    implements VisiblePrivateMessageRepository {
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessagePage(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    String? cursor,
  });
  Future<void> markVisiblePrivateMessagesRead(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
  });
}

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

  Future<void> openNotificationSettings();
}
