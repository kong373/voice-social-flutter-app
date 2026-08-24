import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  test('message repository exposes first-party capability boundary', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);
    final BackendMessageRepository repository = harness.repository;
    expect(repository.supportsConversationList, isTrue);
    expect(repository.supportsPrivateHistory, isTrue);
    expect(repository.supportsPrivateSend, isTrue);
    expect(repository.supportsPrivateRealtime, isFalse);
    expect(repository.supportsSystemNotificationList, isTrue);
    expect(repository.supportsNativeNotificationPermission, isFalse);
    final MessageRecoverySnapshot snapshot = await repository
        .fetchRecoverySnapshot();
    expect(snapshot.privateRealtimeAvailable, isFalse);
    expect(
      snapshot.notificationPermission,
      NativeNotificationPermissionState.unavailable,
    );
    expect(snapshot.message, contains('VENDOR_BLOCKED'));
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
    'live message recovery reads and requests native notification permission',
    () async {
      final _FakeNativePermissionAdapter adapter = _FakeNativePermissionAdapter(
        PermissionState.denied,
      );
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{}),
        nativePermissionAdapter: adapter,
      );
      addTearDown(harness.close);

      expect(harness.repository.supportsNativeNotificationPermission, isTrue);
      expect(
        (await harness.repository.fetchRecoverySnapshot())
            .notificationPermission,
        NativeNotificationPermissionState.denied,
      );
      adapter.state = PermissionState.granted;
      expect(
        (await harness.repository.requestNotificationPermission())
            .notificationPermission,
        NativeNotificationPermissionState.allowed,
      );
      await harness.repository.openNotificationSettings();
      expect(adapter.requested, 1);
      expect(adapter.openedSettings, 1);
    },
  );

  test(
    'conversation list uses page map and exact first-party GET contract',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.method, 'GET');
        expect(request.path, '/app-mini-api/mini/v1/message/conversations');
        expect(request.query, <String, String>{
          'pageNum': '1',
          'pageSize': '100',
        });
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'conversationId': 'conversation-99',
              'targetUserId': 99,
              'nickName': '对方',
              'headImgUrl': 'https://example.test/avatar.png',
              'lastMessage': '第二条',
              'lastMessageAt': '2026-08-21T10:02:00Z',
              'unreadCount': 2,
            },
            <String, Object?>{
              'conversationId': 'conversation-88',
              'targetUserId': 88,
              'nickName': '晚星',
              'lastMessage': '第一条',
              'lastMessageAt': '2026-08-21T10:01:00Z',
              'unreadCount': 0,
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 2,
          'pages': 1,
          'hasMore': false,
        });
      });
      addTearDown(harness.close);
      final List<ConversationSummary> conversations = await harness.repository
          .fetchConversations();
      expect(conversations, hasLength(2));
      expect(conversations.first.targetUserId, 99);
      expect(conversations.first.title, '对方');
      expect(conversations.first.unreadCount, 2);
      expect(conversations.first.avatarUrl, 'https://example.test/avatar.png');
    },
  );

  test(
    'conversation list fetches every page before applying updated-time order',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int page = int.parse(request.query['pageNum']!);
        expect(request.query['pageSize'], '100');
        return _Response.ok(
          _conversationPage(
            page: page,
            hasMore: page == 1,
            total: 101,
            pages: 2,
            itemCount: page == 1 ? 100 : 1,
          ),
        );
      });
      addTearDown(harness.close);

      final List<ConversationSummary> conversations = await harness.repository
          .fetchConversations();

      expect(
        conversations
            .map((ConversationSummary item) => item.targetUserId)
            .take(2),
        <int>[2, 1],
      );
      expect(conversations, hasLength(101));
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test('conversation pagination rejects a short non-final page', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      final int page = int.parse(request.query['pageNum']!);
      return _Response.ok(
        _conversationPage(
          page: page,
          hasMore: page == 1,
          total: 101,
          pages: 2,
          itemCount: page == 1 ? 1 : 1,
        ),
      );
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchConversations(),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            )
            .having(
              (ApiException error) => error.message,
              'message',
              contains('短页'),
            ),
      ),
    );
    expect(harness.requests, hasLength(1));
  });

  test(
    'conversation pagination rejects a final page with missing records',
    () async {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(
          _conversationPage(
            page: 1,
            hasMore: false,
            total: 2,
            pages: 1,
            itemCount: 1,
          ),
        ),
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchConversations(),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('累计'),
              ),
        ),
      );
    },
  );

  test(
    'conversation unreadCount must be an explicit non-negative integer',
    () async {
      for (final Object? unreadCount in <Object?>[null, '1', -1, true]) {
        final _Harness harness = await _Harness.start(
          (_) => _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'conversationId': 'conversation-unread',
                'targetUserId': 99,
                'nickName': '对方',
                'lastMessage': '未读数',
                'lastMessageAt': '2026-08-21T10:02:00Z',
                if (unreadCount != null) 'unreadCount': unreadCount,
              },
            ],
            'pageNum': 1,
            'pageSize': 100,
            'total': 1,
            'pages': 1,
            'hasMore': false,
          }),
        );
        try {
          await expectLater(
            harness.repository.fetchConversations(),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
            reason: 'unreadCount=$unreadCount',
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test('conversation list rejects missing server identity or time', () async {
    for (final Map<String, Object?> item in <Map<String, Object?>>[
      <String, Object?>{
        'targetUserId': 99,
        'lastMessageAt': '2026-08-21T10:02:00Z',
      },
      <String, Object?>{
        'conversationId': 'conversation-99',
        'targetUserId': 99,
      },
    ]) {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{
          'list': <Object?>[item],
          'pageNum': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
          'hasMore': false,
        }),
      );
      try {
        await expectLater(
          harness.repository.fetchConversations(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await harness.close();
      }
    }
  });

  test(
    'conversation pagination rejects an empty page that still has more',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int page = int.parse(request.query['pageNum']!);
        if (page > 1) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected extra request',
            data: null,
          );
        }
        return _Response.ok(
          _conversationPage(page: page, hasMore: true, empty: true),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchConversations(),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('空'),
              ),
        ),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'conversation pagination rejects a page number that makes no progress',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int page = int.parse(request.query['pageNum']!);
        if (page > 2) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected extra request',
            data: null,
          );
        }
        return _Response.ok(
          _conversationPage(
            page: page,
            reportedPage: 1,
            hasMore: true,
            total: 101,
            pages: 2,
            itemCount: 100,
          ),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchConversations(),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('页码'),
              ),
        ),
      );
      expect(harness.requests, hasLength(2));
    },
  );

  test('conversation pagination stops at the maximum page limit', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      final int page = int.parse(request.query['pageNum']!);
      if (page > 100) {
        return const _Response(
          statusCode: 500,
          code: 500,
          message: 'unexpected request past page limit',
          data: null,
        );
      }
      return _Response.ok(
        _conversationPage(
          page: page,
          hasMore: true,
          total: 10001,
          pages: 101,
          itemCount: 100,
        ),
      );
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchConversations(),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            )
            .having(
              (ApiException error) => error.message,
              'message',
              contains('上限'),
            ),
      ),
    );
    expect(harness.requests, hasLength(1));
    expect(harness.requests.last.query['pageNum'], '1');
  });

  test(
    'conversation page metadata must match the requested page contract',
    () async {
      final List<Map<String, Object?>> invalidPages = <Map<String, Object?>>[
        <String, Object?>{
          'pageNum': 1,
          'pageSize': 99,
          'total': 0,
          'pages': 0,
          'hasMore': false,
        },
        <String, Object?>{
          'pageNum': 1,
          'pageSize': 100,
          'total': -1,
          'pages': 0,
          'hasMore': false,
        },
        <String, Object?>{
          'pageNum': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 1,
          'hasMore': false,
        },
        <String, Object?>{
          'pageNum': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
          'hasMore': false,
        },
      ];
      for (final Map<String, Object?> metadata in invalidPages) {
        final _Harness harness = await _Harness.start(
          (_) =>
              _Response.ok(<String, Object?>{'list': <Object?>[], ...metadata}),
        );
        try {
          await expectLater(
            harness.repository.fetchConversations(),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'b709 conversation pages succeed without an optional pages field',
    () async {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'conversationId': 'conversation-b709',
              'targetUserId': 99,
              'nickName': '对方',
              'lastMessage': '真实分页响应',
              'lastMessageAt': '2026-08-21T10:02:00Z',
              'unreadCount': 0,
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 1,
          'hasMore': false,
        }),
      );
      addTearDown(harness.close);

      final List<ConversationSummary> conversations = await harness.repository
          .fetchConversations();
      expect(conversations.single.id, 'conversation-b709');
    },
  );

  test(
    'conversation pages reject an optional pages value that disagrees',
    () async {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'conversationId': 'conversation-pages',
              'targetUserId': 99,
              'nickName': '对方',
              'lastMessage': '页数冲突',
              'lastMessageAt': '2026-08-21T10:02:00Z',
              'unreadCount': 0,
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 2,
          'hasMore': false,
        }),
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchConversations(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'conversation page rejects a missing or mismatched reported page',
    () async {
      for (final Map<String, Object?> metadata in <Map<String, Object?>>[
        <String, Object?>{
          'pageSize': 100,
          'total': 0,
          'pages': 0,
          'hasMore': false,
        },
        <String, Object?>{
          'pageNum': 2,
          'pageSize': 100,
          'total': 0,
          'pages': 0,
          'hasMore': false,
        },
      ]) {
        final _Harness harness = await _Harness.start(
          (_) =>
              _Response.ok(<String, Object?>{'list': <Object?>[], ...metadata}),
        );
        try {
          await expectLater(
            harness.repository.fetchConversations(),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test('conversation list rejects a non-map list item', () async {
    final _Harness harness = await _Harness.start(
      (_) => _Response.ok(<String, Object?>{
        'list': <Object?>['not-a-map'],
        'pageNum': 1,
        'pageSize': 100,
        'total': 1,
        'pages': 1,
        'hasMore': false,
      }),
    );
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchConversations(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'private history uses targetUserId/cursor and marks read with POST',
    () async {
      int historyPage = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/user/imMessage/queryChat') {
          historyPage += 1;
          expect(request.method, 'GET');
          expect(
            request.query,
            historyPage == 1
                ? <String, String>{'targetUserId': '99', 'pageSize': '100'}
                : <String, String>{
                    'targetUserId': '99',
                    'pageSize': '100',
                    'cursor': '10',
                  },
          );
          return historyPage == 1
              ? _Response.ok(<String, Object?>{
                  'conversationId': 'conversation-99',
                  'list': <Object?>[
                    <String, Object?>{
                      'messageId': 'msg-2',
                      'senderUserId': 99,
                      'direction': 'INCOMING',
                      'content': '第二条',
                      'createdAt': '2026-08-21T10:02:00Z',
                      'deliveryStatus': 'VENDOR_BLOCKED',
                    },
                    <String, Object?>{
                      'messageId': 'msg-1',
                      'senderUserId': 10001,
                      'direction': 'OUTGOING',
                      'content': '第一条',
                      'createdAt': '2026-08-21T10:01:00Z',
                      'storageStatus': 'FIRST_PARTY_STORED',
                    },
                  ],
                  'nextCursor': '10',
                  'hasMore': true,
                  'unreadCount': 1,
                  'targetUserId': 99,
                  'imStatus': 'VENDOR_BLOCKED',
                  'providerInvocation': false,
                })
              : _Response.ok(<String, Object?>{
                  'conversationId': 'conversation-99',
                  'list': <Object?>[
                    <String, Object?>{
                      'messageId': 'msg-3',
                      'senderUserId': 99,
                      'direction': 'INCOMING',
                      'content': '第三条',
                      'createdAt': '2026-08-21T10:03:00Z',
                      'deliveryStatus': 'VENDOR_BLOCKED',
                    },
                  ],
                  'nextCursor': '',
                  'hasMore': false,
                  'unreadCount': 0,
                  'targetUserId': 99,
                  'imStatus': 'VENDOR_BLOCKED',
                  'providerInvocation': false,
                });
        }
        expect(request.path, '/app-mini-api/mini/v1/message/read');
        expect(request.method, 'POST');
        expect(request.body, <String, Object?>{'targetUserId': 99});
        return _Response.ok(<String, Object?>{
          'targetUserId': 99,
          'markedRead': 1,
          'unreadCount': 0,
        });
      });
      addTearDown(harness.close);
      final List<ChatMessage> messages = await harness.repository
          .fetchPrivateMessages(_conversation());
      expect(messages.map((ChatMessage item) => item.id), <String>[
        'msg-1',
        'msg-2',
        'msg-3',
      ]);
      expect(messages.first.isMine, isTrue);
      expect(messages.last.status, ChatMessageStatus.received);
      expect(
        harness.requests.map((RequestRecord request) => request.path),
        <String>[
          '/app-api/user/imMessage/queryChat',
          '/app-api/user/imMessage/queryChat',
          '/app-mini-api/mini/v1/message/read',
        ],
      );
    },
  );

  test(
    'private history rejects an empty page that still has more without reading',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/user/imMessage/queryChat');
        return _Response.ok(
          _historyPage(
            page: 1,
            hasMore: true,
            nextCursor: 'cursor-1',
            empty: true,
          ),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('空'),
              ),
        ),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'private history rejects hasMore without a next cursor before reading',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/user/imMessage/queryChat');
        return _Response.ok(
          _historyPage(page: 1, hasMore: true, nextCursor: ''),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('游标'),
              ),
        ),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'private history rejects a repeated cursor before marking read',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/user/imMessage/queryChat');
        final String? cursor = request.query['cursor'];
        return _Response.ok(
          _historyPage(
            page: cursor == null ? 1 : 2,
            hasMore: true,
            nextCursor: 'same-cursor',
          ),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('重复'),
              ),
        ),
      );
      expect(harness.requests, hasLength(2));
    },
  );

  test(
    'private history stops at the maximum page limit before marking read',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/user/imMessage/queryChat');
        final int page = request.query['cursor'] == null
            ? 1
            : int.parse(request.query['cursor']!.split('-').last) + 1;
        if (page > 100) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected request past page limit',
            data: null,
          );
        }
        return _Response.ok(
          _historyPage(page: page, hasMore: true, nextCursor: 'cursor-$page'),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('上限'),
              ),
        ),
      );
      expect(harness.requests, hasLength(100));
      expect(harness.requests.last.query['cursor'], 'cursor-99');
    },
  );

  test(
    'private history rejects unavailable conversation without network access',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);
      final ConversationSummary unavailable = _conversation(
        targetUserId: 0,
        available: false,
        unavailableReason: '目标用户不可用',
      );
      await expectLater(
        harness.repository.fetchPrivateMessages(unavailable),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await expectLater(
        harness.repository.sendPrivateMessage(
          conversation: unavailable,
          content: '不会发送',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      expect(harness.requests, isEmpty);
    },
  );

  test(
    'send persists first-party message and preserves vendor-blocked semantics',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.method, 'POST');
        expect(request.path, '/app-mini-api/mini/v1/message/send');
        expect(request.body, <String, Object?>{
          'targetUserId': 99,
          'content': '你好',
          'messageType': 'TEXT',
        });
        return _Response.ok(<String, Object?>{
          'messageId': 'msg-new',
          'senderUserId': 10001,
          'direction': 'OUTGOING',
          'receiverUserId': 99,
          'content': '你好',
          'messageType': 'TEXT',
          'storageStatus': 'FIRST_PARTY_STORED',
          'deliveryStatus': 'VENDOR_BLOCKED',
          'createdAt': '2026-08-21T10:03:00Z',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);
      final ChatMessage message = await harness.repository.sendPrivateMessage(
        conversation: _conversation(),
        content: ' 你好 ',
      );
      expect(message.id, 'msg-new');
      expect(message.content, '你好');
      expect(message.isMine, isTrue);
      expect(message.status, ChatMessageStatus.storedPendingDelivery);
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'concurrent duplicate send is one HTTP request and returns same message',
    () async {
      final Completer<void> release = Completer<void>();
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        expect(request.path, '/app-mini-api/mini/v1/message/send');
        await release.future;
        return _Response.ok(<String, Object?>{
          'messageId': 'msg-dedupe',
          'senderUserId': 10001,
          'receiverUserId': 99,
          'direction': 'OUTGOING',
          'messageType': 'TEXT',
          'content': '重复点击',
          'createdAt': '2026-08-21T10:04:00Z',
          'deliveryStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);
      final Future<ChatMessage> first = harness.repository.sendPrivateMessage(
        conversation: _conversation(),
        content: '重复点击',
        requestId: 'message-dedupe-1',
      );
      final Future<ChatMessage> second = harness.repository.sendPrivateMessage(
        conversation: _conversation(),
        content: '重复点击',
        requestId: 'message-dedupe-1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.requests, hasLength(1));
      release.complete();
      final List<ChatMessage> messages = await Future.wait(
        <Future<ChatMessage>>[first, second],
      );
      expect(messages[0].id, 'msg-dedupe');
      expect(messages[1].id, 'msg-dedupe');
    },
  );

  test(
    'same request ID with a different fingerprint fails before a second HTTP request',
    () async {
      final Completer<void> release = Completer<void>();
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        expect(request.path, '/app-mini-api/mini/v1/message/send');
        await release.future;
        return _Response.ok(<String, Object?>{
          'messageId': 'msg-fingerprint',
          'senderUserId': 10001,
          'receiverUserId': 99,
          'direction': 'OUTGOING',
          'messageType': 'TEXT',
          'content': '第一条',
          'createdAt': '2026-08-21T10:04:00Z',
          'deliveryStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      final Future<ChatMessage> first = harness.repository.sendPrivateMessage(
        conversation: _conversation(targetUserId: 99),
        content: '第一条',
        requestId: 'message-fingerprint-1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final Future<ChatMessage> conflicting = harness.repository
          .sendPrivateMessage(
            conversation: _conversation(targetUserId: 99),
            content: '第二条',
            requestId: 'message-fingerprint-1',
          );
      await expectLater(
        conflicting,
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      expect(harness.requests, hasLength(1));

      release.complete();
      await first;
      expect(harness.requests, hasLength(1));
    },
  );

  test('message send rejects a missing server timestamp', () async {
    final _Harness harness = await _Harness.start(
      (_) => _Response.ok(<String, Object?>{
        'messageId': 'msg-without-time',
        'senderUserId': 10001,
        'receiverUserId': 99,
        'direction': 'OUTGOING',
        'messageType': 'TEXT',
        'content': '缺少时间',
        'providerInvocation': false,
      }),
    );
    addTearDown(harness.close);

    await expectLater(
      harness.repository.sendPrivateMessage(
        conversation: _conversation(),
        content: '缺少时间',
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'system and interaction notification lists parse page maps and cache',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/nolg/getPushMsg') {
          expect(request.query, <String, String>{
            'notificationId': 'interaction-1',
          });
          return _Response.ok(<String, Object?>{
            'notificationId': 'interaction-1',
            'category': 'DYNAMIC_COMMENT',
            'subjectType': 'DYNAMIC',
            'subjectId': 'dynamic-1',
            'title': '动态收到评论',
            'body': '南风 评论了你的动态',
            'read': false,
            'createdAt': '2026-08-21T10:01:00Z',
          });
        }
        expect(request.method, 'GET');
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        expect(request.query['pageSize'], '100');
        final String category = request.query['category']!;
        expect(category, anyOf('SYSTEM', 'INTERACTION'));
        if (category == 'SYSTEM') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'notificationId': 'system-1',
                'category': 'SYSTEM',
                'title': '系统公告',
                'body': '请查看详情',
                'subjectType': 'SYSTEM',
                'subjectId': '',
                'read': false,
                'createdAt': '2026-08-21T10:00:00Z',
              },
            ],
            'nextCursor': '',
            'hasMore': false,
            'unreadCount': 1,
          });
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'notificationId': 'interaction-1',
              'actorUserId': 99,
              'actorNickName': '南风',
              'category': 'DYNAMIC_COMMENT',
              'subjectType': 'DYNAMIC',
              'subjectId': 'dynamic-1',
              'title': '动态收到评论',
              'body': '南风 评论了你的动态',
              'read': false,
              'createdAt': '2026-08-21T10:01:00Z',
            },
          ],
          'nextCursor': '',
          'hasMore': false,
          'unreadCount': 1,
        });
      });
      addTearDown(harness.close);
      final List<AppNotification> system = await harness.repository
          .fetchNotifications(NotificationCategory.system);
      final List<AppNotification> interaction = await harness.repository
          .fetchNotifications(NotificationCategory.interaction);
      expect(system.single.id, 'system-1');
      expect(system.single.unread, isTrue);
      expect(interaction.single.id, 'interaction-1');
      expect(interaction.single.category, NotificationCategory.interaction);
      expect(interaction.single.targetType, NotificationTargetType.dynamicPost);
      expect(interaction.single.targetId, 'dynamic-1');
      expect(
        interaction.single.createdAt,
        DateTime.parse('2026-08-21T10:01:00Z'),
      );
      final AppNotification detail = await harness.repository.fetchNotification(
        'interaction-1',
      );
      expect(detail.id, 'interaction-1');
      expect(harness.requests, hasLength(5));
    },
  );

  test(
    'draft history requires and propagates one authoritative conversation ID',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/user/imMessage/queryChat') {
          return _Response.ok(<String, Object?>{
            'conversationId': 'server-conversation-99',
            'list': <Object?>[
              <String, Object?>{
                'messageId': 'server-message-1',
                'senderUserId': 99,
                'direction': 'INCOMING',
                'content': '第一条',
                'createdAt': '2026-08-21T10:01:00Z',
              },
            ],
            'nextCursor': '',
            'hasMore': false,
            'unreadCount': 0,
            'targetUserId': 99,
            'imStatus': 'VENDOR_BLOCKED',
            'providerInvocation': false,
          });
        }
        expect(request.path, '/app-mini-api/mini/v1/message/read');
        return _Response.ok(<String, Object?>{
          'targetUserId': 99,
          'markedRead': 1,
          'unreadCount': 0,
          'conversationId': 'server-conversation-99',
        });
      });
      addTearDown(harness.close);

      final List<ChatMessage> messages = await harness.repository
          .fetchPrivateMessages(_conversationDraft());

      expect(messages.single.conversationId, 'server-conversation-99');
      expect(messages.single.status, ChatMessageStatus.received);
    },
  );

  test(
    'an empty draft history may remain unresolved without a conversation ID',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/user/imMessage/queryChat') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[],
            'nextCursor': '',
            'hasMore': false,
            'unreadCount': 0,
          });
        }
        expect(request.path, '/app-mini-api/mini/v1/message/read');
        return _Response.ok(<String, Object?>{
          'targetUserId': 99,
          'markedRead': 0,
          'unreadCount': 0,
        });
      });
      addTearDown(harness.close);

      final List<ChatMessage> messages = await harness.repository
          .fetchPrivateMessages(_conversationDraft());

      expect(messages, isEmpty);
    },
  );

  test(
    'private history rejects a page whose conversation ID changes',
    () async {
      int page = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/user/imMessage/queryChat') {
          page += 1;
          return _Response.ok(<String, Object?>{
            'conversationId': page == 1
                ? 'server-conversation-99'
                : 'other-conversation',
            'list': <Object?>[
              <String, Object?>{
                'messageId': 'server-message-$page',
                'senderUserId': 99,
                'direction': 'INCOMING',
                'content': '第$page条',
                'createdAt': '2026-08-21T10:0$page:00Z',
              },
            ],
            'nextCursor': page == 1 ? 'cursor-1' : '',
            'hasMore': page == 1,
            'unreadCount': 0,
            'targetUserId': 99,
            'imStatus': 'VENDOR_BLOCKED',
            'providerInvocation': false,
          });
        }
        fail('read must not run after inconsistent history');
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversationDraft()),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(harness.requests, hasLength(2));
    },
  );

  test(
    'private history rejects a direction that disagrees with sender identity',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/user/imMessage/queryChat');
        return _Response.ok(<String, Object?>{
          'conversationId': 'server-conversation-99',
          'list': <Object?>[
            <String, Object?>{
              'messageId': 'server-message-identity',
              'senderUserId': 99,
              'direction': 'OUTGOING',
              'content': '身份冲突',
              'createdAt': '2026-08-21T10:01:00Z',
            },
          ],
          'nextCursor': '',
          'hasMore': false,
          'unreadCount': 0,
          'targetUserId': 99,
          'imStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversationDraft()),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'draft send forwards stable request ID and leaves unresolved identity explicit',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-mini-api/mini/v1/message/send') {
          expect(request.requestId, 'draft-send-1');
          return _Response.ok(<String, Object?>{
            'messageId': 'server-message-draft',
            'senderUserId': 10001,
            'receiverUserId': 99,
            'direction': 'OUTGOING',
            'messageType': 'TEXT',
            'content': '首句',
            'storageStatus': 'FIRST_PARTY_STORED',
            'deliveryStatus': 'VENDOR_BLOCKED',
            'createdAt': '2026-08-21T10:05:00Z',
            'providerInvocation': false,
          });
        }
        if (request.path == '/app-mini-api/mini/v1/message/conversations') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[],
            'pageNum': 1,
            'pageSize': 100,
            'total': 0,
            'pages': 0,
            'hasMore': false,
          });
        }
        if (request.path == '/app-mini-api/mini/v1/message/read') {
          return _Response.ok(<String, Object?>{
            'targetUserId': 99,
            'markedRead': 0,
            'unreadCount': 0,
          });
        }
        expect(request.path, '/app-api/user/imMessage/queryChat');
        return _Response.ok(<String, Object?>{
          'list': <Object?>[],
          'nextCursor': '',
          'hasMore': false,
          'unreadCount': 0,
        });
      });
      addTearDown(harness.close);

      final ChatMessage message = await harness.repository.sendPrivateMessage(
        conversation: _conversationDraft(),
        content: '首句',
        requestId: 'draft-send-1',
      );

      expect(message.conversationId, isNull);
      expect(message.status, ChatMessageStatus.storedPendingDelivery);
      expect(
        harness.requests.map((RequestRecord request) => request.path),
        <String>[
          '/app-mini-api/mini/v1/message/send',
          '/app-mini-api/mini/v1/message/conversations',
          '/app-api/user/imMessage/queryChat',
          '/app-mini-api/mini/v1/message/read',
        ],
      );
    },
  );

  test('a new identical submission gets a new request ID', () async {
    int sendCount = 0;
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.path, '/app-mini-api/mini/v1/message/send');
      sendCount += 1;
      return _Response.ok(<String, Object?>{
        'messageId': 'server-message-$sendCount',
        'senderUserId': 10001,
        'receiverUserId': 99,
        'direction': 'OUTGOING',
        'messageType': 'TEXT',
        'content': '相同内容',
        'storageStatus': 'FIRST_PARTY_STORED',
        'deliveryStatus': 'VENDOR_BLOCKED',
        'createdAt': '2026-08-21T10:05:0${sendCount}Z',
        'providerInvocation': false,
      });
    });
    addTearDown(harness.close);

    await harness.repository.sendPrivateMessage(
      conversation: _conversation(),
      content: '相同内容',
      requestId: 'send-1',
    );
    await harness.repository.sendPrivateMessage(
      conversation: _conversation(),
      content: '相同内容',
      requestId: 'send-2',
    );

    expect(sendCount, 2);
    expect(
      harness.requests.map((RequestRecord request) => request.requestId),
      <String>['send-1', 'send-2'],
    );
  });

  test(
    'notification list fetches every cursor page before sorting and caching',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        final int page = request.query['cursor'] == null
            ? 1
            : int.parse(request.query['cursor']!.split('-').last) + 1;
        expect(request.query['pageSize'], '100');
        expect(request.query['category'], 'SYSTEM');
        return _Response.ok(
          _notificationPage(
            page: page,
            hasMore: page == 1,
            category: 'SYSTEM',
            nextCursor: page == 1 ? 'cursor-1' : '',
          ),
        );
      });
      addTearDown(harness.close);

      final List<AppNotification> notifications = await harness.repository
          .fetchNotifications(NotificationCategory.system);

      expect(notifications.map((AppNotification item) => item.id), <String>[
        'notification-SYSTEM-2',
        'notification-SYSTEM-1',
      ]);
      expect(
        harness.requests
            .where(
              (RequestRecord request) =>
                  request.path == '/app-mini-api/mini/v1/notifications',
            )
            .map((RequestRecord request) => request.query['cursor']),
        <String?>[null, 'cursor-1'],
      );
      final MessageRecoverySnapshot snapshot = await harness.repository
          .fetchRecoverySnapshot();
      expect(snapshot.lastNotificationSyncAt, isNotNull);
    },
  );

  test(
    'notification list sends explicit category filters on every page',
    () async {
      final Map<String, int> pagesByCategory = <String, int>{};
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.method, 'GET');
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        expect(request.query['pageSize'], '100');
        final String category = request.query['category']!;
        expect(category, anyOf('SYSTEM', 'INTERACTION'));
        final int page = request.query['cursor'] == null
            ? 1
            : int.parse(request.query['cursor']!.split('-').last) + 1;
        pagesByCategory[category] = page;
        final String responseCategory = category == 'SYSTEM'
            ? 'SYSTEM'
            : 'DYNAMIC_LIKE';
        return _Response.ok(
          _notificationPage(
            page: page,
            hasMore: page == 1,
            category: responseCategory,
            nextCursor: page == 1 ? 'cursor-$category-1' : '',
          ),
        );
      });
      addTearDown(harness.close);

      final List<AppNotification> system = await harness.repository
          .fetchNotifications(NotificationCategory.system);
      final List<AppNotification> interaction = await harness.repository
          .fetchNotifications(NotificationCategory.interaction);

      expect(system.map((AppNotification item) => item.id), <String>[
        'notification-SYSTEM-2',
        'notification-SYSTEM-1',
      ]);
      expect(interaction.map((AppNotification item) => item.id), <String>[
        'notification-DYNAMIC_LIKE-2',
        'notification-DYNAMIC_LIKE-1',
      ]);
      expect(pagesByCategory, <String, int>{'SYSTEM': 2, 'INTERACTION': 2});
      final List<RequestRecord> listRequests = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/notifications',
          )
          .toList();
      expect(
        listRequests.map((RequestRecord request) => request.query['category']),
        <String?>['SYSTEM', 'SYSTEM', 'INTERACTION', 'INTERACTION'],
      );
      expect(
        listRequests.map((RequestRecord request) => request.query['cursor']),
        <String?>[null, 'cursor-SYSTEM-1', null, 'cursor-INTERACTION-1'],
      );
    },
  );

  test(
    'notification sync retries an ambiguous result with one ID then refreshes',
    () async {
      int syncAttempts = 0;
      final _Harness harness = await _Harness.start(
        (RequestRecord request) {
          expect(request.method, 'GET');
          expect(request.path, '/app-mini-api/mini/v1/notifications');
          return _Response.ok(
            _notificationPage(
              page: 1,
              hasMore: false,
              category: 'SYSTEM',
              nextCursor: '',
            ),
          );
        },
        notificationSyncHandler: (RequestRecord request) {
          syncAttempts += 1;
          expect(request.method, 'POST');
          expect(request.body, isNull);
          expect(request.requestId, isNotEmpty);
          if (syncAttempts == 1) {
            return _Response.empty();
          }
          return _Response.ok(_notificationSyncResponse());
        },
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchNotifications(NotificationCategory.system),
        throwsA(isA<ApiException>()),
      );
      final List<String> firstAttemptIds = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/notifications/sync',
          )
          .map((RequestRecord request) => request.requestId)
          .toList();
      expect(firstAttemptIds, hasLength(1));
      expect(
        harness.requests.where(
          (RequestRecord request) =>
              request.path == '/app-mini-api/mini/v1/notifications',
        ),
        isEmpty,
      );

      await harness.repository.fetchNotifications(NotificationCategory.system);
      await harness.repository.fetchNotifications(NotificationCategory.system);
      final List<String> syncIds = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/notifications/sync',
          )
          .map((RequestRecord request) => request.requestId)
          .toList();
      expect(syncAttempts, 3);
      expect(syncIds[0], syncIds[1]);
      expect(syncIds[2], isNot(syncIds[1]));
    },
  );

  test('notification sync fails closed before making a list GET', () async {
    final List<Map<String, Object?>> invalidResponses = <Map<String, Object?>>[
      <String, Object?>{..._notificationSyncResponse(), 'synced': false},
      <String, Object?>{
        ..._notificationSyncResponse(),
        'projectionStatus': 'FIRST_PARTY_PENDING',
      },
      <String, Object?>{
        ..._notificationSyncResponse(),
        'providerInvocation': true,
      },
      <String, Object?>{..._notificationSyncResponse(), 'totalUnread': 1},
    ];
    for (final Map<String, Object?> invalidResponse in invalidResponses) {
      final _Harness harness = await _Harness.start(
        (_) => fail('notification list GET must wait for a valid sync'),
        notificationSyncHandler: (_) => _Response.ok(invalidResponse),
      );
      try {
        await expectLater(
          harness.repository.fetchNotifications(NotificationCategory.system),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        expect(
          harness.requests.where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/notifications',
          ),
          isEmpty,
        );
        expect(
          (await harness.repository.fetchRecoverySnapshot())
              .lastNotificationSyncAt,
          isNull,
        );
      } finally {
        await harness.close();
      }
    }
  });

  test('concurrent notification fetches share one projection sync', () async {
    final Completer<void> releaseSync = Completer<void>();
    int syncCalls = 0;
    final _Harness harness = await _Harness.start(
      (RequestRecord request) {
        expect(request.method, 'GET');
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        final String category = request.query['category'] == 'SYSTEM'
            ? 'SYSTEM'
            : 'DYNAMIC_LIKE';
        return _Response.ok(
          _notificationPage(
            page: 1,
            hasMore: false,
            category: category,
            nextCursor: '',
          ),
        );
      },
      notificationSyncHandler: (RequestRecord request) async {
        syncCalls += 1;
        expect(request.method, 'POST');
        expect(request.requestId, isNotEmpty);
        await releaseSync.future;
        return _Response.ok(_notificationSyncResponse());
      },
    );
    addTearDown(harness.close);

    final Future<List<AppNotification>> first = harness.repository
        .fetchNotifications(NotificationCategory.system);
    final Future<List<AppNotification>> second = harness.repository
        .fetchNotifications(NotificationCategory.interaction);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(syncCalls, 1);
    releaseSync.complete();
    final List<List<AppNotification>> values = await Future.wait(
      <Future<List<AppNotification>>>[first, second],
    );
    expect(values[0].single.category, NotificationCategory.system);
    expect(values[1].single.category, NotificationCategory.interaction);
    expect(
      harness.requests.where(
        (RequestRecord request) =>
            request.path == '/app-mini-api/mini/v1/notifications/sync',
      ),
      hasLength(1),
    );
    expect(
      harness.requests.where(
        (RequestRecord request) =>
            request.path == '/app-mini-api/mini/v1/notifications',
      ),
      hasLength(2),
    );
  });

  test(
    'notification list rejects non-map items instead of dropping them',
    () async {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{
          'list': <Object?>['not-a-map'],
          'nextCursor': '',
          'hasMore': false,
          'unreadCount': 0,
        }),
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchNotifications(NotificationCategory.system),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'notification read state must have one explicit boolean authority',
    () async {
      for (final Map<String, Object?> item in <Map<String, Object?>>[
        <String, Object?>{
          'notificationId': 'missing-read',
          'category': 'SYSTEM',
          'title': '系统公告',
          'body': '缺少已读状态',
          'createdAt': '2026-08-21T10:00:00Z',
        },
        <String, Object?>{
          'notificationId': 'invalid-read',
          'category': 'SYSTEM',
          'title': '系统公告',
          'body': '已读状态无法判断',
          'read': 'unknown',
          'createdAt': '2026-08-21T10:00:00Z',
        },
      ]) {
        final _Harness harness = await _Harness.start(
          (_) => _Response.ok(<String, Object?>{
            'list': <Object?>[item],
            'nextCursor': '',
            'hasMore': false,
            'unreadCount': 0,
          }),
        );
        try {
          await expectLater(
            harness.repository.fetchNotifications(NotificationCategory.system),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'notification pagination rejects an empty page that still has more',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        return _Response.ok(
          _notificationPage(
            page: 1,
            hasMore: true,
            category: 'SYSTEM',
            nextCursor: 'cursor-1',
            empty: true,
          ),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchNotifications(NotificationCategory.system),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('空'),
              ),
        ),
      );
      expect(harness.requests, hasLength(2));
      expect(
        (await harness.repository.fetchRecoverySnapshot())
            .lastNotificationSyncAt,
        isNotNull,
      );
    },
  );

  test(
    'notification pagination rejects hasMore without a next cursor',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        return _Response.ok(
          _notificationPage(
            page: 1,
            hasMore: true,
            category: 'SYSTEM',
            nextCursor: '',
          ),
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchNotifications(NotificationCategory.system),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('游标'),
              ),
        ),
      );
      expect(harness.requests, hasLength(2));
    },
  );

  test('notification pagination rejects a repeated cursor', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.path, '/app-mini-api/mini/v1/notifications');
      final int page = request.query['cursor'] == null ? 1 : 2;
      return _Response.ok(
        _notificationPage(
          page: page,
          hasMore: true,
          category: 'SYSTEM',
          nextCursor: 'same-cursor',
        ),
      );
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchNotifications(NotificationCategory.system),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            )
            .having(
              (ApiException error) => error.message,
              'message',
              contains('重复'),
            ),
      ),
    );
    expect(harness.requests, hasLength(3));
  });

  test('notification pagination stops at the maximum page limit', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.path, '/app-mini-api/mini/v1/notifications');
      final int page = request.query['cursor'] == null
          ? 1
          : int.parse(request.query['cursor']!.split('-').last) + 1;
      if (page > 100) {
        return const _Response(
          statusCode: 500,
          code: 500,
          message: 'unexpected request past page limit',
          data: null,
        );
      }
      return _Response.ok(
        _notificationPage(
          page: page,
          hasMore: true,
          category: 'SYSTEM',
          nextCursor: 'cursor-$page',
        ),
      );
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchNotifications(NotificationCategory.system),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            )
            .having(
              (ApiException error) => error.message,
              'message',
              contains('上限'),
            ),
      ),
    );
    expect(harness.requests, hasLength(101));
    expect(harness.requests.last.query['cursor'], 'cursor-99');
  });

  test('notification detail and read are real backend operations', () async {
    bool backendRead = false;
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path == '/app-api/nolg/getPushMsg') {
        expect(request.method, 'GET');
        expect(request.query, <String, String>{'notificationId': 'system-77'});
        return _Response.ok(<String, Object?>{
          'notificationId': 'system-77',
          'category': 'SYSTEM',
          'title': '系统公告',
          'body': '请查看详情',
          'subjectType': 'ROOM',
          'subjectId': 'room-7',
          'read': backendRead,
          'createdAt': '2026-08-21T10:00:00Z',
        });
      }
      expect(request.path, '/app-mini-api/mini/v1/notifications/read');
      expect(request.method, 'POST');
      expect(request.body, <String, Object?>{'notificationId': 'system-77'});
      backendRead = true;
      return _Response.ok(<String, Object?>{
        'notificationId': 'system-77',
        'category': 'SYSTEM',
        'title': '系统公告',
        'body': '请查看详情',
        'subjectType': 'ROOM',
        'subjectId': 'room-7',
        'read': true,
        'createdAt': '2026-08-21T10:00:00Z',
        'pushStatus': 'VENDOR_BLOCKED',
        'providerInvocation': false,
      });
    });
    addTearDown(harness.close);
    final AppNotification notification = await harness.repository
        .fetchNotification('system-77');
    expect(notification.category, NotificationCategory.system);
    expect(notification.targetType, NotificationTargetType.room);
    expect(notification.targetId, 'room-7');
    await harness.repository.markNotificationRead(notification.id);
    final AppNotification read = await harness.repository.fetchNotification(
      notification.id,
    );
    expect(read.unread, isFalse);
    expect(harness.requests, hasLength(3));
  });

  test('notification detail rejects missing or mismatched authority', () async {
    for (final Map<String, Object?> data in <Map<String, Object?>>[
      <String, Object?>{
        'notificationId': 'different-id',
        'category': 'SYSTEM',
        'createdAt': '2026-08-21T10:00:00Z',
      },
      <String, Object?>{'notificationId': 'system-77', 'category': 'SYSTEM'},
    ]) {
      final _Harness harness = await _Harness.start((_) => _Response.ok(data));
      try {
        await expectLater(
          harness.repository.fetchNotification('system-77'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await harness.close();
      }
    }
  });

  test(
    'late notification response does not replace the newer request result',
    () async {
      final Completer<void> releaseFirst = Completer<void>();
      int notificationRequestCount = 0;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        expect(request.path, '/app-mini-api/mini/v1/notifications');
        notificationRequestCount += 1;
        if (notificationRequestCount == 1) {
          await releaseFirst.future;
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'notificationId': 'stale',
                'category': 'DYNAMIC_LIKE',
                'subjectType': 'DYNAMIC',
                'subjectId': 'dynamic-stale',
                'title': '旧响应',
                'body': '旧响应',
                'read': false,
                'createdAt': '2026-08-21T10:00:00Z',
              },
            ],
            'nextCursor': '',
            'hasMore': false,
            'unreadCount': 1,
          });
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'notificationId': 'fresh',
              'category': 'DYNAMIC_LIKE',
              'subjectType': 'DYNAMIC',
              'subjectId': 'dynamic-fresh',
              'title': '新响应',
              'body': '新响应',
              'read': false,
              'createdAt': '2026-08-21T10:01:00Z',
            },
          ],
          'nextCursor': '',
          'hasMore': false,
          'unreadCount': 1,
        });
      });
      addTearDown(harness.close);
      final Future<List<AppNotification>> staleFuture = harness.repository
          .fetchNotifications(NotificationCategory.interaction);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final List<AppNotification> fresh = await harness.repository
          .fetchNotifications(NotificationCategory.interaction);
      releaseFirst.complete();
      final List<AppNotification> stale = await staleFuture;
      expect(fresh.single.id, 'fresh');
      expect(stale.single.id, 'stale');
      expect(notificationRequestCount, 2);
    },
  );

  test('interaction clear keeps the first-party legacy clear route', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.method, 'POST');
      expect(request.path, '/app-api/dynamic/emptyUserDynamicNotify');
      return _Response.ok(<String, Object?>{
        'dynamicUnread': 0,
        'notificationUnread': 2,
        'messageUnread': 1,
        'totalUnread': 3,
        'pushStatus': 'VENDOR_BLOCKED',
        'imStatus': 'VENDOR_BLOCKED',
        'providerInvocation': false,
      });
    });
    addTearDown(harness.close);
    await harness.repository.clearInteractionNotifications();
    expect(harness.requests, hasLength(1));
  });

  test(
    'message mutation request IDs survive auth and unknown-result retries per intent',
    () async {
      int privateReadAttempts = 0;
      int notificationReadAttempts = 0;
      int clearAttempts = 0;
      int recoveryAttempts = 0;
      final _Harness harness = await _Harness.start(
        (RequestRecord request) {
          switch (request.path) {
            case '/app-api/user/imMessage/queryChat':
              return _Response.ok(
                _historyPage(
                  page: 1,
                  hasMore: false,
                  nextCursor: '',
                  empty: true,
                ),
              );
            case '/app-mini-api/mini/v1/message/read':
              privateReadAttempts += 1;
              if (privateReadAttempts == 1) {
                return _Response.empty();
              }
              return _Response.ok(<String, Object?>{
                'targetUserId': 99,
                'markedRead': 0,
                'unreadCount': 0,
              });
            case '/app-mini-api/mini/v1/notifications/read':
              notificationReadAttempts += 1;
              if (notificationReadAttempts == 1) {
                return _Response(
                  statusCode: 401,
                  code: 401,
                  message: '需要刷新登录态',
                  data: null,
                );
              }
              return _Response.ok(<String, Object?>{
                'notificationId': 'system-77',
                'category': 'SYSTEM',
                'title': '系统公告',
                'body': '已读',
                'subjectType': 'SYSTEM',
                'subjectId': '',
                'read': true,
                'createdAt': '2026-08-21T10:00:00Z',
                'pushStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
              });
            case '/app-api/dynamic/emptyUserDynamicNotify':
              clearAttempts += 1;
              if (clearAttempts == 1) {
                return _Response.empty();
              }
              return _Response.ok(<String, Object?>{
                'dynamicUnread': 0,
                'notificationUnread': 0,
                'messageUnread': 0,
                'totalUnread': 0,
                'pushStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
              });
            default:
              fail('unexpected message mutation route: ${request.path}');
          }
        },
        unauthorizedRecovery: () async {
          recoveryAttempts += 1;
          return true;
        },
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.fetchPrivateMessages(_conversation());

      await harness.repository.markNotificationRead('system-77');

      await expectLater(
        harness.repository.clearInteractionNotifications(),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.clearInteractionNotifications();

      final List<String> privateReadIds = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/message/read',
          )
          .map((RequestRecord request) => request.requestId)
          .toList();
      final List<String> notificationReadIds = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-mini-api/mini/v1/notifications/read',
          )
          .map((RequestRecord request) => request.requestId)
          .toList();
      final List<String> clearIds = harness.requests
          .where(
            (RequestRecord request) =>
                request.path == '/app-api/dynamic/emptyUserDynamicNotify',
          )
          .map((RequestRecord request) => request.requestId)
          .toList();
      expect(privateReadIds, hasLength(2));
      expect(notificationReadIds, hasLength(2));
      expect(clearIds, hasLength(2));
      expect(privateReadIds[0], privateReadIds[1]);
      expect(notificationReadIds[0], notificationReadIds[1]);
      expect(clearIds[0], clearIds[1]);
      expect(recoveryAttempts, 1);
      expect(<String>{
        privateReadIds.first,
        notificationReadIds.first,
        clearIds.first,
      }, hasLength(3));
    },
  );

  test('private history requires explicit cursor-page authority', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.path, '/app-api/user/imMessage/queryChat');
      return _Response.ok(<String, Object?>{
        'list': <Object?>[],
        'nextCursor': '',
        'unreadCount': 0,
      });
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchPrivateMessages(_conversationDraft()),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
    expect(harness.requests, hasLength(1));
  });

  test(
    'private read result must belong to the requested conversation',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/user/imMessage/queryChat') {
          return _Response.ok(
            _historyPage(page: 1, hasMore: false, nextCursor: '', empty: true),
          );
        }
        expect(request.path, '/app-mini-api/mini/v1/message/read');
        return _Response.ok(<String, Object?>{
          'targetUserId': 12345,
          'markedRead': 0,
          'unreadCount': 0,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPrivateMessages(_conversation()),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('message send rejects non-authoritative success payloads', () async {
    final List<Map<String, Object?>> invalidResponses = <Map<String, Object?>>[
      <String, Object?>{
        'receiverUserId': 12345,
        'messageType': 'TEXT',
        'content': '严格校验',
        'providerInvocation': false,
      },
      <String, Object?>{
        'receiverUserId': 99,
        'messageType': 'IMAGE',
        'content': '严格校验',
        'providerInvocation': false,
      },
      <String, Object?>{
        'receiverUserId': 99,
        'messageType': 'TEXT',
        'content': '被服务端改写',
        'providerInvocation': false,
      },
      <String, Object?>{
        'receiverUserId': 99,
        'messageType': 'TEXT',
        'content': '严格校验',
        'providerInvocation': true,
      },
    ];
    for (int index = 0; index < invalidResponses.length; index += 1) {
      final _Harness harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{
          'messageId': 'invalid-$index',
          'senderUserId': 10001,
          'direction': 'OUTGOING',
          'storageStatus': 'FIRST_PARTY_STORED',
          'deliveryStatus': 'VENDOR_BLOCKED',
          'createdAt': '2026-08-21T10:05:00Z',
          ...invalidResponses[index],
        }),
      );
      try {
        await expectLater(
          harness.repository.sendPrivateMessage(
            conversation: _conversation(),
            content: '严格校验',
            requestId: 'invalid-authority-$index',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await harness.close();
      }
    }
  });

  test('notification write responses remain server-authoritative', () async {
    final _Harness readHarness = await _Harness.start(
      (_) => _Response.ok(<String, Object?>{
        'notificationId': 'other-notification',
        'category': 'SYSTEM',
        'title': '错误通知',
        'body': '错误通知',
        'subjectType': 'SYSTEM',
        'subjectId': '',
        'read': true,
        'createdAt': '2026-08-21T10:00:00Z',
        'pushStatus': 'VENDOR_BLOCKED',
        'providerInvocation': false,
      }),
    );
    try {
      await expectLater(
        readHarness.repository.markNotificationRead('system-77'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    } finally {
      await readHarness.close();
    }

    final _Harness clearHarness = await _Harness.start(
      (_) => _Response.ok(<String, Object?>{
        'dynamicUnread': 1,
        'notificationUnread': 1,
        'messageUnread': 0,
        'totalUnread': 1,
        'pushStatus': 'VENDOR_BLOCKED',
        'imStatus': 'VENDOR_BLOCKED',
        'providerInvocation': false,
      }),
    );
    try {
      await expectLater(
        clearHarness.repository.clearInteractionNotifications(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    } finally {
      await clearHarness.close();
    }
  });

  for (final (int status, ApiFailureKind kind) in <(int, ApiFailureKind)>[
    (401, ApiFailureKind.unauthorized),
    (403, ApiFailureKind.forbidden),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test(
      'private send preserves $status failure without a fake message',
      () async {
        final _Harness harness = await _Harness.start((RequestRecord request) {
          expect(request.path, '/app-mini-api/mini/v1/message/send');
          return _Response(
            statusCode: status,
            code: status == 500 ? 50001 : status,
            message: 'send failure $status',
            data: null,
          );
        });
        addTearDown(harness.close);

        await expectLater(
          harness.repository.sendPrivateMessage(
            conversation: _conversation(),
            content: '不会伪造成功',
            requestId: 'message-failure-$status',
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException error) => error.kind, 'kind', kind)
                .having(
                  (ApiException error) => error.message,
                  'message',
                  'send failure $status',
                ),
          ),
        );
        expect(harness.requests, hasLength(1));
      },
    );
  }

  test('private send network failure never creates a local message', () async {
    final _Harness harness = await _Harness.start(
      (_) => _Response.ok(<String, Object?>{}),
    );
    await harness.close();

    await expectLater(
      harness.repository.sendPrivateMessage(
        conversation: _conversation(),
        content: '离线时不能伪造成功',
        requestId: 'message-offline-1',
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.network,
        ),
      ),
    );
    expect(harness.requests, isEmpty);
  });

  for (final (int status, int code, ApiFailureKind kind)
      in <(int, int, ApiFailureKind)>[
        (401, 401, ApiFailureKind.unauthorized),
        (403, 403, ApiFailureKind.forbidden),
        (409, 409, ApiFailureKind.conflict),
        (422, 422, ApiFailureKind.validation),
        (500, 500, ApiFailureKind.server),
      ]) {
    test('message API preserves $status failure classification', () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response(
          statusCode: status,
          code: code,
          message: 'contract error $status',
          data: null,
        );
      });
      addTearDown(harness.close);
      await expectLater(
        harness.repository.fetchConversations(),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', kind)
              .having((ApiException e) => e.httpStatus, 'httpStatus', status)
              .having(
                (ApiException e) => e.message,
                'message',
                'contract error $status',
              ),
        ),
      );
    });
  }
}

ConversationSummary _conversation({
  int targetUserId = 99,
  bool available = true,
  String unavailableReason = '',
}) {
  return ConversationSummary(
    id: targetUserId > 0
        ? 'conversation-$targetUserId'
        : 'conversation-invalid',
    kind: ConversationKind.privateChat,
    title: '对方',
    lastMessage: '',
    updatedAt: DateTime(2026, 8, 21),
    unreadCount: 0,
    targetUserId: targetUserId,
    available: available,
    unavailableReason: unavailableReason,
  );
}

ConversationSummary _conversationDraft({
  int targetUserId = 99,
  bool available = true,
  String unavailableReason = '',
}) {
  return ConversationSummary.draft(
    kind: ConversationKind.privateChat,
    title: '对方',
    lastMessage: '',
    unreadCount: 0,
    targetUserId: targetUserId,
    available: available,
    unavailableReason: unavailableReason,
  );
}

Map<String, Object?> _conversationPage({
  required int page,
  required bool hasMore,
  bool empty = false,
  int? reportedPage,
  int? total,
  int? pages,
  int itemCount = 1,
}) {
  final int resolvedTotal = total ?? (hasMore ? 101 : page);
  final int resolvedPages =
      pages ?? (resolvedTotal == 0 ? 0 : (resolvedTotal + 99) ~/ 100);
  return <String, Object?>{
    'list': empty
        ? <Object?>[]
        : List<Object?>.generate(
            itemCount,
            (_) => <String, Object?>{
              'conversationId': 'conversation-$page',
              'targetUserId': page,
              'nickName': '用户$page',
              'lastMessage': '消息$page',
              'lastMessageAt': DateTime.utc(
                2026,
                8,
                21,
                10,
              ).add(Duration(minutes: page)).toIso8601String(),
              'unreadCount': page,
            },
          ),
    'pageNum': reportedPage ?? page,
    'pageSize': 100,
    'total': resolvedTotal,
    'pages': resolvedPages,
    'hasMore': hasMore,
  };
}

Map<String, Object?> _historyPage({
  required int page,
  required bool hasMore,
  required String nextCursor,
  bool empty = false,
}) {
  return <String, Object?>{
    'list': empty
        ? <Object?>[]
        : <Object?>[
            <String, Object?>{
              'messageId': 'history-$page',
              'senderUserId': page.isEven ? 99 : 10001,
              'direction': page.isEven ? 'INCOMING' : 'OUTGOING',
              'content': '历史$page',
              'deliveryStatus': 'VENDOR_BLOCKED',
              'createdAt': DateTime.utc(
                2026,
                8,
                21,
                10,
              ).add(Duration(minutes: page)).toIso8601String(),
            },
          ],
    'nextCursor': nextCursor,
    'hasMore': hasMore,
    'unreadCount': 0,
    'conversationId': 'conversation-99',
    'targetUserId': 99,
    'imStatus': 'VENDOR_BLOCKED',
    'providerInvocation': false,
  };
}

Map<String, Object?> _notificationPage({
  required int page,
  required bool hasMore,
  required String category,
  required String nextCursor,
  bool empty = false,
}) {
  return <String, Object?>{
    'list': empty
        ? <Object?>[]
        : <Object?>[
            <String, Object?>{
              'notificationId': 'notification-$category-$page',
              'category': category,
              'title': '通知$page',
              'body': '通知内容$page',
              'subjectType': 'SYSTEM',
              'subjectId': '',
              'read': false,
              'createdAt': DateTime.utc(
                2026,
                8,
                21,
                10,
              ).add(Duration(minutes: page)).toIso8601String(),
            },
          ],
    'nextCursor': nextCursor,
    'hasMore': hasMore,
    'unreadCount': 0,
  };
}

Map<String, Object?> _notificationSyncResponse({
  bool synced = true,
  String projectionStatus = 'FIRST_PARTY_MATERIALIZED',
  String pushStatus = 'VENDOR_BLOCKED',
  String imStatus = 'VENDOR_BLOCKED',
  bool providerInvocation = false,
  int dynamicUnread = 0,
  int notificationUnread = 0,
  int messageUnread = 0,
  int totalUnread = 0,
}) {
  return <String, Object?>{
    'synced': synced,
    'projectionStatus': projectionStatus,
    'pushStatus': pushStatus,
    'imStatus': imStatus,
    'providerInvocation': providerInvocation,
    'dynamicUnread': dynamicUnread,
    'notificationUnread': notificationUnread,
    'messageUnread': messageUnread,
    'totalUnread': totalUnread,
  };
}

class _Harness {
  _Harness._(
    this.server,
    this.requests, {
    UnauthorizedRecovery? unauthorizedRecovery,
    NativePermissionAdapter? nativePermissionAdapter,
  }) : repository = BackendMessageRepository(
         apiClient: ApiClient(
           baseUri: Uri.parse(
             'http://${server.address.address}:${server.port}/',
           ),
           clientType: 'Android',
           clientInnerVersion: '6',
           authorizationProvider: () => 'Bearer contract-test',
           unauthorizedRecovery: unauthorizedRecovery,
         ),
         routes: const BackendRouteCatalog(),
         currentUserIdProvider: () => 10001,
         nativePermissionAdapter: nativePermissionAdapter,
       );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendMessageRepository repository;

  static Future<_Harness> start(
    FutureOr<_Response> Function(RequestRecord) handler, {
    UnauthorizedRecovery? unauthorizedRecovery,
    NativePermissionAdapter? nativePermissionAdapter,
    FutureOr<_Response> Function(RequestRecord)? notificationSyncHandler,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final _Harness harness = _Harness._(
      server,
      requests,
      unauthorizedRecovery: unauthorizedRecovery,
      nativePermissionAdapter: nativePermissionAdapter,
    );
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        requestId: request.headers.value('X-Request-Id') ?? '',
        authorization: captureContractAuthorization(request),
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Response response =
          record.path == '/app-mini-api/mini/v1/notifications/sync'
          ? await (notificationSyncHandler?.call(record) ??
                _Response.ok(_notificationSyncResponse()))
          : await handler(record);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      if (!response.omitBody) {
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': response.code,
            'message': response.message,
            'data': response.data,
          }),
        );
      }
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class _FakeNativePermissionAdapter implements NativePermissionAdapter {
  _FakeNativePermissionAdapter(this.state);

  PermissionState state;
  int requested = 0;
  int openedSettings = 0;

  @override
  Future<PermissionState> status(PermissionKind kind) async => state;

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    requested++;
    return state;
  }

  @override
  Future<void> openAppSettings() async {
    openedSettings++;
  }
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.query,
    required this.requestId,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String requestId;
  final String authorization;
  final Object? body;
}

class _Response {
  const _Response({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  }) : omitBody = false;

  const _Response.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data,
      omitBody = false;

  const _Response.empty()
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = null,
      omitBody = true;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
  final bool omitBody;
}
