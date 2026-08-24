import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

void main() {
  test(
    'dynamic feed, detail, like, comments, and delete use live contracts',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      int detailCalls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/list') {
          expect(request.method, 'GET');
          expect(request.uri.queryParameters, <String, String>{
            'pageNum': '1',
            'pageSize': '1',
            'category': 'LIFE',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'dynamicId': '42',
                  'userId': 10001,
                  'nickName': '晚星',
                  'content': '今晚听歌吗',
                  'createdAt': '2026-08-22T09:00:00Z',
                  'category': 'LIFE',
                  'topic': '夜聊',
                  'location': '上海',
                  'likeCount': 2,
                  'commentCount': 1,
                  'liked': false,
                  'isLike': 0,
                  'images': <String>[],
                },
              ],
              'list': <Object?>[
                <String, Object?>{
                  'dynamicId': '42',
                  'userId': 10001,
                  'nickName': '晚星',
                  'content': '今晚听歌吗',
                  'createdAt': '2026-08-22T09:00:00Z',
                  'category': 'LIFE',
                  'topic': '夜聊',
                  'location': '上海',
                  'likeCount': 2,
                  'commentCount': 1,
                  'liked': false,
                  'isLike': 0,
                  'images': <String>[],
                },
              ],
              'current': 1,
              'pageSize': 1,
              'total': 2,
              'pages': 2,
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/detail') {
          expect(request.method, 'GET');
          expect(request.uri.queryParameters, <String, String>{
            'dynamicId': '42',
          });
          detailCalls += 1;
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'userId': 10001,
              'nickName': '晚星',
              'content': '今晚听歌吗',
              'createdAt': '2026-08-22T09:00:00Z',
              'category': 'LIFE',
              'topic': '夜聊',
              'location': '上海',
              'likeCount': detailCalls >= 1 ? 3 : 2,
              'commentCount': 1,
              'liked': detailCalls >= 1,
              'isLike': detailCalls >= 1 ? 1 : 0,
              'images': <String>[],
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/comment/list') {
          expect(request.method, 'GET');
          expect(request.uri.queryParameters, <String, String>{
            'dynamicId': '42',
            'pageNum': '2',
            'pageSize': '1',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'commentId': 'c-1',
                  'userId': 10002,
                  'nickName': '南风',
                  'content': '可以呀',
                  'createdAt': '2026-08-22T09:01:00Z',
                  'parentCommentId': 'c-0',
                },
              ],
              'list': <Object?>[
                <String, Object?>{
                  'commentId': 'c-1',
                  'userId': 10002,
                  'nickName': '南风',
                  'content': '可以呀',
                  'createdAt': '2026-08-22T09:01:00Z',
                  'parentCommentId': 'c-0',
                },
              ],
              'current': 2,
              'pageSize': 1,
              'total': 2,
              'pages': 2,
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/like') {
          expect(request.method, 'POST');
          expect(request.uri.queryParameters, isEmpty);
          expect(body, <String, Object?>{
            'dynamicId': '42',
            'liked': true,
            'type': 1,
          });
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'liked': true,
              'isLike': 1,
              'likeCount': 3,
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/comment') {
          expect(request.method, 'POST');
          expect(body, <String, Object?>{
            'dynamicId': 42,
            'content': '收到',
            'replyToUserId': 10002,
            'parentCommentId': 'c-0',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'commentId': 'c-2',
              'userId': 10001,
              'nickName': '晚星',
              'content': '收到',
              'createdAt': '2026-08-22T09:02:00Z',
              'parentCommentId': 'c-0',
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/delete/42') {
          expect(request.method, 'DELETE');
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'deleted': true,
              'status': 'DELETED',
            },
          );
        }
        return _reply(request, status: 404, code: 404, message: 'not found');
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      final PagedResult<DynamicPost> feed = await repository.fetchFeed(
        category: DynamicCategory.companionship,
        page: 1,
        pageSize: 1,
      );
      expect(feed.items.single.id, '42');
      expect(feed.items.single.author.nickname, '晚星');
      expect(feed.items.single.tags, <String>['LIFE']);
      expect(feed.items.single.topics, <String>['夜聊']);
      expect(feed.items.single.isLiked, isFalse);
      expect(feed.items.single.location, '上海');
      expect(feed.hasMore, isTrue);

      final PagedResult<DynamicComment> comments = await repository
          .fetchComments(dynamicId: '42', page: 2, pageSize: 1);
      expect(comments.items.single.id, 'c-1');
      expect(comments.items.single.replyToCommentId, 'c-0');
      expect(comments.hasMore, isFalse);

      final DynamicPost liked = await repository.toggleLike(
        '42',
        liked: true,
        requestId: 'dynamic-like-contract-1',
      );
      expect(liked.isLiked, isTrue);
      expect(liked.likeCount, 3);
      expect(detailCalls, 1);

      final DynamicComment added = await repository.addComment(
        dynamicId: '42',
        content: ' 收到 ',
        replyToUserId: 10002,
        replyToCommentId: 'c-0',
        requestId: 'dynamic-comment-contract-1',
      );
      expect(added.id, 'c-2');
      expect(added.author.userId, 10001);
      expect(added.replyToCommentId, 'c-0');
      await repository.deletePost('42');
      expect(requests.map((_RequestRecord item) => item.method), <String>[
        'GET',
        'GET',
        'POST',
        'GET',
        'POST',
        'DELETE',
      ]);
    },
  );

  test('dynamic publish and rankings serialize first-party fields', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      if (request.uri.path == '/app-mini-api/mini/v1/dynamic/publish') {
        expect(request.method, 'POST');
        expect(body, <String, Object?>{
          'content': '一条新动态',
          'category': 'CHAT',
          'topic': '生活,夜聊',
          'location': '上海',
        });
        return _reply(
          request,
          data: <String, Object?>{
            'dynamicId': '100',
            'userId': 10001,
            'nickname': '晚星',
            'content': '一条新动态',
            'category': 'CHAT',
            'topic': '生活,夜聊',
            'createdAt': '2026-08-22T09:00:00Z',
            'likeCount': 0,
            'commentCount': 0,
            'liked': false,
            'isLike': 0,
            'images': <String>[],
          },
        );
      }
      if (request.uri.path == '/app-api/rankinglist/charmrank') {
        expect(request.method, 'POST');
        expect(body, <String, Object?>{'theType': 2});
        return _reply(
          request,
          data: <String, Object?>{
            'records': <Object?>[
              <String, Object?>{
                'rank': 1,
                'userId': 20001,
                'nickName': '南风',
                'score': 99,
              },
            ],
            'list': <Object?>[
              <String, Object?>{
                'rank': 1,
                'userId': 20001,
                'nickName': '南风',
                'score': 99,
              },
            ],
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'metric': 'CHARM',
            'serverAuthoritative': true,
          },
        );
      }
      if (request.uri.path == '/app-api/dfrank/queryRoomDfRank') {
        expect(request.method, 'POST');
        expect(body, <String, Object?>{'rankType': 1});
        return _reply(
          request,
          data: <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'rank': 1,
                'roomId': 'room-1',
                'roomName': '夜航',
                'score': 88,
              },
            ],
            'records': <Object?>[
              <String, Object?>{
                'rank': 1,
                'roomId': 'room-1',
                'roomName': '夜航',
                'score': 88,
              },
            ],
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'metric': 'ROOM_CONTRIBUTION',
            'serverAuthoritative': true,
          },
        );
      }
      return _reply(request, status: 404, code: 404, message: 'not found');
    });
    addTearDown(() => server.close(force: true));
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

    final DynamicPost post = await repository.publish(
      const PublishDynamicRequest(
        content: ' 一条新动态 ',
        category: DynamicCategory.chat,
        topics: <String>['生活', '夜聊'],
        location: ' 上海 ',
      ),
      requestId: 'dynamic-publish-contract-1',
    );
    expect(post.id, '100');
    expect(post.tags, <String>['CHAT']);
    expect(post.topics, <String>['生活', '夜聊']);
    final RankingSnapshot users = await repository.fetchRanking(
      board: RankingBoard.charm,
      period: RankingPeriod.week,
    );
    expect(users.entries.single.userId, 20001);
    expect(users.entries.single.rank, 1);
    expect(users.entries.single.value, 99);
    final RankingSnapshot rooms = await repository.fetchRanking(
      board: RankingBoard.room,
      period: RankingPeriod.day,
    );
    expect(rooms.entries.single.roomId, 'room-1');
    expect(rooms.entries.single.rank, 1);
    expect(rooms.entries.single.value, 88);
  });

  test('media publishing remains explicitly vendor blocked', () async {
    final HttpServer server = await _startServer(
      (HttpRequest request, Object? body) => _reply(
        request,
        status: 500,
        code: 50001,
        message: 'must not be called',
      ),
    );
    addTearDown(() => server.close(force: true));
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );
    expect(repository.supportsImagePublishing, isFalse);
    await expectLater(
      repository.publish(
        const PublishDynamicRequest(
          content: '图片动态',
          category: DynamicCategory.chat,
          images: <String>['local://image'],
        ),
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
  });

  test(
    'dynamic error envelopes preserve 400, 403, 409, 422, and 500 kinds',
    () async {
      const List<int> statuses = <int>[400, 403, 409, 422, 500];
      for (final int status in statuses) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(
            request,
            status: status,
            code: status == 500 ? 50001 : status * 100,
            message: 'failure',
          ),
        );
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );
        final ApiFailureKind expected = switch (status) {
          403 => ApiFailureKind.forbidden,
          409 => ApiFailureKind.conflict,
          500 => ApiFailureKind.server,
          _ => ApiFailureKind.validation,
        };
        await expectLater(
          repository.fetchFeed(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              expected,
            ),
          ),
        );
        await server.close(force: true);
      }
    },
  );

  test(
    'empty mutation responses fail closed instead of creating local data',
    () async {
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/detail') {
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'userId': 10001,
              'nickName': '晚星',
              'content': '内容',
              'liked': false,
            },
          );
        }
        return _reply(request, data: <String, Object?>{});
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );
      await expectLater(
        repository.toggleLike('42', liked: true),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.addComment(dynamicId: '42', content: '评论'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('dynamic detail must echo the requested post id', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/detail');
      return _reply(
        request,
        data: <String, Object?>{
          'dynamicId': 'different-post',
          'userId': 10001,
          'content': '不属于请求的动态',
          'createdAt': '2026-08-22T09:00:00Z',
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.fetchPost('42'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('dynamic comments require server ids and service timestamps', () async {
    int call = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/comment');
      final int index = call++;
      final Map<String, Object?> data = index == 0
          ? <String, Object?>{
              'content': '缺少评论编号',
              'createdAt': '2026-08-22T09:00:00Z',
            }
          : <String, Object?>{
              'commentId': 'comment-1',
              'content': '缺少服务时间',
              'createdAt': 'not-a-time',
            };
      return _reply(request, data: data);
    });
    addTearDown(() => server.close(force: true));
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

    for (int index = 0; index < 2; index += 1) {
      await expectLater(
        repository.addComment(dynamicId: '42', content: '评论'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    }
  });

  test(
    'dynamic posts require service timestamps and pagination metadata',
    () async {
      int call = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/list');
        final int index = call++;
        final Map<String, Object?> data = index == 0
            ? <String, Object?>{
                'records': <Object?>[
                  <String, Object?>{
                    'dynamicId': '42',
                    'userId': 10001,
                    'content': '缺少服务时间',
                  },
                ],
                'total': 1,
              }
            : <String, Object?>{
                'records': <Object?>[
                  <String, Object?>{
                    'dynamicId': '42',
                    'userId': 10001,
                    'content': '缺少分页元数据',
                    'createdAt': '2026-08-22T09:00:00Z',
                  },
                ],
              };
        return _reply(request, data: data);
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 2; index += 1) {
        await expectLater(
          repository.fetchFeed(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
    },
  );

  test(
    'dynamic write retries preserve X-Request-Id and desired state on ambiguous failures',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      int likeAttempts = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/like') {
          likeAttempts += 1;
          expect(request.method, 'POST');
          expect(request.headers.value('X-Request-Id'), 'dynamic-like-retry-1');
          expect(body, <String, Object?>{
            'dynamicId': '42',
            'liked': true,
            'type': 1,
          });
          if (likeAttempts == 1) {
            return _reply(
              request,
              status: 500,
              code: 50001,
              message: 'committed but response unknown',
            );
          }
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'liked': true,
              'isLike': 1,
              'likeCount': 3,
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/detail') {
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'userId': 10001,
              'nickName': '晚星',
              'content': '今晚听歌吗',
              'createdAt': '2026-08-22T09:00:00Z',
              'category': 'CHAT',
              'topic': '夜聊',
              'location': '上海',
              'likeCount': 3,
              'commentCount': 1,
              'liked': true,
              'isLike': 1,
              'images': <String>[],
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/comment') {
          expect(request.method, 'POST');
          expect(
            request.headers.value('X-Request-Id'),
            'dynamic-comment-retry-1',
          );
          expect(body, <String, Object?>{'dynamicId': 42, 'content': '同一条评论'});
          return _reply(
            request,
            data: <String, Object?>{
              'commentId': 'comment-1',
              'userId': 10001,
              'nickName': '晚星',
              'content': '同一条评论',
              'createdAt': '2026-08-22T09:02:00Z',
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/publish') {
          expect(request.method, 'POST');
          expect(
            request.headers.value('X-Request-Id'),
            'dynamic-publish-retry-1',
          );
          expect(body, <String, Object?>{
            'content': '幂等动态',
            'category': 'CHAT',
            'topic': '生活',
            'location': '上海',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '100',
              'userId': 10001,
              'nickname': '晚星',
              'content': '幂等动态',
              'category': 'CHAT',
              'topic': '生活',
              'createdAt': '2026-08-22T09:00:00Z',
              'likeCount': 0,
              'commentCount': 0,
              'liked': false,
              'isLike': 0,
              'images': <String>[],
            },
          );
        }
        return _reply(request, status: 404, code: 404, message: 'not found');
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.toggleLike(
          '42',
          liked: true,
          requestId: 'dynamic-like-retry-1',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      final DynamicPost liked = await repository.toggleLike(
        '42',
        liked: true,
        requestId: 'dynamic-like-retry-1',
      );
      expect(liked.isLiked, isTrue);

      final DynamicComment comment = await repository.addComment(
        dynamicId: '42',
        content: '同一条评论',
        requestId: 'dynamic-comment-retry-1',
      );
      expect(comment.id, 'comment-1');

      final DynamicPost published = await repository.publish(
        const PublishDynamicRequest(
          content: '幂等动态',
          category: DynamicCategory.chat,
          topics: <String>['生活'],
          location: '上海',
        ),
        requestId: 'dynamic-publish-retry-1',
      );
      expect(published.id, '100');
      expect(
        requests
            .where(
              (_RequestRecord item) =>
                  item.path == '/app-mini-api/mini/v1/dynamic/like',
            )
            .map((_RequestRecord item) => item.requestId)
            .toSet(),
        <String>{'dynamic-like-retry-1'},
      );
    },
  );

  test(
    'dynamic pages require the first-party current, pageSize, total, pages, and records fields',
    () async {
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        _dynamicPagePayload()..remove('current'),
        _dynamicPagePayload()..remove('pageSize'),
        _dynamicPagePayload()..remove('total'),
        _dynamicPagePayload()..remove('pages'),
        _dynamicPagePayload()..remove('records'),
      ];

      for (final Map<String, Object?> payload in payloads) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(request, data: payload),
        );
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );
        await expectLater(
          repository.fetchFeed(page: 1, pageSize: 1),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await server.close(force: true);
      }
    },
  );

  for (final (int status, ApiFailureKind kind) in <(int, ApiFailureKind)>[
    (401, ApiFailureKind.unauthorized),
    (403, ApiFailureKind.forbidden),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test(
      'dynamic comment preserves $status failure without fake success',
      () async {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(
            request,
            status: status,
            code: status == 500 ? 50001 : status,
            message: 'comment failure $status',
          ),
        );
        addTearDown(() => server.close(force: true));
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );

        await expectLater(
          repository.addComment(
            dynamicId: '42',
            content: '不会伪造成功',
            requestId: 'dynamic-comment-failure-$status',
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException error) => error.kind, 'kind', kind)
                .having(
                  (ApiException error) => error.message,
                  'message',
                  'comment failure $status',
                ),
          ),
        );
      },
    );
  }

  for (final (int conflictCode, bool shouldReuseRequestId) in <(int, bool)>[
    (40901, true),
    (40902, true),
    (40903, false),
  ]) {
    test(
      'dynamic delete handles $conflictCode with explicit request-id policy',
      () async {
        final List<String> requestIds = <String>[];
        int calls = 0;
        final HttpServer server = await _startServer((
          HttpRequest request,
          Object? body,
        ) {
          expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/delete/42');
          requestIds.add(request.headers.value('X-Request-Id') ?? '');
          calls += 1;
          if (calls == 1) {
            return _reply(
              request,
              status: 409,
              code: conflictCode,
              message: 'idempotency conflict',
            );
          }
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '42',
              'deleted': true,
              'status': 'DELETED',
            },
          );
        });
        addTearDown(() => server.close(force: true));
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );

        await expectLater(
          repository.deletePost('42'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.code,
              'code',
              conflictCode,
            ),
          ),
        );
        await repository.deletePost('42');

        expect(requestIds, hasLength(2));
        expect(requestIds[0], isNotEmpty);
        expect(
          requestIds[1] == requestIds[0],
          shouldReuseRequestId,
          reason: '$conflictCode request-id policy',
        );
      },
    );
  }

  test(
    'dynamic pages require request-aligned current and pageSize and consistent totals',
    () async {
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        _dynamicPagePayload()..['current'] = 2,
        _dynamicPagePayload()..['pageSize'] = 2,
        _dynamicPagePayload()..['total'] = 3,
        _dynamicPagePayload()..['pages'] = 2,
      ];
      // The last payload has total=2 and pages=2 but pageSize=1, so it remains
      // valid; replace it with a genuinely inconsistent pages value.
      payloads[3]['total'] = 2;
      payloads[3]['pages'] = 3;

      for (final Map<String, Object?> payload in payloads) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(request, data: payload),
        );
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );
        await expectLater(
          repository.fetchFeed(page: 1, pageSize: 1),
          throwsA(isA<ApiException>()),
        );
        await server.close(force: true);
      }
    },
  );

  test(
    'dynamic pages reject non-map records instead of silently dropping them',
    () async {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          data: <String, Object?>{
            ..._dynamicPagePayload(),
            'pageSize': 2,
            'total': 2,
            'pages': 1,
            'records': <Object?>[_dynamicPostRecord(), 'not-a-record'],
          },
        ),
      );
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchFeed(page: 1, pageSize: 2),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await server.close(force: true);
    },
  );

  test(
    'dynamic pages reject item counts that disagree with total and page size',
    () async {
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        <String, Object?>{
          ..._dynamicPagePayload(),
          'pageSize': 2,
          'total': 3,
          'pages': 2,
          'records': <Object?>[_dynamicPostRecord()],
        },
        <String, Object?>{
          ..._dynamicPagePayload(),
          'current': 2,
          'pageSize': 2,
          'total': 3,
          'pages': 2,
          'records': <Object?>[
            _dynamicPostRecord(),
            _dynamicPostRecord(id: '43'),
          ],
        },
      ];

      for (final Map<String, Object?> payload in payloads) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(request, data: payload),
        );
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );
        await expectLater(
          repository.fetchFeed(
            page: payload['current'] as int? ?? 1,
            pageSize: payload['pageSize'] as int? ?? 2,
          ),
          throwsA(isA<ApiException>()),
        );
        await server.close(force: true);
      }
    },
  );

  test(
    'dynamic pages reject an empty page that still claims more data',
    () async {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          data: <String, Object?>{
            ..._dynamicPagePayload(),
            'total': 2,
            'pages': 2,
            'records': <Object?>[],
          },
        ),
      );
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchFeed(page: 1, pageSize: 1),
        throwsA(isA<ApiException>()),
      );
      await server.close(force: true);
    },
  );

  test(
    'dynamic pages accept an empty requested page beyond the latest total',
    () async {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          data: <String, Object?>{
            'current': 2,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'records': <Object?>[],
            'list': <Object?>[],
          },
        ),
      );
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      final PagedResult<DynamicPost> result = await repository.fetchFeed(
        page: 2,
        pageSize: 20,
      );
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
      await server.close(force: true);
    },
  );

  test('dynamic pages allow valid datasets with more than 100 pages', () async {
    final HttpServer server = await _startServer(
      (HttpRequest request, Object? body) => _reply(
        request,
        data: <String, Object?>{
          ..._dynamicPagePayload(),
          'pageSize': 1,
          'total': 101,
          'pages': 101,
          'records': <Object?>[_dynamicPostRecord()],
          'list': <Object?>[_dynamicPostRecord()],
        },
      ),
    );
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

    final PagedResult<DynamicPost> page = await repository.fetchFeed(
      page: 1,
      pageSize: 1,
    );
    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    await server.close(force: true);
  });

  test(
    'dynamic delete requires the authoritative final state response',
    () async {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          data: <String, Object?>{
            'dynamicId': '42',
            'deleted': false,
            'status': 'DELETED',
          },
        ),
      );
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.deletePost('42'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await server.close(force: true);
    },
  );

  test(
    'dynamic delete retains pending idempotency keys and coalesces duplicates',
    () async {
      final List<String> requestIds = <String>[];
      final Completer<void> releaseCommittedReplay = Completer<void>();
      int calls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/delete/42');
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        calls += 1;
        if (calls == 1) {
          return _reply(
            request,
            status: 409,
            code: 40902,
            message: 'request still in progress',
          );
        }
        if (calls == 2) {
          await releaseCommittedReplay.future;
        }
        return _reply(
          request,
          data: <String, Object?>{
            'dynamicId': '42',
            'deleted': true,
            'status': 'DELETED',
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.deletePost('42'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40902,
          ),
        ),
      );
      final Future<void> retry = repository.deletePost('42');
      final Future<void> duplicate = repository.deletePost('42');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 2);
      releaseCommittedReplay.complete();
      await Future.wait(<Future<void>>[retry, duplicate]);

      expect(requestIds, hasLength(2));
      expect(requestIds[0], isNotEmpty);
      expect(requestIds[1], requestIds[0]);
    },
  );

  test(
    'dynamic ranking rejects non-authoritative or incomplete pages',
    () async {
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        <String, Object?>{
          'records': <Object?>[],
          'list': <Object?>[],
          'current': 1,
          'pageSize': 20,
          'total': 0,
          'pages': 0,
          'metric': 'CHARM',
          'serverAuthoritative': false,
        },
        <String, Object?>{
          'records': <Object?>[
            <String, Object?>{
              'rank': 1,
              'userId': 10001,
              'nickName': '晚星',
              'score': 1,
            },
          ],
          'list': <Object?>[],
          'current': 1,
          'pageSize': 20,
          'total': 1,
          'pages': 1,
          'metric': 'CHARM',
          'serverAuthoritative': true,
        },
        <String, Object?>{
          'records': <Object?>[],
          'list': <Object?>[],
          'current': 1,
          'pageSize': 10,
          'total': 0,
          'pages': 0,
          'metric': 'CHARM',
          'serverAuthoritative': true,
        },
      ];
      for (final Map<String, Object?> payload in payloads) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(request, data: payload),
        );
        final BackendDynamicRepository repository = BackendDynamicRepository(
          apiClient: _client(server),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 10001,
        );
        await expectLater(
          repository.fetchRanking(
            board: RankingBoard.charm,
            period: RankingPeriod.day,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await server.close(force: true);
      }
    },
  );

  test('dynamic posts reject missing authoritative fields', () async {
    final List<String> missingFields = <String>[
      'userId',
      'nickName',
      'content',
      'likeCount',
      'commentCount',
      'liked',
      'images',
    ];
    for (final String missingField in missingFields) {
      final Map<String, Object?> record = _dynamicPostRecord();
      record.remove(missingField);
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          data: <String, Object?>{
            ..._dynamicPagePayload(),
            'records': <Object?>[record],
            'list': <Object?>[record],
          },
        ),
      );
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );
      await expectLater(
        repository.fetchFeed(),
        throwsA(isA<ApiException>()),
        reason: missingField,
      );
      await server.close(force: true);
    }
  });

  test('dynamic pages reject divergent list and records aliases', () async {
    final HttpServer server = await _startServer(
      (HttpRequest request, Object? body) => _reply(
        request,
        data: <String, Object?>{
          ..._dynamicPagePayload(),
          'list': <Object?>[_dynamicPostRecord(id: 'different')],
        },
      ),
    );
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );
    await expectLater(repository.fetchFeed(), throwsA(isA<ApiException>()));
    await server.close(force: true);
  });

  test(
    'dynamic page requests reject non-positive values and oversized pageSize',
    () async {
      bool called = false;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        called = true;
        await _reply(request, data: _dynamicPagePayload());
      });
      final BackendDynamicRepository repository = BackendDynamicRepository(
        apiClient: _client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );

      for (final ({int page, int pageSize}) request
          in <({int page, int pageSize})>[
            (page: 0, pageSize: 1),
            (page: 1, pageSize: 0),
            (page: 1, pageSize: 51),
          ]) {
        await expectLater(
          repository.fetchFeed(page: request.page, pageSize: request.pageSize),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.validation,
            ),
          ),
        );
      }
      expect(called, isFalse);
      await server.close(force: true);
    },
  );
}

Map<String, Object?> _dynamicPagePayload() => <String, Object?>{
  'current': 1,
  'pageSize': 1,
  'total': 1,
  'pages': 1,
  'records': <Object?>[_dynamicPostRecord()],
  'list': <Object?>[_dynamicPostRecord()],
};

Map<String, Object?> _dynamicPostRecord({String id = '42'}) =>
    <String, Object?>{
      'dynamicId': id,
      'userId': 10001,
      'nickName': '晚星',
      'content': '内容',
      'category': 'CHAT',
      'likeCount': 0,
      'commentCount': 0,
      'liked': false,
      'isLike': 0,
      'images': <String>[],
      'createdAt': '2026-08-22T09:00:00Z',
    };

class _RequestRecord {
  _RequestRecord(HttpRequest request, this.body)
    : method = request.method,
      path = request.uri.path,
      authorization = captureContractAuthorization(request),
      requestId = request.headers.value('X-Request-Id') ?? '';

  final String method;
  final String path;
  final String authorization;
  final String requestId;
  final Object? body;
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request, Object? body) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? body = raw.trim().isEmpty ? null : jsonDecode(raw);
    await handler(request, body);
  });
  return server;
}

Future<void> _reply(
  HttpRequest request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{
        'code': code,
        'message': message,
        'data': data,
      }),
    );
  await request.response.close();
}

ApiClient _client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);
