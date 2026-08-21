import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';

void main() {
  test(
    'community guild contracts preserve routes, payloads, and empty pages',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guild/getGuildHomepageDetails' => _Response.ok(
            request.query.isEmpty
                ? <String, Object?>{
                    'id': 'g-1',
                    'guildName': '星河公会',
                    'guildRole': 10,
                    'memberNum': 12,
                    'playhouseList': <Object?>[
                      <String, Object?>{
                        'roomId': 'room-1',
                        'roomName': '夜航房',
                        'onlineNum': 5,
                      },
                    ],
                  }
                : <String, Object?>{
                    'id': 'g-2',
                    'name': '搜索结果公会',
                    'guildRole': 0,
                  },
          ),
          '/app-api/guild/getRecommendGuildPage' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'guildId': 'g-2',
                  'guildName': '推荐公会',
                  'guildRole': 0,
                },
              ],
              'current': 1,
              'size': 20,
            },
          ),
          '/app-api/guild/searchGuild' => _Response.ok(<String, Object?>{
            'records': <Object?>[],
          }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final GuildHomeSnapshot home = await repository.fetchGuildHome();
      expect(home.currentGuild?.id, 'g-1');
      expect(home.currentGuild?.role, GuildRole.owner);
      expect(home.currentGuild?.rooms.single.onlineUsers, 5);
      expect(home.recommended.single.name, '推荐公会');

      final List<GuildSummary> emptySearch = await repository.searchGuilds(
        '  星河  ',
      );
      expect(emptySearch, isEmpty);
      final GuildSummary guild = await repository.fetchGuild('g-2');
      expect(guild.name, '搜索结果公会');

      final RequestRecord recommend = harness.requests.firstWhere(
        (RequestRecord item) => item.path.endsWith('getRecommendGuildPage'),
      );
      expect(recommend.method, 'POST');
      expect(recommend.body, <String, Object?>{'pageNum': 1, 'pageSize': 20});
      final RequestRecord search = harness.requests.firstWhere(
        (RequestRecord item) => item.path.endsWith('searchGuild'),
      );
      expect(search.method, 'GET');
      expect(search.query, <String, String>{'searchParam': '星河'});
      final RequestRecord detail = harness.requests.lastWhere(
        (RequestRecord item) => item.path.endsWith('getGuildHomepageDetails'),
      );
      expect(detail.query, <String, String>{'guildId': 'g-2'});
    },
  );

  test('community guild mutations use exact legacy contracts', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);
    final BackendCommunityRepository repository = harness.repository;

    await repository.applyToJoinGuild('g-7');
    await repository.quitGuild('g-7');
    await repository.signGuild('7');
    await repository.resolveGuildApplication(
      applicationId: 'app-2',
      accepted: true,
    );
    await repository.setGuildMemberMuted(memberRecordId: 'm-1', muted: false);
    await repository.removeGuildMember('m-1');

    final List<RequestRecord> requests = harness.requests;
    expect(requests.map((RequestRecord item) => item.path), <String>[
      '/app-api/guildManagement/applyForMembership',
      '/app-api/guildManagement/quitGuild',
      '/app-api/guild/sign',
      '/app-api/guildManagement/approvalMembershipApplication',
      '/app-api/guildManagement/memberBanOrUnseal',
      '/app-api/guildManagement/kickOutMember',
    ]);
    expect(requests[0].method, 'GET');
    expect(requests[0].query, <String, String>{'guildId': 'g-7'});
    expect(requests[1].query, <String, String>{'guildId': 'g-7'});
    expect(requests[2].method, 'POST');
    expect(requests[2].body, <String, Object?>{'guildId': 7});
    expect(requests[3].query, <String, String>{'id': 'app-2', 'type': '1'});
    expect(requests[4].query, <String, String>{'id': 'm-1', 'isMuted': '0'});
    expect(requests[5].query, <String, String>{'id': 'm-1'});
  });

  test(
    'community guild members and applications parse records and page bodies',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guild/getGuildMembers' => _Response.ok(<String, Object?>{
            'records': <Object?>[
              <String, Object?>{
                'id': 'm-1',
                'userId': 21,
                'nickName': '成员甲',
                'guildRole': 3,
                'isMuted': 1,
                'isSignUp': 1,
              },
            ],
          }),
          '/app-api/guild/getMembershipApplications' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'applicationId': 'a-1',
                  'userId': 22,
                  'nickname': '申请者',
                  'remark': '想加入',
                },
              ],
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final List<GuildMember> members = await repository.fetchGuildMembers('7');
      final List<GuildApplication> applications = await repository
          .fetchGuildApplications('7');
      expect(members.single.nickname, '成员甲');
      expect(members.single.role, GuildRole.manager);
      expect(members.single.isMuted, isTrue);
      expect(applications.single.id, 'a-1');
      expect(applications.single.message, '想加入');
      expect(harness.requests[0].body, <String, Object?>{
        'guildId': 7,
        'pageNum': 1,
        'pageSize': 200,
      });
      expect(harness.requests[1].body, <String, Object?>{
        'guildId': 7,
        'pageNum': 1,
        'pageSize': 100,
      });
    },
  );

  test('community cp contracts parse state and preserve numeric ids', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-mini-api/mini/v1/cp/my-list' => _Response.ok(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'cp-1',
              'userId': 31,
              'nickname': 'CP甲',
              'days': 9,
            },
          ],
        }),
        '/app-mini-api/mini/v1/cp/pending-requests' => _Response.ok(
          <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'invite-1',
                'userId': 32,
                'nickname': '邀请者',
              },
            ],
          },
        ),
        '/app-mini-api/mini/v1/cp/check-invitation-eligibility' => _Response.ok(
          <String, Object?>{'eligible': true, 'reason': '可以邀请'},
        ),
        '/app-mini-api/mini/v1/cp/request' => _Response.ok(<String, Object?>{
          'invitationId': 'invite-2',
        }),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);
    final BackendCommunityRepository repository = harness.repository;

    expect((await repository.fetchCpRelations()).single.nickname, 'CP甲');
    expect(
      (await repository.fetchPendingCpInvitations()).single.invitationId,
      'invite-1',
    );
    final CpEligibility eligibility = await repository.checkCpEligibility(42);
    expect(eligibility.allowed, isTrue);
    expect(eligibility.message, '可以邀请');
    expect(await repository.requestCp(42), 'invite-2');
    await repository.resolveCpInvitation(invitationId: '9', accepted: true);
    await repository.resolveCpInvitation(
      invitationId: 'invite-1',
      accepted: false,
    );

    expect(harness.requests[2].query, <String, String>{'targetUserId': '42'});
    expect(harness.requests[3].body, <String, Object?>{'targetUserId': 42});
    expect(harness.requests[4].path, '/app-mini-api/mini/v1/cp/accept');
    expect(harness.requests[4].body, <String, Object?>{'invitationId': 9});
    expect(harness.requests[5].path, '/app-mini-api/mini/v1/cp/reject');
    expect(harness.requests[5].body, <String, Object?>{
      'invitationId': 'invite-1',
    });
  });

  test(
    'community guardian and fan snapshot fans out four GET contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/room/radio/v1/queryGuardianLevels' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'levelId': '2',
                  'levelName': '银色守护',
                  'diamond': 88,
                  'days': 30,
                },
              ],
            },
          ),
          '/app-api/room/radio/v1/queryOenGuardianInfo' => _Response.ok(
            <String, Object?>{'anchorName': '主播甲', 'guardianLevelId': '2'},
          ),
          '/app-api/room/radio/v1/queryFansTeamRelation' => _Response.ok(
            <String, Object?>{
              'teamName': '甲的粉团',
              'fansLevel': 3,
              'intimacyValue': 66,
              'hasJoined': true,
            },
          ),
          '/app-api/room/radio/v1/queryFansTeamTaskPage' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'taskId': 'task-1',
                  'taskName': '陪伴主播',
                  'progress': 2,
                  'target': 5,
                  'isReceive': 1,
                },
              ],
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final GuardianFanSnapshot snapshot = await repository.fetchGuardianFan(
        88,
      );
      expect(snapshot.anchorName, '主播甲');
      expect(snapshot.currentGuardianLevel?.name, '银色守护');
      expect(snapshot.fansTeamName, '甲的粉团');
      expect(snapshot.fansLevel, 3);
      expect(snapshot.intimacy, 66);
      expect(snapshot.joinedFansTeam, isTrue);
      expect(snapshot.tasks.single.claimed, isTrue);
      expect(harness.requests, hasLength(4));
      expect(
        harness.requests.map(
          (RequestRecord item) => item.query['anchorUserId'],
        ),
        containsAll(<String?>[null, '88', '88', '88']),
      );
    },
  );

  test(
    'community guardian and task mutations preserve body and follow-up reads',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'taskId': 'daily-1',
                  'taskName': '签到',
                  'status': 1,
                  'progress': 1,
                  'target': 1,
                },
              ],
            },
          ),
          '/app-api/taskSystem/querySignReward' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{'day': 1, 'reward': '10币', 'isToday': 1},
              ],
            },
          ),
          '/app-api/taskSystem/queryTodaySignStatus' => _Response.ok(
            <String, Object?>{'signedToday': false, 'continuousDays': 2},
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      await repository.becomeGuardian(anchorUserId: 88, levelId: '2');
      await repository.joinFansTeam(88);
      final TaskCenterSnapshot tasks = await repository.fetchTaskCenter();
      expect(tasks.tasks.single.state, TaskState.claimable);
      expect(tasks.signedToday, isFalse);
      await repository.completeDailyCheckIn();
      await repository.claimTask('daily-1');

      expect(harness.requests[0].path, '/app-api/room/radio/v1/becomeGuard');
      expect(harness.requests[0].body, <String, Object?>{
        'anchorUserId': 88,
        'guardianLevelId': 2,
      });
      expect(harness.requests[1].path, '/app-api/room/radio/v1/joinFansTeam');
      expect(harness.requests[1].body, <String, Object?>{'anchorUserId': 88});
      expect(harness.requests[2].query, <String, String>{'type': '1'});
      expect(
        harness.requests[5].path,
        '/app-api/taskSystem/completeDailySignIn',
      );
      expect(harness.requests[9].query, <String, String>{'taskId': 'daily-1'});
    },
  );

  test(
    'community unsupported capabilities are explicit and error envelopes map',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return const _Response(
          statusCode: 422,
          code: 422,
          message: '关键词不可用',
          data: null,
        );
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;
      expect(repository.supportsInviteAttribution, isFalse);
      expect(repository.supportsActivityCatalog, isFalse);
      expect((await repository.fetchInviteAttribution()).available, isFalse);
      await expectLater(
        repository.fetchActivities(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.searchGuilds('bad'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiFailureKind.validation,
              )
              .having((ApiException e) => e.httpStatus, 'httpStatus', 422)
              .having((ApiException e) => e.message, 'message', '关键词不可用'),
        ),
      );
    },
  );
}

class _Harness {
  _Harness._(this.server, this.requests)
    : repository = BackendCommunityRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
        ),
        routes: const BackendRouteCatalog(),
      );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommunityRepository repository;

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
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
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
