import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  test('message repository exposes current capability boundary', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);
    final BackendMessageRepository repository = harness.repository;
    expect(repository.supportsConversationList, isFalse);
    expect(repository.supportsPrivateHistory, isTrue);
    expect(repository.supportsPrivateSend, isFalse);
    expect(repository.supportsSystemNotificationList, isFalse);
    expect(repository.supportsNativeNotificationPermission, isFalse);
    expect(await repository.fetchConversations(), isEmpty);
    expect(harness.requests, isEmpty);
    final MessageRecoverySnapshot snapshot = await repository
        .fetchRecoverySnapshot();
    expect(snapshot.privateRealtimeAvailable, isFalse);
    expect(
      snapshot.notificationPermission,
      NativeNotificationPermissionState.unavailable,
    );
    expect(snapshot.message, contains('腾讯 IM'));
    await expectLater(
      repository.requestNotificationPermission(),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
  });

  test(
    'message private history posts exact body and sorts ascending',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'records': <Object?>[
            <String, Object?>{
              'msgId': 'msg-2',
              'senderUserId': 99,
              'nickName': '对方',
              'message': '第二条',
              'createTime': '2026-08-21T10:02:00Z',
            },
            <String, Object?>{
              'msgId': 'msg-1',
              'senderUserId': 10001,
              'senderName': '晚星',
              'content': '第一条',
              'createTime': '2026-08-21T10:01:00Z',
            },
          ],
        });
      });
      addTearDown(harness.close);
      final BackendMessageRepository repository = harness.repository;
      final ConversationSummary conversation = ConversationSummary(
        id: 'conversation-99',
        kind: ConversationKind.privateChat,
        title: '对方',
        lastMessage: '',
        updatedAt: DateTime(2026, 8, 21),
        unreadCount: 0,
        targetUserId: 99,
      );
      final List<ChatMessage> messages = await repository.fetchPrivateMessages(
        conversation,
      );
      expect(messages.map((ChatMessage item) => item.id), <String>[
        'msg-1',
        'msg-2',
      ]);
      expect(messages.first.isMine, isTrue);
      expect(messages.last.status, ChatMessageStatus.received);
      expect(harness.requests.single.method, 'POST');
      expect(harness.requests.single.path, '/app-api/user/imMessage/queryChat');
      expect(harness.requests.single.body, <String, Object?>{
        'otherUserId': 99,
        'pageNum': 1,
        'pageSize': 100,
      });
    },
  );

  test(
    'message private history rejects unavailable conversation and sending is disabled',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);
      final BackendMessageRepository repository = harness.repository;
      final ConversationSummary unavailable = ConversationSummary(
        id: 'conversation-unavailable',
        kind: ConversationKind.privateChat,
        title: '不可用',
        lastMessage: '',
        updatedAt: DateTime(2026),
        unreadCount: 0,
        targetUserId: 0,
        available: false,
        unavailableReason: '目标用户不可用',
      );
      await expectLater(
        repository.fetchPrivateMessages(unavailable),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await expectLater(
        repository.sendPrivateMessage(
          conversation: unavailable,
          content: '不会发送',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      expect(harness.requests, isEmpty);
    },
  );

  test(
    'message interaction notifications parse, cache, mark read, and clear locally',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/dynamic/queryUserDynamicNotify' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'id': 'notify-1',
                  'notifyType': 1,
                  'nickName': '南风',
                  'commentContent': '很棒',
                  'dynamicId': 'dynamic-1',
                  'isRedPoint': 1,
                  'createDate': '2026-08-21T10:00:00Z',
                  'userId': 99,
                },
              ],
            },
          ),
          '/app-api/dynamic/emptyUserDynamicNotify' => _Response.ok(
            <String, Object?>{},
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendMessageRepository repository = harness.repository;
      final List<AppNotification> notifications = await repository
          .fetchNotifications(NotificationCategory.interaction);
      expect(notifications.single.title, '南风 评论了你的动态');
      expect(notifications.single.unread, isTrue);
      expect(notifications.single.targetId, 'dynamic-1');
      expect(
        notifications.single.targetType,
        NotificationTargetType.dynamicPost,
      );

      final AppNotification cached = await repository.fetchNotification(
        'notify-1',
      );
      expect(cached.unread, isTrue);
      await repository.markNotificationRead('notify-1');
      final AppNotification read = await repository.fetchNotification(
        'notify-1',
      );
      expect(read.unread, isFalse);
      await repository.clearInteractionNotifications();
      expect(harness.requests[0].body, <String, Object?>{
        'pageNum': 1,
        'pageSize': 100,
      });
      expect(harness.requests[1].method, 'POST');
      await expectLater(
        repository.fetchNotification('notify-1'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
    },
  );

  test(
    'message system notification detail uses push id and caches response',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'title': '系统公告',
          'summary': '版本更新',
          'content': '请查看详情',
          'createTime': '2026-08-21T10:00:00Z',
          'targetType': 1,
          'targetId': 'room-7',
        });
      });
      addTearDown(harness.close);
      final BackendMessageRepository repository = harness.repository;
      final AppNotification notification = await repository.fetchNotification(
        'push-77',
      );
      expect(notification.category, NotificationCategory.system);
      expect(notification.title, '系统公告');
      expect(notification.details, '请查看详情');
      expect(notification.targetType, NotificationTargetType.room);
      expect(notification.targetId, 'room-7');
      expect((await repository.fetchNotification('push-77')).id, 'push-77');
      expect(harness.requests, hasLength(1));
      expect(harness.requests.single.method, 'GET');
      expect(harness.requests.single.query, <String, String>{'id': '77'});
    },
  );

  test(
    'message system notification list is explicitly empty without a request',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);
      expect(
        await harness.repository.fetchNotifications(
          NotificationCategory.system,
        ),
        isEmpty,
      );
      expect(harness.requests, isEmpty);
    },
  );

  test(
    'message error envelope preserves validation status and message',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return const _Response(
          statusCode: 429,
          code: 429,
          message: '通知请求过于频繁',
          data: null,
        );
      });
      addTearDown(harness.close);
      await expectLater(
        harness.repository.fetchNotifications(NotificationCategory.interaction),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiFailureKind.business,
              )
              .having((ApiException e) => e.httpStatus, 'httpStatus', 429)
              .having((ApiException e) => e.message, 'message', '通知请求过于频繁'),
        ),
      );
    },
  );
}

class _Harness {
  _Harness._(this.server, this.requests)
    : repository = BackendMessageRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendMessageRepository repository;

  static Future<_Harness> start(
    FutureOr<_Response> Function(RequestRecord) handler,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final _Harness harness = _Harness._(server, requests);
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        authorization: captureContractAuthorization(request),
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Response response = await handler(record);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': response.code,
          'message': response.message,
          'data': response.data,
        }),
      );
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String authorization;
  final Object? body;
}

class _Response {
  const _Response({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Response.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}
