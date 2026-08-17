import 'dart:async';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';

class MockMessageRepository implements MessageRepository {
  MockMessageRepository()
      : _conversations = <ConversationSummary>[
          ConversationSummary(
            id: 'conversation-20001',
            kind: ConversationKind.privateChat,
            title: '晚星',
            lastMessage: '今晚房间的话题很温柔。',
            updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
            unreadCount: 2,
            targetUserId: 20001,
          ),
          ConversationSummary(
            id: 'conversation-20002',
            kind: ConversationKind.privateChat,
            title: '南风',
            lastMessage: '改天再一起听轻音乐。',
            updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
            unreadCount: 0,
            targetUserId: 20002,
          ),
          ConversationSummary(
            id: 'conversation-20003',
            kind: ConversationKind.privateChat,
            title: '青禾',
            lastMessage: '该会话对象已不可用',
            updatedAt: DateTime.now().subtract(const Duration(days: 1)),
            unreadCount: 0,
            targetUserId: 20003,
            available: false,
            unavailableReason: '用户已注销或当前关系不可用',
          ),
        ],
        _messages = <String, List<ChatMessage>>{
          'conversation-20001': <ChatMessage>[
            ChatMessage(
              id: 'message-1',
              conversationId: 'conversation-20001',
              senderUserId: 20001,
              senderName: '晚星',
              content: '今晚房间的话题很温柔。',
              createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
              isMine: false,
              status: ChatMessageStatus.received,
            ),
            ChatMessage(
              id: 'message-2',
              conversationId: 'conversation-20001',
              senderUserId: 10001,
              senderName: '我',
              content: '谢谢你认真回应每个人。',
              createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
              isMine: true,
              status: ChatMessageStatus.sent,
            ),
          ],
          'conversation-20002': <ChatMessage>[
            ChatMessage(
              id: 'message-3',
              conversationId: 'conversation-20002',
              senderUserId: 20002,
              senderName: '南风',
              content: '改天再一起听轻音乐。',
              createdAt: DateTime.now().subtract(const Duration(hours: 2)),
              isMine: false,
              status: ChatMessageStatus.received,
            ),
          ],
        },
        _notifications = <AppNotification>[
          AppNotification(
            id: 'notification-system-1',
            category: NotificationCategory.system,
            title: '账号安全提醒',
            summary: '你的账号在新设备上完成登录。',
            details: '设备：Android 测试设备\n时间：今天 09:20\n如非本人操作，请前往账号与安全检查登录设备。',
            createdAt: DateTime.now().subtract(const Duration(hours: 1)),
            unread: true,
            targetType: NotificationTargetType.none,
          ),
          AppNotification(
            id: 'notification-room-1',
            category: NotificationCategory.system,
            title: '收藏房间正在进行',
            summary: '“深夜温柔陪伴”已经开房。',
            details: '房间当前有 36 人在线，点击可直接进入。',
            createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
            unread: true,
            targetType: NotificationTargetType.room,
            targetId: '880217',
          ),
          AppNotification(
            id: 'notification-interaction-1',
            category: NotificationCategory.interaction,
            title: '晚星赞了你的动态',
            summary: '“一条不依赖图片上传的真实动态”',
            details: '晚星对你的动态表达了喜欢。',
            createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
            unread: true,
            targetType: NotificationTargetType.dynamicPost,
            targetId: 'dynamic-1001',
            actorUserId: 20001,
            actorName: '晚星',
          ),
          AppNotification(
            id: 'notification-unavailable-1',
            category: NotificationCategory.interaction,
            title: '动态收到一条评论',
            summary: '目标动态已被作者删除。',
            details: '该通知保留，但目标内容已经不可用。',
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
            unread: false,
            targetType: NotificationTargetType.dynamicPost,
            targetId: 'dynamic-deleted',
            targetAvailable: false,
            unavailableReason: '动态已删除或不可见',
          ),
        ];

  final List<ConversationSummary> _conversations;
  final Map<String, List<ChatMessage>> _messages;
  final List<AppNotification> _notifications;
  int _messageSequence = 100;
  NativeNotificationPermissionState _permission =
      NativeNotificationPermissionState.unknown;
  DateTime? _lastSyncAt;

  @override
  bool get supportsConversationList => true;

  @override
  bool get supportsPrivateHistory => true;

  @override
  bool get supportsPrivateSend => true;

  @override
  bool get supportsSystemNotificationList => true;

  @override
  bool get supportsNativeNotificationPermission => true;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    await _delay();
    return List<ConversationSummary>.unmodifiable(
      <ConversationSummary>[..._conversations]
        ..sort((ConversationSummary left, ConversationSummary right) =>
            right.updatedAt.compareTo(left.updatedAt)),
    );
  }

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    await _delay();
    if (!conversation.available) {
      throw ApiException(
        kind: ApiFailureKind.conflict,
        message: conversation.unavailableReason,
      );
    }
    final List<ChatMessage> values =
        _messages[conversation.id] ?? const <ChatMessage>[];
    final int conversationIndex = _conversations.indexWhere(
      (ConversationSummary item) => item.id == conversation.id,
    );
    if (conversationIndex >= 0) {
      _conversations[conversationIndex] =
          _conversations[conversationIndex].copyWith(unreadCount: 0);
    }
    return List<ChatMessage>.unmodifiable(values);
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
  }) async {
    final String text = content.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '消息内容需为 1～1000 个字',
      );
    }
    if (!conversation.available) {
      throw ApiException(
        kind: ApiFailureKind.conflict,
        message: conversation.unavailableReason,
      );
    }
    await _delay();
    final ChatMessage message = ChatMessage(
      id: 'message-${_messageSequence++}',
      conversationId: conversation.id,
      senderUserId: 10001,
      senderName: '我',
      content: text,
      createdAt: DateTime.now(),
      isMine: true,
      status: ChatMessageStatus.sent,
    );
    _messages.putIfAbsent(conversation.id, () => <ChatMessage>[]).add(message);
    final int index = _conversations.indexWhere(
      (ConversationSummary item) => item.id == conversation.id,
    );
    if (index >= 0) {
      _conversations[index] = _conversations[index].copyWith(
        lastMessage: text,
        updatedAt: message.createdAt,
        unreadCount: 0,
      );
    }
    return message;
  }

  @override
  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  ) async {
    await _delay();
    _lastSyncAt = DateTime.now();
    return _notifications
        .where((AppNotification item) => item.category == category)
        .toList(growable: false)
      ..sort((AppNotification left, AppNotification right) =>
          right.createdAt.compareTo(left.createdAt));
  }

  @override
  Future<AppNotification> fetchNotification(String notificationId) async {
    await _delay();
    for (final AppNotification item in _notifications) {
      if (item.id == notificationId) {
        return item;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '通知不存在或已失效',
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    await _delay();
    final int index = _notifications.indexWhere(
      (AppNotification item) => item.id == notificationId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知不存在或已失效',
      );
    }
    _notifications[index] = _notifications[index].copyWith(unread: false);
  }

  @override
  Future<void> clearInteractionNotifications() async {
    await _delay();
    _notifications.removeWhere(
      (AppNotification item) =>
          item.category == NotificationCategory.interaction,
    );
    _lastSyncAt = DateTime.now();
  }

  @override
  Future<MessageRecoverySnapshot> fetchRecoverySnapshot() async {
    await _delay();
    return MessageRecoverySnapshot(
      privateRealtimeAvailable: true,
      notificationPermission: _permission,
      lastNotificationSyncAt: _lastSyncAt,
      message: 'Mock 模式可以验证会话和通知状态。正式环境仍以腾讯 IM 与系统权限适配器为准。',
    );
  }

  @override
  Future<MessageRecoverySnapshot> requestNotificationPermission() async {
    await _delay();
    _permission = NativeNotificationPermissionState.allowed;
    return fetchRecoverySnapshot();
  }

  static Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 35));
}
