import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

const String _roomId = '11111111-1111-4111-8111-111111111111';
const String _targetRoomId = '22222222-2222-4222-8222-222222222222';
const String _invitationId = '33333333-3333-4333-8333-333333333333';
const String _battleId = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'F3-A uses exact first-party paths, bodies, headers, and projection fields',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.requestId, isNotEmpty);
        switch (request.path) {
          case '/app-api/activityPk/getRoomPkHotRoomList':
            expect(request.method, 'GET');
            expect(request.query, isEmpty);
            return _Reply(
              data: <String, Object?>{
                'records': <Map<String, Object?>>[
                  <String, Object?>{
                    'roomId': _roomId,
                    'roomCode': 'R111',
                    'roomName': '当前房',
                    'coverImgUrl': null,
                    'onlineNum': 1,
                    'hasActivePk': false,
                    'pkStatus': 'AVAILABLE',
                  },
                  <String, Object?>{
                    'roomId': _targetRoomId,
                    'roomCode': 'R222',
                    'roomName': '目标房',
                    'coverImgUrl': 'https://cdn.example/target.png',
                    'onlineNum': 33,
                    'hasActivePk': false,
                    'pkStatus': 'AVAILABLE',
                  },
                ],
                'list': <Map<String, Object?>>[
                  <String, Object?>{
                    'roomId': _roomId,
                    'roomCode': 'R111',
                    'roomName': '当前房',
                    'coverImgUrl': null,
                    'onlineNum': 1,
                    'hasActivePk': false,
                    'pkStatus': 'AVAILABLE',
                  },
                  <String, Object?>{
                    'roomId': _targetRoomId,
                    'roomCode': 'R222',
                    'roomName': '目标房',
                    'coverImgUrl': 'https://cdn.example/target.png',
                    'onlineNum': 33,
                    'hasActivePk': false,
                    'pkStatus': 'AVAILABLE',
                  },
                ],
                'current': 1,
                'pageSize': 20,
                'total': 2,
              },
            );
          case '/app-api/activityPk/searchRoomPk':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'keyword': 'target',
              'pageNum': '2',
              'pageSize': '10',
            });
            return _Reply(
              data: _page(
                <Map<String, Object?>>[
                  <String, Object?>{
                    'roomId': _targetRoomId,
                    'roomCode': 'R222',
                    'roomName': '目标房',
                    'coverImgUrl': 'https://cdn.example/target.png',
                    'onlineNum': 33,
                    'hasActivePk': false,
                    'pkStatus': 'AVAILABLE',
                  },
                ],
                current: 2,
                pageSize: 10,
                total: 11,
              ),
            );
          case '/app-api/activityPk/inviteRoomPk':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'roomId': _roomId,
              'targetRoomId': _targetRoomId,
            });
            return _Reply(data: _invitationProjection());
          case '/app-api/activityPk/acceptRoomPkInvitation':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'invitationId': _invitationId,
            });
            return _Reply(data: _battleProjection());
          case '/app-api/activityPk/rejectRoomPkInvitation':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'invitationId': _invitationId,
            });
            return _Reply(data: _invitationProjection(status: 'REJECTED'));
          case '/app-api/activityPk/surrenderRoomPk':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{'battleId': _battleId});
            return _Reply(data: _battleProjection(status: 'SURRENDERED'));
          case '/app-api/activityPk/endRoomPk':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{'battleId': _battleId});
            return _Reply(data: _battleProjection(status: 'COMPLETED'));
          case '/app-api/activityPk/queryRoomPkProcess':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': _roomId});
            return _Reply(data: _battleProjection());
          case '/app-api/activityPk/queryRoomPkHistory':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'roomId': _roomId,
              'pageNum': '3',
              'pageSize': '5',
            });
            return _Reply(
              data: _page(
                <Map<String, Object?>>[
                  <String, Object?>{
                    'battleId': _battleId,
                    'invitationId': _invitationId,
                    'status': 'COMPLETED',
                    'battleStatus': 'COMPLETED',
                    'resultCode': 'DRAW',
                    'roomId': _roomId,
                    'targetRoomId': _targetRoomId,
                    'leftRoomId': _roomId,
                    'rightRoomId': _targetRoomId,
                    'winnerRoomId': null,
                    'surrenderedRoomId': null,
                    'startedAt': '2030-08-21T11:59:00Z',
                    'endsAt': '2030-08-21T12:09:00Z',
                    'completedAt': '2030-08-21T12:09:01Z',
                    'endedAt': '2030-08-21T12:09:01Z',
                  },
                ],
                current: 3,
                pageSize: 5,
                total: 16,
              ),
            );
          default:
            fail('unexpected F3-A route: ${request.method} ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      const RoomPkOpponent target = RoomPkOpponent(
        roomId: _targetRoomId,
        roomCode: 'R222',
        roomName: '目标房',
      );
      final RoomPkInvitation invitation = RoomPkInvitation(
        id: _invitationId,
        direction: RoomPkInvitationDirection.incoming,
        currentRoomId: _roomId,
        opponent: target,
        punishmentTheme: '',
        durationMinutes: 0,
        status: RoomPkInvitationStatus.pending,
        createdAt: DateTime.utc(2030, 8, 21, 11, 59),
        expiresAt: DateTime.utc(2030, 8, 21, 12, 14),
      );

      expect(
        (await repository.fetchHotOpponents(roomId: _roomId)).single.roomId,
        _targetRoomId,
      );
      expect(
        (await repository.searchOpponents(
          roomId: _roomId,
          keyword: 'target',
          pageNum: 2,
          pageSize: 10,
        )).single.roomId,
        _targetRoomId,
      );
      final RoomPkInvitation sent = await repository.sendInvitation(
        roomId: _roomId,
        inviterUserId: 10,
        opponent: target,
        punishmentTheme: 'ignored by F3-A backend',
        durationMinutes: 5,
      );
      expect(sent.id, _invitationId);
      expect(sent.status, RoomPkInvitationStatus.pending);
      expect(
        await repository.acceptInvitation(invitation),
        isA<RoomPkBattle>(),
      );
      await repository.rejectInvitation(invitation);
      final RoomPkBattle? active = await repository.fetchActiveBattle(
        roomId: _roomId,
      );
      expect(active, isNotNull);
      expect(active!.id, _battleId);
      expect(active.remainingSeconds, 120);
      expect(active.currentSide.roomId, _roomId);
      expect(active.opponentSide.roomId, _targetRoomId);
      expect(
        (await repository.refreshBattle(
          roomId: _roomId,
          battleId: _battleId,
        )).id,
        _battleId,
      );
      expect(
        await repository.surrender(roomId: _roomId, battleId: _battleId),
        isA<RoomPkBattle>(),
      );
      expect(
        await repository.end(roomId: _roomId, battleId: _battleId),
        isA<RoomPkBattle>(),
      );
      final List<RoomPkRecord> history = await repository.fetchHistory(
        roomId: _roomId,
        pageNum: 3,
        pageSize: 5,
      );
      expect(history.single.id, _battleId);
      expect(history.single.result, RoomPkResult.draw);
      expect(
        history.single.completedAt.toUtc(),
        DateTime.utc(2030, 8, 21, 12, 9, 1),
      );
      expect(
        server.requests.every((_CapturedRequest request) {
          return request.method == 'GET' || request.requestId.isNotEmpty;
        }),
        isTrue,
      );
    },
  );

  test('F3-A retains the same request id across an auth replay', () async {
    int calls = 0;
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      expect(request.method, 'POST');
      expect(request.path, '/app-api/activityPk/inviteRoomPk');
      calls += 1;
      return calls == 1
          ? const _Reply(code: 40100, message: 'expired', httpStatus: 401)
          : _Reply(data: _invitationProjection());
    });
    addTearDown(server.close);
    server.client.setUnauthorizedRecovery(() async => true);
    final BackendRoomPkRepository repository = BackendRoomPkRepository(
      apiClient: server.client,
      routes: const BackendRouteCatalog(),
    );

    await repository.sendInvitation(
      roomId: _roomId,
      inviterUserId: 10,
      opponent: const RoomPkOpponent(
        roomId: _targetRoomId,
        roomCode: 'R222',
        roomName: '目标房',
      ),
      punishmentTheme: '主题',
      durationMinutes: 5,
    );
    expect(server.requests, hasLength(2));
    expect(server.requests[0].requestId, isNotEmpty);
    expect(server.requests[1].requestId, server.requests[0].requestId);
  });

  test(
    'F3-A retains the same request id for idempotency pending conflicts',
    () async {
      for (final int code in <int>[40901, 40902]) {
        int calls = 0;
        final _RunningServer server = await _RunningServer.start((
          _CapturedRequest request,
        ) {
          expect(request.method, 'POST');
          expect(request.path, '/app-api/activityPk/inviteRoomPk');
          calls += 1;
          return calls == 1
              ? _Reply(
                  code: code,
                  message: 'idempotency pending',
                  httpStatus: 409,
                )
              : _Reply(data: _invitationProjection());
        });
        addTearDown(server.close);
        final BackendRoomPkRepository repository = BackendRoomPkRepository(
          apiClient: server.client,
          routes: const BackendRouteCatalog(),
        );
        const RoomPkOpponent target = RoomPkOpponent(
          roomId: _targetRoomId,
          roomCode: 'R222',
          roomName: '目标房',
        );

        await expectLater(
          repository.sendInvitation(
            roomId: _roomId,
            inviterUserId: 10,
            opponent: target,
            punishmentTheme: '主题',
            durationMinutes: 5,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.conflict,
            ),
          ),
        );
        await repository.sendInvitation(
          roomId: _roomId,
          inviterUserId: 10,
          opponent: target,
          punishmentTheme: '主题',
          durationMinutes: 5,
        );
        expect(server.requests, hasLength(2));
        expect(server.requests[0].requestId, isNotEmpty);
        expect(server.requests[1].requestId, server.requests[0].requestId);
        await server.close();
      }
    },
  );

  test(
    'F3-A accepts inviter-oriented mutation projections for an incoming invitation',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/activityPk/acceptRoomPkInvitation':
            return _Reply(
              data: _battleProjection(
                roomId: _roomId,
                targetRoomId: _targetRoomId,
              ),
            );
          case '/app-api/activityPk/rejectRoomPkInvitation':
            return _Reply(
              data: _invitationProjection(
                status: 'REJECTED',
                roomId: _roomId,
                targetRoomId: _targetRoomId,
              ),
            );
          default:
            fail('unexpected incoming projection route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      final RoomPkInvitation incoming = RoomPkInvitation(
        id: _invitationId,
        direction: RoomPkInvitationDirection.incoming,
        currentRoomId: _targetRoomId,
        opponent: const RoomPkOpponent(
          roomId: _roomId,
          roomCode: 'R111',
          roomName: '邀请方房间',
        ),
        punishmentTheme: '主题',
        durationMinutes: 5,
        status: RoomPkInvitationStatus.pending,
        createdAt: DateTime.utc(2030, 8, 21, 11, 59),
      );

      final RoomPkBattle accepted = await repository.acceptInvitation(incoming);
      expect(accepted.currentRoomId, _targetRoomId);
      expect(accepted.targetRoomId, _roomId);
      await repository.rejectInvitation(incoming);
    },
  );

  test(
    'F3-A rotates request id after a definitive idempotency conflict',
    () async {
      int calls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-api/activityPk/inviteRoomPk');
        calls += 1;
        return calls == 1
            ? const _Reply(
                code: 40903,
                message: 'request fingerprint mismatch',
                httpStatus: 409,
              )
            : _Reply(data: _invitationProjection());
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      const RoomPkOpponent target = RoomPkOpponent(
        roomId: _targetRoomId,
        roomCode: 'R222',
        roomName: '目标房',
      );

      await expectLater(
        repository.sendInvitation(
          roomId: _roomId,
          inviterUserId: 10,
          opponent: target,
          punishmentTheme: '主题',
          durationMinutes: 5,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await repository.sendInvitation(
        roomId: _roomId,
        inviterUserId: 10,
        opponent: target,
        punishmentTheme: '主题',
        durationMinutes: 5,
      );
      expect(server.requests, hasLength(2));
      expect(server.requests[0].requestId, isNot(server.requests[1].requestId));
    },
  );

  test(
    'F3-A maps backend 400/401/403/404/409/5xx without synthetic success',
    () async {
      const List<(int, ApiFailureKind)> failures = <(int, ApiFailureKind)>[
        (400, ApiFailureKind.validation),
        (401, ApiFailureKind.unauthorized),
        (403, ApiFailureKind.forbidden),
        (404, ApiFailureKind.validation),
        (409, ApiFailureKind.conflict),
        (500, ApiFailureKind.server),
      ];
      for (final (int status, ApiFailureKind kind) in failures) {
        final _RunningServer server = await _RunningServer.start(
          (_CapturedRequest request) => _Reply(
            code: status == 409 ? 40901 : status,
            message: 'failure',
            httpStatus: status,
          ),
        );
        final BackendRoomPkRepository repository = BackendRoomPkRepository(
          apiClient: server.client,
          routes: const BackendRouteCatalog(),
        );
        try {
          await expectLater(
            repository.fetchHotOpponents(roomId: _roomId),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                kind,
              ),
            ),
          );
        } finally {
          await server.close();
        }
      }
    },
  );

  test(
    'F3-A rejects stale battle projections and invalid pagination metadata',
    () async {
      int processCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        if (request.path == '/app-api/activityPk/queryRoomPkProcess') {
          processCalls += 1;
          return _Reply(
            data: _battleProjection(
              battleId: processCalls == 1 ? _battleId : _invitationId,
            ),
          );
        }
        expect(request.path, '/app-api/activityPk/queryRoomPkHistory');
        return _Reply(
          data: _page(
            <Map<String, Object?>>[],
            current: 99,
            pageSize: 5,
            total: 0,
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );

      expect(
        (await repository.fetchActiveBattle(roomId: _roomId))!.id,
        _battleId,
      );
      await expectLater(
        repository.refreshBattle(roomId: _roomId, battleId: _battleId),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      await expectLater(
        repository.fetchHistory(roomId: _roomId, pageNum: 1, pageSize: 5),
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

Map<String, Object?> _invitationProjection({
  String status = 'PENDING',
  String roomId = _roomId,
  String targetRoomId = _targetRoomId,
  String invitationId = _invitationId,
}) => <String, Object?>{
  'roomId': roomId,
  'invitationId': invitationId,
  'invitationStatus': status,
  'targetRoomId': targetRoomId,
  'createdAt': '2030-08-21T11:59:00Z',
  'expiresAt': '2030-08-21T12:14:00Z',
  'resolvedAt': status == 'PENDING' ? null : '2030-08-21T12:00:00Z',
  'status': status,
  'state': status,
  'providerInvocation': false,
  'vendorInvocation': false,
  'rtcStatus': 'VENDOR_BLOCKED',
  'imStatus': 'VENDOR_BLOCKED',
  'realtimeProvisioned': false,
};

Map<String, Object?> _battleProjection({
  String status = 'IN_PROGRESS',
  String battleId = _battleId,
  String roomId = _roomId,
  String targetRoomId = _targetRoomId,
  String invitationId = _invitationId,
}) => <String, Object?>{
  ..._invitationProjection(
    status: 'ACCEPTED',
    roomId: roomId,
    targetRoomId: targetRoomId,
    invitationId: invitationId,
  ),
  'battleId': battleId,
  'battleStatus': status,
  'resultCode': status == 'SURRENDERED' ? 'LEFT_WIN' : 'UNDECIDED',
  'startedAt': '2030-08-21T11:59:00Z',
  'endsAt': '2030-08-21T12:09:00Z',
  'completedAt': status == 'IN_PROGRESS' ? null : '2030-08-21T12:01:00Z',
  'countdownSeconds': status == 'IN_PROGRESS' ? 120 : 0,
  'timedOut': false,
  'battleEnded': status != 'IN_PROGRESS',
  'ended': status != 'IN_PROGRESS',
  'endedAt': status == 'IN_PROGRESS' ? null : '2030-08-21T12:01:00Z',
  'winnerRoomId': status == 'SURRENDERED' ? _targetRoomId : null,
  'surrenderedRoomId': status == 'SURRENDERED' ? _roomId : null,
};

Map<String, Object?> _page(
  List<Map<String, Object?>> records, {
  required int current,
  required int pageSize,
  required int total,
}) => <String, Object?>{
  'records': records,
  'list': records,
  'current': current,
  'pageSize': pageSize,
  'size': pageSize,
  'total': total,
  'pages': total == 0 ? 0 : (total / pageSize).ceil(),
};

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.requestId,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final String requestId;
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
    authorizationProvider: () => contractTestAuthorization,
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
        requestId: request.headers.value('X-Request-Id') ?? '',
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
