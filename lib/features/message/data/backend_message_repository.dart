import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';

class BackendMessageRepository implements MessageRepository {
  BackendMessageRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required int Function() currentUserIdProvider,
  }) : _apiClient = apiClient,
       _routes = routes,
       _currentUserIdProvider = currentUserIdProvider;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int Function() _currentUserIdProvider;
  final Map<String, AppNotification> _notificationCache =
      <String, AppNotification>{};
  DateTime? _lastSyncAt;

  @override
  bool get supportsConversationList => false;

  @override
  bool get supportsPrivateHistory => true;

  @override
  bool get supportsPrivateSend => false;

  @override
  bool get supportsSystemNotificationList => false;

  @override
  bool get supportsNativeNotificationPermission => false;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    // The authorized backend contains per-user private history endpoints, but
    // no confirmed user-facing conversation list contract. Returning an empty
    // list keeps the boundary honest until Tencent IM supplies that index.
    return const <ConversationSummary>[];
  }

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    if (!conversation.available || conversation.targetUserId <= 0) {
      throw ApiException(
        kind: ApiFailureKind.conflict,
        message: conversation.unavailableReason.isEmpty
            ? '会话对象不可用'
            : conversation.unavailableReason,
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.privateChatHistory,
      body: <String, Object?>{
        'otherUserId': conversation.targetUserId,
        'pageNum': 1,
        'pageSize': 100,
      },
    );
    return _extractList(response.data)
        .map(
          (Map<String, Object?> item) =>
              _chatMessageFromMap(conversation, item),
        )
        .where((ChatMessage item) => item.id.isNotEmpty)
        .toList(growable: false)
      ..sort(
        (ChatMessage left, ChatMessage right) =>
            left.createdAt.compareTo(right.createdAt),
      );
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '腾讯 IM 尚未接入，当前版本不能发送私聊消息',
    );
  }

  @override
  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  ) async {
    if (category == NotificationCategory.system) {
      return const <AppNotification>[];
    }
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicNotifications,
      body: const <String, Object?>{'pageNum': 1, 'pageSize': 100},
    );
    final List<AppNotification> notifications =
        _extractList(response.data)
            .map(_interactionNotificationFromMap)
            .where((AppNotification item) => item.id.isNotEmpty)
            .toList(growable: false)
          ..sort(
            (AppNotification left, AppNotification right) =>
                right.createdAt.compareTo(left.createdAt),
          );
    for (final AppNotification item in notifications) {
      _notificationCache[item.id] = item;
    }
    _lastSyncAt = DateTime.now();
    return notifications;
  }

  @override
  Future<AppNotification> fetchNotification(String notificationId) async {
    final AppNotification? cached = _notificationCache[notificationId];
    if (cached != null) {
      return cached;
    }
    if (!notificationId.startsWith('push-')) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知不存在或已失效',
      );
    }
    final String pushId = notificationId.substring('push-'.length);
    final ApiResponse response = await _apiClient.get(
      _routes.pushNotificationDetail,
      query: <String, String>{'id': pushId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知详情不可用',
      );
    }
    final AppNotification notification = AppNotification(
      id: notificationId,
      category: NotificationCategory.system,
      title: _string(data['title'], fallback: '系统通知'),
      summary: _string(data['summary'] ?? data['content'], fallback: '查看通知详情'),
      details: _string(data['content'] ?? data['details']),
      createdAt: _asDateTime(data['createTime'] ?? data['createdAt']),
      unread: false,
      targetType: _targetType(data['targetType'] ?? data['type']),
      targetId: _optionalString(data['targetId'] ?? data['businessId']),
      targetAvailable: !_asBool(data['targetUnavailable']),
      unavailableReason: _string(data['unavailableReason']),
    );
    _notificationCache[notification.id] = notification;
    return notification;
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    final AppNotification? current = _notificationCache[notificationId];
    if (current != null) {
      _notificationCache[notificationId] = current.copyWith(unread: false);
    }
  }

  @override
  Future<void> clearInteractionNotifications() async {
    await _apiClient.post(_routes.clearDynamicNotifications);
    _notificationCache.removeWhere(
      (_, AppNotification item) =>
          item.category == NotificationCategory.interaction,
    );
    _lastSyncAt = DateTime.now();
  }

  @override
  Future<MessageRecoverySnapshot> fetchRecoverySnapshot() async {
    return MessageRecoverySnapshot(
      privateRealtimeAvailable: false,
      notificationPermission: NativeNotificationPermissionState.unavailable,
      lastNotificationSyncAt: _lastSyncAt,
      message: '腾讯 IM 和系统通知权限适配器尚未接入。当前只能刷新服务端已落库的互动通知，不伪造私聊漫游或完整消息恢复。',
    );
  }

  @override
  Future<MessageRecoverySnapshot> requestNotificationPermission() async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '系统通知权限适配器尚未接入',
    );
  }

  ChatMessage _chatMessageFromMap(
    ConversationSummary conversation,
    Map<String, Object?> item,
  ) {
    final int senderId =
        _asInt(item['senderUserId'] ?? item['fromUserId'] ?? item['userId']) ??
        0;
    final int currentUserId = _currentUserIdProvider();
    final bool mine = senderId == currentUserId || _asBool(item['isMine']);
    return ChatMessage(
      id: _string(item['id'] ?? item['messageId'] ?? item['msgId']),
      conversationId: conversation.id,
      senderUserId: senderId,
      senderName: _string(
        item['senderName'] ?? item['nickName'],
        fallback: mine ? '我' : conversation.title,
      ),
      content: _string(item['content'] ?? item['message']),
      createdAt: _asDateTime(item['createTime'] ?? item['createdAt']),
      isMine: mine,
      status: mine ? ChatMessageStatus.sent : ChatMessageStatus.received,
    );
  }

  static AppNotification _interactionNotificationFromMap(
    Map<String, Object?> item,
  ) {
    final int type = _asInt(item['notifyType']) ?? 0;
    final String actorName = _string(
      item['nickName'] ?? item['nickname'],
      fallback: '用户',
    );
    final String title = switch (type) {
      1 => '$actorName 评论了你的动态',
      2 => '$actorName 回复了你的评论',
      _ => '$actorName 赞了你的动态',
    };
    final String dynamicId = _string(item['dynamicId']);
    final bool targetAvailable = dynamicId.isNotEmpty;
    return AppNotification(
      id: _string(
        item['id'] ??
            item['commentId'] ??
            'dynamic-$dynamicId-${item['createDate'] ?? ''}',
      ),
      category: NotificationCategory.interaction,
      title: title,
      summary: _string(
        item['commentContent'] ??
            item['dynamicContent'] ??
            item['publishNickName'],
      ),
      details: _string(item['commentContent'] ?? item['dynamicContent']),
      createdAt: _asDateTime(item['createDate'] ?? item['createTime']),
      unread: _asBool(item['isRedPoint'] ?? 1),
      targetType: NotificationTargetType.dynamicPost,
      targetId: targetAvailable ? dynamicId : null,
      targetAvailable: targetAvailable,
      unavailableReason: targetAvailable ? '' : '目标动态已删除或不可见',
      actorUserId: _asInt(item['userId']),
      actorName: actorName,
    );
  }

  static NotificationTargetType _targetType(Object? value) {
    final String text = value?.toString().toLowerCase() ?? '';
    if (text.contains('room') || text == '1') {
      return NotificationTargetType.room;
    }
    if (text.contains('user') || text == '2') {
      return NotificationTargetType.user;
    }
    if (text.contains('dynamic') || text == '3') {
      return NotificationTargetType.dynamicPost;
    }
    if (text.contains('order') || text == '4') {
      return NotificationTargetType.order;
    }
    return NotificationTargetType.none;
  }

  static List<Map<String, Object?>> _extractList(Object? value) {
    final Map<String, Object?> map = _asMap(value);
    final Object? source =
        map['records'] ??
        map['list'] ??
        map['rows'] ??
        map['items'] ??
        map['data'] ??
        value;
    return _asMapList(source);
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static List<Map<String, Object?>> _asMapList(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList(growable: false)
      : const <Map<String, Object?>>[];
  static String _string(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static bool _asBool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';
  static DateTime _asDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}
