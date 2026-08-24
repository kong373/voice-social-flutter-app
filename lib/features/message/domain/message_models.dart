enum ConversationKind { privateChat }

enum ChatMessageStatus {
  sending,
  sent,
  storedPendingDelivery,
  failed,
  received,
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.lastMessage,
    required this.updatedAt,
    required this.unreadCount,
    required this.targetUserId,
    this.avatarUrl,
    this.available = true,
    this.unavailableReason = '',
  });

  /// Null until the first-party backend gives this draft a public ID.
  ///
  /// A newly opened private chat must not invent a conversation identifier.
  final String? id;
  final ConversationKind kind;
  final String title;
  final String? avatarUrl;
  final String lastMessage;

  /// Null for a draft because the client has no authoritative server time yet.
  final DateTime? updatedAt;
  final int unreadCount;
  final int targetUserId;
  final bool available;
  final String unavailableReason;

  bool get isDraft => id == null || id!.trim().isEmpty;

  const ConversationSummary.draft({
    required this.kind,
    required this.title,
    required this.lastMessage,
    required this.unreadCount,
    required this.targetUserId,
    this.avatarUrl,
    this.available = true,
    this.unavailableReason = '',
  }) : id = null,
       updatedAt = null;

  ConversationSummary withServerIdentity({
    required String conversationId,
    required DateTime serverUpdatedAt,
  }) {
    final String normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }
    return ConversationSummary(
      id: normalizedId,
      kind: kind,
      title: title,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      updatedAt: serverUpdatedAt,
      unreadCount: unreadCount,
      targetUserId: targetUserId,
      available: available,
      unavailableReason: unavailableReason,
    );
  }

  ConversationSummary copyWith({
    String? lastMessage,
    DateTime? updatedAt,
    int? unreadCount,
    bool? available,
    String? unavailableReason,
  }) {
    return ConversationSummary(
      id: id,
      kind: kind,
      title: title,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      targetUserId: targetUserId,
      available: available ?? this.available,
      unavailableReason: unavailableReason ?? this.unavailableReason,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.isMine,
    required this.status,
  });

  final String id;
  final String? conversationId;
  final int senderUserId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final bool isMine;
  final ChatMessageStatus status;

  ChatMessage copyWith({ChatMessageStatus? status, String? conversationId}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId ?? this.conversationId,
      senderUserId: senderUserId,
      senderName: senderName,
      content: content,
      createdAt: createdAt,
      isMine: isMine,
      status: status ?? this.status,
    );
  }
}

enum NotificationCategory { system, interaction }

enum NotificationTargetType { none, user, room, dynamicPost, order }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.unread,
    required this.targetType,
    this.targetId,
    this.details = '',
    this.targetAvailable = true,
    this.unavailableReason = '',
    this.actorUserId,
    this.actorName,
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String summary;
  final String details;
  final DateTime createdAt;
  final bool unread;
  final NotificationTargetType targetType;
  final String? targetId;
  final bool targetAvailable;
  final String unavailableReason;
  final int? actorUserId;
  final String? actorName;

  AppNotification copyWith({
    bool? unread,
    bool? targetAvailable,
    String? unavailableReason,
  }) {
    return AppNotification(
      id: id,
      category: category,
      title: title,
      summary: summary,
      details: details,
      createdAt: createdAt,
      unread: unread ?? this.unread,
      targetType: targetType,
      targetId: targetId,
      targetAvailable: targetAvailable ?? this.targetAvailable,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      actorUserId: actorUserId,
      actorName: actorName,
    );
  }
}

enum NativeNotificationPermissionState {
  unknown,
  allowed,
  denied,
  restricted,
  unavailable,
}

class MessageRecoverySnapshot {
  const MessageRecoverySnapshot({
    required this.privateRealtimeAvailable,
    required this.notificationPermission,
    required this.lastNotificationSyncAt,
    required this.message,
  });

  final bool privateRealtimeAvailable;
  final NativeNotificationPermissionState notificationPermission;
  final DateTime? lastNotificationSyncAt;
  final String message;
}
