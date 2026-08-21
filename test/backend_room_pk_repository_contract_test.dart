import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

void main() {
  test(
    'PK read/write contracts preserve route shape and parse battle data',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/activityPk/getRoomPkHotRoomList':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <Map<String, Object?>>[
                <String, Object?>{'id': '9527', 'code': 'R9527', 'name': '当前房'},
                <String, Object?>{
                  'roomId': '10001',
                  'roomCode': 'R10001',
                  'roomName': '星河房',
                  'roomHeadImgUrl': 'https://cdn.example/star.png',
                  'label': '热门',
                  'roomOnlinePersonnelNumber': '33',
                  'isInPK': 0,
                },
              ],
            );
          case '/app-api/activityPk/searchRoomPk':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomCode': 'R10001'});
            return _Reply(
              data: <String, Object?>{
                'records': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': '10001',
                    'code': 'R10001',
                    'name': '星河房',
                    'isInPk': false,
                  },
                ],
              },
            );
          case '/app-api/activityPk/inviteRoomPk':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'inviteUserId': 10001,
              'currentRoomId': 9527,
              'otherRoomId': 10001,
              'punishmentTheme': '分享今天最开心的事',
              'pkTime': 5,
            });
            return const _Reply(
              data: <String, Object?>{'pkInviteId': 'invite-1'},
            );
          case '/app-api/activityPk/getRoomPkProgress':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(data: _battleData());
          case '/app-api/activityPk/acceptRoomPkInvitation':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'id': 'invite-1'});
            return const _Reply(data: null);
          case '/app-api/activityPk/rejectRoomPkInvitation':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'id': 'invite-1'});
            return const _Reply(data: null);
          case '/app-api/activityPk/getRoomFightRecord':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'pageNum': 1,
              'pageSize': 20,
            });
            return _Reply(
              data: <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'record-1',
                  'senderRoomId': '9527',
                  'senderRoomName': '当前房',
                  'receiverRoomName': '星河房',
                  'senderRoomHeadImg': 'https://cdn.example/current.png',
                  'receiverRoomHeadImg': 'https://cdn.example/star.png',
                  'senderScore': '80',
                  'receiverScore': 60,
                  'result': 1,
                  'pkDate': '2026-08-21T12:00:00Z',
                },
              ],
            );
          default:
            fail('unexpected PK route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );

      expect(repository.supportsRealtimeInvitations, isFalse);
      expect(repository.supportsSurrender, isFalse);
      expect(await repository.fetchIncomingInvitation(roomId: '9527'), isNull);

      final List<RoomPkOpponent> hot = await repository.fetchHotOpponents(
        roomId: '9527',
      );
      expect(hot, hasLength(1));
      expect(hot.single.roomId, '10001');
      expect(hot.single.onlineUsers, 33);
      expect(hot.single.coverUrl, 'https://cdn.example/star.png');

      final List<RoomPkOpponent> searched = await repository.searchOpponents(
        roomId: '9527',
        keyword: 'R10001',
      );
      expect(searched.single.roomCode, 'R10001');

      final List<RoomPkOpponent> fallback = await repository.searchOpponents(
        roomId: '9527',
        keyword: '  ',
      );
      expect(fallback.single.roomId, '10001');

      final RoomPkInvitation opponentInvitation = await repository
          .sendInvitation(
            roomId: '9527',
            inviterUserId: 10001,
            opponent: hot.single,
            punishmentTheme: '分享今天最开心的事',
            durationMinutes: 5,
          );
      expect(opponentInvitation.id, 'invite-1');
      expect(opponentInvitation.status, RoomPkInvitationStatus.pending);
      expect(opponentInvitation.direction, RoomPkInvitationDirection.outgoing);

      final RoomPkInvitation acceptedInvitation = await repository
          .refreshInvitation(opponentInvitation);
      expect(acceptedInvitation.status, RoomPkInvitationStatus.accepted);

      final RoomPkBattle? active = await repository.fetchActiveBattle(
        roomId: '9527',
      );
      expect(active, isNotNull);
      expect(active!.id, 'pk-1');
      expect(active.currentSide.roomId, '9527');
      expect(active.opponentSide.roomName, '星河房');
      expect(active.remainingSeconds, 120);
      expect(active.stage, RoomPkBattleStage.fighting);
      expect(active.sender.supporters.single.nickname, '晚星');
      expect(active.sender.supporters.single.value, 12.5);

      final RoomPkBattle accepted = await repository.acceptInvitation(
        opponentInvitation,
      );
      expect(accepted.isActive, isTrue);
      await repository.rejectInvitation(opponentInvitation);

      final RoomPkBattle refreshed = await repository.refreshBattle(
        roomId: '9527',
        battleId: 'pk-1',
      );
      expect(refreshed.id, 'pk-1');

      final List<RoomPkRecord> history = await repository.fetchHistory(
        roomId: '9527',
      );
      expect(history.single.id, 'record-1');
      expect(history.single.opponentRoomName, '星河房');
      expect(history.single.result, RoomPkResult.win);
      expect(history.single.currentScore, 80);
      expect(history.single.opponentScore, 60);
      expect(history.single.completedAt.toUtc(), DateTime.utc(2026, 8, 21, 12));

      expect(
        server.requests.where(
          (_CapturedRequest request) =>
              request.path == '/app-api/activityPk/getRoomPkHotRoomList',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'PK empty states, conflicts, and vendor boundaries stay explicit',
    () async {
      int progressCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/activityPk/getRoomPkHotRoomList':
            return const _Reply(data: <Object?>[]);
          case '/app-api/activityPk/getRoomPkProgress':
            progressCalls += 1;
            return const _Reply(data: <String, Object?>{});
          case '/app-api/activityPk/acceptRoomPkInvitation':
            return const _Reply(data: null);
          case '/app-api/activityPk/getRoomFightRecord':
            return const _Reply(
              data: <String, Object?>{'records': <Object?>[]},
            );
          default:
            fail('unexpected empty PK route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );

      expect(await repository.fetchHotOpponents(roomId: '9527'), isEmpty);
      expect(await repository.fetchActiveBattle(roomId: '9527'), isNull);
      expect(await repository.fetchHistory(roomId: '9527'), isEmpty);

      final RoomPkInvitation expired = RoomPkInvitation(
        id: 'invite-expired',
        direction: RoomPkInvitationDirection.outgoing,
        currentRoomId: '9527',
        opponent: const RoomPkOpponent(
          roomId: '10001',
          roomCode: 'R10001',
          roomName: '星河房',
        ),
        punishmentTheme: '主题',
        durationMinutes: 5,
        status: RoomPkInvitationStatus.pending,
        createdAt: DateTime(2026, 8, 20),
        expiresAt: DateTime(2026, 8, 20, 0, 1),
      );
      expect(
        (await repository.refreshInvitation(expired)).status,
        RoomPkInvitationStatus.expired,
      );
      expect(progressCalls, 1);

      final RoomPkInvitation pending = expired.copyWith(
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await expectLater(
        repository.acceptInvitation(pending),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      await expectLater(
        repository.refreshBattle(roomId: '9527', battleId: 'missing'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await expectLater(
        repository.surrender(roomId: '9527', battleId: 'pk-1'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.configuration,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('认输'),
              ),
        ),
      );
    },
  );

  test(
    'PK search accepts a single opponent nested under a data envelope',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'GET');
        expect(request.path, '/app-api/activityPk/searchRoomPk');
        final String roomCode = request.query['roomCode']!;
        return switch (roomCode) {
          'R10001' => const _Reply(
            data: <String, Object?>{
              'data': <String, Object?>{
                'roomId': '10001',
                'roomCode': 'R10001',
                'roomName': '星河房',
              },
            },
          ),
          'R10002' => const _Reply(
            data: <String, Object?>{
              'roomId': '10002',
              'roomCode': 'R10002',
              'roomName': '南风房',
            },
          ),
          'R10003' => const _Reply(
            data: <Map<String, Object?>>[
              <String, Object?>{
                'roomId': '10003',
                'roomCode': 'R10003',
                'roomName': '青禾房',
              },
            ],
          ),
          _ => const _Reply(data: <String, Object?>{}),
        };
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );

      List<RoomPkOpponent> opponents = await repository.searchOpponents(
        roomId: '9527',
        keyword: 'R10001',
      );
      expect(opponents, hasLength(1));
      expect(opponents.single.roomId, '10001');
      expect(opponents.single.roomName, '星河房');

      opponents = await repository.searchOpponents(
        roomId: '9527',
        keyword: 'R10002',
      );
      expect(opponents.single.roomId, '10002');

      opponents = await repository.searchOpponents(
        roomId: '9527',
        keyword: 'R10003',
      );
      expect(opponents.single.roomId, '10003');

      opponents = await repository.searchOpponents(
        roomId: '9527',
        keyword: 'empty',
      );
      expect(opponents, isEmpty);
    },
  );

  test(
    'PK validation and error envelopes do not become synthetic success',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 40301,
          message: '没有 PK 权限',
          data: null,
          httpStatus: 403,
        ),
      );
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      const RoomPkOpponent opponent = RoomPkOpponent(
        roomId: '10001',
        roomCode: 'R10001',
        roomName: '星河房',
      );

      await expectLater(
        repository.sendInvitation(
          roomId: '9527',
          inviterUserId: 0,
          opponent: opponent,
          punishmentTheme: '主题',
          durationMinutes: 5,
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.sendInvitation(
          roomId: '9527',
          inviterUserId: 10001,
          opponent: opponent,
          punishmentTheme: '',
          durationMinutes: 5,
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.sendInvitation(
          roomId: '9527',
          inviterUserId: 10001,
          opponent: opponent,
          punishmentTheme: '主题',
          durationMinutes: 7,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests, isEmpty);

      await expectLater(
        repository.fetchHotOpponents(roomId: '9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.forbidden,
          ),
        ),
      );
      expect(server.requests, hasLength(1));
    },
  );
}

Map<String, Object?> _battleData() => <String, Object?>{
  'pkId': 'pk-1',
  'remainingTime': '120',
  'punishmentTheme': '分享今天最开心的事',
  'senderRoom': <String, Object?>{
    'id': '9527',
    'code': 'R9527',
    'name': '当前房',
    'popularity': '120',
    'sendUsers': <Map<String, Object?>>[
      <String, Object?>{'userId': '10001', 'nickname': '晚星', 'value': '12.5'},
    ],
  },
  'receiverRoom': <String, Object?>{
    'id': '10001',
    'code': 'R10001',
    'name': '星河房',
    'score': 80,
    'supporters': <Map<String, Object?>>[],
  },
};

class _CapturedRequest {
  const _CapturedRequest({
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

class _Reply {
  const _Reply({
    this.code = 200,
    this.message = 'OK',
    this.data,
    this.httpStatus = 200,
  });

  final int code;
  final String message;
  final Object? data;
  final int httpStatus;
}

typedef _Responder = _Reply Function(_CapturedRequest request);

class _RunningServer {
  _RunningServer._(this.server, this.requests);

  final HttpServer server;
  final List<_CapturedRequest> requests;

  late final ApiClient client = ApiClient(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
    clientType: 'Android',
    clientInnerVersion: '6',
    authorizationProvider: () => 'Bearer contract-test',
  );

  static Future<_RunningServer> start(_Responder responder) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<_CapturedRequest> requests = <_CapturedRequest>[];
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? body = rawBody.trim().isEmpty ? null : jsonDecode(rawBody);
      final _CapturedRequest captured = _CapturedRequest(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: body,
      );
      requests.add(captured);
      final _Reply reply = responder(captured);
      request.response
        ..statusCode = reply.httpStatus
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': reply.code,
            'message': reply.message,
            'data': reply.data,
          }),
        );
      await request.response.close();
    });
    return _RunningServer._(server, requests);
  }

  Future<void> close() => server.close(force: true);
}
