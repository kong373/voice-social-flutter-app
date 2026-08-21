import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

void main() {
  test(
    'dynamic feed, comments, like, comment, and delete use live contracts',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
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
            'tags': '音乐',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'id': '42',
                  'userId': 10001,
                  'nickName': '晚星',
                  'content': '今晚听歌吗',
                  'createTimeText': '刚刚',
                  'likeCount': 2,
                  'commentCount': 1,
                  'isLiked': false,
                  'tags': '音乐,陪伴',
                },
              ],
              'total': 2,
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
                  'createTimeText': '1分钟前',
                  'replyToUserId': 10001,
                  'replyToNickname': '晚星',
                  'replyToCommentId': 'c-0',
                },
              ],
              'pages': 2,
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/like') {
          expect(request.method, 'POST');
          expect(request.uri.queryParameters, <String, String>{
            'dynamicId': '42',
          });
          return _reply(request, data: null);
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/comment') {
          expect(request.method, 'POST');
          expect(body, <String, Object?>{
            'dynamicId': 42,
            'content': '收到',
            'replyToUserId': 10002,
            'replyToCommentId': 7,
          });
          return _reply(
            request,
            data: <String, Object?>{
              'commentId': 'c-2',
              'userId': 10001,
              'nickName': '晚星',
              'content': '收到',
              'createTimeText': '刚刚',
            },
          );
        }
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/delete/42') {
          expect(request.method, 'DELETE');
          return _reply(request, data: null);
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
        category: DynamicCategory.music,
        page: 1,
        pageSize: 1,
      );
      expect(feed.items.single.id, '42');
      expect(feed.items.single.author.nickname, '晚星');
      expect(feed.items.single.tags, <String>['音乐', '陪伴']);
      expect(feed.hasMore, isTrue);

      final PagedResult<DynamicComment> comments = await repository
          .fetchComments(dynamicId: '42', page: 2, pageSize: 1);
      expect(comments.items.single.id, 'c-1');
      expect(comments.items.single.replyToCommentId, 'c-0');
      expect(comments.hasMore, isFalse);

      final DynamicPost liked = await repository.toggleLike('42');
      expect(liked.isLiked, isTrue);
      expect(liked.likeCount, 3);

      final DynamicComment added = await repository.addComment(
        dynamicId: '42',
        content: ' 收到 ',
        replyToUserId: 10002,
        replyToCommentId: '7',
      );
      expect(added.id, 'c-2');
      expect(added.author.userId, 10001);
      await repository.deletePost('42');
      expect(requests.map((_RequestRecord item) => item.method), <String>[
        'GET',
        'GET',
        'POST',
        'POST',
        'DELETE',
      ]);
    },
  );

  test(
    'dynamic publish and rankings serialize backend-specific payloads',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        if (request.uri.path == '/app-mini-api/mini/v1/dynamic/publish') {
          expect(request.method, 'POST');
          expect(body, <String, Object?>{
            'content': '一条新动态',
            'images': '',
            'tags': '聊天',
            'location': '上海',
            'topics': '生活,夜聊',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'dynamicId': '100',
              'userId': 10001,
              'nickname': '晚星',
              'content': '一条新动态',
              'createTime': '刚刚',
            },
          );
        }
        if (request.uri.path == '/app-api/rankinglist/charmrank') {
          expect(body, <String, Object?>{'theType': 2});
          return _reply(
            request,
            data: <String, Object?>{
              'ranks': <Object?>[
                <String, Object?>{
                  'rankNo': 1,
                  'attachUserId': 20001,
                  'userNickname': '南风',
                  'theVal': 99,
                },
              ],
              'countdown': 120,
              'selfRank': <String, Object?>{
                'rankNo': 8,
                'attachUserId': 10001,
                'userNickname': '晚星',
                'theVal': 22,
              },
            },
          );
        }
        if (request.uri.path == '/app-api/dfrank/queryRoomDfRank') {
          expect(body, <String, Object?>{'rankType': 1});
          return _reply(
            request,
            data: <String, Object?>{
              'itemVos': <Object?>[
                <String, Object?>{
                  'rankNo': 1,
                  'roomId': 'room-1',
                  'roomName': '夜航',
                  'theVal': 88,
                  'text': '热度',
                },
              ],
              'cd': 60,
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
      );
      expect(post.id, '100');
      final RankingSnapshot users = await repository.fetchRanking(
        board: RankingBoard.charm,
        period: RankingPeriod.week,
      );
      expect(users.entries.single.userId, 20001);
      expect(users.selfEntry?.rank, 8);
      final RankingSnapshot rooms = await repository.fetchRanking(
        board: RankingBoard.room,
        period: RankingPeriod.day,
      );
      expect(rooms.entries.single.roomId, 'room-1');
      expect(rooms.countdownSeconds, 60);
      expect(requests, hasLength(3));
    },
  );

  test('dynamic error envelope is surfaced as unauthorized', () async {
    final HttpServer server = await _startServer(
      (HttpRequest request, Object? body) => _reply(
        request,
        status: 401,
        code: 40100,
        message: '登录已过期',
        data: null,
      ),
    );
    addTearDown(() => server.close(force: true));
    final BackendDynamicRepository repository = BackendDynamicRepository(
      apiClient: _client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.fetchFeed(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });
}

class _RequestRecord {
  _RequestRecord(HttpRequest request, this.body)
    : method = request.method,
      path = request.uri.path;

  final String method;
  final String path;
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
