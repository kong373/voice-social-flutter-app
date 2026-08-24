import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
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
          '/app-api/guild/getGuildHomepageDetails' =>
            _Response.ok(<String, Object?>{
              ..._b709GuildRow(includeHomepageState: true),
              'guildId': 'g-2',
              'guildName': '搜索结果公会',
              'name': '搜索结果公会',
              'viewerRole': 'MEMBER',
              'joined': true,
              'memberCount': 7,
            }),
          '/app-api/guild/getRecommendGuildPage' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  ..._b709GuildRow(),
                  'guildId': 'g-1',
                  'guildName': '星河公会',
                  'name': '星河公会',
                  'viewerRole': 'OWNER',
                  'joined': true,
                  'memberCount': 12,
                  'roomId': 'room-1',
                  'roomCode': '880217',
                  'roomName': '夜航房',
                },
                <String, Object?>{
                  ..._b709GuildRow(),
                  'guildId': 'g-2',
                  'guildName': '推荐公会',
                  'name': '推荐公会',
                  'viewerRole': 'NONE',
                },
              ],
              'records': <Object?>[
                <String, Object?>{
                  ..._b709GuildRow(),
                  'guildId': 'g-1',
                  'guildName': '星河公会',
                  'name': '星河公会',
                  'viewerRole': 'OWNER',
                  'joined': true,
                  'memberCount': 12,
                  'roomId': 'room-1',
                  'roomCode': '880217',
                  'roomName': '夜航房',
                },
                <String, Object?>{
                  ..._b709GuildRow(),
                  'guildId': 'g-2',
                  'guildName': '推荐公会',
                  'name': '推荐公会',
                  'viewerRole': 'NONE',
                },
              ],
              'current': 1,
              'pageSize': 50,
              'total': 2,
              'pages': 1,
            },
          ),
          '/app-api/guild/searchGuild' => _Response.ok(<String, Object?>{
            'list': <Object?>[],
            'records': <Object?>[],
            'current': 1,
            'pageSize': 50,
            'total': 0,
            'pages': 0,
          }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final GuildHomeSnapshot home = await repository.fetchGuildHome();
      expect(home.currentGuild, isNull);
      expect(home.currentGuildAuthority, GuildCurrentAuthority.unavailable);
      expect(home.recommended.first.role, GuildRole.owner);
      expect(home.recommended.first.rooms.single.onlineUsers, 0);
      expect(home.recommended.first.code, 'guild-code-1');
      expect(home.recommended, hasLength(2));
      expect(home.recommended[1].name, '推荐公会');

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
      expect(recommend.body, <String, Object?>{'pageNum': 1, 'pageSize': 50});
      final RequestRecord search = harness.requests.firstWhere(
        (RequestRecord item) => item.path.endsWith('searchGuild'),
      );
      expect(search.method, 'GET');
      expect(search.query, <String, String>{
        'keyword': '星河',
        'pageNum': '1',
        'pageSize': '50',
      });
      final RequestRecord detail = harness.requests.lastWhere(
        (RequestRecord item) => item.path.endsWith('getGuildHomepageDetails'),
      );
      expect(detail.query, <String, String>{'guildId': 'g-2'});
    },
  );

  test(
    'community rejects current-guild responses without authority schema',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'currentGuild': null,
          'list': <Object?>[],
          'records': <Object?>[],
          'current': 1,
          'pageSize': 50,
          'total': 0,
          'pages': 0,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchGuildHome(),
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
    'community keeps authoritative no-guild state distinct from unavailable',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guild/getCurrentGuild' => _Response.ok(<String, Object?>{
            'currentGuildAuthority': 'AUTHORITATIVE',
            'authority': 'AUTHORITATIVE',
            'available': true,
            'fabricated': false,
            'membershipStatus': 'NONE',
            'currentGuild': null,
            'currentGuildId': '',
          }),
          '/app-api/guild/getRecommendGuildPage' =>
            _Response.ok(<String, Object?>{
              'list': <Object?>[],
              'records': <Object?>[],
              'current': 1,
              'pageSize': 50,
              'total': 0,
              'pages': 0,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final GuildHomeSnapshot home = await harness.repository.fetchGuildHome();

      expect(home.currentGuild, isNull);
      expect(home.currentGuildAuthority, GuildCurrentAuthority.authoritative);
      expect(
        harness.requests.where(
          (RequestRecord request) =>
              request.path == '/app-api/guild/getCurrentGuild',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'guild sign checks status and recovers a committed write after lost response',
    () async {
      int signAttempts = 0;
      int statusReads = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/sign/status') {
          statusReads += 1;
          expect(request.method, 'GET');
          expect(request.query, <String, String>{'guildId': 'g-7'});
          final bool signed = statusReads > 1;
          return _Response.ok(<String, Object?>{
            'guildId': 'g-7',
            'hasGuild': true,
            'member': true,
            'signed': signed,
            'signedToday': signed,
            'isSign': signed,
            'alreadySigned': signed,
            'businessDate': '2026-08-23',
            'signDate': signed ? '2026-08-23' : '',
            'rewardPoints': signed ? 1 : 0,
            'status': signed ? 'SIGNED' : 'AVAILABLE',
            'providerInvocation': false,
          });
        }
        if (request.path == '/app-api/guild/sign') {
          signAttempts += 1;
          expect(request.method, 'POST');
          expect(request.body, <String, Object?>{'guildId': 'g-7'});
          return const _Response(
            statusCode: 500,
            code: 50001,
            message: 'response lost after commit',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await harness.repository.signGuild('g-7');

      expect(signAttempts, 1);
      expect(statusReads, 2);
      final List<RequestRecord> signRequests = harness.requests
          .where(
            (RequestRecord request) => request.path == '/app-api/guild/sign',
          )
          .toList();
      expect(signRequests.single.requestId, startsWith('flutter-'));
    },
  );

  test(
    'community preserves authoritative member sign state and CP days',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/getGuildMembers') {
          final Map<String, Object?> row = <String, Object?>{
            ..._b709GuildMemberRow(),
            'userId': 21,
            'isSigned': true,
            'roomId': 'room-21',
          };
          return _Response.ok(<String, Object?>{
            'list': <Object?>[row],
            'records': <Object?>[row],
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
          });
        }
        if (request.path == '/app-mini-api/mini/v1/cp/my-list') {
          final Map<String, Object?> row = <String, Object?>{
            ..._b709CpRelationRow(),
            'cpRelationId': 'cp-21',
            'days': 12,
          };
          return _Response.ok(<String, Object?>{
            'list': <Object?>[row],
            'records': <Object?>[row],
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final List<GuildMember> members = await harness.repository
          .fetchGuildMembers('guild-1');
      final List<CpRelation> relations = await harness.repository
          .fetchCpRelations();

      expect(members.single.isSigned, isTrue);
      expect(members.single.roomId, 'room-21');
      expect(relations.single.days, 12);
    },
  );

  test(
    'community guild detail rejects a mismatched response identity',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          ..._b709GuildRow(includeHomepageState: true),
          'guildId': 'different-guild',
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchGuild('requested-guild'),
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
    'community recommendation and search reject mixed active and closed rows',
    () async {
      final Map<String, Object?> active = _b709GuildRow();
      final Map<String, Object?> closed = <String, Object?>{
        ..._b709GuildRow(),
        'guildId': 'guild-closed',
        'status': 'CLOSED',
      };
      final List<Object?> mixed = <Object?>[active, closed];
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/getRecommendGuildPage' ||
            request.path == '/app-api/guild/searchGuild') {
          return _Response.ok(<String, Object?>{
            'list': mixed,
            'records': mixed,
            'current': 1,
            'pageSize': 50,
            'total': 2,
            'pages': 1,
          });
        }
        if (request.path == '/app-api/guild/getGuildHomepageDetails') {
          return _Response.ok(<String, Object?>{
            ...closed,
            'signedToday': false,
            'applicationPending': false,
            'businessDate': '2026-08-23',
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      Future<void> expectProtocol(Future<Object?> value) => expectLater(
        value,
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await expectProtocol(harness.repository.fetchGuildHome());
      await expectProtocol(harness.repository.searchGuilds('closed'));

      final GuildSummary detail = await harness.repository.fetchGuild(
        'guild-closed',
      );
      expect(detail.id, 'guild-closed');
      expect(detail.code, 'guild-code-1');
      expect(detail.status, GuildStatus.closed);
    },
  );

  test(
    'community guild mutations use canonical first-party contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guild/getGuildHomepageDetails' =>
            _Response.ok(<String, Object?>{
              ..._b709GuildRow(includeHomepageState: true),
              'guildId': 'g-7',
              'guildName': '星河公会',
              'name': '星河公会',
              'viewerRole': 'OWNER',
              'joined': true,
            }),
          '/app-api/guildManagement/applyForMembership' => _Response.ok(
            <String, Object?>{
              'applicationId': 'app-created',
              'guildId': 'g-7',
              'status': 'PENDING',
            },
          ),
          '/app-api/guildManagement/quitGuild' => _Response.ok(
            <String, Object?>{'guildId': 'g-7', 'status': 'LEFT', 'left': true},
          ),
          '/app-api/guild/sign/status' => _Response.ok(<String, Object?>{
            'guildId': 'g-7',
            'hasGuild': true,
            'member': true,
            'signed': false,
            'signedToday': false,
            'isSign': false,
            'alreadySigned': false,
            'businessDate': '2026-08-23',
            'signDate': '',
            'rewardPoints': 0,
            'status': 'AVAILABLE',
            'providerInvocation': false,
          }),
          '/app-api/guild/sign' => _Response.ok(<String, Object?>{
            'guildId': 'g-7',
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'signDate': '2026-08-23',
            'businessDate': '2026-08-23',
            'rewardPoints': 1,
            'status': 'SIGNED',
            'providerInvocation': false,
          }),
          '/app-api/guildManagement/approvalMembershipApplication' =>
            _Response.ok(<String, Object?>{
              'applicationId': 'app-2',
              'guildId': 'g-7',
              'status': 'APPROVED',
            }),
          '/app-api/guildManagement/memberBanOrUnseal' => _Response.ok(
            <String, Object?>{'guildId': 'g-7', 'userId': 21, 'muted': false},
          ),
          '/app-api/guildManagement/kickOutMember' => _Response.ok(
            <String, Object?>{'guildId': 'g-7', 'userId': 21, 'removed': true},
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      await repository.fetchGuild('g-7');
      await repository.applyToJoinGuild('g-7');
      await repository.quitGuild('g-7');
      await repository.signGuild('g-7');
      await repository.resolveGuildApplication(
        applicationId: 'app-2',
        accepted: true,
      );
      await repository.setGuildMemberMuted(
        guildId: 'g-7',
        userId: 21,
        muted: false,
      );
      await repository.removeGuildMember(guildId: 'g-7', userId: 21);

      RequestRecord byPath(String path) => harness.requests.firstWhere(
        (RequestRecord item) => item.path == path && item.method == 'POST',
      );
      expect(
        byPath('/app-api/guildManagement/applyForMembership').body,
        <String, Object?>{'guildId': 'g-7'},
      );
      expect(
        byPath('/app-api/guildManagement/quitGuild').body,
        <String, Object?>{'guildId': 'g-7'},
      );
      expect(byPath('/app-api/guild/sign').body, <String, Object?>{
        'guildId': 'g-7',
      });
      expect(
        byPath('/app-api/guildManagement/approvalMembershipApplication').body,
        <String, Object?>{'applicationId': 'app-2', 'approved': true},
      );
      expect(
        byPath('/app-api/guildManagement/memberBanOrUnseal').body,
        <String, Object?>{'guildId': 'g-7', 'userId': 21, 'muted': false},
      );
      expect(
        byPath('/app-api/guildManagement/kickOutMember').body,
        <String, Object?>{'guildId': 'g-7', 'userId': 21},
      );
    },
  );

  test(
    'community mutations fail closed without exact b709 confirmation',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guildManagement/applyForMembership' => _Response.ok(
            <String, Object?>{
              'applicationId': 'app-1',
              'guildId': 'different',
              'status': 'PENDING',
            },
          ),
          '/app-api/guildManagement/quitGuild' => _Response.ok(
            <String, Object?>{
              'guildId': 'g-1',
              'status': 'LEFT',
              'left': false,
            },
          ),
          '/app-api/guild/sign' => _Response.ok(<String, Object?>{
            'guildId': 'g-1',
            'signed': true,
            'alreadySigned': false,
            'signDate': 'not-a-date',
            'rewardPoints': 1,
          }),
          '/app-api/guildManagement/approvalMembershipApplication' =>
            _Response.ok(<String, Object?>{
              'applicationId': 'different',
              'guildId': 'g-1',
              'status': 'APPROVED',
            }),
          '/app-api/guildManagement/memberBanOrUnseal' => _Response.ok(
            <String, Object?>{'guildId': 'g-1', 'userId': 99, 'muted': true},
          ),
          '/app-api/guildManagement/kickOutMember' => _Response.ok(
            <String, Object?>{'guildId': 'g-1', 'userId': 21, 'removed': false},
          ),
          '/app-api/room/radio/v1/becomeGuard' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'active': false,
              'guardianLevelId': '2',
              'providerInvocation': false,
            }),
          '/app-api/room/radio/v1/joinFansTeam' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'joined': true,
              'fansTeamId': 'fans-team-1',
              'status': 'INACTIVE',
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/completeDailySignIn' =>
            _Response.ok(<String, Object?>{
              'signed': false,
              'signedToday': true,
              'isSign': true,
              'alreadySigned': false,
              'businessDate': '2026-08-23',
              'taskId': 100,
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/receiveTaskReward' =>
            _Response.ok(<String, Object?>{
              'taskId': 999,
              'claimed': true,
              'isReceive': true,
              'status': 2,
              'providerInvocation': false,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      Future<void> expectProtocol(Future<Object?> future) => expectLater(
        future,
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await expectProtocol(harness.repository.applyToJoinGuild('g-1'));
      await expectProtocol(harness.repository.quitGuild('g-1'));
      await expectProtocol(harness.repository.signGuild('g-1'));
      await expectProtocol(
        harness.repository.resolveGuildApplication(
          applicationId: 'app-1',
          accepted: true,
        ),
      );
      await expectProtocol(
        harness.repository.setGuildMemberMuted(
          guildId: 'g-1',
          userId: 21,
          muted: true,
        ),
      );
      await expectProtocol(
        harness.repository.removeGuildMember(guildId: 'g-1', userId: 21),
      );
      await expectProtocol(
        harness.repository.becomeGuardian(anchorUserId: 88, levelId: '2'),
      );
      await expectProtocol(harness.repository.joinFansTeam(88));
      await expectProtocol(harness.repository.completeDailyCheckIn());
      await expectProtocol(harness.repository.claimTask('101'));
    },
  );

  test(
    'community guild members and applications parse records and page bodies',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/getGuildMembers') {
          final Map<String, Object?> body =
              request.body! as Map<String, Object?>;
          final int page = body['pageNum']! as int;
          final List<Object?> items = page == 1
              ? <Object?>[
                  <String, Object?>{
                    ..._b709GuildMemberRow(),
                    'userId': 21,
                    'nickName': '成员甲',
                    'role': 'ADMIN',
                    'muted': true,
                  },
                  ...List<Object?>.generate(
                    49,
                    (int index) => <String, Object?>{
                      ..._b709GuildMemberRow(),
                      'userId': 1000 + index,
                      'nickName': '成员${index + 1}',
                      'role': 'MEMBER',
                      'muted': false,
                    },
                  ),
                ]
              : <Object?>[
                  <String, Object?>{
                    ..._b709GuildMemberRow(),
                    'userId': 23,
                    'nickName': '成员乙',
                    'role': 'MEMBER',
                    'muted': false,
                  },
                ];
          return _Response.ok(<String, Object?>{
            'list': items,
            'records': items,
            'current': page,
            'size': 50,
            'pageSize': 50,
            'total': 51,
            'pages': 2,
          });
        }
        if (request.path == '/app-api/guild/getMembershipApplications') {
          final Map<String, Object?> body =
              request.body! as Map<String, Object?>;
          final int page = body['pageNum']! as int;
          final List<Object?> items = page == 1
              ? <Object?>[
                  <String, Object?>{
                    ..._b709GuildApplicationRow(),
                    'applicationId': 'a-1',
                    'userId': 22,
                    'nickName': '申请者',
                    'message': '想加入',
                    'status': 'APPROVED',
                    'createdAt': '2026-08-22T00:00:00Z',
                    'resolvedAt': '2026-08-22T01:00:00Z',
                  },
                  ...List<Object?>.generate(
                    49,
                    (int index) => <String, Object?>{
                      ..._b709GuildApplicationRow(),
                      'applicationId': 'a-${index + 10}',
                      'userId': 2000 + index,
                      'nickName': '申请者${index + 1}',
                      'message': '申请说明',
                      'status': switch (index) {
                        1 => 'REJECTED',
                        2 => 'CANCELLED',
                        _ => 'PENDING',
                      },
                      'createdAt': '2026-08-21T00:00:00Z',
                      if (index == 1 || index == 2)
                        'resolvedAt': '2026-08-21T01:00:00Z',
                    },
                  ),
                ]
              : <Object?>[
                  <String, Object?>{
                    ..._b709GuildApplicationRow(),
                    'applicationId': 'a-2',
                    'userId': 24,
                    'nickName': '申请者乙',
                    'message': '也想加入',
                    'status': 'PENDING',
                    'createdAt': '2026-08-21T00:00:00Z',
                  },
                ];
          return _Response.ok(<String, Object?>{
            'list': items,
            'records': items,
            'current': page,
            'size': 50,
            'pageSize': 50,
            'total': 51,
            'pages': 2,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final List<GuildMember> members = await repository.fetchGuildMembers('7');
      final List<GuildApplication> applications = await repository
          .fetchGuildApplications('7');
      expect(members, hasLength(51));
      expect(members.first.nickname, '成员甲');
      expect(members.first.recordId, '21');
      expect(members.first.role, GuildRole.manager);
      expect(members.first.isMuted, isTrue);
      expect(applications, hasLength(51));
      expect(applications.first.id, 'a-1');
      expect(applications.first.message, '想加入');
      expect(applications.first.status, GuildApplicationStatus.accepted);
      expect(
        applications.map((GuildApplication value) => value.status).toSet(),
        containsAll(GuildApplicationStatus.values),
      );
      expect(harness.requests[0].body, <String, Object?>{
        'guildId': '7',
        'pageNum': 1,
        'pageSize': 50,
      });
      expect(harness.requests[1].body, <String, Object?>{
        'guildId': '7',
        'pageNum': 2,
        'pageSize': 50,
      });
      expect(harness.requests[2].body, <String, Object?>{
        'guildId': '7',
        'pageNum': 1,
        'pageSize': 50,
      });
      expect(harness.requests[3].body, <String, Object?>{
        'guildId': '7',
        'pageNum': 2,
        'pageSize': 50,
      });
    },
  );

  test('community rejects unknown guild application status', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      final List<Object?> rows = <Object?>[
        <String, Object?>{
          'applicationId': 'application-unknown',
          'userId': 21,
          'status': 'UNKNOWN',
          'createdAt': '2026-08-23T00:00:00Z',
        },
      ];
      return _Response.ok(<String, Object?>{
        'list': rows,
        'records': rows,
        'current': 1,
        'pageSize': 50,
        'total': 1,
        'pages': 1,
      });
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchGuildApplications('g-1'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('community validates application status against resolvedAt', () async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[
      <String, Object?>{
        ..._b709GuildApplicationRow(),
        'status': 'PENDING',
        'resolvedAt': '2026-08-23T00:00:00Z',
      },
      <String, Object?>{
        ..._b709GuildApplicationRow(),
        'status': 'APPROVED',
        'resolvedAt': '',
      },
      <String, Object?>{
        ..._b709GuildApplicationRow(),
        'status': 'REJECTED',
        'resolvedAt': '',
      },
      <String, Object?>{
        ..._b709GuildApplicationRow(),
        'status': 'CANCELLED',
        'resolvedAt': '',
      },
    ];

    for (final Map<String, Object?> row in rows) {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(_b709Page(row, pageSize: 50));
      });
      try {
        await expectLater(
          harness.repository.fetchGuildApplications('guild-1'),
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

  test('community cp contracts parse state and preserve numeric ids', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path == '/app-mini-api/mini/v1/cp/my-list') {
        final int page = int.parse(request.query['pageNum']!);
        final List<Object?> items = page == 1
            ? <Object?>[
                <String, Object?>{
                  ..._b709CpRelationRow(),
                  'cpRelationId': 'cp-1',
                  'userId': 31,
                  'nickName': 'CP甲',
                  'createdAt': '2026-08-22T00:00:00Z',
                },
                ...List<Object?>.generate(
                  19,
                  (int index) => <String, Object?>{
                    ..._b709CpRelationRow(),
                    'cpRelationId': 'cp-extra-${index + 1}',
                    'userId': 100 + index,
                    'nickName': 'CP${index + 1}',
                    'createdAt': '2026-08-22T00:00:00Z',
                  },
                ),
              ]
            : <Object?>[
                <String, Object?>{
                  ..._b709CpRelationRow(),
                  'cpRelationId': 'cp-2',
                  'userId': 33,
                  'nickName': 'CP乙',
                  'createdAt': '2026-08-21T00:00:00Z',
                },
              ];
        expect(request.query['pageSize'], '20');
        return _Response.ok(<String, Object?>{
          'list': items,
          'records': items,
          'current': page,
          'size': 20,
          'pageSize': 20,
          'total': 21,
          'pages': 2,
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/pending-requests') {
        final int page = int.parse(request.query['pageNum']!);
        final List<Object?> items = page == 1
            ? <Object?>[
                <String, Object?>{
                  ..._b709CpInvitationRow(),
                  'cpRequestId': 'invite-1',
                  'userId': 32,
                  'nickName': '邀请者',
                  'createdAt': '2026-08-22T00:00:00Z',
                },
                ...List<Object?>.generate(
                  19,
                  (int index) => <String, Object?>{
                    ..._b709CpInvitationRow(),
                    'cpRequestId': 'invite-extra-${index + 1}',
                    'userId': 200 + index,
                    'nickName': '邀请者${index + 1}',
                    'createdAt': '2026-08-22T00:00:00Z',
                  },
                ),
              ]
            : <Object?>[
                <String, Object?>{
                  ..._b709CpInvitationRow(),
                  'cpRequestId': 'invite-2',
                  'userId': 34,
                  'nickName': '邀请者乙',
                  'createdAt': '2026-08-21T00:00:00Z',
                },
              ];
        expect(request.query['pageSize'], '20');
        return _Response.ok(<String, Object?>{
          'list': items,
          'records': items,
          'current': page,
          'size': 20,
          'pageSize': 20,
          'total': 21,
          'pages': 2,
        });
      }
      if (request.path ==
          '/app-mini-api/mini/v1/cp/check-invitation-eligibility') {
        return _Response.ok(<String, Object?>{
          'eligible': true,
          'reason': 'ELIGIBLE',
          'targetUserId': 42,
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/request') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': 'invite-3',
          'targetUserId': 42,
          'status': 'PENDING',
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/accept') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': '9',
          'status': 'ACCEPTED',
          'cpRelationId': 'cp-accepted-9',
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/reject') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': 'invite-1',
          'status': 'REJECTED',
          'cpRelationId': '',
        });
      }
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);
    final BackendCommunityRepository repository = harness.repository;

    final List<CpRelation> relations = await repository.fetchCpRelations();
    expect(relations, hasLength(21));
    expect(relations.first.nickname, 'CP甲');
    expect(relations.first.boundAt, '2026-08-22T00:00:00Z');
    final List<CpInvitation> invitations = await repository
        .fetchPendingCpInvitations();
    expect(invitations, hasLength(21));
    expect(invitations.first.invitationId, 'invite-1');
    final CpEligibility eligibility = await repository.checkCpEligibility(42);
    expect(eligibility.allowed, isTrue);
    expect(eligibility.message, 'ELIGIBLE');
    expect(await repository.requestCp(42), 'invite-3');
    await repository.resolveCpInvitation(invitationId: '9', accepted: true);
    await repository.resolveCpInvitation(
      invitationId: 'invite-1',
      accepted: false,
    );

    expect(harness.requests[4].query, <String, String>{'userId': '42'});
    expect(harness.requests[5].body, <String, Object?>{'targetUserId': 42});
    expect(harness.requests[6].path, '/app-mini-api/mini/v1/cp/accept');
    expect(harness.requests[6].body, <String, Object?>{'cpRequestId': '9'});
    expect(harness.requests[7].path, '/app-mini-api/mini/v1/cp/reject');
    expect(harness.requests[7].body, <String, Object?>{
      'cpRequestId': 'invite-1',
    });
  });

  test(
    'community CP writes reject mismatched identity and non-terminal state',
    () async {
      final Map<String, Object?> responses = <String, Object?>{
        'request-missing-id': <String, Object?>{
          'targetUserId': 42,
          'status': 'PENDING',
        },
        'request-wrong-target': <String, Object?>{
          'cpRequestId': 'request-wrong-target',
          'targetUserId': 99,
          'status': 'PENDING',
        },
        'request-wrong-state': <String, Object?>{
          'cpRequestId': 'request-wrong-state',
          'targetUserId': 44,
          'status': 'ACCEPTED',
        },
        'accept-wrong-id': <String, Object?>{
          'cpRequestId': 'different',
          'status': 'ACCEPTED',
          'cpRelationId': 'relation-1',
        },
        'accept-no-relation': <String, Object?>{
          'cpRequestId': 'accept-no-relation',
          'status': 'ACCEPTED',
          'cpRelationId': '',
        },
        'reject-has-relation': <String, Object?>{
          'cpRequestId': 'reject-has-relation',
          'status': 'REJECTED',
          'cpRelationId': 'relation-should-not-exist',
        },
        'reject-wrong-state': <String, Object?>{
          'cpRequestId': 'reject-wrong-state',
          'status': 'PENDING',
          'cpRelationId': '',
        },
      };
      int requestCall = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/cp/request')) {
          requestCall += 1;
          return _Response.ok(
            responses[switch (requestCall) {
              1 => 'request-missing-id',
              2 => 'request-wrong-target',
              _ => 'request-wrong-state',
            }],
          );
        }
        final Map<String, Object?> body = request.body! as Map<String, Object?>;
        return _Response.ok(responses[body['cpRequestId']]);
      });
      addTearDown(harness.close);

      Future<void> expectProtocol(Future<Object?> future) => expectLater(
        future,
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await expectProtocol(harness.repository.requestCp(42));
      await expectProtocol(harness.repository.requestCp(43));
      await expectProtocol(harness.repository.requestCp(44));
      await expectProtocol(
        harness.repository.resolveCpInvitation(
          invitationId: 'accept-wrong-id',
          accepted: true,
        ),
      );
      await expectProtocol(
        harness.repository.resolveCpInvitation(
          invitationId: 'accept-no-relation',
          accepted: true,
        ),
      );
      await expectProtocol(
        harness.repository.resolveCpInvitation(
          invitationId: 'reject-has-relation',
          accepted: false,
        ),
      );
      await expectProtocol(
        harness.repository.resolveCpInvitation(
          invitationId: 'reject-wrong-state',
          accepted: false,
        ),
      );
    },
  );

  test(
    'community pagination rejects unsafe and non-progressing envelopes',
    () async {
      int calls = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/getGuildMembers') {
          final int call = calls++;
          if (call == 0) {
            return _Response.ok(<String, Object?>{
              'list': <Object?>[],
              'current': 1,
              'pageSize': 50,
              'total': 51,
              'pages': 2,
            });
          }
          if (call < 3) {
            return _Response.ok(<String, Object?>{
              'list': <Object?>[
                <String, Object?>{'userId': 41, 'nickName': '成员'},
              ],
              'current': 1,
              'pageSize': 50,
              'total': 51,
              'pages': 2,
            });
          }
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{'userId': 41},
            ],
            'current': 1,
            'pageSize': 50,
            'total': 50001,
            'pages': 1001,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      Future<void> expectProtocol() async {
        await expectLater(
          harness.repository.fetchGuildMembers('guild-1'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }

      await expectProtocol();
      await expectProtocol();
      await expectProtocol();
    },
  );

  test(
    'community pagination requires list/records parity and object rows',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/searchGuild') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{'guildId': 'g-1'},
            ],
            'records': <Object?>[
              <String, Object?>{'guildId': 'g-2'},
            ],
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.searchGuilds('guild'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      final _Harness nonMapHarness = await _Harness.start((
        RequestRecord request,
      ) {
        if (request.path == '/app-api/guild/searchGuild') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>['not-an-object'],
            'records': <Object?>['not-an-object'],
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(nonMapHarness.close);
      await expectLater(
        nonMapHarness.repository.searchGuilds('guild'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'community preserves authoritative live counts and member presence fields',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/guild/getRecommendGuildPage') {
          final List<Object?> rows = <Object?>[
            <String, Object?>{
              ..._b709GuildRow(),
              'guildId': 'g-unknown',
              'guildName': '未知公会',
              'name': '未知公会',
              'roomId': 'room-1',
              'roomCode': '10001',
              'roomName': '未知房间',
            },
          ];
          return _Response.ok(<String, Object?>{
            'list': rows,
            'records': rows,
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
          });
        }
        if (request.path == '/app-api/guild/getGuildMembers') {
          final List<Object?> rows = <Object?>[
            <String, Object?>{
              ..._b709GuildMemberRow(),
              'userId': 7,
              'nickName': '成员',
            },
          ];
          return _Response.ok(<String, Object?>{
            'list': rows,
            'records': rows,
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
          });
        }
        if (request.path == '/app-mini-api/mini/v1/invite/attribution') {
          return _Response.ok(<String, Object?>{
            'attributionAvailable': true,
            'inviterUserId': 7,
            'inviterName': '邀请人',
            'channelCode': 'channel-1',
            'attributedAt': '2026-08-20T00:00:00Z',
            'source': 'FIRST_PARTY_RECORDED',
          });
        }
        if (request.path == '/app-mini-api/mini/v1/cp/my-list') {
          final List<Object?> rows = <Object?>[
            <String, Object?>{
              ..._b709CpRelationRow(),
              'cpRelationId': 'cp-unknown-days',
              'userId': 31,
              'createdAt': '2026-08-22T00:00:00Z',
            },
          ];
          return _Response.ok(<String, Object?>{
            'list': rows,
            'records': rows,
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final GuildHomeSnapshot home = await harness.repository.fetchGuildHome();
      expect(home.currentGuild, isNull);
      expect(home.currentGuildAuthority, GuildCurrentAuthority.unavailable);
      expect(home.recommended.single.rooms.single.onlineUsers, 0);
      expect(home.recommended.single.applicationPending, isNull);
      expect(home.recommended.single.hasSignedToday, isNull);
      expect(home.recommended.single.hasNewApplications, isFalse);
      final List<GuildMember> members = await harness.repository
          .fetchGuildMembers('g-unknown');
      expect(members.single.roomId, isNull);
      expect(members.single.isSigned, isFalse);
      expect(
        (await harness.repository.fetchInviteAttribution()).invitedUsers,
        isNull,
      );
      expect((await harness.repository.fetchCpRelations()).single.days, 1);
    },
  );

  test(
    'community ends CP relation through the first-party mutation route',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'cpRelationId': 'cp-relation-1',
          'status': 'ENDED',
          'ended': true,
        });
      });
      addTearDown(harness.close);

      await harness.repository.endCpRelation('cp-relation-1');
      expect(harness.requests.single.path, '/app-mini-api/mini/v1/cp/end');
      expect(harness.requests.single.method, 'POST');
      expect(harness.requests.single.body, <String, Object?>{
        'cpRelationId': 'cp-relation-1',
      });
      await expectLater(
        harness.repository.endCpRelation(''),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test('community rejects unconfirmed or mismatched CP termination', () async {
    final List<Map<String, Object?>> invalidResponses = <Map<String, Object?>>[
      <String, Object?>{},
      <String, Object?>{
        'cpRelationId': 'different-relation',
        'status': 'ENDED',
        'ended': true,
      },
      <String, Object?>{
        'cpRelationId': 'cp-relation-1',
        'status': 'ACTIVE',
        'ended': true,
      },
      <String, Object?>{
        'cpRelationId': 'cp-relation-1',
        'status': 'ENDED',
        'ended': 1,
      },
    ];
    int responseIndex = 0;
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(invalidResponses[responseIndex++]);
    });
    addTearDown(harness.close);

    for (int index = 0; index < invalidResponses.length; index += 1) {
      await expectLater(
        harness.repository.endCpRelation('cp-relation-1'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    }
    expect(harness.requests, hasLength(invalidResponses.length));
  });

  test('CP relation requires server createdAt', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path == '/app-mini-api/mini/v1/cp/my-list') {
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{'cpRelationId': 'cp-missing-time', 'userId': 31},
          ],
          'current': 1,
          'pageSize': 20,
          'total': 1,
          'pages': 1,
        });
      }
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchCpRelations(),
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
    'community guardian and fan snapshot fans out four GET contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/room/radio/v1/queryGuardianLevels' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'id': '2',
                  'name': '银色守护',
                  'price': 88,
                  'durationDays': 30,
                },
              ],
              'total': 1,
              'providerInvocation': false,
            },
          ),
          '/app-api/room/radio/v1/queryOenGuardianInfo' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'anchorName': '主播甲',
              'nickName': '主播甲',
              'roomId': 'room-88',
              'active': true,
              'guardianLevelId': '2',
              'levelId': '2',
              'levelName': '银色守护',
              'price': 88,
              'durationDays': 30,
              'startedAt': '2026-08-01T00:00:00Z',
              'expiresAt': '2026-08-31T00:00:00Z',
              'providerInvocation': false,
            }),
          '/app-api/room/radio/v1/queryFansTeamRelation' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'roomId': 'room-88',
              'fansTeamId': 'fans-88',
              'fansTeamName': '甲的粉团',
              'teamName': '甲的粉团',
              'teamExists': true,
              'fansLevel': 3,
              'level': 3,
              'intimacy': 66,
              'joined': true,
              'isJoin': true,
              'providerInvocation': false,
            }),
          '/app-api/room/radio/v1/queryFansTeamTaskPage' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                _b709TaskRow(
                  taskId: 201,
                  taskCode: 'FANS_STAY',
                  taskName: '陪伴主播',
                  progress: 2,
                  target: 5,
                  status: 2,
                  claimed: true,
                ),
              ],
              'records': <Object?>[
                _b709TaskRow(
                  taskId: 201,
                  taskCode: 'FANS_STAY',
                  taskName: '陪伴主播',
                  progress: 2,
                  target: 5,
                  status: 2,
                  claimed: true,
                ),
              ],
              'total': 1,
              'anchorUserId': 88,
              'roomId': 'room-88',
              'fansTeamId': 'fans-88',
              'fansTeamName': '甲的粉团',
              'teamExists': true,
              'joined': true,
              'isJoin': true,
              'providerInvocation': false,
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
          '/app-api/room/radio/v1/becomeGuard' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'active': true,
              'guardianLevelId': '2',
              'providerInvocation': false,
            }),
          '/app-api/room/radio/v1/joinFansTeam' =>
            _Response.ok(<String, Object?>{
              'anchorUserId': 88,
              'joined': true,
              'fansTeamId': 'fans-team-88',
              'status': 'ACTIVE',
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/completeDailySignIn' =>
            _Response.ok(<String, Object?>{
              'signed': true,
              'signedToday': true,
              'isSign': true,
              'alreadySigned': false,
              'businessDate': '2026-08-23',
              'taskId': 100,
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/receiveTaskReward' =>
            _Response.ok(<String, Object?>{
              'taskId': 101,
              'claimed': true,
              'isReceive': true,
              'status': 2,
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                _b709TaskRow(
                  taskId: 101,
                  taskCode: 'DAILY_SIGN_IN',
                  taskName: '签到',
                  progress: 1,
                  target: 1,
                  status: 1,
                  claimed: false,
                ),
              ],
              'records': <Object?>[
                _b709TaskRow(
                  taskId: 101,
                  taskCode: 'DAILY_SIGN_IN',
                  taskName: '签到',
                  progress: 1,
                  target: 1,
                  status: 1,
                  claimed: false,
                ),
              ],
              'total': 1,
              'type': 1,
              'providerInvocation': false,
            },
          ),
          '/app-api/taskSystem/querySignReward' =>
            _Response.ok(<String, Object?>{
              'list': _b709SignRows(),
              'records': _b709SignRows(),
              'total': 7,
              'cycleStart': '2026-08-17',
              'cycleEnd': '2026-08-23',
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/queryTodaySignStatus' =>
            _Response.ok(<String, Object?>{
              'signedToday': false,
              'isSign': false,
              'continuousDays': 2,
              'consecutiveDays': 2,
              'businessDate': '2026-08-23',
              'providerInvocation': false,
            }),
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
      await repository.claimTask('101');

      expect(harness.requests[0].path, '/app-api/room/radio/v1/becomeGuard');
      expect(harness.requests[0].body, <String, Object?>{
        'anchorUserId': 88,
        'guardianLevelId': '2',
      });
      expect(harness.requests[1].path, '/app-api/room/radio/v1/joinFansTeam');
      expect(harness.requests[1].body, <String, Object?>{'anchorUserId': 88});
      expect(harness.requests[2].query, <String, String>{'type': '1'});
      expect(
        harness.requests[5].path,
        '/app-api/taskSystem/completeDailySignIn',
      );
      expect(harness.requests[5].method, 'POST');
      expect(harness.requests[5].body, <String, Object?>{});
      expect(harness.requests[5].requestId, startsWith('flutter-'));
      expect(harness.requests[9].method, 'POST');
      expect(harness.requests[9].body, <String, Object?>{'taskId': 101});
      expect(harness.requests[9].requestId, startsWith('flutter-'));
      expect(
        harness.requests[9].requestId,
        isNot(harness.requests[5].requestId),
      );
    },
  );

  test('community attribution, activities, and error envelopes map', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-mini-api/mini/v1/invite/attribution' =>
          _Response.ok(<String, Object?>{
            'attributionAvailable': true,
            'inviterUserId': 7,
            'channelCode': 'invite-7',
            'inviterName': '邀请人',
            'attributedAt': '2026-08-22T00:00:00Z',
            'source': 'FIRST_PARTY_RECORDED',
          }),
        '/app-mini-api/mini/v1/activity/list' => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'activityId': 'activity-1',
              'title': '夏日活动',
              'description': '活动说明',
              'startsAt': '2026-08-22T00:00:00Z',
              'endsAt': '2026-08-30T00:00:00Z',
            },
          ],
          'records': <Object?>[
            <String, Object?>{
              'activityId': 'activity-1',
              'title': '夏日活动',
              'description': '活动说明',
              'startsAt': '2026-08-22T00:00:00Z',
              'endsAt': '2026-08-30T00:00:00Z',
            },
          ],
          'current': 1,
          'pageSize': 50,
          'total': 1,
          'pages': 1,
          'fabricated': false,
          'catalogAvailable': true,
        }),
        _ => const _Response(
          statusCode: 422,
          code: 422,
          message: '关键词不可用',
          data: null,
        ),
      };
    });
    addTearDown(harness.close);
    final BackendCommunityRepository repository = harness.repository;
    expect(repository.supportsInviteAttribution, isTrue);
    expect(repository.supportsActivityCatalog, isTrue);
    final InviteAttribution attribution = await repository
        .fetchInviteAttribution();
    expect(attribution.available, isTrue);
    expect(attribution.inviteCode, 'invite-7');
    final ThemeActivity activity = (await repository.fetchActivities()).single;
    expect(activity.title, '夏日活动');
    expect(activity.status, ThemeActivityStatus.active);
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
  });

  test(
    'community attribution accepts b709 unavailable inviter identity',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'attributionAvailable': true,
          'inviterUserId': '',
          'inviterName': '',
          'channelCode': 'legacy-channel',
          'attributedAt': '2026-08-22T00:00:00Z',
          'source': 'FIRST_PARTY_RECORDED',
        });
      });
      addTearDown(harness.close);

      final InviteAttribution attribution = await harness.repository
          .fetchInviteAttribution();
      expect(attribution.available, isTrue);
      expect(attribution.channelName, isEmpty);
      expect(attribution.invitedUsers, isNull);
    },
  );

  test('community CP eligibility rejects inconsistent b709 reason', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{
        'eligible': true,
        'reason': 'ACTIVE_CP_EXISTS',
        'targetUserId': 42,
      });
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.checkCpEligibility(42),
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
    'activity without status trusts the first-party active-row invariant',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-mini-api/mini/v1/activity/list') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'activityId': 'activity-active-row',
                'title': '服务端活动',
                'description': '',
                // Deliberately outside the client clock window: the endpoint
                // contract, rather than DateTime.now(), determines the status.
                'startsAt': '2099-01-01T00:00:00Z',
                'endsAt': '2099-02-01T00:00:00Z',
              },
            ],
            'records': <Object?>[
              <String, Object?>{
                'activityId': 'activity-active-row',
                'title': '服务端活动',
                'description': '',
                'startsAt': '2099-01-01T00:00:00Z',
                'endsAt': '2099-02-01T00:00:00Z',
              },
            ],
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'fabricated': false,
            'catalogAvailable': true,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final ThemeActivity activity =
          (await harness.repository.fetchActivities()).single;
      expect(activity.status, ThemeActivityStatus.active);
    },
  );

  test(
    'activity status is server-authoritative and unknown status fails closed',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-mini-api/mini/v1/activity/list') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'activityId': 'activity-unknown',
                'title': '未知状态活动',
                'description': '',
                'status': 'MYSTERY',
                'startsAt': '2026-08-22T00:00:00Z',
                'endsAt': '2026-08-30T00:00:00Z',
              },
            ],
            'records': <Object?>[
              <String, Object?>{
                'activityId': 'activity-unknown',
                'title': '未知状态活动',
                'description': '',
                'status': 'MYSTERY',
                'startsAt': '2026-08-22T00:00:00Z',
                'endsAt': '2026-08-30T00:00:00Z',
              },
            ],
            'current': 1,
            'pageSize': 50,
            'total': 1,
            'pages': 1,
            'fabricated': false,
            'catalogAvailable': true,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchActivities(),
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
    'community preserves validation, authorization, conflict, and server errors',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guild/searchGuild' => const _Response(
            statusCode: 400,
            code: 400,
            message: '搜索参数无效',
            data: null,
          ),
          '/app-api/guild/getGuildHomepageDetails' => const _Response(
            statusCode: 403,
            code: 403,
            message: '无权查看',
            data: null,
          ),
          '/app-mini-api/mini/v1/cp/request' => const _Response(
            statusCode: 409,
            code: 409,
            message: '已有待处理请求',
            data: null,
          ),
          '/app-mini-api/mini/v1/activity/list' => const _Response(
            statusCode: 422,
            code: 422,
            message: '活动参数无效',
            data: null,
          ),
          '/app-api/taskSystem/queryTaskRecords' => const _Response(
            statusCode: 500,
            code: 500,
            message: '服务暂不可用',
            data: null,
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      Future<void> expectFailure(
        Future<Object?> Function() action,
        ApiFailureKind kind,
        int status,
      ) async {
        await expectLater(
          action,
          throwsA(
            isA<ApiException>()
                .having((ApiException error) => error.kind, 'kind', kind)
                .having(
                  (ApiException error) => error.httpStatus,
                  'httpStatus',
                  status,
                ),
          ),
        );
      }

      await expectFailure(
        () => repository.searchGuilds('x'),
        ApiFailureKind.validation,
        400,
      );
      await expectFailure(
        () => repository.fetchGuild('g-1'),
        ApiFailureKind.forbidden,
        403,
      );
      await expectFailure(
        () => repository.requestCp(42),
        ApiFailureKind.conflict,
        409,
      );
      await expectFailure(
        () => repository.fetchActivities(),
        ApiFailureKind.validation,
        422,
      );
      await expectFailure(
        () => repository.fetchTaskCenter(),
        ApiFailureKind.server,
        500,
      );
    },
  );

  test(
    'community repeated reads keep stable ids and stale application status',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-mini-api/mini/v1/cp/request' => _Response.ok(<String, Object?>{
            'cpRequestId': 'request-stable',
            'targetUserId': 42,
            'status': 'PENDING',
          }),
          '/app-api/guild/getMembershipApplications' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  ..._b709GuildApplicationRow(),
                  'applicationId': 'application-stale',
                  'userId': 8,
                  'nickName': '历史申请用户',
                  'status': 'REJECTED',
                  'createdAt': '2026-08-21T00:00:00Z',
                  'resolvedAt': '2026-08-21T01:00:00Z',
                },
              ],
              'records': <Object?>[
                <String, Object?>{
                  ..._b709GuildApplicationRow(),
                  'applicationId': 'application-stale',
                  'userId': 8,
                  'nickName': '历史申请用户',
                  'status': 'REJECTED',
                  'createdAt': '2026-08-21T00:00:00Z',
                  'resolvedAt': '2026-08-21T01:00:00Z',
                },
              ],
              'current': 1,
              'size': 50,
              'pageSize': 50,
              'total': 1,
              'pages': 1,
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommunityRepository repository = harness.repository;

      final String firstRequest = await repository.requestCp(42);
      final String repeatedRequest = await repository.requestCp(42);
      expect(firstRequest, 'request-stable');
      expect(repeatedRequest, firstRequest);
      expect(
        harness.requests
            .where((RequestRecord item) => item.path.endsWith('/cp/request'))
            .map((RequestRecord item) => item.body)
            .toList(),
        <Object?>[
          <String, Object?>{'targetUserId': 42},
          <String, Object?>{'targetUserId': 42},
        ],
      );

      final List<GuildApplication> applications = await repository
          .fetchGuildApplications('guild-1');
      expect(applications.single.status, GuildApplicationStatus.rejected);
      expect(applications.single.appliedAt, '2026-08-21T00:00:00Z');
    },
  );

  test(
    'concurrent CP requests for one target coalesce without swallowing 409',
    () async {
      final Completer<void> release = Completer<void>();
      int cpCalls = 0;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path == '/app-mini-api/mini/v1/cp/request') {
          cpCalls += 1;
          await release.future;
          return _Response.ok(<String, Object?>{
            'cpRequestId': 'cp-request-1',
            'targetUserId': 42,
            'status': 'PENDING',
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final Future<String> first = harness.repository.requestCp(42);
      final Future<String> second = harness.repository.requestCp(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cpCalls, 1);
      expect(
        harness.requests.where(
          (RequestRecord item) => item.path.endsWith('/cp/request'),
        ),
        hasLength(1),
      );
      release.complete();
      expect(await Future.wait(<Future<String>>[first, second]), <String>[
        'cp-request-1',
        'cp-request-1',
      ]);
    },
  );

  test(
    'community b709 read rows fail closed instead of fabricating required fields',
    () async {
      final List<
        ({
          String path,
          Map<String, Object?> row,
          String missingField,
          Future<Object?> Function(BackendCommunityRepository repository) read,
          int pageSize,
        })
      >
      cases =
          <
            ({
              String path,
              Map<String, Object?> row,
              String missingField,
              Future<Object?> Function(BackendCommunityRepository repository)
              read,
              int pageSize,
            })
          >[
            (
              path: '/app-api/guild/getGuildHomepageDetails',
              row: _b709GuildRow(includeHomepageState: true),
              missingField: 'ownerUserId',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchGuild('guild-1'),
              pageSize: 0,
            ),
            (
              path: '/app-api/guild/getGuildMembers',
              row: _b709GuildMemberRow(),
              missingField: 'nickName',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchGuildMembers('guild-1'),
              pageSize: 50,
            ),
            (
              path: '/app-api/guild/getMembershipApplications',
              row: _b709GuildApplicationRow(),
              missingField: 'createdAt',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchGuildApplications('guild-1'),
              pageSize: 50,
            ),
            (
              path: '/app-mini-api/mini/v1/cp/my-list',
              row: _b709CpRelationRow(),
              missingField: 'status',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchCpRelations(),
              pageSize: 20,
            ),
            (
              path: '/app-mini-api/mini/v1/cp/pending-requests',
              row: _b709CpInvitationRow(),
              missingField: 'userId',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchPendingCpInvitations(),
              pageSize: 20,
            ),
            (
              path: '/app-mini-api/mini/v1/activity/list',
              row: _b709ActivityRow(),
              missingField: 'title',
              read: (BackendCommunityRepository repository) =>
                  repository.fetchActivities(),
              pageSize: 50,
            ),
          ];

      for (final testCase in cases) {
        final Map<String, Object?> malformed = Map<String, Object?>.from(
          testCase.row,
        )..remove(testCase.missingField);
        final _Harness harness = await _Harness.start((RequestRecord request) {
          if (request.path != testCase.path) {
            return _Response.ok(<String, Object?>{});
          }
          if (testCase.pageSize == 0) {
            return _Response.ok(malformed);
          }
          final Map<String, Object?> page = _b709Page(
            malformed,
            pageSize: testCase.pageSize,
          );
          if (testCase.path.endsWith('/activity/list')) {
            page
              ..['fabricated'] = false
              ..['catalogAvailable'] = true;
          }
          return _Response.ok(page);
        });
        try {
          await expectLater(
            testCase.read(harness.repository),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
            reason:
                '${testCase.path} must reject missing ${testCase.missingField}',
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test('community maps exact b709 guardian and fans payloads', () async {
    final Map<String, Object?> fansTask = _b709TaskRow(
      taskId: 201,
      taskCode: 'FANS_STAY',
      taskName: '陪伴主播',
      progress: 2,
      target: 5,
      status: 0,
      claimed: false,
    );
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-api/room/radio/v1/queryGuardianLevels' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'id': 'SILVER',
                'name': '银色守护',
                'price': 88,
                'durationDays': 30,
              },
            ],
            'total': 1,
            'providerInvocation': false,
          },
        ),
        '/app-api/room/radio/v1/queryOenGuardianInfo' =>
          _Response.ok(<String, Object?>{
            'anchorUserId': 88,
            'anchorName': '主播甲',
            'nickName': '主播甲',
            'roomId': 'room-88',
            'active': true,
            'guardianLevelId': 'SILVER',
            'levelId': 'SILVER',
            'levelName': '银色守护',
            'price': 88,
            'durationDays': 30,
            'startedAt': '2026-08-01T00:00:00Z',
            'expiresAt': '2026-08-31T00:00:00Z',
            'providerInvocation': false,
          }),
        '/app-api/room/radio/v1/queryFansTeamRelation' =>
          _Response.ok(<String, Object?>{
            'anchorUserId': 88,
            'roomId': 'room-88',
            'fansTeamId': 'fans-88',
            'fansTeamName': '甲的粉团',
            'teamName': '甲的粉团',
            'teamExists': true,
            'fansLevel': 3,
            'level': 3,
            'intimacy': 66,
            'joined': true,
            'isJoin': true,
            'providerInvocation': false,
          }),
        '/app-api/room/radio/v1/queryFansTeamTaskPage' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[fansTask],
            'records': <Object?>[fansTask],
            'total': 1,
            'anchorUserId': 88,
            'roomId': 'room-88',
            'fansTeamId': 'fans-88',
            'fansTeamName': '甲的粉团',
            'teamExists': true,
            'joined': true,
            'isJoin': true,
            'providerInvocation': false,
          },
        ),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    final GuardianFanSnapshot snapshot = await harness.repository
        .fetchGuardianFan(88);
    expect(snapshot.anchorName, '主播甲');
    expect(snapshot.currentGuardianLevel?.id, 'SILVER');
    expect(snapshot.fansTeamName, '甲的粉团');
    expect(snapshot.fansLevel, 3);
    expect(snapshot.intimacy, 66);
    expect(snapshot.joinedFansTeam, isTrue);
    expect(snapshot.tasks.single.id, '201');
    expect(snapshot.tasks.single.progress, 2);
  });

  test(
    'community guardian catalog rejects missing b709 level identity',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/room/radio/v1/queryGuardianLevels') {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'id': 'SILVER',
                // b709 always exposes a non-empty name.
                'price': 88,
                'durationDays': 30,
              },
            ],
            'total': 1,
            'providerInvocation': false,
          });
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchGuardianFan(88),
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

  test('community fans relation rejects divergent b709 join aliases', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-api/room/radio/v1/queryGuardianLevels' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[],
            'total': 0,
            'providerInvocation': false,
          },
        ),
        '/app-api/room/radio/v1/queryOenGuardianInfo' =>
          _Response.ok(<String, Object?>{
            'anchorUserId': 88,
            'anchorName': '主播甲',
            'nickName': '主播甲',
            'roomId': 'room-88',
            'active': false,
            'guardianLevelId': '',
            'levelId': '',
            'levelName': '',
            'price': 0,
            'durationDays': 0,
            'startedAt': '',
            'expiresAt': '',
            'providerInvocation': false,
          }),
        '/app-api/room/radio/v1/queryFansTeamRelation' =>
          _Response.ok(<String, Object?>{
            'anchorUserId': 88,
            'roomId': 'room-88',
            'fansTeamId': 'fans-88',
            'fansTeamName': '甲的粉团',
            'teamName': '甲的粉团',
            'teamExists': true,
            'fansLevel': 1,
            'level': 1,
            'intimacy': 3,
            'joined': true,
            'isJoin': false,
            'providerInvocation': false,
          }),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchGuardianFan(88),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('community exact b709 task payload rejects alias divergence', () async {
    final Map<String, Object?> task = _b709TaskRow(
      taskId: 101,
      taskCode: 'DAILY_SIGN_IN',
      taskName: '每日签到',
      progress: 1,
      target: 1,
      status: 2,
      claimed: true,
    )..['currentValue'] = 0;
    final Map<String, Object?> signDay = <String, Object?>{
      'day': 1,
      'signDay': 1,
      'date': '2026-08-17',
      'rewardDesc': '1积分',
      'reward': '1积分',
      'completed': true,
      'isSign': true,
      'today': true,
      'isToday': true,
    };
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[task],
            'records': <Object?>[task],
            'total': 1,
            'type': 1,
            'providerInvocation': false,
          },
        ),
        '/app-api/taskSystem/querySignReward' => _Response.ok(<String, Object?>{
          'list': <Object?>[signDay],
          'records': <Object?>[signDay],
          'total': 1,
          'cycleStart': '2026-08-17',
          'cycleEnd': '2026-08-23',
          'providerInvocation': false,
        }),
        '/app-api/taskSystem/queryTodaySignStatus' =>
          _Response.ok(<String, Object?>{
            'signedToday': true,
            'isSign': true,
            'continuousDays': 1,
            'consecutiveDays': 1,
            'businessDate': '2026-08-17',
            'providerInvocation': false,
          }),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchTaskCenter(),
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
    'task description aliases may differ from the title when they agree',
    () async {
      final Map<String, Object?> task =
          _b709TaskRow(
              taskId: 102,
              taskCode: 'DAILY_SIGN_IN',
              taskName: '每日签到',
              progress: 1,
              target: 1,
              status: 2,
              claimed: true,
            )
            ..['description'] = '完成签到后领取积分'
            ..['taskDesc'] = '完成签到后领取积分';
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[task],
              'records': <Object?>[task],
              'total': 1,
              'type': 1,
              'providerInvocation': false,
            },
          ),
          '/app-api/taskSystem/querySignReward' =>
            _Response.ok(<String, Object?>{
              'list': _b709SignRows(),
              'records': _b709SignRows(),
              'total': 7,
              'cycleStart': '2026-08-17',
              'cycleEnd': '2026-08-23',
              'providerInvocation': false,
            }),
          '/app-api/taskSystem/queryTodaySignStatus' =>
            _Response.ok(<String, Object?>{
              'signedToday': true,
              'isSign': true,
              'continuousDays': 1,
              'consecutiveDays': 1,
              'businessDate': '2026-08-17',
              'providerInvocation': false,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final TaskCenterSnapshot snapshot = await harness.repository
          .fetchTaskCenter();

      expect(snapshot.tasks.single.title, '每日签到');
      expect(snapshot.tasks.single.description, '完成签到后领取积分');
    },
  );

  test('task description aliases are both required', () async {
    final Map<String, Object?> task = _b709TaskRow(
      taskId: 103,
      taskCode: 'DAILY_SIGN_IN',
      taskName: '每日签到',
      progress: 1,
      target: 1,
      status: 2,
      claimed: true,
    )..remove('taskDesc');
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[task],
            'records': <Object?>[task],
            'total': 1,
            'type': 1,
            'providerInvocation': false,
          },
        ),
        '/app-api/taskSystem/querySignReward' => _Response.ok(<String, Object?>{
          'list': _b709SignRows(),
          'records': _b709SignRows(),
          'total': 7,
          'cycleStart': '2026-08-17',
          'cycleEnd': '2026-08-23',
          'providerInvocation': false,
        }),
        '/app-api/taskSystem/queryTodaySignStatus' =>
          _Response.ok(<String, Object?>{
            'signedToday': true,
            'isSign': true,
            'continuousDays': 1,
            'consecutiveDays': 1,
            'businessDate': '2026-08-17',
            'providerInvocation': false,
          }),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchTaskCenter(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('task description aliases must agree', () async {
    final Map<String, Object?> task = _b709TaskRow(
      taskId: 104,
      taskCode: 'DAILY_SIGN_IN',
      taskName: '每日签到',
      progress: 1,
      target: 1,
      status: 2,
      claimed: true,
    )..['description'] = '说明一';
    final _Harness harness = await _Harness.start((RequestRecord request) {
      final Map<String, Object?> responseTask = task..['taskDesc'] = '说明二';
      return switch (request.path) {
        '/app-api/taskSystem/queryTaskRecords' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[responseTask],
            'records': <Object?>[responseTask],
            'total': 1,
            'type': 1,
            'providerInvocation': false,
          },
        ),
        '/app-api/taskSystem/querySignReward' => _Response.ok(<String, Object?>{
          'list': _b709SignRows(),
          'records': _b709SignRows(),
          'total': 7,
          'cycleStart': '2026-08-17',
          'cycleEnd': '2026-08-23',
          'providerInvocation': false,
        }),
        '/app-api/taskSystem/queryTodaySignStatus' =>
          _Response.ok(<String, Object?>{
            'signedToday': true,
            'isSign': true,
            'continuousDays': 1,
            'consecutiveDays': 1,
            'businessDate': '2026-08-17',
            'providerInvocation': false,
          }),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchTaskCenter(),
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
    'community guild writes reject an explicit provider invocation',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/guildManagement/applyForMembership' =>
            _Response.ok(<String, Object?>{
              'applicationId': 'app-provider',
              'guildId': 'g-provider',
              'status': 'PENDING',
              'providerInvocation': true,
            }),
          '/app-api/guildManagement/quitGuild' =>
            _Response.ok(<String, Object?>{
              'guildId': 'g-provider',
              'status': 'LEFT',
              'left': true,
              'providerInvocation': true,
            }),
          '/app-api/guild/sign' => _Response.ok(<String, Object?>{
            'guildId': 'g-provider',
            'signed': true,
            'alreadySigned': false,
            'signDate': '2026-08-23',
            'rewardPoints': 1,
            'providerInvocation': true,
          }),
          '/app-api/guildManagement/approvalMembershipApplication' =>
            _Response.ok(<String, Object?>{
              'applicationId': 'app-provider',
              'guildId': 'g-provider',
              'status': 'APPROVED',
              'providerInvocation': true,
            }),
          '/app-api/guildManagement/memberBanOrUnseal' =>
            _Response.ok(<String, Object?>{
              'guildId': 'g-provider',
              'userId': 21,
              'muted': false,
              'providerInvocation': true,
            }),
          '/app-api/guildManagement/kickOutMember' =>
            _Response.ok(<String, Object?>{
              'guildId': 'g-provider',
              'userId': 21,
              'removed': true,
              'providerInvocation': true,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      Future<void> expectProtocol(Future<Object?> future) => expectLater(
        future,
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await expectProtocol(harness.repository.applyToJoinGuild('g-provider'));
      await expectProtocol(harness.repository.quitGuild('g-provider'));
      await expectProtocol(harness.repository.signGuild('g-provider'));
      await expectProtocol(
        harness.repository.resolveGuildApplication(
          applicationId: 'app-provider',
          accepted: true,
        ),
      );
      await expectProtocol(
        harness.repository.setGuildMemberMuted(
          guildId: 'g-provider',
          userId: 21,
          muted: false,
        ),
      );
      await expectProtocol(
        harness.repository.removeGuildMember(guildId: 'g-provider', userId: 21),
      );
    },
  );

  test('community CP writes reject an explicit provider invocation', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path == '/app-mini-api/mini/v1/cp/request') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': 'cp-request-provider',
          'targetUserId': 42,
          'status': 'PENDING',
          'providerInvocation': true,
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/accept') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': 'cp-accept-provider',
          'status': 'ACCEPTED',
          'cpRelationId': 'cp-relation-provider',
          'providerInvocation': true,
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/reject') {
        return _Response.ok(<String, Object?>{
          'cpRequestId': 'cp-reject-provider',
          'status': 'REJECTED',
          'cpRelationId': '',
          'providerInvocation': true,
        });
      }
      if (request.path == '/app-mini-api/mini/v1/cp/end') {
        return _Response.ok(<String, Object?>{
          'cpRelationId': 'cp-end-provider',
          'status': 'ENDED',
          'ended': true,
          'providerInvocation': true,
        });
      }
      return _Response.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    Future<void> expectProtocol(Future<Object?> future) => expectLater(
      future,
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );

    await expectProtocol(harness.repository.requestCp(42));
    await expectProtocol(
      harness.repository.resolveCpInvitation(
        invitationId: 'cp-accept-provider',
        accepted: true,
      ),
    );
    await expectProtocol(
      harness.repository.resolveCpInvitation(
        invitationId: 'cp-reject-provider',
        accepted: false,
      ),
    );
    await expectProtocol(harness.repository.endCpRelation('cp-end-provider'));
  });

  test(
    'community paginated collections reject cross-page authoritative ID duplicates',
    () async {
      Future<void> expectDuplicate({
        required String route,
        required int pageSize,
        required Map<String, Object?> Function(int index) rowForIndex,
        required Future<void> Function(BackendCommunityRepository repository)
        load,
        bool activity = false,
      }) async {
        final _Harness harness = await _Harness.start((RequestRecord request) {
          if (request.path != route) {
            return _Response.ok(<String, Object?>{});
          }
          final Object? body = request.body;
          final int page = body is Map
              ? body['pageNum']! as int
              : int.parse(request.query['pageNum']!);
          final List<Object?> items = page == 1
              ? List<Object?>.generate(pageSize, rowForIndex)
              : <Object?>[rowForIndex(0)];
          return _Response.ok(<String, Object?>{
            'list': items,
            'records': items,
            'current': page,
            'pageSize': pageSize,
            'total': pageSize + 1,
            'pages': 2,
            if (activity) ...<String, Object?>{
              'fabricated': false,
              'catalogAvailable': true,
            },
          });
        });
        try {
          await expectLater(
            load(harness.repository),
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

      await expectDuplicate(
        route: '/app-api/guild/getRecommendGuildPage',
        pageSize: 50,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709GuildRow(),
          'guildId': index == 0 ? 'guild-duplicate' : 'guild-$index',
          'guildName': '公会$index',
          'name': '公会$index',
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchGuildHome();
        },
      );
      await expectDuplicate(
        route: '/app-api/guild/searchGuild',
        pageSize: 50,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709GuildRow(),
          'guildId': index == 0 ? 'guild-duplicate' : 'guild-$index',
          'guildName': '公会$index',
          'name': '公会$index',
        },
        load: (BackendCommunityRepository repository) async {
          await repository.searchGuilds('公会');
        },
      );
      await expectDuplicate(
        route: '/app-api/guild/getGuildMembers',
        pageSize: 50,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709GuildMemberRow(),
          'userId': index == 0 ? 21 : 1000 + index,
          'nickName': '成员$index',
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchGuildMembers('guild-1');
        },
      );
      await expectDuplicate(
        route: '/app-api/guild/getMembershipApplications',
        pageSize: 50,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709GuildApplicationRow(),
          'applicationId': index == 0
              ? 'application-duplicate'
              : 'application-$index',
          'userId': 31 + index,
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchGuildApplications('guild-1');
        },
      );
      await expectDuplicate(
        route: '/app-mini-api/mini/v1/cp/my-list',
        pageSize: 20,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709CpRelationRow(),
          'cpRelationId': index == 0 ? 'relation-duplicate' : 'relation-$index',
          'userId': 41 + index,
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchCpRelations();
        },
      );
      await expectDuplicate(
        route: '/app-mini-api/mini/v1/cp/pending-requests',
        pageSize: 20,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709CpInvitationRow(),
          'cpRequestId': index == 0 ? 'request-duplicate' : 'request-$index',
          'userId': 42 + index,
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchPendingCpInvitations();
        },
      );
      await expectDuplicate(
        route: '/app-mini-api/mini/v1/activity/list',
        pageSize: 50,
        activity: true,
        rowForIndex: (int index) => <String, Object?>{
          ..._b709ActivityRow(),
          'activityId': index == 0 ? 'activity-duplicate' : 'activity-$index',
          'title': '活动$index',
        },
        load: (BackendCommunityRepository repository) async {
          await repository.fetchActivities();
        },
      );
    },
  );
}

Map<String, Object?> _b709GuildRow({bool includeHomepageState = false}) {
  return <String, Object?>{
    'guildId': 'guild-1',
    'code': 'guild-code-1',
    'guildName': '星河公会',
    'name': '星河公会',
    'introduction': '',
    'ownerUserId': 7,
    'ownerName': '会长',
    'ownerAvatar': '',
    'status': 'ACTIVE',
    'memberCount': 12,
    'onlineUsers': 0,
    'artwork': 'https://example.test/guild-artwork.png',
    'hasNewApplications': false,
    'viewerRole': 'NONE',
    'joined': false,
    'roomId': '',
    'roomCode': '',
    'roomName': '',
    'createdAt': '2026-08-01T00:00:00Z',
    'updatedAt': '2026-08-20T00:00:00Z',
    if (includeHomepageState) ...<String, Object?>{
      'signedToday': false,
      'applicationPending': false,
      'businessDate': '2026-08-23',
    },
  };
}

Map<String, Object?> _b709GuildMemberRow() => <String, Object?>{
  'userId': 21,
  'nickName': '公会成员',
  'headImgUrl': '',
  'signature': '',
  'role': 'MEMBER',
  'muted': false,
  'isSigned': false,
  'roomId': '',
  'joinedAt': '2026-08-01T00:00:00Z',
};

Map<String, Object?> _b709GuildApplicationRow() => <String, Object?>{
  'applicationId': 'application-1',
  'userId': 31,
  'nickName': '申请用户',
  'headImgUrl': '',
  'message': '',
  'status': 'PENDING',
  'createdAt': '2026-08-21T00:00:00Z',
  'resolvedAt': '',
};

Map<String, Object?> _b709CpRelationRow() => <String, Object?>{
  'cpRelationId': 'relation-1',
  'userId': 41,
  'nickName': 'CP 用户',
  'headImgUrl': '',
  'status': 'ACTIVE',
  'days': 1,
  'createdAt': '2026-08-10T00:00:00Z',
};

Map<String, Object?> _b709CpInvitationRow() => <String, Object?>{
  'cpRequestId': 'request-1',
  'message': '',
  'status': 'PENDING',
  'userId': 42,
  'nickName': '邀请用户',
  'headImgUrl': '',
  'createdAt': '2026-08-22T00:00:00Z',
};

Map<String, Object?> _b709ActivityRow() => <String, Object?>{
  'activityId': 'activity-1',
  'title': '夏日活动',
  'description': '',
  'startsAt': '2026-08-22T00:00:00Z',
  'endsAt': '2026-08-30T00:00:00Z',
};

Map<String, Object?> _b709TaskRow({
  required int taskId,
  required String taskCode,
  required String taskName,
  required int progress,
  required int target,
  required int status,
  required bool claimed,
}) => <String, Object?>{
  'taskId': taskId,
  'id': taskId,
  'taskCode': taskCode,
  'taskName': taskName,
  'title': taskName,
  'description': taskName,
  'taskDesc': taskName,
  'currentValue': progress,
  'progress': progress,
  'targetValue': target,
  'target': target,
  'rewardDesc': '1积分',
  'reward': '1积分',
  'isReceive': claimed,
  'claimed': claimed,
  'status': status,
  'businessDate': '2026-08-23',
};

List<Object?> _b709SignRows() => List<Object?>.generate(7, (int index) {
  final int day = index + 1;
  return <String, Object?>{
    'day': day,
    'signDay': day,
    'date': '2026-08-${17 + index}',
    'rewardDesc': '1积分',
    'reward': '1积分',
    'completed': index < 2,
    'isSign': index < 2,
    'today': index == 6,
    'isToday': index == 6,
  };
});

Map<String, Object?> _b709Page(
  Map<String, Object?> row, {
  required int pageSize,
}) => <String, Object?>{
  'list': <Object?>[row],
  'records': <Object?>[row],
  'current': 1,
  'pageSize': pageSize,
  'total': 1,
  'pages': 1,
};

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
        clock: () => DateTime(2026, 8, 23),
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
        authorization: captureContractAuthorization(request),
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      _Response response = await handler(record);
      if (record.path == '/app-api/guild/getCurrentGuild' &&
          response.data is Map &&
          (response.data! as Map).isEmpty) {
        response = _Response.ok(<String, Object?>{
          'currentGuildAuthority': 'UNAVAILABLE',
          'authority': 'UNAVAILABLE',
          'available': false,
          'fabricated': false,
          'membershipStatus': 'UNAVAILABLE',
          'currentGuild': null,
          'currentGuildId': '',
        });
      }
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
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String authorization;
  final String requestId;
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
