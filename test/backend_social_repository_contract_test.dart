import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
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
                'userId': 10001,
                'loginName': '13800138000',
                'nickName': '晚星',
                'headImageUrl': '',
                'mobile': '138****0000',
                'sex': 0,
                'birthday': '',
                'roles': 'ROLE_USER',
                'status': 'ACTIVE',
                'realNameAuthStatus': 0,
                'forbiddenState': 0,
              },
            );
          case '/app-api/user/updateUserByUserId':
            expect(request.method, 'PATCH');
            expect(request.headers.value('X-Request-Id'), isNotEmpty);
            expect(body, <String, Object?>{
              'nickName': '新晚星',
              'signature': '新的签名',
              'sex': 2,
              'birthday': '2000-01-02',
              'address': '上海',
            });
            return _reply(
              request,
              data: <String, Object?>{
                'id': 10001,
                'loginName': '13800138000',
                'nickName': '新晚星',
                'signature': '新的签名',
                'headImgUrl': '',
                'piAddress': '上海',
                'address': '上海',
                'sex': 2,
                'birthday': '2000-01-02',
                'coverImgUrl': '',
                'status': 'ACTIVE',
                'realNameAuthStatus': 0,
                'fansNum': 8,
                'attentionNum': 12,
                'dynamicNum': 3,
                'level': 7,
                'playmateNum': 0,
                'isAttention': 0,
                'isBlacklist': false,
                'isOnline': 0,
                'isInRoom': 0,
                'roomId': '',
              },
            );
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
                  'loginName': 'public-20003',
                  'nickName': '南风',
                  'signature': '听见风',
                  'headImgUrl': 'https://example.test/public-head.png',
                  'piAddress': '',
                  'address': '',
                  'sex': 0,
                  'birthday': '',
                  'coverImgUrl': '',
                  'status': 'ACTIVE',
                  'realNameAuthStatus': 0,
                  'isAttention': 2,
                  'isBlacklist': false,
                  'isOnline': 1,
                  'isInRoom': 0,
                  'roomId': '',
                  'fansNum': 20,
                  'attentionNum': 9,
                  'playmateNum': 0,
                  'dynamicNum': 0,
                  'level': 1,
                },
              );
            }
            return _reply(
              request,
              data: <String, Object?>{
                'id': 10001,
                'loginName': '13800138000',
                'nickName': '晚星',
                'signature': '和晚风聊天',
                'headImgUrl': '',
                'piAddress': '',
                'address': '',
                'sex': 0,
                'birthday': '',
                'coverImgUrl': '',
                'status': 'ACTIVE',
                'realNameAuthStatus': 0,
                'fansNum': 8,
                'attentionNum': 12,
                'dynamicNum': 3,
                'level': 7,
                'playmateNum': 0,
                'isAttention': 0,
                'isBlacklist': false,
                'isOnline': 0,
                'isInRoom': 0,
                'roomId': '',
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
      expect(after.user.name, '新晚星');
      expect(after.user.signature, '新的签名');
      expect(after.city, '上海');

      final SocialProfile publicProfile = await repository.fetchPublicProfile(
        20003,
      );
      expect(publicProfile.user.userId, 20003);
      expect(publicProfile.user.name, '南风');
      expect(
        publicProfile.user.avatarUrl,
        'https://example.test/public-head.png',
      );
      expect(publicProfile.user.isFollowing, isTrue);
      expect(publicProfile.user.isFriend, isFalse);
      expect(requests.map((_RequestRecord item) => item.path), <String>[
        '/app-api/user/getPersonalData',
        '/app-api/user/personalHomepage',
        '/app-api/user/updateUserByUserId',
        '/app-api/user/personalHomepage',
      ]);
    },
  );

  test('profile preserves an explicit unavailable level authority', () async {
    final Map<String, Object?> personal = <String, Object?>{
      'userId': 10001,
      'loginName': 'public-10001',
      'nickName': '新用户',
      'headImageUrl': '',
      'sex': 0,
      'birthday': '',
    };
    final Map<String, Object?> homepage = <String, Object?>{
      'id': 10001,
      'loginName': 'public-10001',
      'nickName': '新用户',
      'signature': '',
      'headImgUrl': '',
      'piAddress': '',
      'sex': 0,
      'birthday': '',
      'coverImgUrl': '',
      'attentionNum': 0,
      'fansNum': 0,
      'playmateNum': 0,
      'dynamicNum': 0,
      'level': null,
      'levelAvailable': false,
      'levelStatus': 'UNAVAILABLE',
      'isAttention': 0,
      'isBlacklist': false,
      'isOnline': 1,
      'isInRoom': 0,
      'roomId': '',
    };
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      return _reply(
        request,
        data: request.uri.path == '/app-api/user/getPersonalData'
            ? personal
            : homepage,
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    final SocialProfile profile = await repository.fetchMyProfile();

    expect(profile.level, isNull);
    expect(profile.levelAvailable, isFalse);
    final SocialProfile available = profile.copyWith(level: 3);
    expect(available.level, 3);
    expect(available.levelAvailable, isTrue);
    final SocialProfile unavailable = available.copyWith(clearLevel: true);
    expect(unavailable.level, isNull);
    expect(unavailable.levelAvailable, isFalse);
  });

  test('unavailable level authority fails closed when contradictory', () async {
    final Map<String, Object?> personal = <String, Object?>{
      'userId': 10001,
      'loginName': 'public-10001',
      'nickName': '新用户',
      'headImageUrl': '',
      'sex': 0,
      'birthday': '',
    };
    final Map<String, Object?> baseHomepage = <String, Object?>{
      'id': 10001,
      'loginName': 'public-10001',
      'nickName': '新用户',
      'signature': '',
      'headImgUrl': '',
      'piAddress': '',
      'sex': 0,
      'birthday': '',
      'coverImgUrl': '',
      'attentionNum': 0,
      'fansNum': 0,
      'playmateNum': 0,
      'dynamicNum': 0,
      'level': null,
      'levelAvailable': false,
      'levelStatus': 'UNAVAILABLE',
      'isAttention': 0,
      'isBlacklist': false,
      'isOnline': 1,
      'isInRoom': 0,
      'roomId': '',
    };
    final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
      <String, Object?>{...baseHomepage}..remove('levelAvailable'),
      <String, Object?>{...baseHomepage}..remove('levelStatus'),
      <String, Object?>{...baseHomepage, 'levelAvailable': true},
      <String, Object?>{...baseHomepage, 'levelStatus': 'AVAILABLE'},
      <String, Object?>{...baseHomepage, 'level': 1, 'levelAvailable': false},
    ];
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      if (request.uri.path == '/app-api/user/getPersonalData') {
        return _reply(request, data: personal);
      }
      return _reply(request, data: malformed.removeAt(0));
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    for (int index = 0; index < 5; index += 1) {
      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    }
    expect(malformed, isEmpty);
  });

  test(
    'social writes reuse one id after ambiguity and rotate for a new intent',
    () async {
      final List<String> requestIds = <String>[];
      int calls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-api/user/relation/buildFriendRelation');
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        calls += 1;
        if (calls == 1) {
          return _reply(
            request,
            status: 500,
            code: 50001,
            message: 'response lost after commit',
          );
        }
        final Map<String, Object?> requestBody = body! as Map<String, Object?>;
        expect(request.method, 'POST');
        expect(requestBody['userId'], 20001);
        final bool following = requestBody['type'] == 1;
        return _reply(
          request,
          data: <String, Object?>{
            'userId': 20001,
            'following': following,
            'follower': false,
            'friend': false,
            'blocked': false,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.setFollowing(userId: 20001, following: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      await repository.setFollowing(userId: 20001, following: true);
      await repository.setFollowing(userId: 20001, following: false);

      expect(requestIds, hasLength(3));
      expect(requestIds.every((String value) => value.isNotEmpty), isTrue);
      expect(requestIds[1], requestIds.first);
      expect(requestIds[2], isNot(requestIds.first));
    },
  );

  test('concurrent identical friend requests are single-flight', () async {
    final Completer<void> release = Completer<void>();
    int calls = 0;
    String? requestId;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(
        request.uri.path,
        '/app-mini-api/mini/v1/social/friend-request/send',
      );
      calls += 1;
      requestId = request.headers.value('X-Request-Id');
      await release.future;
      return _reply(
        request,
        data: <String, Object?>{
          'requestId': 'friend-request-1',
          'status': 'PENDING',
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    final Future<FriendRequestSendResult> first = repository.sendFriendRequest(
      userId: 20004,
      message: ' 一起聊天 ',
    );
    final Future<FriendRequestSendResult> duplicate = repository
        .sendFriendRequest(userId: 20004, message: '一起聊天');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    release.complete();
    final List<FriendRequestSendResult> results = await Future.wait(
      <Future<FriendRequestSendResult>>[first, duplicate],
    );
    expect(
      results.map((FriendRequestSendResult value) => value.requestId),
      <String>['friend-request-1', 'friend-request-1'],
    );
    expect(requestId, isNotEmpty);
  });

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
                'pageSize': 2,
                'total': 6,
                'pages': 3,
                'list': <Object?>[
                  <String, Object?>{
                    'userId': 20001,
                    'nickName': '南风',
                    'signature': '听见风',
                    'headImgUrl': '',
                    'mark': 0,
                    'isOnline': 1,
                    'isInRoom': 0,
                    'roomId': '',
                  },
                  <String, Object?>{
                    'userId': 20002,
                    'nickName': '北风',
                    'signature': '听见雨',
                    'headImgUrl': '',
                    'mark': 1,
                    'isOnline': 0,
                    'isInRoom': 0,
                    'roomId': '',
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'userId': 20001,
                    'nickName': '南风',
                    'signature': '听见风',
                    'headImgUrl': '',
                    'mark': 0,
                    'isOnline': 1,
                    'isInRoom': 0,
                    'roomId': '',
                  },
                  <String, Object?>{
                    'userId': 20002,
                    'nickName': '北风',
                    'signature': '听见雨',
                    'headImgUrl': '',
                    'mark': 1,
                    'isOnline': 0,
                    'isInRoom': 0,
                    'roomId': '',
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
                'pageSize': 20,
                'total': 0,
                'pages': 0,
                'list': <Object?>[],
                'records': <Object?>[],
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
                'pageSize': 20,
                'total': 1,
                'pages': 1,
                'list': <Object?>[
                  <String, Object?>{
                    'userId': 20002,
                    'nickName': '被屏蔽用户',
                    'headImgUrl': 'https://example.test/avatar.png',
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'userId': 20002,
                    'nickName': '被屏蔽用户',
                    'headImgUrl': 'https://example.test/avatar.png',
                  },
                ],
              },
            );
          case '/app-api/user/relation/buildFriendRelation':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{'userId': 20001, 'type': 1});
            return _reply(
              request,
              data: <String, Object?>{
                'userId': 20001,
                'following': true,
                'follower': false,
                'friend': false,
                'blocked': false,
              },
            );
          case '/app-api/user/relation/blackUserRelation':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{'userId': 20002, 'type': 1});
            return _reply(
              request,
              data: <String, Object?>{'userId': 20002, 'blocked': true},
            );
          case '/app-api/user/onlyFollowedCanFollow/set':
            if (request.method == 'GET') {
              expect(request.uri.queryParameters, isEmpty);
              return _reply(
                request,
                data: <String, Object?>{'onlyFollowedCanFollow': false},
              );
            }
            expect(request.method, 'PATCH');
            expect(body, <String, Object?>{'onlyFollowedCanFollow': true});
            return _reply(
              request,
              data: <String, Object?>{'onlyFollowedCanFollow': true},
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

      for (final SocialRelationList type in SocialRelationList.values) {
        final SocialPage<SocialUser> page = await repository.fetchRelations(
          type: type,
          page: 2,
          pageSize: 2,
        );
        expect(page.items.first.userId, 20001);
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
      final PrivacySettings beforePrivacy = await repository
          .fetchPrivacySettings();
      expect(beforePrivacy.onlyFollowedCanFollow, isFalse);
      expect(beforePrivacy.serverValueKnown, isTrue);
      final PrivacySettings privacy = await repository.updatePrivacySettings(
        onlyFollowedCanFollow: true,
      );
      expect(privacy.onlyFollowedCanFollow, isTrue);
      expect(privacy.serverValueKnown, isTrue);
      expect(requests, hasLength(9));
    },
  );

  test(
    'relationship writes and privacy fail closed on missing or contradictory authority',
    () async {
      final List<Map<String, Object?>> responses = <Map<String, Object?>>[
        <String, Object?>{
          'userId': 20001,
          'following': true,
          'follower': false,
          'friend': false,
          'blocked': false,
        },
        <String, Object?>{
          'userId': 20001,
          'following': true,
          'friend': false,
          'blocked': false,
        },
        <String, Object?>{
          'userId': 99999,
          'following': true,
          'follower': false,
          'friend': false,
          'blocked': false,
        },
        <String, Object?>{'requestId': 'request-1', 'status': 'ACCEPTED'},
        <String, Object?>{'requestId': 'other-request', 'status': 'ACCEPTED'},
        <String, Object?>{'requestId': 'request-1', 'status': 'REJECTED'},
        <String, Object?>{'requestId': 'request-1', 'status': 'REJECTED'},
        <String, Object?>{'onlyFollowedCanFollow': false},
        <String, Object?>{},
        <String, Object?>{'onlyFollowedCanFollow': 'false'},
        <String, Object?>{'onlyFollowedCanFollow': true},
        <String, Object?>{'userId': 20002, 'blocked': true},
        <String, Object?>{'userId': 99999, 'blocked': true},
        <String, Object?>{'userId': 20002, 'blocked': 'false'},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(responses, isNotEmpty);
        return _reply(request, data: responses.removeAt(0));
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await repository.setFollowing(userId: 20001, following: true);
      await expectLater(
        repository.setFollowing(userId: 20001, following: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.setFollowing(userId: 20001, following: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await repository.resolveFriendRequest(
        requestId: 'request-1',
        accepted: true,
      );
      await expectLater(
        repository.resolveFriendRequest(requestId: 'request-1', accepted: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.resolveFriendRequest(requestId: 'request-1', accepted: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await repository.resolveFriendRequest(
        requestId: 'request-1',
        accepted: false,
      );

      expect(
        (await repository.fetchPrivacySettings()).onlyFollowedCanFollow,
        isFalse,
      );
      await expectLater(
        repository.fetchPrivacySettings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchPrivacySettings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(
        (await repository.updatePrivacySettings(
          onlyFollowedCanFollow: true,
        )).onlyFollowedCanFollow,
        isTrue,
      );

      await repository.setBlocked(userId: 20002, blocked: true);
      await expectLater(
        repository.setBlocked(userId: 20002, blocked: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.setBlocked(userId: 20002, blocked: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(responses, isEmpty);
    },
  );

  test(
    'relation, visitor, and blacklist pages do not fabricate missing metadata',
    () async {
      final List<String> paths = <String>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        paths.add(request.uri.path);
        return _reply(request, data: <String, Object?>{'list': <Object?>[]});
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchVisitors(
          type: VisitorRecordType.viewedMe,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchBlacklist(page: 1, pageSize: 20),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(paths, <String>[
        '/app-api/user/relation/queryUserFollowList',
        '/app-api/user/personalHomepage/visitedRecords',
        '/app-api/user/relation/queryUserBlackList',
      ]);
    },
  );

  test(
    'relation, visitor, and blacklist pages reject non-map items instead of dropping them',
    () async {
      final List<String> paths = <String>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        paths.add(request.uri.path);
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 2,
            'pageSize': 2,
            'total': 1,
            'pages': 1,
            'list': <Object?>['not-a-user-map'],
            'records': <Object?>['not-a-user-map'],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 1,
          pageSize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchVisitors(
          type: VisitorRecordType.viewedMe,
          page: 1,
          pageSize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchBlacklist(page: 1, pageSize: 2),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(paths, hasLength(3));
    },
  );

  test(
    'relation items require authoritative ids, names, and state fields',
    () async {
      final Map<String, Object?> valid = <String, Object?>{
        'userId': 20001,
        'nickName': '南风',
        'signature': '',
        'headImgUrl': '',
        'isOnline': 0,
        'isInRoom': 0,
        'roomId': '',
        'mark': 1,
      };
      final List<Map<String, Object?>> items = <Map<String, Object?>>[
        <String, Object?>{...valid, 'userId': 0},
        <String, Object?>{...valid, 'nickName': ''},
        <String, Object?>{...valid}..remove('mark'),
        <String, Object?>{...valid, 'isOnline': '0'},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        final Map<String, Object?> item = items.removeAt(0);
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 20,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'list': <Object?>[item],
            'records': <Object?>[item],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 4; index += 1) {
        await expectLater(
          repository.fetchRelations(
            type: SocialRelationList.following,
            page: 1,
            pageSize: 20,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
      expect(items, isEmpty);
    },
  );

  test(
    'visitor items require authoritative id, nickname, time, and count',
    () async {
      final Map<String, Object?> valid = <String, Object?>{
        'userId': 20001,
        'nickname': '南风',
        'headImgUrl': '',
        'visitedDate': '2026-08-22T12:00:00Z',
        'visitUserNum': 2,
      };
      final List<Map<String, Object?>> items = <Map<String, Object?>>[
        <String, Object?>{...valid}..remove('userId'),
        <String, Object?>{...valid, 'nickname': ''},
        <String, Object?>{...valid, 'visitedDate': 'not-a-time'},
        <String, Object?>{...valid, 'visitUserNum': 0},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        final Map<String, Object?> item = items.removeAt(0);
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 20,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'list': <Object?>[item],
            'records': <Object?>[item],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 4; index += 1) {
        await expectLater(
          repository.fetchVisitors(
            type: VisitorRecordType.viewedMe,
            page: 1,
            pageSize: 20,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
      expect(items, isEmpty);
    },
  );

  test('blacklist items require authoritative id and nickname', () async {
    final Map<String, Object?> valid = <String, Object?>{
      'userId': 20001,
      'nickName': '南风',
      'headImgUrl': '',
    };
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      <String, Object?>{...valid}..remove('userId'),
      <String, Object?>{...valid, 'nickName': ''},
      <String, Object?>{...valid, 'userId': 0},
    ];
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      final Map<String, Object?> item = items.removeAt(0);
      return _reply(
        request,
        data: <String, Object?>{
          'current': 1,
          'size': 20,
          'pageSize': 20,
          'total': 1,
          'pages': 1,
          'list': <Object?>[item],
          'records': <Object?>[item],
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    for (int index = 0; index < 3; index += 1) {
      await expectLater(
        repository.fetchBlacklist(page: 1, pageSize: 20),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    }
    expect(items, isEmpty);
  });

  test(
    'social pages validate requested metadata, item counts, and empty-more semantics',
    () async {
      final List<Map<String, Object?>> responses = <Map<String, Object?>>[
        <String, Object?>{
          'current': 1,
          'size': 2,
          'pageSize': 2,
          'total': 2,
          'pages': 1,
          'list': <Object?>[
            <String, Object?>{'userId': 20001},
            <String, Object?>{'userId': 20002},
          ],
          'records': <Object?>[
            <String, Object?>{'userId': 20001},
            <String, Object?>{'userId': 20002},
          ],
        },
        <String, Object?>{
          'current': 1,
          'size': 2,
          'pageSize': 2,
          'total': 3,
          'pages': 2,
          'list': <Object?>[],
          'records': <Object?>[],
        },
        <String, Object?>{
          'current': 1,
          'size': 2,
          'pageSize': 2,
          'total': 0,
          'pages': 0,
          'list': <Object?>[
            <String, Object?>{'userId': 20001},
          ],
          'records': <Object?>[
            <String, Object?>{'userId': 20001},
          ],
        },
        <String, Object?>{
          'current': 1,
          'size': 2,
          'pageSize': 2,
          'total': 1,
          'pages': 1,
          'list': <Object?>[
            <String, Object?>{'userId': 20001},
            <String, Object?>{'userId': 20002},
          ],
          'records': <Object?>[
            <String, Object?>{'userId': 20001},
            <String, Object?>{'userId': 20002},
          ],
        },
      ];
      final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(<String, Object?>{
          'path': request.uri.path,
          'page': request.uri.queryParameters['pageNum'] ?? body,
        });
        return _reply(request, data: responses.removeAt(0));
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 2,
          pageSize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchVisitors(
          type: VisitorRecordType.viewedMe,
          page: 1,
          pageSize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchBlacklist(page: 1, pageSize: 2),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 1,
          pageSize: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(requests, hasLength(4));
    },
  );

  test(
    'social page input rejects non-positive page values before HTTP',
    () async {
      int calls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        calls += 1;
        return _reply(request, data: const <String, Object?>{});
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 0,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.fetchVisitors(
          type: VisitorRecordType.viewedMe,
          page: 1,
          pageSize: 0,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.fetchBlacklist(page: 1, pageSize: 0),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.fetchRelations(
          type: SocialRelationList.following,
          page: 1,
          pageSize: 51,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test('my profile only falls back for the documented 404 response', () async {
    const List<int> homepageStatuses = <int>[404, 401, 403, 409, 422, 500];
    int homepageCalls = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      switch (request.uri.path) {
        case '/app-api/user/getPersonalData':
          return _reply(
            request,
            data: <String, Object?>{
              'userId': 10001,
              'loginName': '13800138000',
              'nickName': '晚星',
              'headImageUrl': '',
              'mobile': '138****0000',
              'sex': 0,
              'birthday': '',
              'roles': 'ROLE_USER',
              'status': 'ACTIVE',
              'realNameAuthStatus': 0,
              'forbiddenState': 0,
            },
          );
        case '/app-api/user/personalHomepage':
          final int status = homepageStatuses[homepageCalls++];
          if (status == 404) {
            return _reply(request, status: 404, code: 404, message: 'missing');
          }
          return _reply(
            request,
            status: status,
            code: status,
            message: 'homepage failure',
          );
        default:
          return _reply(request, status: 404, code: 404, message: 'not found');
      }
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    final SocialProfile fallback = await repository.fetchMyProfile();
    expect(fallback.user.userId, 10001);
    expect(fallback.level, isNull);
    expect(fallback.levelAvailable, isFalse);
    for (final int status in homepageStatuses.skip(1)) {
      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.httpStatus,
            'httpStatus',
            status,
          ),
        ),
      );
    }
  });

  test(
    'profile 200 responses reject missing authoritative id, name, or counts',
    () async {
      final Map<String, Object?> personal = <String, Object?>{
        'userId': 10001,
        'loginName': '13800138000',
        'nickName': '晚星',
        'headImageUrl': '',
        'mobile': '138****0000',
        'sex': 0,
        'birthday': '',
        'roles': 'ROLE_USER',
        'status': 'ACTIVE',
        'realNameAuthStatus': 0,
        'forbiddenState': 0,
      };
      final Map<String, Object?> homepage = <String, Object?>{
        'id': 10001,
        'loginName': '13800138000',
        'nickName': '晚星',
        'headImgUrl': '',
        'signature': '',
        'piAddress': '',
        'address': '',
        'sex': 0,
        'birthday': '',
        'coverImgUrl': '',
        'status': 'ACTIVE',
        'realNameAuthStatus': 0,
        'attentionNum': 1,
        'fansNum': 2,
        'playmateNum': 3,
        'dynamicNum': 4,
        'level': 1,
        'isAttention': 0,
        'isBlacklist': false,
        'isOnline': 0,
        'isInRoom': 0,
        'roomId': '',
      };
      final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{...homepage}..remove('id'),
        <String, Object?>{...homepage, 'id': 0},
        <String, Object?>{...homepage, 'nickName': ''},
        <String, Object?>{...homepage}..remove('attentionNum'),
        <String, Object?>{...homepage, 'fansNum': '2'},
        <String, Object?>{...homepage, 'playmateNum': -1},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          return _reply(request, data: personal);
        }
        expect(request.uri.path, '/app-api/user/personalHomepage');
        return _reply(request, data: malformed.removeAt(0));
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 7; index += 1) {
        await expectLater(
          repository.fetchMyProfile(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
      expect(malformed, isEmpty);
    },
  );

  test(
    'malformed personal profile 200 response fails before homepage fallback',
    () async {
      int homepageCalls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          return _reply(
            request,
            data: <String, Object?>{
              'loginName': '13800138000',
              'nickName': '晚星',
            },
          );
        }
        homepageCalls += 1;
        return _reply(request, status: 404, code: 404, message: 'unused');
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(homepageCalls, 0);
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
            return _reply(
              request,
              data: <String, Object?>{
                'reportId': 'report-1',
                'status': 'SUBMITTED',
                'providerInvocation': false,
              },
            );
          case '/app-api/user/getCustomerServiceDetail':
            expect(request.method, 'GET');
            return _reply(
              request,
              data: <String, Object?>{'accid': 'service-1'},
            );
          case '/app-api/suggestion/saveSugggestion':
            expect(request.method, 'POST');
            expect(request.uri.queryParameters, isEmpty);
            expect(body, <String, Object?>{
              'subject': '页面问题',
              'content': '页面反馈',
            });
            return _reply(
              request,
              data: <String, Object?>{
                'ticketId': 'ticket-1',
                'subject': '页面问题',
                'content': '页面反馈',
                'status': 'SUBMITTED',
                'createdAt': '2026-08-22T12:00:00Z',
                'progressAvailable': true,
              },
            );
          case '/app-mini-api/mini/v1/support/ticket':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'ticketId': 'ticket-1',
            });
            return _reply(
              request,
              data: <String, Object?>{
                'ticketId': 'ticket-1',
                'subject': '页面问题',
                'content': '页面反馈',
                'status': 'PROCESSING',
                'createdAt': '2026-08-22T12:00:00Z',
                'progressAvailable': true,
                'events': <Object?>[],
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

      final String receipt = await repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: ' 房间内持续骚扰 ',
        alsoBlock: true,
      );
      expect(receipt, 'report-1');
      final SupportChannel channel = await repository.fetchCustomerService();
      expect(channel.id, 'service-1');
      expect(channel.liveConversationAvailable, isFalse);
      final SupportTicket ticket = await repository.submitFeedback(
        subject: '页面问题',
        content: ' 页面反馈 ',
      );
      expect(ticket.status, SupportTicketStatus.submitted);
      expect((await repository.fetchSupportTicket(ticket.id)).id, ticket.id);
      expect(requests, hasLength(4));
    },
  );

  test('room reports send the canonical public UUID authority', () async {
    const String roomId = '00000000-0000-0000-0000-000000000123';
    int httpCalls = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      httpCalls += 1;
      expect(body, <String, Object?>{
        'userId': 10001,
        'beTipUserId': null,
        'beTipRoomId': roomId,
        'tipType': 2,
        'tipDescrib': '房间内持续骚扰',
        'tipOffImages': <String>[],
        'type': 2,
      });
      return _reply(
        request,
        data: <String, Object?>{
          'reportId': 'room-report-1',
          'status': 'SUBMITTED',
          'providerInvocation': false,
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    expect(
      await repository.submitReport(
        targetType: ReportTargetType.room,
        targetId: roomId,
        reasonCode: 2,
        description: '房间内持续骚扰',
        alsoBlock: false,
      ),
      'room-report-1',
    );
    expect(httpCalls, 1);
  });

  test(
    'user reports reject invalid or out-of-range ids before auth and HTTP',
    () async {
      int httpCalls = 0;
      int currentUserLookups = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        httpCalls += 1;
        return _reply(
          request,
          data: <String, Object?>{
            'reportId': 'unexpected-report',
            'status': 'SUBMITTED',
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () {
          currentUserLookups += 1;
          return 10001;
        },
      );

      for (final String targetId in <String>[
        'user-20003',
        '0',
        '9223372036854775808',
      ]) {
        await expectLater(
          repository.submitReport(
            targetType: ReportTargetType.user,
            targetId: targetId,
            reasonCode: 2,
            description: '房间内持续骚扰',
            alsoBlock: false,
          ),
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException error) => error.kind,
                  'kind',
                  ApiFailureKind.validation,
                )
                .having(
                  (ApiException error) => error.message,
                  'message',
                  contains('正整数'),
                ),
          ),
        );
      }
      expect(httpCalls, 0);
      expect(currentUserLookups, 0);
    },
  );

  test(
    'report retries ambiguous committed writes with one X-Request-Id and no duplicate insert',
    () async {
      final List<String> requestIds = <String>[];
      final Map<String, String> committedReports = <String, String>{};
      int reportInserts = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
        final String requestId = request.headers.value('X-Request-Id') ?? '';
        expect(requestId, isNotEmpty);
        requestIds.add(requestId);
        final String reportId = committedReports[requestId] ??=
            'report-${++reportInserts}';
        if (requestIds.length == 1) {
          return _reply(request, data: <String, Object?>{'accepted': true});
        }
        return _reply(
          request,
          data: <String, Object?>{
            'reportId': reportId,
            'status': 'SUBMITTED',
            'providerInvocation': false,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.submitReport(
          targetType: ReportTargetType.user,
          targetId: '20003',
          reasonCode: 2,
          description: '骚扰',
          alsoBlock: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      final String receipt = await repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: '骚扰',
        alsoBlock: false,
      );
      expect(receipt, 'report-1');
      expect(reportInserts, 1);
      expect(requestIds, hasLength(2));
      expect(requestIds[1], requestIds.first);
    },
  );

  test('concurrent report submits coalesce by normalized intent', () async {
    final Completer<void> release = Completer<void>();
    int reportCalls = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
      reportCalls += 1;
      await release.future;
      return _reply(
        request,
        data: const <String, Object?>{
          'reportId': 'report-1',
          'status': 'SUBMITTED',
          'providerInvocation': false,
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    final Future<String> first = repository.submitReport(
      targetType: ReportTargetType.user,
      targetId: '20003',
      reasonCode: 2,
      description: ' 同一条举报 ',
      alsoBlock: false,
    );
    final Future<String> second = repository.submitReport(
      targetType: ReportTargetType.user,
      targetId: '20003',
      reasonCode: 2,
      description: '同一条举报',
      alsoBlock: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reportCalls, 1);
    release.complete();
    expect(await Future.wait(<Future<String>>[first, second]), <String>[
      'report-1',
      'report-1',
    ]);
  });

  test('report fails closed when the backend omits reportId', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
      return _reply(request, data: const <String, Object?>{});
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: '骚扰',
        alsoBlock: false,
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

  test('report requires the authoritative SUBMITTED status', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
      return _reply(
        request,
        data: const <String, Object?>{
          'reportId': 'report-1',
          'status': 'REJECTED',
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: '骚扰',
        alsoBlock: false,
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

  for (final Object? providerInvocation in <Object?>[null, true]) {
    test(
      'report requires providerInvocation=false (${providerInvocation ?? 'missing'})',
      () async {
        final HttpServer server = await _startServer((
          HttpRequest request,
          Object? body,
        ) async {
          expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
          return _reply(
            request,
            data: <String, Object?>{
              'reportId': 'report-provider-boundary',
              'status': 'SUBMITTED',
              if (providerInvocation != null)
                'providerInvocation': providerInvocation,
            },
          );
        });
        addTearDown(() => server.close(force: true));
        final BackendSocialRepository repository = BackendSocialRepository(
          apiClient: _client(server),
          currentUserIdProvider: () => 10001,
        );

        await expectLater(
          repository.submitReport(
            targetType: ReportTargetType.user,
            targetId: '20003',
            reasonCode: 2,
            description: '骚扰',
            alsoBlock: false,
          ),
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
  }

  test('report rotates the request id after hard 40903 conflicts', () async {
    final List<String> requestIds = <String>[];
    int calls = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      expect(request.uri.path, '/app-api/util/tipOffUserOrRoom');
      requestIds.add(request.headers.value('X-Request-Id') ?? '');
      calls += 1;
      if (calls == 1) {
        return _reply(
          request,
          status: 409,
          code: 40903,
          message: 'report already rejected',
        );
      }
      return _reply(
        request,
        data: const <String, Object?>{
          'reportId': 'report-2',
          'status': 'SUBMITTED',
          'providerInvocation': false,
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: '骚扰',
        alsoBlock: false,
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.code,
          'code',
          40903,
        ),
      ),
    );
    expect(
      await repository.submitReport(
        targetType: ReportTargetType.user,
        targetId: '20003',
        reasonCode: 2,
        description: '骚扰',
        alsoBlock: false,
      ),
      'report-2',
    );
    expect(requestIds, hasLength(2));
    expect(requestIds[1], isNot(requestIds.first));
  });

  test(
    'support ticket fails closed when the backend omits createdAt',
    () async {
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-api/suggestion/saveSugggestion');
        return _reply(
          request,
          data: <String, Object?>{
            'ticketId': 'ticket-1',
            'status': 'SUBMITTED',
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.submitFeedback(subject: '主题', content: '内容'),
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
    'feedback retries 40901 with the same request id, rotates after content changes, and coalesces duplicates',
    () async {
      final List<String> requestIds = <String>[];
      final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
      final Completer<void> releaseDuplicate = Completer<void>();
      int feedbackCalls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-api/suggestion/saveSugggestion');
        final Map<String, Object?> payload = body! as Map<String, Object?>;
        bodies.add(payload);
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        feedbackCalls += 1;
        if (feedbackCalls == 1) {
          return _reply(
            request,
            status: 409,
            code: 40901,
            message: 'feedback write outcome unknown',
          );
        }
        if (feedbackCalls == 2) {
          return _reply(
            request,
            data: <String, Object?>{
              'ticketId': 'ticket-1',
              'subject': '页面问题',
              'content': '页面反馈',
              'status': 'SUBMITTED',
              'createdAt': '2026-08-22T12:00:00Z',
              'progressAvailable': true,
            },
          );
        }
        if (feedbackCalls == 3) {
          return _reply(
            request,
            data: <String, Object?>{
              'ticketId': 'ticket-2',
              'subject': '页面问题',
              'content': '新的反馈内容',
              'status': 'SUBMITTED',
              'createdAt': '2026-08-22T12:01:00Z',
              'progressAvailable': true,
            },
          );
        }
        await releaseDuplicate.future;
        return _reply(
          request,
          data: <String, Object?>{
            'ticketId': 'ticket-3',
            'subject': '页面问题',
            'content': '重复提交',
            'status': 'SUBMITTED',
            'createdAt': '2026-08-22T12:02:00Z',
            'progressAvailable': true,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.submitFeedback(subject: '页面问题', content: '页面反馈'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40901,
          ),
        ),
      );

      final SupportTicket retried = await repository.submitFeedback(
        subject: '页面问题',
        content: '页面反馈',
      );
      expect(retried.id, 'ticket-1');
      expect(requestIds[1], requestIds.first);

      final SupportTicket changed = await repository.submitFeedback(
        subject: '页面问题',
        content: '新的反馈内容',
      );
      expect(changed.id, 'ticket-2');
      expect(requestIds[2], isNot(requestIds.first));

      final Future<SupportTicket> firstDuplicate = repository.submitFeedback(
        subject: '页面问题',
        content: '重复提交',
      );
      final Future<SupportTicket> secondDuplicate = repository.submitFeedback(
        subject: ' 页面问题 ',
        content: '重复提交 ',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(feedbackCalls, 4);
      releaseDuplicate.complete();
      final List<SupportTicket> coalesced = await Future.wait<SupportTicket>(
        <Future<SupportTicket>>[firstDuplicate, secondDuplicate],
      );
      expect(
        coalesced.map((SupportTicket ticket) => ticket.id).toList(),
        <String>['ticket-3', 'ticket-3'],
      );

      expect(bodies, <Map<String, Object?>>[
        <String, Object?>{'subject': '页面问题', 'content': '页面反馈'},
        <String, Object?>{'subject': '页面问题', 'content': '页面反馈'},
        <String, Object?>{'subject': '页面问题', 'content': '新的反馈内容'},
        <String, Object?>{'subject': '页面问题', 'content': '重复提交'},
      ]);
    },
  );

  test(
    'friend request workflow parses pages and preserves server conflicts',
    () async {
      int listCalls = 0;
      int resolveCalls = 0;
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-mini-api/mini/v1/social/friend-request/list':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters['sent'], 'false');
            expect(request.uri.queryParameters['pageSize'], '50');
            listCalls += 1;
            final int page = int.parse(request.uri.queryParameters['pageNum']!);
            expect(page, listCalls == 2 ? 2 : 1);
            return _reply(
              request,
              data: listCalls == 1
                  ? <String, Object?>{
                      'current': 1,
                      'size': 50,
                      'pageSize': 50,
                      'total': 51,
                      'pages': 2,
                      'list': <Object?>[
                        <String, Object?>{
                          'requestId': 'request-1',
                          'userId': 20004,
                          'nickName': '北岛',
                          'headImageUrl': 'https://example.test/north.png',
                          'message': '一起做产品',
                          'status': 'PENDING',
                          'createdAt': '2026-08-22T12:00:00Z',
                        },
                      ],
                      'records': <Object?>[
                        <String, Object?>{
                          'requestId': 'request-1',
                          'userId': 20004,
                          'nickName': '北岛',
                          'headImageUrl': 'https://example.test/north.png',
                          'message': '一起做产品',
                          'status': 'PENDING',
                          'createdAt': '2026-08-22T12:00:00Z',
                        },
                      ],
                    }
                  : listCalls == 2
                  ? <String, Object?>{
                      'current': 2,
                      'size': 50,
                      'pageSize': 50,
                      'total': 51,
                      'pages': 2,
                      'list': <Object?>[
                        <String, Object?>{
                          'requestId': 'request-2',
                          'userId': 20005,
                          'nickName': '北辰',
                          'message': '继续交流',
                          'status': 'ACCEPTED',
                          'createdAt': '2026-08-21T12:00:00Z',
                        },
                      ],
                      'records': <Object?>[
                        <String, Object?>{
                          'requestId': 'request-2',
                          'userId': 20005,
                          'nickName': '北辰',
                          'message': '继续交流',
                          'status': 'ACCEPTED',
                          'createdAt': '2026-08-21T12:00:00Z',
                        },
                      ],
                    }
                  : <String, Object?>{
                      'current': 1,
                      'size': 50,
                      'pageSize': 50,
                      'total': 0,
                      'pages': 0,
                      'list': <Object?>[],
                      'records': <Object?>[],
                    },
            );
          case '/app-mini-api/mini/v1/social/friend-request/resolve':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{
              'requestId': 'request-1',
              'accepted': true,
            });
            resolveCalls += 1;
            if (resolveCalls > 1) {
              return _reply(
                request,
                status: 409,
                code: 40913,
                message: '好友请求已处理',
              );
            }
            return _reply(
              request,
              data: <String, Object?>{
                'requestId': 'request-1',
                'status': 'ACCEPTED',
              },
            );
          default:
            return _reply(request, status: 404, code: 404);
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      expect(repository.supportsFriendRequestWorkflow, isTrue);
      final List<FriendRequest> first = await repository.fetchFriendRequests();
      expect(first, hasLength(2));
      expect(first.first.id, 'request-1');
      expect(first.first.user.avatarUrl, 'https://example.test/north.png');
      expect(first.first.status, FriendRequestStatus.pending);
      expect(await repository.fetchFriendRequests(), isEmpty);

      await repository.resolveFriendRequest(
        requestId: ' request-1 ',
        accepted: true,
      );
      await expectLater(
        repository.resolveFriendRequest(requestId: 'request-1', accepted: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      expect(requests, hasLength(5));
    },
  );

  test('friend request pagination stops at the 100-page safety cap', () async {
    int calls = 0;
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      calls += 1;
      return _reply(
        request,
        data: <String, Object?>{
          'current': 1,
          'size': 50,
          'pageSize': 50,
          'total': 5001,
          'pages': 101,
          'list': <Object?>[],
          'records': <Object?>[],
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendSocialRepository repository = BackendSocialRepository(
      apiClient: _client(server),
      currentUserIdProvider: () => 10001,
    );

    await expectLater(
      repository.fetchFriendRequests(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'friend request send uses the first-party endpoint and validates the response',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        expect(request.method, 'POST');
        expect(
          request.uri.path,
          '/app-mini-api/mini/v1/social/friend-request/send',
        );
        expect(body, <String, Object?>{'userId': 20004, 'message': '想和你成为好友'});
        return _reply(
          request,
          data: <String, Object?>{
            'requestId': 'friend-request-uuid-1',
            'status': 'PENDING',
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      final FriendRequestSendResult result = await repository.sendFriendRequest(
        userId: 20004,
        message: ' 想和你成为好友 ',
      );

      expect(result.requestId, 'friend-request-uuid-1');
      expect(result.status, FriendRequestStatus.pending);
      expect(requests, hasLength(1));
    },
  );

  test(
    'friend request records require server id, time, and known status',
    () async {
      int call = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(
          request.uri.path,
          '/app-mini-api/mini/v1/social/friend-request/list',
        );
        final int index = call++;
        final Map<String, Object?> item = switch (index) {
          0 => <String, Object?>{
            'userId': 20004,
            'status': 'PENDING',
            'createdAt': '2026-08-22T12:00:00Z',
          },
          1 => <String, Object?>{
            'requestId': 'request-1',
            'userId': 20004,
            'status': 'PENDING',
            'createdAt': 'not-a-time',
          },
          _ => <String, Object?>{
            'requestId': 'request-1',
            'userId': 20004,
            'status': 'UNKNOWN',
            'createdAt': '2026-08-22T12:00:00Z',
          },
        };
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'list': <Object?>[item],
            'records': <Object?>[item],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 3; index += 1) {
        await expectLater(
          repository.fetchFriendRequests(),
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
    'friend request user identities must be positive integers in the current view',
    () async {
      final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'userId': 0},
        <String, Object?>{'userId': -20004},
        <String, Object?>{'userId': 'not-a-user-id'},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        final Map<String, Object?> item = malformed.removeAt(0);
        item.addAll(<String, Object?>{
          'requestId': 'request-${malformed.length}',
          'status': 'PENDING',
          'createdAt': '2026-08-22T12:00:00Z',
        });
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'list': <Object?>[item],
            'records': <Object?>[item],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      for (int index = 0; index < 4; index += 1) {
        await expectLater(
          repository.fetchFriendRequests(),
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
    'friend request requester, target, and current-user aliases must agree',
    () async {
      final List<Map<String, Object?>> responses = <Map<String, Object?>>[
        <String, Object?>{
          'userId': 20004,
          'user_id': '20004',
          'requesterUserId': 20004,
          'requester_id': '20004',
          'targetUserId': 10001,
          'target_id': '10001',
          'currentUserId': 10001,
          'current_id': '10001',
        },
        <String, Object?>{'userId': 20004, 'user_id': 20005},
        <String, Object?>{'userId': 20004, 'requesterUserId': 20005},
        <String, Object?>{
          'requesterUserId': 20004,
          'requester_id': '20005',
          'targetUserId': 10001,
        },
        <String, Object?>{'userId': 20004, 'targetUserId': 10002},
        <String, Object?>{'userId': 20004, 'currentUserId': 10002},
      ];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        final Map<String, Object?> item = responses.removeAt(0);
        item.addAll(<String, Object?>{
          'requestId': 'request-${responses.length}',
          'status': 'PENDING',
          'createdAt': '2026-08-22T12:00:00Z',
        });
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'list': <Object?>[item],
            'records': <Object?>[item],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      final List<FriendRequest> valid = await repository.fetchFriendRequests();
      expect(valid.single.user.userId, 20004);
      for (int index = 0; index < 5; index += 1) {
        await expectLater(
          repository.fetchFriendRequests(),
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
    'friend request parsing fails when the current view has no user id',
    () async {
      int calls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        calls += 1;
        return _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'list': <Object?>[
              <String, Object?>{
                'requestId': 'request-1',
                'userId': 20004,
                'status': 'PENDING',
                'createdAt': '2026-08-22T12:00:00Z',
              },
            ],
            'records': <Object?>[
              <String, Object?>{
                'requestId': 'request-1',
                'userId': 20004,
                'status': 'PENDING',
                'createdAt': '2026-08-22T12:00:00Z',
              },
            ],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 0,
      );

      await expectLater(
        repository.fetchFriendRequests(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'friend request send fails closed for empty response and preserves HTTP errors',
    () async {
      final List<int> statuses = <int>[403, 409, 422, 500];
      final List<int> codes = <int>[40301, 40901, 42201, 50001];
      int call = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(
          request.uri.path,
          '/app-mini-api/mini/v1/social/friend-request/send',
        );
        expect(body, <String, Object?>{'userId': 20004, 'message': '你好'});
        final int index = call++;
        if (index == 0) {
          return _reply(request, data: const <String, Object?>{});
        }
        if (index.isEven) {
          return _reply(
            request,
            data: <String, Object?>{
              'requestId': 'retry-${index ~/ 2}',
              'status': 'PENDING',
            },
          );
        }
        final int failureIndex = (index - 1) ~/ 2;
        return _reply(
          request,
          status: statuses[failureIndex],
          code: codes[failureIndex],
          message: 'send failure',
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.sendFriendRequest(userId: 20004, message: '你好'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      for (final ApiFailureKind expected in <ApiFailureKind>[
        ApiFailureKind.forbidden,
        ApiFailureKind.conflict,
        ApiFailureKind.validation,
        ApiFailureKind.server,
      ]) {
        await expectLater(
          repository.sendFriendRequest(userId: 20004, message: '你好'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              expected,
            ),
          ),
        );
        final FriendRequestSendResult retry = await repository
            .sendFriendRequest(userId: 20004, message: '你好');
        expect(retry.requestId, startsWith('retry-'));
      }
      await expectLater(
        repository.sendFriendRequest(userId: 0, message: '你好'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
    },
  );

  test(
    'live social errors keep HTTP failure kinds and feedback has no local cache',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      int feedbackCalls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/user/onlyFollowedCanFollow/set':
            return _reply(
              request,
              status: 400,
              code: 40001,
              message: 'invalid privacy',
            );
          case '/app-mini-api/mini/v1/support/ticket':
            return _reply(
              request,
              status: 403,
              code: 40304,
              message: 'not your ticket',
            );
          case '/app-api/suggestion/saveSugggestion':
            expect(body, isA<Map<String, Object?>>());
            feedbackCalls += 1;
            if (feedbackCalls == 1) {
              return _reply(
                request,
                data: <String, Object?>{
                  'ticketId': 'ticket-1',
                  'subject': '页面问题',
                  'content': '页面反馈',
                  'status': 'SUBMITTED',
                  'createdAt': '2026-08-22T12:00:00Z',
                  'progressAvailable': true,
                },
              );
            }
            return _reply(
              request,
              status: 500,
              code: 50001,
              message: 'temporary backend failure',
            );
          case '/app-mini-api/mini/v1/social/friend-request/list':
            return _reply(
              request,
              status: 422,
              code: 42201,
              message: 'invalid page',
            );
          default:
            return _reply(request, status: 404, code: 404);
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendSocialRepository repository = BackendSocialRepository(
        apiClient: _client(server),
        currentUserIdProvider: () => 10001,
      );

      await expectLater(
        repository.fetchPrivacySettings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.fetchSupportTicket('ticket-1'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.forbidden,
          ),
        ),
      );
      await expectLater(
        repository.fetchFriendRequests(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );

      final SupportTicket first = await repository.submitFeedback(
        subject: '页面问题',
        content: '页面反馈',
      );
      expect(repository.supportsTicketProgress, isTrue);
      expect(first.id, 'ticket-1');
      expect(first.progressAvailable, isTrue);
      expect(first.statusText, '已提交，等待客服处理');
      await expectLater(
        repository.submitFeedback(subject: '页面问题', content: '页面反馈'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      expect(feedbackCalls, 2);
      expect(
        requests.map((_RequestRecord request) => request.path),
        contains('/app-api/suggestion/saveSugggestion'),
      );
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
      path = request.uri.path,
      requestId = request.headers.value('X-Request-Id'),
      authorization = captureContractAuthorization(request);

  final String method;
  final String path;
  final String? requestId;
  final String authorization;
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
