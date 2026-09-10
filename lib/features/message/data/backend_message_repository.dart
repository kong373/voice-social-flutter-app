import 'dart:convert';
import '../domain/private_history.dart';
import '../../account/domain/user_avatar_descriptor.dart';

import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_request_id.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';

class BackendMessageRepository
    implements
        MessageRepository,
        PagedPrivateMessageRepository,
        ClearablePrivateHistoryRepository,
        MediaPrivateMessageRepository {
  BackendMessageRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required int Function() currentUserIdProvider,
    int Function()? identityGenerationProvider,
    NativePermissionAdapter? nativePermissionAdapter,
    bool Function()? privateRealtimeAvailabilityProvider,
  }) : _apiClient = apiClient,
       _routes = routes,
       _currentUserIdProvider = currentUserIdProvider,
       _identityGenerationProvider = identityGenerationProvider,
       _nativePermissionAdapter = nativePermissionAdapter,
       _privateRealtimeAvailabilityProvider =
           privateRealtimeAvailabilityProvider;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int Function() _currentUserIdProvider;
  final int Function()? _identityGenerationProvider;
  _PrivateHistorySession? _historySession;

  _PrivateHistorySession _captureHistory() {
    final identity = (
      _currentUserIdProvider(),
      _identityGenerationProvider?.call() ?? 0,
    );
    if (identity.$1 <= 0) throw _changedIdentity;
    if (_historySession?.identity != identity) {
      _historySession = _PrivateHistorySession(identity);
    }
    return _historySession!;
  }

  static const _changedIdentity = ApiException(
    kind: ApiFailureKind.unauthorized,
    message: '登录状态已改变，请重新进入会话。',
  );
  void _requireHistory(_PrivateHistorySession scope) {
    if (scope.identity !=
        (_currentUserIdProvider(), _identityGenerationProvider?.call() ?? 0)) {
      throw _changedIdentity;
    }
  }

  @override
  PrivateHistoryState get privateHistory => _captureHistory();
  @override
  bool hasPendingHistoryClear(int targetUserId) =>
      _captureHistory().clears.containsKey(targetUserId);

  @override
  Future<void> clearPrivateHistory(ConversationSummary conversation) async {
    final scope = _captureHistory();
    if (conversation.isDraft || conversation.targetUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '尚未建立可清空的会话',
      );
    }
    // Peer availability is deliberately NOT required to clear one's own copy.
    final intent = scope.clears.putIfAbsent(
      conversation.targetUserId,
      () => _HistoryClearIntent(createMessageRequestId()),
    );
    final flight = intent.flight ??= _clearHistory(scope, intent, conversation);
    try {
      await flight;
      _requireHistory(scope);
    } finally {
      if (identical(intent.flight, flight)) intent.flight = null;
    }
  }

  Future<void> _clearHistory(
    _PrivateHistorySession scope,
    _HistoryClearIntent intent,
    ConversationSummary conversation,
  ) async {
    try {
      final response = await _apiClient.postBoundToIdentity(
        _routes.clearPrivateHistory,
        requireIdentity: () => _requireHistory(scope),
        headers: {'X-Request-Id': intent.requestId},
        body: {'targetUserId': conversation.targetUserId},
      );
      _requireHistory(scope);
      final data = _asMap(response.data);
      if (data['conversationId'] != conversation.id ||
          data['targetUserId'] is! int ||
          data['targetUserId'] != conversation.targetUserId) {
        throw privateHistoryProtocol;
      }
      final mark = PrivateHistoryWatermark.parse(data);
      if (mark.version == BigInt.zero) throw privateHistoryProtocol;
      scope.accept(conversation.targetUserId, mark);
      scope.clears.remove(conversation.targetUserId);
    } catch (error) {
      _requireHistory(scope);
      if (!_isAmbiguousMessageWriteError(error))
        scope.clears.remove(conversation.targetUserId);
      rethrow;
    }
  }

  final NativePermissionAdapter? _nativePermissionAdapter;
  final bool Function()? _privateRealtimeAvailabilityProvider;
  final Map<String, AppNotification> _notificationCache =
      <String, AppNotification>{};
  final Map<NotificationCategory, int> _notificationFetchVersions =
      <NotificationCategory, int>{};
  final Map<String, _PendingMessageWrite> _inFlightWrites =
      <String, _PendingMessageWrite>{};
  final Map<String, String> _ambiguousWriteRequestIds = <String, String>{};
  final Map<String, _PendingMessageSend> _inFlightSends =
      <String, _PendingMessageSend>{};
  // Weak scope keys: intents survive an unknown result while its owner lives,
  // without retaining abandoned account generations or sharing their Futures.
  final _mediaSendIntents = Expando<Map<String, _MediaMessageIntent>>();
  DateTime? _lastSyncAt;

  static const String _privateMessageType = 'TEXT';
  static const int _maximumPageSize = 100;
  static const int _maximumBackendPages = 100;

  void _checkMediaIdentity(MediaIdentityScope identity) {
    identity.check();
    if (identity.userId != _currentUserIdProvider()) {
      identity.dispose();
      throw MediaIdentityScope.invalid;
    }
  }

  @override
  Future<ChatMessage> sendPrivateMediaMessage({
    required ConversationSummary conversation,
    required MediaReference media,
    required MediaIdentityScope identity,
    required String requestId,
  }) async {
    _checkMediaIdentity(identity);
    if (!conversation.available || conversation.targetUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '当前会话暂不可发送消息',
      );
    }
    final type = ChatMessageType.values.firstWhere(
      (type) => type.mediaPurpose == media.purpose,
      orElse: () => throw mediaProtocol(),
    );
    // Unlike text drafts, media retries may never silently mint a new key.
    if (requestId.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '媒体发送必须保留原请求 ID',
      );
    }
    final key = normalizeMessageRequestId(requestId);
    final fingerprint = jsonEncode({
      'targetUserId': conversation.targetUserId,
      'messageType': type.wire,
      'media': media.toJson(),
    });
    final intents = _mediaSendIntents[identity] ??=
        <String, _MediaMessageIntent>{};
    final intent = intents.putIfAbsent(
      key,
      () => _MediaMessageIntent(fingerprint),
    );
    if (intent.fingerprint != fingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '同一请求 ID 不能替换媒体或接收者',
      );
    }
    final flight = intent.flight ??= _sendPrivateMedia(
      conversation: conversation,
      media: media,
      type: type,
      identity: identity,
      requestId: key,
    );
    try {
      final message = await identity.wait(flight);
      _checkMediaIdentity(identity);
      return message;
    } catch (_) {
      // Neither success nor an error from an old actor may reach the new one.
      _checkMediaIdentity(identity);
      rethrow;
    } finally {
      if (identical(intent.flight, flight)) intent.flight = null;
    }
  }

  Future<ChatMessage> _sendPrivateMedia({
    required ConversationSummary conversation,
    required MediaReference media,
    required ChatMessageType type,
    required MediaIdentityScope identity,
    required String requestId,
  }) async {
    final scope = _captureHistory();
    final response = await identity.wait(
      _apiClient.postBoundToIdentity(
        _routes.sendPrivateMessage,
        requireIdentity: () => _checkMediaIdentity(identity),
        headers: {'X-Request-Id': requestId},
        body: {
          'targetUserId': conversation.targetUserId,
          'messageType': type.wire,
          'mediaAssetId': media.assetId,
        },
      ),
    );
    _checkMediaIdentity(identity);
    final row = _asMap(response.data);
    if (row['senderUserId'] is! int ||
        row['senderUserId'] != identity.userId ||
        row['receiverUserId'] is! int ||
        row['receiverUserId'] != conversation.targetUserId ||
        row['messageType'] != type.wire ||
        row['content'] != '') {
      throw mediaProtocol();
    }
    final message = _chatMessageFromMap(
      conversation,
      row,
      authoritativeConversationId: conversation.id,
    );
    if (message.media == null ||
        jsonEncode(message.media!.toJson()) != jsonEncode(media.toJson())) {
      throw mediaProtocol();
    }
    _acceptSentMessage(scope, conversation, row, message);
    return message;
  }

  @override
  bool get supportsConversationList => true;

  @override
  bool get supportsPrivateHistory => true;

  @override
  bool get supportsPrivateSend => true;

  @override
  bool get supportsPrivateRealtime =>
      _privateRealtimeAvailabilityProvider?.call() ?? false;

  @override
  bool get supportsSystemNotificationList => true;

  @override
  bool get supportsNativeNotificationPermission =>
      _nativePermissionAdapter != null;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    final scope = _captureHistory();
    final List<ConversationSummary> conversations = <ConversationSummary>[];
    var pageNum = 1;
    int? expectedTotal;
    int? expectedPages;
    var hasMore = true;
    while (hasMore && pageNum <= _maximumBackendPages) {
      final ApiResponse response = await _apiClient.getBoundToIdentity(
        _routes.messageConversations,
        requireIdentity: () => _requireHistory(scope),
        query: <String, String>{
          'pageNum': '$pageNum',
          'pageSize': '$_maximumPageSize',
        },
      );
      _requireHistory(scope);
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
      for (final item in page.items) {
        final row = _conversationFromMap(item);
        final current = scope.accept(
          row.targetUserId,
          PrivateHistoryWatermark.parse(item),
        );
        conversations.add(
          current
              ? scope.project(row)
              : row.copyWith(
                  lastMessage: '',
                  unreadCount: 0,
                  clearUpdatedAt: true,
                ),
        );
      }
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
    _requireHistory(scope);
    return conversations.map(scope.project).toList();
  }

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async => (await _fetchPrivateMessages(
    conversation,
    isCurrent: () => true,
  )).messages;

  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessages(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    Set<String> knownMessageIds = const <String>{},
    String? resumeCursor,
  }) => _fetchPrivateMessages(
    conversation,
    isCurrent: isCurrent,
    knownMessageIds: knownMessageIds,
    resumeCursor: resumeCursor,
    allowBoundedWindow: true,
  );

  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessagePage(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    String? cursor,
  }) => _fetchPrivateMessages(
    conversation,
    isCurrent: isCurrent,
    resumeCursor: cursor,
    allowBoundedWindow: true,
    maximumPages: 1,
    markRead: false,
  );

  Future<PrivateMessageSyncBatch> _fetchPrivateMessages(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    Set<String> knownMessageIds = const <String>{},
    String? resumeCursor,
    bool allowBoundedWindow = false,
    int maximumPages = _maximumBackendPages,
    bool markRead = true,
  }) async {
    final scope = _captureHistory();
    bool active() =>
        isCurrent() &&
        scope.identity ==
            (
              _currentUserIdProvider(),
              _identityGenerationProvider?.call() ?? 0,
            );
    if (!active()) return const PrivateMessageSyncBatch([]);
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
    String? cursor = resumeCursor;
    var hasMore = true;
    var fetchedPages = 0;
    while (hasMore && fetchedPages < maximumPages) {
      fetchedPages += 1;
      final Map<String, String> query = <String, String>{
        'targetUserId': '${conversation.targetUserId}',
        'pageSize': '$_maximumPageSize',
        if (cursor != null) 'cursor': cursor,
      };
      final ApiResponse response = await _apiClient.getBoundToIdentity(
        _routes.privateChatHistory,
        requireIdentity: () => _requireHistory(scope),
        query: query,
      );
      if (!active()) return const PrivateMessageSyncBatch([]);
      final Map<String, Object?> data = _asMap(response.data);
      final mark = PrivateHistoryWatermark.parse(data);
      if (data['targetUserId'] is! int ||
          data['targetUserId'] != conversation.targetUserId ||
          data['conversationId'] is! String) {
        throw privateHistoryProtocol;
      }
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
        if (mark.version != BigInt.zero || mark.through != BigInt.zero)
          throw privateHistoryProtocol;
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
      if (maximumPages == 1 && hasMore) {
        final nextId = BigInt.tryParse(nextCursor);
        final previousId = cursor == null ? null : BigInt.tryParse(cursor);
        if (nextId == null ||
            nextId <= BigInt.zero ||
            (cursor != null && (previousId == null || nextId >= previousId))) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊历史分页游标必须为递减的正整数',
          );
        }
      }
      if (pageConversationId != null) {
        final int targetUserId = _requiredPositiveInt(
          data['targetUserId'],
          field: 'targetUserId',
        );
        final MessageImStatus historyImStatus = _requiredMessageImStatus(
          data['imStatus'],
          context: '私聊历史响应',
        );
        final bool providerInvocation = _requiredBool(
          data['providerInvocation'],
          field: 'providerInvocation',
        );
        if (targetUserId != conversation.targetUserId ||
            !_isTrustedMessageStatusBoundary(
              historyImStatus,
              providerInvocation,
            )) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '私聊历史响应的会话权限或 IM 投递状态不可信',
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
      if (!scope.accept(conversation.targetUserId, mark)) {
        return const PrivateMessageSyncBatch([]);
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
      // queryChat is newest-first (id DESC). Once the page overlaps the
      messages.removeWhere(
        (item) => !scope.visible(conversation.targetUserId, item),
      );
      // visible snapshot, all unseen newer messages have been collected.
      // Keep the entire overlap page so delivery/read projections can update.
      if (knownMessageIds.isNotEmpty &&
          messages.any((item) => knownMessageIds.contains(item.id))) {
        hasMore = false;
      }
      if (hasMore) {
        seenCursors.add(nextCursor);
        cursor = nextCursor;
      }
    }
    if (hasMore && !allowBoundedWindow) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '私聊历史超过客户端安全分页上限',
      );
    }
    // The server uses id DESC across cursor pages. Reverse that order for
    // equal timestamps instead of relying on Dart's unstable List.sort.
    final ordered = messages.asMap().entries.toList()
      ..sort((left, right) {
        final byTime = left.value.createdAt.compareTo(right.value.createdAt);
        return byTime != 0 ? byTime : right.key.compareTo(left.key);
      });
    messages
      ..clear()
      ..addAll(ordered.map((entry) => entry.value));
    if (hasMore) {
      // Publish the newest bounded batch without marking unseen older rows
      // read. The visible page owns and accepts the continuation cursor.
      return PrivateMessageSyncBatch(
        messages,
        nextCursor: cursor,
        conversationId: authoritativeConversationId,
      );
    }
    if (markRead)
      await markVisiblePrivateMessagesRead(conversation, isCurrent: active);
    messages.removeWhere(
      (item) => !scope.visible(conversation.targetUserId, item),
    );
    return active()
        ? PrivateMessageSyncBatch(
            messages,
            conversationId: authoritativeConversationId,
          )
        : const PrivateMessageSyncBatch([]);
  }

  @override
  Future<void> markVisiblePrivateMessagesRead(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
  }) async {
    final scope = _captureHistory();
    bool active() =>
        isCurrent() &&
        scope.identity ==
            (
              _currentUserIdProvider(),
              _identityGenerationProvider?.call() ?? 0,
            );
    // Entering a conversation is the first-party read boundary.  Provider
    // delivery remains represented by the response-level status mapping; this
    // HTTP read never treats a provider callback as message content.
    if (!active()) return;
    await _runStableMessageWrite<void>(
      intent: 'private-read:${scope.identity}:${conversation.targetUserId}',
      action: (Map<String, String> headers) async {
        if (!active()) return;
        final ApiResponse readResponse = await _apiClient.postBoundToIdentity(
          _routes.markPrivateMessageRead,
          requireIdentity: () => _requireHistory(scope),
          headers: headers,
          body: <String, Object?>{'targetUserId': conversation.targetUserId},
        );
        _requireHistory(scope);
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
        scope.accept(
          conversation.targetUserId,
          PrivateHistoryWatermark.parse(readData),
        );
      },
    );
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async {
    final scope = _captureHistory();
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
    final scopedKey = '${scope.identity}:$key';
    final String fingerprint = _sendFingerprint(
      targetUserId: conversation.targetUserId,
      content: normalizedContent,
      messageType: _privateMessageType,
    );
    final _PendingMessageSend? pending = _inFlightSends[scopedKey];
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
      scope: scope,
      key: scopedKey,
      requestId: key,
      conversation: conversation,
      content: normalizedContent,
    );
    _inFlightSends[scopedKey] = _PendingMessageSend(
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
        'category': category == NotificationCategory.system
            ? 'SYSTEM'
            : 'INTERACTION',
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
        final MessageImStatus syncImStatus = _requiredMessageImStatus(
          imStatus,
          context: '通知同步响应',
        );
        if (!synced ||
            projectionStatus != 'FIRST_PARTY_MATERIALIZED' ||
            pushStatus != 'VENDOR_BLOCKED' ||
            !_isTrustedMessageStatusBoundary(
              syncImStatus,
              providerInvocation,
            ) ||
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
        final MessageImStatus clearImStatus = _requiredMessageImStatus(
          data['imStatus'],
          context: '清空互动通知响应',
        );
        final bool clearProviderInvocation = _requiredBool(
          data['providerInvocation'],
          field: 'providerInvocation',
        );
        if (!_isTrustedMessageStatusBoundary(
          clearImStatus,
          clearProviderInvocation,
        )) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '清空互动通知响应的 IM 投递状态不可信',
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
    final bool privateRealtimeAvailable = supportsPrivateRealtime;
    const String unavailableRealtimeMessage = '实时消息暂不可用，消息记录仍可查看。';
    return MessageRecoverySnapshot(
      privateRealtimeAvailable: privateRealtimeAvailable,
      notificationPermission: notificationPermission,
      lastNotificationSyncAt: _lastSyncAt,
      message:
          notificationPermission ==
              NativeNotificationPermissionState.unavailable
          ? privateRealtimeAvailable
                ? '实时消息已连接，当前无法获取系统通知权限状态。'
                : '当前无法获取系统通知权限状态。$unavailableRealtimeMessage'
          : privateRealtimeAvailable
          ? '实时消息已连接，系统通知权限状态如下。'
          : '系统通知权限状态如下。$unavailableRealtimeMessage',
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
    final type = item.containsKey('messageType')
        ? ChatMessageType.values.firstWhere(
            (type) => type.wire == item['messageType'],
            orElse: () => throw mediaProtocol(),
          )
        : ChatMessageType.text;
    final MediaReference? media = _privateMessageMedia(item, type);
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
    if (media != null &&
        (item['senderUserId'] is! int ||
            item['receiverUserId'] is! int ||
            senderId != (mine ? currentUserId : conversation.targetUserId) ||
            item['receiverUserId'] !=
                (mine ? conversation.targetUserId : currentUserId))) {
      throw mediaProtocol();
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
    final _ParsedMessageStatus parsedStatus = _statusFromMap(
      item,
      isMine: mine,
    );
    final String? conversationId =
        authoritativeConversationId ??
        (itemConversationId.isEmpty ? conversation.id : itemConversationId);
    final Object? rawRead = item['read'];
    final Object? rawReadAt = item['readAt'];
    DateTime? readAt;
    if (rawRead != null && rawRead is! bool) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '私聊 read 必须为布尔值',
      );
    }
    // FirstPartyMessageService.instant(null) serializes exactly "".
    if (rawReadAt != null && rawReadAt != '') {
      // Require an unambiguous server instant; DateTime.parse alone accepts
      // overflowing calendar dates and timezone-less local timestamps.
      if (rawReadAt is! String ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$',
          ).hasMatch(rawReadAt)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊 readAt 必须为 UTC 时间',
        );
      }
      readAt = DateTime.tryParse(rawReadAt);
      if (readAt == null ||
          readAt.toIso8601String().substring(0, 19) !=
              rawReadAt.substring(0, 19) ||
          rawRead == false) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '私聊已读状态或时间不一致',
        );
      }
    }
    return ChatMessage(
      id: id,
      messageSequence: privateSequence(item['messageSequence'], positive: true),
      conversationId: conversationId,
      senderUserId: senderId,
      senderAvatar: UserAvatarDescriptor.parseOptional(item['senderAvatar']),
      receiverAvatar: UserAvatarDescriptor.parseOptional(
        item['receiverAvatar'],
      ),
      senderName: _string(
        item['senderName'] ?? item['nickName'],
        fallback: mine ? '我' : conversation.title,
      ),
      content: _string(item['content'] ?? item['message']),
      createdAt: createdAt,
      isMine: mine,
      status: parsedStatus.status,
      messageType: type,
      media: media,
      deliveryStatus: parsedStatus.deliveryStatus,
      read: readAt != null ? true : rawRead as bool?,
      readAt: readAt,
    );
  }

  static MediaReference? _privateMessageMedia(
    Map<String, Object?> row,
    ChatMessageType type,
  ) {
    final raw = row['media'];
    if (type == ChatMessageType.text) {
      if (row.containsKey('media') && (raw is! List || raw.isNotEmpty))
        throw mediaProtocol();
      return null;
    }
    if (raw is! List || raw.length != 1 || row['content'] != '')
      throw mediaProtocol();
    final media = MediaReference.fromJson(raw.single);
    if (media.purpose != type.mediaPurpose ||
        row['storageStatus'] != 'FIRST_PARTY_STORED')
      throw mediaProtocol();
    final providerInvocation = _requiredStrictBool(
      row['providerInvocation'],
      field: 'providerInvocation',
    );
    final im = _requiredMessageImStatus(row['imStatus'], context: '媒体消息');
    final delivery = _requiredMessageDeliveryStatus(
      row['deliveryStatus'],
      context: '媒体消息',
    );
    if (!_isTrustedMessageStatusBoundary(im, providerInvocation) ||
        !_isTrustedMessageDeliveryBoundary(delivery, providerInvocation))
      throw mediaProtocol();
    return media;
  }

  static _ParsedMessageStatus _statusFromMap(
    Map<String, Object?> item, {
    required bool isMine,
  }) {
    if (!isMine) {
      return _ParsedMessageStatus(
        status: ChatMessageStatus.received,
        deliveryStatus:
            _optionalMessageDeliveryStatus(item['deliveryStatus']) ??
            _optionalMessageDeliveryStatus(item['imStatus']) ??
            MessageDeliveryStatus.unknown,
      );
    }
    final String storageStatus = _string(item['storageStatus']).toUpperCase();
    final Object? rawDeliveryStatus =
        item['deliveryStatus'] ?? item['imStatus'];
    final MessageDeliveryStatus deliveryStatus =
        _optionalMessageDeliveryStatus(rawDeliveryStatus) ??
        (storageStatus == 'FIRST_PARTY_STORED'
            ? MessageDeliveryStatus.vendorBlocked
            : (throw const ApiException(
                kind: ApiFailureKind.protocol,
                message: '消息响应缺少可确认的投递状态',
              )));
    return _ParsedMessageStatus(
      status: switch (deliveryStatus) {
        MessageDeliveryStatus.delivered => ChatMessageStatus.sent,
        MessageDeliveryStatus.failed => ChatMessageStatus.failed,
        MessageDeliveryStatus.pending ||
        MessageDeliveryStatus.processing ||
        MessageDeliveryStatus.retry ||
        MessageDeliveryStatus.unknown ||
        MessageDeliveryStatus.vendorBlocked =>
          ChatMessageStatus.storedPendingDelivery,
      },
      deliveryStatus: deliveryStatus,
    );
  }

  static MessageDeliveryStatus? _optionalMessageDeliveryStatus(Object? value) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      return null;
    }
    final MessageDeliveryStatus? parsed = tryParseMessageDeliveryStatus(value);
    if (parsed == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '消息响应包含无法识别的 IM 投递状态',
      );
    }
    return parsed;
  }

  static MessageDeliveryStatus _requiredMessageDeliveryStatus(
    Object? value, {
    required String context,
  }) {
    final MessageDeliveryStatus? parsed = _optionalMessageDeliveryStatus(value);
    if (parsed == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context 缺少有效的 IM 投递状态',
      );
    }
    return parsed;
  }

  static bool _isTrustedMessageStatusBoundary(
    MessageImStatus status,
    bool providerInvocation,
  ) => status != MessageImStatus.vendorBlocked || !providerInvocation;

  static bool _isTrustedMessageDeliveryBoundary(
    MessageDeliveryStatus status,
    bool providerInvocation,
  ) => status != MessageDeliveryStatus.vendorBlocked || !providerInvocation;

  static MessageImStatus _requiredMessageImStatus(
    Object? value, {
    required String context,
  }) {
    final MessageImStatus? parsed = tryParseMessageImStatus(value);
    if (parsed == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context 缺少有效的 IM 能力状态',
      );
    }
    return parsed;
  }

  Future<ChatMessage> _sendPrivateMessage({
    required _PrivateHistorySession scope,
    required String key,
    required String requestId,
    required ConversationSummary conversation,
    required String content,
  }) async {
    try {
      final ApiResponse response = await _apiClient.postBoundToIdentity(
        _routes.sendPrivateMessage,
        requireIdentity: () => _requireHistory(scope),
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
      _requireHistory(scope);
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
      final MessageDeliveryStatus responseDeliveryStatus =
          _requiredMessageDeliveryStatus(
            message['deliveryStatus'] ?? message['imStatus'],
            context: '发送消息响应',
          );
      if (receiverUserId != conversation.targetUserId ||
          returnedType != _privateMessageType ||
          returnedContent != content ||
          !_isTrustedMessageDeliveryBoundary(
            responseDeliveryStatus,
            providerInvocation,
          )) {
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
          scope,
        );
        if (resolvedId != null) {
          parsed = parsed.copyWith(conversationId: resolvedId);
        }
      }
      _acceptSentMessage(scope, conversation, message, parsed);
      return parsed;
    } finally {
      _inFlightSends.remove(key);
    }
  }

  void _acceptSentMessage(
    _PrivateHistorySession scope,
    ConversationSummary conversation,
    Map<String, Object?> data,
    ChatMessage message,
  ) {
    _requireHistory(scope);
    final current = scope.accept(
      conversation.targetUserId,
      PrivateHistoryWatermark.parse(data),
    );
    if (!scope.visible(conversation.targetUserId, message)) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        code: 40481,
        message: '此消息已清空，请刷新聊天记录',
      );
    }
    if (!current) throw privateHistoryProtocol;
  }

  Future<String?> _resolveDraftConversationId(
    ConversationSummary draft,
    _PrivateHistorySession scope,
  ) async {
    _requireHistory(scope);
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

    _requireHistory(scope);
    try {
      final List<ChatMessage> history = await fetchPrivateMessages(draft);
      return history
          .map((ChatMessage item) => item.conversationId)
          .whereType<String>()
          .where((String id) => id.trim().isNotEmpty)
          .firstOrNull;
    } on ApiException {
      _requireHistory(scope);
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
    final sequence = privateSequence(item['lastMessageSequence']);
    final rawTime = item['lastMessageAt'] ?? item['updatedAt'];
    final DateTime? updatedAt = sequence == BigInt.zero && rawTime == ''
        ? null
        : _requiredDateTime(rawTime, '消息会话响应缺少有效的服务端更新时间');
    final int unreadCount = _requiredExplicitNonNegativeInt(
      item['unreadCount'],
      field: 'unreadCount',
    );
    if (sequence == BigInt.zero &&
        (_string(item['lastMessage'] ?? item['content']).isNotEmpty ||
            unreadCount != 0 ||
            updatedAt != null))
      throw privateHistoryProtocol;
    return ConversationSummary(
      id: id,
      kind: ConversationKind.privateChat,
      title: _string(item['nickName'] ?? item['nickname'], fallback: '用户'),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      avatar: UserAvatarDescriptor.parseOptional(item['avatar']),
      lastMessage: _string(item['lastMessage'] ?? item['content']),
      lastMessageSequence: sequence,
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

class _PrivateHistorySession extends PrivateHistoryState {
  _PrivateHistorySession(this.identity);
  final (int, int) identity;
  final clears = <int, _HistoryClearIntent>{};
}

class _HistoryClearIntent {
  _HistoryClearIntent(this.requestId);
  final String requestId;
  Future<void>? flight;
}

class _MediaMessageIntent {
  _MediaMessageIntent(this.fingerprint);
  final String fingerprint;
  Future<ChatMessage>? flight;
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

class _ParsedMessageStatus {
  const _ParsedMessageStatus({
    required this.status,
    required this.deliveryStatus,
  });

  final ChatMessageStatus status;
  final MessageDeliveryStatus deliveryStatus;
}
