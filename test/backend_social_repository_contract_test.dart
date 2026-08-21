import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

void main() {
  test(
    'profile, profile update, and public profile use exact endpoints',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/user/getPersonalData':
            return _reply(
              request,
              data: <String, Object?>{
                'id': 10001,
                'loginName': '13800138000',
                'nickName': '晚星',
                'signature': '和晚风聊天',
                'fansNum': 8,
                'attentionNum': 12,
                'dynamicNum': 3,
              },
            );
          case '/app-api/user/updateUserByUserId':
            expect(request.method, 'PATCH');
            expect(body, <String, Object?>{
              'nickName': '新晚星',
              'signature': '新的签名',
              'sex': 2,
              'birthday': '2000-01-02',
              'address': '上海',
            });
            return _reply(request, data: null);
          case '/app-api/user/personalHomepage':
            if (request.uri.queryParameters.containsKey('userId')) {
              expect(request.method, 'GET');
              expect(request.uri.queryParameters, <String, String>{
                'userId': '20003',
              });
              return _reply(
                request,
                data: <String, Object?>{
                  'id': 20003,
                  'nickName': '南风',
                  'signature': '听见风',
                  'isAttention': 2,
                  'isOnline': 1,
                  'fansNum': 20,
                  'attentionNum': 9,
                },
              );
            }
            return _reply(
              request,
              data: <String, Object?>{
                'id': 10001,
                'nickName': '晚星',
                'signature': '和晚风聊天',
                'fansNum': 8,
                'attentionNum': 12,
                'dynamicNum': 3,
                'level': 7,
              },
            );
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      final SocialProfile before = await repository.fetchMyProfile();
      expect(before.user.userId, 10001);
      expect(before.user.name, '晚星');
      expect(before.account, '13800138000');
      expect(before.followerCount, 8);
      expect(before.level, 7);

      final SocialProfile after = await repository.updateMyProfile(
        nickname: '新晚星',
        signature: '新的签名',
        sex: 2,
        birthday: '2000-01-02',
        city: '上海',
      );
      expect(after.user.name, '晚星');

      final SocialProfile publicProfile = await repository.fetchPublicProfile(
        20003,
      );
      expect(publicProfile.user.userId, 20003);
      expect(publicProfile.user.name, '南风');
      expect(publicProfile.user.isFollowing, isTrue);
      expect(publicProfile.user.isFriend, isFalse);
      expect(requests.map((_RequestRecord item) => item.path), <String>[
        '/app-api/user/getPersonalData',
        '/app-api/user/personalHomepage',
        '/app-api/user/updateUserByUserId',
        '/app-api/user/getPersonalData',
        '/app-api/user/personalHomepage',
        '/app-api/user/personalHomepage',
      ]);
    },
  );

  test(
    'relations, visitors, blacklist, and privacy preserve pagination/query',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/user/relation/queryUserFollowList':
          case '/app-api/user/relation/queryUserFansList':
          case '/app-api/user/relation/queryUserPlaymateList':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{
              'pageNum': 2,
              'pageSize': 2,
              'isSearchCount': true,
            });
            return _reply(
              request,
              data: <String, Object?>{
                'current': 2,
                'size': 2,
                'total': 6,
                'pages': 3,
                'list': <Object?>[
                  <String, Object?>{
                    'userId': 20001,
                    'nickName': '南风',
                    'signature': '听见风',
                    'mark': 0,
                    'isOnline': 1,
                  },
                ],
              },
            );
          case '/app-api/user/personalHomepage/visitedRecords':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'type': '1',
              'pageNum': '1',
              'pageSize': '20',
              'isSearchCount': 'true',
            });
            return _reply(
              request,
              data: <String, Object?>{
                'current': 1,
                'size': 20,
                'total': 0,
                'list': <Object?>[],
              },
            );
          case '/app-api/user/relation/queryUserBlackList':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{
              'pageNum': 1,
              'pageSize': 20,
              'isSearchCount': true,
            });
            return _reply(
              request,
              data: <String, Object?>{
                'current': 1,
                'size': 20,
                'total': 1,
                'pages': 1,
                'list': <Object?>[
                  <String, Object?>{
                    'userId': 20002,
                    'nickName': '被屏蔽用户',
                    'headImgUrl': 'https://example.test/avatar.png',
                  },
                ],
              },
            );
          case '/app-api/user/relation/buildFriendRelation':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'userId': '20001',
              'type': '1',
            });
            return _reply(request, data: null);
          case '/app-api/user/relation/blackUserRelation':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'userId': '20002',
              'type': '1',
            });
            return _reply(request, data: null);
          case '/app-api/user/onlyFollowedCanFollow/set':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{'type': '1'});
            return _reply(request, data: null);
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (final SocialRelationList type in SocialRelationList.values) {
        final SocialPage<SocialUser> page = await repository.fetchRelations(
          type: type,
          page: 2,
          pageSize: 2,
        );
        expect(page.items.single.userId, 20001);
        expect(page.hasMore, isTrue);
      }
      final SocialPage<SocialUser> visitors = await repository.fetchVisitors(
        type: VisitorRecordType.viewedMe,
        page: 1,
        pageSize: 20,
      );
      expect(visitors.items, isEmpty);
      final SocialPage<SocialUser> blacklist = await repository.fetchBlacklist(
        page: 1,
        pageSize: 20,
      );
      expect(blacklist.items.single.isBlocked, isTrue);
      await repository.setFollowing(userId: 20001, following: true);
      await repository.setBlocked(userId: 20002, blocked: true);
      final PrivacySettings privacy = await repository.updatePrivacySettings(
        onlyFollowedCanFollow: true,
      );
      expect(privacy.onlyFollowedCanFollow, isTrue);
      expect(privacy.serverValueKnown, isTrue);
      expect(requests, hasLength(8));
    },
  );

  test(
    'report, customer service, and feedback keep safe payload boundaries',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/util/tipOffUserOrRoom':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{
              'userId': 10001,
              'beTipUserId': 20003,
              'beTipRoomId': null,
              'tipType': 2,
              'tipDescrib': '房间内持续骚扰',
              'tipOffImages': <String>[],
              'type': 1,
            });
            return _reply(request, data: null);
          case '/app-api/user/getCustomerServiceDetail':
            expect(request.method, 'GET');
            return _reply(
              request,
              data: <String, Object?>{'accid': 'service-1'},
            );
          case '/app-api/suggestion/saveSugggestion':
            expect(request.method, 'POST');
            expect(request.uri.queryParameters, <String, String>{
              'content': '页面反馈',
            });
            return _reply(request, data: null);
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      final String receipt = await repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: ' 房间内持续骚扰 ',
        alsoBlock: true,
      );
      expect(receipt, startsWith('server-'));
      final SupportChannel channel = await repository.fetchCustomerService();
      expect(channel.id, 'service-1');
      expect(channel.liveConversationAvailable, isFalse);
      final SupportTicket ticket = await repository.submitFeedback(
        subject: '页面问题',
        content: ' 页面反馈 ',
      );
      expect(ticket.status, SupportTicketStatus.submitted);
      expect((await repository.fetchSupportTicket(ticket.id)).id, ticket.id);
      expect(requests, hasLength(3));
    },
  );

  test(
    'social authentication envelope is not converted into an empty profile',
    () async {
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
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchPublicProfile(20003),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.unauthorized,
          ),
        ),
      );
    },
  );
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
