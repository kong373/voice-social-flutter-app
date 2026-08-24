import 'dart:convert';

import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_request_id.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';

class BackendMessageRepository implements MessageRepository {
  BackendMessageRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required int Function() currentUserIdProvider,
    NativePermissionAdapter? nativePermissionAdapter,
  }) : _apiClient = apiClient,
       _routes = routes,
       _currentUserIdProvider = currentUserIdProvider,
       _nativePermissionAdapter = nativePermissionAdapter;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int Function() _currentUserIdProvider;
  final NativePermissionAdapter? _nativePermissionAdapter;
  final Map<String, AppNotification> _notificationCache =
      <String, AppNotification>{};
  final Map<NotificationCategory, int> _notificationFetchVersions =
      <NotificationCategory, int>{};
  final Map<String, _PendingMessageWrite> _inFlightWrites =
      <String, _PendingMessageWrite>{};
  final Map<String, String> _ambiguousWriteRequestIds = <String, String>{};
  final Map<String, _PendingMessageSend> _inFlightSends =
      <String, _PendingMessageSend>{};
  DateTime? _lastSyncAt;

  static const String _privateMessageType = 'TEXT';
  static const int _maximumPageSize = 100;
  static const int _maximumBackendPages = 100;

  @override
  bool get supportsConversationList => true;

  @override
  bool get supportsPrivateHistory => true;

  @override
  bool get supportsPrivateSend => true;

  @override
  bool get supportsPrivateRealtime => false;

  @override
  bool get supportsSystemNotificationList => true;

  @override
  bool get supportsNativeNotificationPermission =>
      _nativePermissionAdapter != null;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    final List<ConversationSummary> conversations = <ConversationSummary>[];
    var pageNum = 1;
    int? expectedTotal;
    int? expectedPages;
    var hasMore = true;
    while (hasMore && pageNum <= _maximumBackendPages) {
      final ApiResponse response = await _apiClient.get(
        _routes.messageConversations,
        query: <String, String>{
          'pageNum': '$pageNum',
          'pageSize': '$_maximumPageSize',
        },
      );
      final _ConversationPage page = _conversationPageFromMap(
        response.data,
        requestedPage: pageNum,
        requestedPageSize: _maximumPageSize,
      );
      if (expectedTotal == null) {
        expectedTotal = page.total;
        expectedPages = page.pages;
      } else if (page.total != expectedTotal || page.pages != expectedPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '消息会话分页元数据在请求间发生变化',
        );
      }
      hasMore = page.hasMore;
      conversations.addAll(page.items.map(_conversationFromMap));
      pageNum += 1;
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话超过客户端安全分页上限',
      );
    }
    if (expectedTotal == null || conversations.length != expectedTotal) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页最终累计记录数与服务端 total 不一致',
      );
    }
    conversations
      ..removeWhere((ConversationSummary item) => item.targetUserId <= 0)
      ..sort(
        (ConversationSummary left, ConversationSummary right) =>
            _compareUpdatedAt(right.updatedAt, left.updatedAt),
      );
    return conversations;
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
    final List<ChatMessage> messages = <ChatMessage>[];
    final Set<String> seenCursors = <String>{};
    String? authoritativeConversationId;
    String? cursor;
    var hasMore = true;
    var fetchedPages = 0;
    while (hasMore && fetchedPages < _maximumBackendPages) {
      fetchedPages += 1;
      final Map<String, String> query = <String, String>{
        'targetUserId': '${conversation.targetUserId}',
        'pageSize': '$_maximumPageSize',
        if (cursor != null) 'cursor': cursor,
      };
      final ApiResponse response = await _apiClient.get(
        _routes.privateChatHistory,
        query: query,
      );
      final Map<String, Object?> data = _asMap(response.data);
      final List<Map<String, Object?>> items = _extractList(response.data);
      hasMore = _requiredBool(data['hasMore'], field: 'hasMore');
      _requiredNonNegativeInt(data['unreadCount'], field: 'unreadCount');
      final String? pageConversationId = _optionalString(
        data['conversationId'],
      );
      if (pageConversationId == null) {
        final bool isUnresolvedEmptyDraft =
            conversation.isDraft &&
            authoritativeConversationId == null &&
            items.isEmpty &&
            !hasMore;
        if (!isUnresolvedEmptyDraft) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊历史响应缺少服务端会话 ID',
          );
        }
      } else if (authoritativeConversationId == null) {
        authoritativeConversationId = pageConversationId;
        if (!conversation.isDraft && conversation.id != pageConversationId) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊历史响应的服务端会话 ID 与当前会话不一致',
          );
        }
      } else if (authoritativeConversationId != pageConversationId) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊历史分页返回了不一致的服务端会话 ID',
        );
      }
      final String nextCursor = _requiredCursor(
        data['nextCursor'],
        field: 'nextCursor',
      );
      if (pageConversationId != null) {
        final int targetUserId = _requiredPositiveInt(
          data['targetUserId'],
          field: 'targetUserId',
        );
        if (targetUserId != conversation.targetUserId ||
            _requiredString(
                  data['imStatus'],
                  '私聊历史响应缺少 IM 阻断状态',
                ).toUpperCase() !=
                'VENDOR_BLOCKED' ||
            _requiredBool(
                  data['providerInvocation'],
                  field: 'providerInvocation',
                ) !=
                false) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊历史响应的会话权限或第三方阻断状态不可信',
          );
        }
      }
      if (hasMore && items.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊历史分页响应为空但仍声明存在下一页',
        );
      }
      if (hasMore && nextCursor.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊历史分页响应缺少下一页游标',
        );
      }
      if (hasMore &&
          (nextCursor == cursor || seenCursors.contains(nextCursor))) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊历史分页游标重复或无进展',
        );
      }
      messages.addAll(
        items
            .map(
              (Map<String, Object?> item) => _chatMessageFromMap(
                conversation,
                item,
                authoritativeConversationId: authoritativeConversationId,
              ),
            )
            .where((ChatMessage item) => item.id.isNotEmpty),
      );
      if (hasMore) {
        seenCursors.add(nextCursor);
        cursor = nextCursor;
      }
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '私聊历史超过客户端安全分页上限',
      );
    }
    messages.sort(
      (ChatMessage left, ChatMessage right) =>
          left.createdAt.compareTo(right.createdAt),
    );
    // Entering a conversation is the first-party read boundary.  This does
    // not claim realtime delivery: the backend keeps imStatus VENDOR_BLOCKED.
    await _runStableMessageWrite<void>(
      intent: 'private-read:${conversation.targetUserId}',
      action: (Map<String, String> headers) async {
        final ApiResponse readResponse = await _apiClient.post(
          _routes.markPrivateMessageRead,
          headers: headers,
          body: <String, Object?>{'targetUserId': conversation.targetUserId},
        );
        final Map<String, Object?> readData = _asMap(readResponse.data);
        final int readTarget = _requiredPositiveInt(
          readData['targetUserId'],
          field: 'targetUserId',
        );
        final int markedRead = _requiredNonNegativeInt(
          readData['markedRead'],
          field: 'markedRead',
        );
        final int unreadCount = _requiredNonNegativeInt(
          readData['unreadCount'],
          field: 'unreadCount',
        );
        final String? readConversationId = _optionalString(
          readData['conversationId'],
        );
        if (readTarget != conversation.targetUserId || unreadCount != 0) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊已读响应与当前会话不一致',
          );
        }
        if (markedRead < 0 ||
            (readConversationId != null &&
                !conversation.isDraft &&
                readConversationId != conversation.id)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊已读响应包含无效的会话权威状态',
          );
        }
      },
    );
    return messages;
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async {
    final String normalizedContent = content.trim();
    if (normalizedContent.isEmpty || normalizedContent.length > 2000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '消息内容需为 1～2000 个字',
      );
    }
    if (!conversation.available || conversation.targetUserId <= 0) {
      throw ApiException(
        kind: ApiFailureKind.conflict,
        message: conversation.unavailableReason.isEmpty
            ? '会话对象不可用'
            : conversation.unavailableReason,
      );
    }
    final String key = normalizeMessageRequestId(requestId);
    final String fingerprint = _sendFingerprint(
      targetUserId: conversation.targetUserId,
      content: normalizedContent,
      messageType: _privateMessageType,
    );
    final _PendingMessageSend? pending = _inFlightSends[key];
    if (pending != null) {
      if (pending.fingerprint != fingerprint) {
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: '相同请求 ID 已用于不同消息，拒绝复用',
        );
      }
      return pending.future;
    }
    final Future<ChatMessage> request = _sendPrivateMessage(
      key: key,
      requestId: key,
      conversation: conversation,
      content: normalizedContent,
    );
    _inFlightSends[key] = _PendingMessageSend(
      fingerprint: fingerprint,
      future: request,
    );
    return request;
  }

  @override
  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  ) async {
    final int requestVersion = (_notificationFetchVersions[category] ?? 0) + 1;
    _notificationFetchVersions[category] = requestVersion;
    await _syncNotifications();
    final List<AppNotification> notifications = <AppNotification>[];
    final Set<String> seenCursors = <String>{};
    String? cursor;
    var hasMore = true;
    var fetchedPages = 0;
    while (hasMore && fetchedPages < _maximumBackendPages) {
      fetchedPages += 1;
      final Map<String, String> query = <String, String>{
        'pageSize': '$_maximumPageSize',
        if (category == NotificationCategory.system) 'category': 'SYSTEM',
        if (cursor != null) 'cursor': cursor,
      };
      final ApiResponse response = await _apiClient.get(
        _routes.systemNotifications,
        query: query,
      );
      final Map<String, Object?> data = _asMap(response.data);
      final List<Map<String, Object?>> items = _extractList(response.data);
      hasMore = _requiredBool(data['hasMore'], field: 'hasMore');
      _requiredNonNegativeInt(data['unreadCount'], field: 'unreadCount');
      final String nextCursor = _requiredCursor(
        data['nextCursor'],
        field: 'nextCursor',
      );
      if (hasMore && items.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '通知分页响应为空但仍声明存在下一页',
        );
      }
      if (hasMore && nextCursor.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '通知分页响应缺少下一页游标',
        );
      }
      if (hasMore &&
          (nextCursor == cursor || seenCursors.contains(nextCursor))) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '通知分页游标重复或无进展',
        );
      }
      notifications.addAll(
        items
            .map(_notificationFromMap)
            .where((AppNotification item) => item.category == category)
            .where((AppNotification item) => item.id.isNotEmpty),
      );
      if (hasMore) {
        seenCursors.add(nextCursor);
        cursor = nextCursor;
      }
    }
    if (hasMore) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '通知超过客户端安全分页上限',
      );
    }
    notifications.sort(
      (AppNotification left, AppNotification right) =>
          right.createdAt.compareTo(left.createdAt),
    );
    if (_notificationFetchVersions[category] == requestVersion) {
      for (final AppNotification item in notifications) {
        _notificationCache[item.id] = item;
      }
      _lastSyncAt = DateTime.now();
    }
    return notifications;
  }

  Future<void> _syncNotifications() async {
    await _runStableMessageWrite<void>(
      intent: 'notifications-sync',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.syncNotifications,
          headers: headers,
        );
        final Map<String, Object?> data = _asMap(response.data);
        final bool synced = _requiredStrictBool(
          data['synced'],
          field: 'synced',
        );
        final String projectionStatus = _requiredString(
          data['projectionStatus'],
          '通知同步响应缺少 projectionStatus',
        );
        final String pushStatus = _requiredString(
          data['pushStatus'],
          '通知同步响应缺少 pushStatus',
        );
        final String imStatus = _requiredString(
          data['imStatus'],
          '通知同步响应缺少 imStatus',
        );
        final bool providerInvocation = _requiredStrictBool(
          data['providerInvocation'],
          field: 'providerInvocation',
        );
        final int dynamicUnread = _requiredNonNegativeInt(
          data['dynamicUnread'],
          field: 'dynamicUnread',
        );
        final int notificationUnread = _requiredNonNegativeInt(
          data['notificationUnread'],
          field: 'notificationUnread',
        );
        final int messageUnread = _requiredNonNegativeInt(
          data['messageUnread'],
          field: 'messageUnread',
        );
        final int totalUnread = _requiredNonNegativeInt(
          data['totalUnread'],
          field: 'totalUnread',
        );
        if (!synced ||
            projectionStatus != 'FIRST_PARTY_MATERIALIZED' ||
            pushStatus != 'VENDOR_BLOCKED' ||
            imStatus != 'VENDOR_BLOCKED' ||
            providerInvocation ||
            dynamicUnread > notificationUnread ||
            totalUnread != notificationUnread + messageUnread) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '通知同步响应未确认第一方投影或权威未读计数',
          );
        }
        _lastSyncAt = DateTime.now();
      },
    );
  }

  @override
  Future<AppNotification> fetchNotification(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知不存在或已失效',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.pushNotificationDetail,
      query: <String, String>{'notificationId': notificationId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知详情不可用',
      );
    }
    final AppNotification notification = _notificationFromMap(data);
    if (notification.id != notificationId.trim()) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '通知详情响应与请求 ID 不一致',
      );
    }
    _notificationCache[notification.id] = notification;
    return notification;
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    final String normalizedId = notificationId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '通知不存在或已失效',
      );
    }
    await _runStableMessageWrite<void>(
      intent: 'notification-read:$normalizedId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.markSystemNotificationRead,
          headers: headers,
          body: <String, Object?>{'notificationId': normalizedId},
        );
        final Map<String, Object?> data = _asMap(response.data);
        final AppNotification authoritative = _notificationFromMap(data);
        if (authoritative.id != normalizedId || authoritative.unread) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '通知已读响应与请求通知不一致',
          );
        }
        _requireVendorBlocked(
          data,
          statusField: 'pushStatus',
          context: '通知已读响应',
        );
        _notificationCache[normalizedId] = authoritative;
      },
    );
  }

  static void _requireVendorBlocked(
    Map<String, Object?> data, {
    required String statusField,
    required String context,
  }) {
    final String status = _requiredString(
      data[statusField],
      '$context 缺少第三方阻断状态',
    ).toUpperCase();
    final bool providerInvocation = _requiredBool(
      data['providerInvocation'],
      field: 'providerInvocation',
    );
    if (status != 'VENDOR_BLOCKED' || providerInvocation) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context 的第三方阻断状态不可信',
      );
    }
  }

  Future<T> _runStableMessageWrite<T>({
    required String intent,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    final _PendingMessageWrite? existing = _inFlightWrites[intent];
    if (existing != null) {
      return existing.future.then((Object? value) => value as T);
    }

    final String requestId =
        _ambiguousWriteRequestIds[intent] ?? createMessageRequestId();
    _ambiguousWriteRequestIds.remove(intent);
    final Future<T> operation = Future<void>.value().then<T>((_) async {
      try {
        final T value = await action(<String, String>{
          'X-Request-Id': requestId,
        });
        _ambiguousWriteRequestIds.remove(intent);
        return value;
      } catch (error, stackTrace) {
        if (_isAmbiguousMessageWriteError(error)) {
          _ambiguousWriteRequestIds[intent] = requestId;
        } else {
          _ambiguousWriteRequestIds.remove(intent);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    final Future<Object?> tracked = operation.then<Object?>((T value) => value);
    final _PendingMessageWrite submission = _PendingMessageWrite(
      requestId: requestId,
      future: tracked,
    );
    _inFlightWrites[intent] = submission;
    tracked.then<void>(
      (_) => _removeMessageWriteIfCurrent(intent, submission),
      onError: (Object _, StackTrace __) =>
          _removeMessageWriteIfCurrent(intent, submission),
    );
    return operation;
  }

  void _removeMessageWriteIfCurrent(
    String intent,
    _PendingMessageWrite submission,
  ) {
    if (identical(_inFlightWrites[intent], submission)) {
      _inFlightWrites.remove(intent);
    }
  }

  static bool _isAmbiguousMessageWriteError(Object error) {
    if (error is! ApiException) {
      return true;
    }
    if (error.code == 40901 || error.code == 40902) {
      return true;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden ||
      ApiFailureKind.validation ||
      ApiFailureKind.conflict ||
      ApiFailureKind.business ||
      ApiFailureKind.configuration => false,
    };
  }

  @override
  Future<void> clearInteractionNotifications() async {
    await _runStableMessageWrite<void>(
      intent: 'interaction-clear-all',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.clearDynamicNotifications,
          headers: headers,
        );
        final Map<String, Object?> data = _asMap(response.data);
        final int dynamicUnread = _requiredNonNegativeInt(
          data['dynamicUnread'],
          field: 'dynamicUnread',
        );
        final int notificationUnread = _requiredNonNegativeInt(
          data['notificationUnread'],
          field: 'notificationUnread',
        );
        final int messageUnread = _requiredNonNegativeInt(
          data['messageUnread'],
          field: 'messageUnread',
        );
        final int totalUnread = _requiredNonNegativeInt(
          data['totalUnread'],
          field: 'totalUnread',
        );
        if (dynamicUnread != 0 ||
            totalUnread != notificationUnread + messageUnread) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '清空互动通知后服务端未返回一致的未读计数',
          );
        }
        _requireVendorBlocked(
          data,
          statusField: 'pushStatus',
          context: '清空互动通知响应',
        );
        if (_requiredString(
              data['imStatus'],
              '清空互动通知响应缺少 IM 阻断状态',
            ).toUpperCase() !=
            'VENDOR_BLOCKED') {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '清空互动通知响应的 IM 阻断状态不可信',
          );
        }
        _notificationCache.removeWhere(
          (_, AppNotification item) =>
              item.category == NotificationCategory.interaction,
        );
        _lastSyncAt = DateTime.now();
      },
    );
  }

  @override
  Future<MessageRecoverySnapshot> fetchRecoverySnapshot() async {
    final NativeNotificationPermissionState notificationPermission =
        await _nativeNotificationPermission();
    return MessageRecoverySnapshot(
      privateRealtimeAvailable: false,
      notificationPermission: notificationPermission,
      lastNotificationSyncAt: _lastSyncAt,
      message:
          notificationPermission ==
              NativeNotificationPermissionState.unavailable
          ? '第一方消息记录与通知已接通；系统通知权限适配器不可用，腾讯 IM 实时投递仍为 VENDOR_BLOCKED。'
          : '系统通知状态由 Android/iOS 原生权限返回；腾讯 IM 实时投递仍为 VENDOR_BLOCKED，不伪造实时状态。',
    );
  }

  @override
  Future<MessageRecoverySnapshot> requestNotificationPermission() async {
    final NativePermissionAdapter? adapter = _nativePermissionAdapter;
    if (adapter == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '系统通知权限需要原生平台适配器，当前不会伪造授权结果',
      );
    }
    final PermissionState state = await adapter.request(
      PermissionKind.notifications,
    );
    if (state == PermissionState.unavailable) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '系统通知权限原生适配器不可用，当前不会伪造授权结果',
      );
    }
    return fetchRecoverySnapshot();
  }

  @override
  Future<void> openNotificationSettings() async {
    final NativePermissionAdapter? adapter = _nativePermissionAdapter;
    if (adapter == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '系统通知权限需要原生平台适配器，当前不会伪造授权结果',
      );
    }
    await adapter.openAppSettings();
  }

  Future<NativeNotificationPermissionState>
  _nativeNotificationPermission() async {
    final NativePermissionAdapter? adapter = _nativePermissionAdapter;
    if (adapter == null) {
      return NativeNotificationPermissionState.unavailable;
    }
    try {
      return _notificationState(
        await adapter.status(PermissionKind.notifications),
      );
    } on Object {
      return NativeNotificationPermissionState.unavailable;
    }
  }

  static NativeNotificationPermissionState _notificationState(
    PermissionState state,
  ) => switch (state) {
    PermissionState.notDetermined => NativeNotificationPermissionState.unknown,
    PermissionState.granted => NativeNotificationPermissionState.allowed,
    PermissionState.denied => NativeNotificationPermissionState.denied,
    PermissionState.permanentlyDenied =>
      NativeNotificationPermissionState.permanentlyDenied,
    PermissionState.restricted => NativeNotificationPermissionState.restricted,
    PermissionState.unavailable =>
      NativeNotificationPermissionState.unavailable,
  };

  ChatMessage _chatMessageFromMap(
    ConversationSummary conversation,
    Map<String, Object?> item, {
    String? authoritativeConversationId,
  }) {
    final String id = _requiredString(
      item['id'] ?? item['messageId'] ?? item['msgId'],
      '消息响应缺少服务端消息 ID',
    );
    final DateTime createdAt = _requiredDateTime(
      item['createTime'] ?? item['createdAt'],
      '消息响应缺少有效的服务端时间',
    );
    final int? senderId = _asInt(
      item['senderUserId'] ?? item['fromUserId'] ?? item['userId'],
    );
    if (senderId == null || senderId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应缺少有效的发送者用户 ID',
      );
    }
    final int currentUserId = _currentUserIdProvider();
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '当前登录用户身份不可用，无法解析私聊消息',
      );
    }
    final String direction = _requiredString(
      item['direction'],
      '消息响应缺少方向字段',
    ).toUpperCase();
    final bool mine = switch (direction) {
      'OUTGOING' || 'SENT' => true,
      'INCOMING' || 'RECEIVED' => false,
      _ => throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应包含无法识别的方向',
      ),
    };
    if (mine != (senderId == currentUserId) ||
        (item.containsKey('isMine') && _asBool(item['isMine']) != mine)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息方向与发送者身份不一致',
      );
    }
    final String itemConversationId =
        _optionalString(item['conversationId']) ?? '';
    if (authoritativeConversationId != null &&
        itemConversationId.isNotEmpty &&
        itemConversationId != authoritativeConversationId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应的会话 ID 与分页顶层会话 ID 不一致',
      );
    }
    final ChatMessageStatus status = _statusFromMap(item, isMine: mine);
    final String? conversationId =
        authoritativeConversationId ??
        (itemConversationId.isEmpty ? conversation.id : itemConversationId);
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderUserId: senderId,
      senderName: _string(
        item['senderName'] ?? item['nickName'],
        fallback: mine ? '我' : conversation.title,
      ),
      content: _string(item['content'] ?? item['message']),
      createdAt: createdAt,
      isMine: mine,
      status: status,
    );
  }

  static ChatMessageStatus _statusFromMap(
    Map<String, Object?> item, {
    required bool isMine,
  }) {
    if (!isMine) {
      return ChatMessageStatus.received;
    }
    final String storageStatus = _string(item['storageStatus']).toUpperCase();
    final String deliveryStatus = _string(item['deliveryStatus']).toUpperCase();
    if (storageStatus == 'FIRST_PARTY_STORED' ||
        deliveryStatus == 'VENDOR_BLOCKED') {
      return ChatMessageStatus.storedPendingDelivery;
    }
    if (deliveryStatus == 'DELIVERED' ||
        deliveryStatus == 'DELIVERED_TO_RECIPIENT') {
      return ChatMessageStatus.sent;
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '消息响应缺少可确认的投递状态',
    );
  }

  Future<ChatMessage> _sendPrivateMessage({
    required String key,
    required String requestId,
    required ConversationSummary conversation,
    required String content,
  }) async {
    try {
      final ApiResponse response = await _apiClient.post(
        _routes.sendPrivateMessage,
        headers: <String, String>{'X-Request-Id': requestId},
        body: <String, Object?>{
          'targetUserId': conversation.targetUserId,
          'content': content,
          'messageType': _privateMessageType,
        },
      );
      final Map<String, Object?> data = _asMap(response.data);
      final Map<String, Object?> message = _asMap(
        data['message'] ?? data['data'] ?? data,
      );
      final int receiverUserId = _requiredPositiveInt(
        message['receiverUserId'],
        field: 'receiverUserId',
      );
      final String returnedType = _requiredString(
        message['messageType'],
        '发送消息响应缺少 messageType',
      ).toUpperCase();
      final String returnedContent = _requiredString(
        message['content'],
        '发送消息响应缺少 content',
      );
      final bool providerInvocation = _requiredBool(
        message['providerInvocation'],
        field: 'providerInvocation',
      );
      if (receiverUserId != conversation.targetUserId ||
          returnedType != _privateMessageType ||
          returnedContent != content ||
          providerInvocation) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '发送消息响应与提交内容或第三方阻断边界不一致',
        );
      }
      ChatMessage parsed = _chatMessageFromMap(
        conversation,
        message,
        authoritativeConversationId: _optionalString(
          message['conversationId'] ?? data['conversationId'],
        ),
      );
      if (parsed.id.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '发送消息响应缺少消息 ID',
        );
      }
      if (conversation.isDraft && parsed.conversationId == null) {
        final String? resolvedId = await _resolveDraftConversationId(
          conversation,
        );
        if (resolvedId != null) {
          parsed = parsed.copyWith(conversationId: resolvedId);
        }
      }
      return parsed;
    } finally {
      _inFlightSends.remove(key);
    }
  }

  Future<String?> _resolveDraftConversationId(ConversationSummary draft) async {
    try {
      final List<ConversationSummary> conversations =
          await fetchConversations();
      final ConversationSummary? resolved = conversations
          .where(
            (ConversationSummary item) =>
                item.targetUserId == draft.targetUserId && !item.isDraft,
          )
          .firstOrNull;
      if (resolved?.id != null) {
        return resolved!.id;
      }
    } on ApiException {
      // Try the authoritative history endpoint below. If it is unavailable
      // too, the caller keeps an explicit unresolved draft.
    }

    try {
      final List<ChatMessage> history = await fetchPrivateMessages(draft);
      return history
          .map((ChatMessage item) => item.conversationId)
          .whereType<String>()
          .where((String id) => id.trim().isNotEmpty)
          .firstOrNull;
    } on ApiException {
      return null;
    }
  }

  static _ConversationPage _conversationPageFromMap(
    Object? value, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final Map<String, Object?> data = _asMap(value);
    final List<Map<String, Object?>> items = _extractList(value);
    final int current = _requiredPageInt(
      data['pageNum'],
      field: 'pageNum',
      allowZero: false,
    );
    final int pageSize = _requiredPageInt(
      data['pageSize'],
      field: 'pageSize',
      allowZero: false,
    );
    final int total = _requiredPageInt(
      data['total'],
      field: 'total',
      allowZero: true,
    );
    final int? reportedPages = data.containsKey('pages')
        ? _requiredPageInt(data['pages'], field: 'pages', allowZero: true)
        : null;
    final bool hasMore = _requiredBool(data['hasMore'], field: 'hasMore');
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页页码或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (reportedPages != null && reportedPages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页 pages 与 total 不一致',
      );
    }
    if (expectedPages > 0 && current > expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页当前页超过服务端页数',
      );
    }
    if (expectedPages > _maximumBackendPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页超过客户端安全上限',
      );
    }
    if (hasMore != (current < expectedPages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页 hasMore 与服务端页数不一致',
      );
    }
    if (items.length > pageSize || (expectedPages == 0 && items.isNotEmpty)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页记录数与服务端元数据不一致',
      );
    }
    if (hasMore && items.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页响应为空但仍声明存在下一页',
      );
    }
    if (current < expectedPages && items.length != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页出现非末页短页',
      );
    }
    if (total > 0 && items.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页总数大于零但当前页为空',
      );
    }
    return _ConversationPage(
      items: items,
      current: current,
      pageSize: pageSize,
      total: total,
      pages: expectedPages,
      hasMore: hasMore,
    );
  }

  static ConversationSummary _conversationFromMap(Map<String, Object?> item) {
    final int targetUserId =
        _asInt(item['targetUserId'] ?? item['userId'] ?? item['otherUserId']) ??
        0;
    if (targetUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话响应缺少有效的目标用户 ID',
      );
    }
    final String id = _requiredString(
      item['conversationId'] ?? item['id'],
      '消息会话响应缺少服务端会话 ID',
    );
    final DateTime updatedAt = _requiredDateTime(
      item['lastMessageAt'] ?? item['updatedAt'],
      '消息会话响应缺少有效的服务端更新时间',
    );
    final int unreadCount = _requiredExplicitNonNegativeInt(
      item['unreadCount'],
      field: 'unreadCount',
    );
    return ConversationSummary(
      id: id,
      kind: ConversationKind.privateChat,
      title: _string(item['nickName'] ?? item['nickname'], fallback: '用户'),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      lastMessage: _string(item['lastMessage'] ?? item['content']),
      updatedAt: updatedAt,
      unreadCount: unreadCount,
      targetUserId: targetUserId,
      available: true,
      unavailableReason: '',
    );
  }

  static AppNotification _notificationFromMap(Map<String, Object?> item) {
    final String code = _string(item['category']).toUpperCase();
    final bool legacyInteraction =
        code.isEmpty &&
        (item.containsKey('dynamicId') || item.containsKey('notifyType'));
    final NotificationCategory category =
        code == 'SYSTEM' || (!legacyInteraction && code.isEmpty)
        ? NotificationCategory.system
        : NotificationCategory.interaction;
    final String actorName = _string(
      item['actorNickName'] ?? item['nickName'] ?? item['nickname'],
      fallback: '用户',
    );
    final String subjectId = _string(
      item['subjectId'] ??
          item['targetId'] ??
          item['businessId'] ??
          item['dynamicId'],
    );
    final int legacyType = _asInt(item['notifyType']) ?? 0;
    final String id = _requiredString(
      item['notificationId'] ?? item['id'] ?? item['commentId'],
      '通知响应缺少服务端通知 ID',
    );
    final DateTime createdAt = _requiredDateTime(
      item['createdAt'] ?? item['createTime'] ?? item['createDate'],
      '通知响应缺少有效的服务端时间',
    );
    final bool unread = _notificationUnread(item);
    final String title = _string(
      item['title'],
      fallback: legacyInteraction
          ? switch (legacyType) {
              1 => '$actorName 评论了你的动态',
              2 => '$actorName 回复了你的评论',
              _ => '$actorName 赞了你的动态',
            }
          : category == NotificationCategory.system
          ? '系统通知'
          : actorName,
    );
    final bool targetAvailable = subjectId.isNotEmpty;
    return AppNotification(
      id: id,
      category: category,
      title: title,
      summary: _string(
        item['body'] ??
            item['summary'] ??
            item['commentContent'] ??
            item['dynamicContent'] ??
            item['content'],
      ),
      details: _string(
        item['details'] ??
            item['content'] ??
            item['body'] ??
            item['commentContent'],
      ),
      createdAt: createdAt,
      unread: unread,
      targetType: _targetType(
        item['subjectType'] ?? item['targetType'] ?? item['type'],
      ),
      targetId: targetAvailable ? subjectId : null,
      targetAvailable: targetAvailable,
      unavailableReason: targetAvailable ? '' : '通知目标已删除或不可见',
      actorUserId: _asInt(item['actorUserId'] ?? item['userId']),
      actorName: actorName,
    );
  }

  static bool _notificationUnread(Map<String, Object?> item) {
    final bool? read = item.containsKey('read')
        ? _requiredNotificationBool(item['read'], field: 'read')
        : null;
    final bool? isRedPoint = item.containsKey('isRedPoint')
        ? _requiredNotificationBool(item['isRedPoint'], field: 'isRedPoint')
        : null;
    if (read == null && isRedPoint == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '通知响应缺少明确的 read 或 isRedPoint 真值',
      );
    }
    if (read != null && isRedPoint != null && (!read) != isRedPoint) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '通知响应的 read 与 isRedPoint 状态不一致',
      );
    }
    return read == null ? isRedPoint! : !read;
  }

  static bool _requiredNotificationBool(
    Object? value, {
    required String field,
  }) {
    if (value is bool) {
      return value;
    }
    if (value is int && (value == 0 || value == 1)) {
      return value == 1;
    }
    final String text = value?.toString().trim().toLowerCase() ?? '';
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '通知响应的 $field 不是明确布尔值',
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
    final Object? source = map['list'];
    if (source is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端响应缺少冻结契约要求的 list',
      );
    }
    return _asMapList(source);
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端对象包含无效字段名',
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Map<String, Object?>> _asMapList(Object? value) {
    if (value is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端响应列表结构无法识别',
      );
    }
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Object? item in value) {
      if (item is! Map) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端列表包含无效记录',
        );
      }
      result.add(_asMap(item));
    }
    return result;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _compareUpdatedAt(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return -1;
    }
    if (right == null) {
      return 1;
    }
    return left.compareTo(right);
  }

  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static String _sendFingerprint({
    required int targetUserId,
    required String content,
    required String messageType,
  }) {
    return jsonEncode(<String, Object?>{
      'targetUserId': targetUserId,
      'content': content,
      'messageType': messageType,
    });
  }

  static int _requiredPageInt(
    Object? value, {
    required String field,
    required bool allowZero,
  }) {
    final int? parsed = _asInt(value);
    if (parsed == null || parsed < (allowZero ? 0 : 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息会话分页 $field 不是有效服务端数字',
      );
    }
    return parsed;
  }

  static bool _requiredBool(Object? value, {required String field}) {
    if (value is bool) {
      return value;
    }
    if (value is int && (value == 0 || value == 1)) {
      return value == 1;
    }
    final String text = value?.toString().trim().toLowerCase() ?? '';
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '消息会话分页 $field 不是明确布尔值',
    );
  }

  static bool _requiredStrictBool(Object? value, {required String field}) {
    if (value is bool) {
      return value;
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '消息同步响应的 $field 必须为布尔值',
    );
  }

  static int _requiredPositiveInt(Object? value, {required String field}) {
    final int? parsed = _asInt(value);
    if (parsed == null || parsed <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应的 $field 不是有效正整数',
      );
    }
    return parsed;
  }

  static int _requiredNonNegativeInt(Object? value, {required String field}) {
    final int? parsed = _asInt(value);
    if (parsed == null || parsed < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应的 $field 不是有效非负整数',
      );
    }
    return parsed;
  }

  static int _requiredExplicitNonNegativeInt(
    Object? value, {
    required String field,
  }) {
    if (value is! int || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应的 $field 必须为显式非负整数',
      );
    }
    return value;
  }

  static String _requiredCursor(Object? value, {required String field}) {
    if (value is! String) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应的 $field 不是有效游标字符串',
      );
    }
    return value.trim();
  }

  static String _requiredString(Object? value, String message) {
    final String text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw ApiException(kind: ApiFailureKind.protocol, message: message);
    }
    return text;
  }

  static DateTime _requiredDateTime(Object? value, String message) {
    if (value is DateTime) {
      return value;
    }
    final String text = value?.toString().trim() ?? '';
    final DateTime? parsed = text.isEmpty ? null : DateTime.tryParse(text);
    if (parsed == null) {
      throw ApiException(kind: ApiFailureKind.protocol, message: message);
    }
    return parsed;
  }

  static bool _asBool(Object? value) =>
      value == true ||
      value == 1 ||
      value?.toString() == '1' ||
      value?.toString().toLowerCase() == 'true';
}

class _PendingMessageSend {
  const _PendingMessageSend({required this.fingerprint, required this.future});

  final String fingerprint;
  final Future<ChatMessage> future;
}

class _PendingMessageWrite {
  const _PendingMessageWrite({required this.requestId, required this.future});

  final String requestId;
  final Future<Object?> future;
}

class _ConversationPage {
  const _ConversationPage({
    required this.items,
    required this.current,
    required this.pageSize,
    required this.total,
    required this.pages,
    required this.hasMore,
  });

  final List<Map<String, Object?>> items;
  final int current;
  final int pageSize;
  final int total;
  final int pages;
  final bool hasMore;
}
