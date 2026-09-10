import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'support/media_http_fakes.dart';

const aRoom = '11111111-1111-4111-8111-111111111111';
const bRoom = '22222222-2222-4222-8222-222222222222';
const invitationId = '33333333-3333-4333-8333-333333333333';
const battleId = '44444444-4444-4444-8444-444444444444';
Map<String, Object?> pkProjection(String room, String? status) {
  if (status == null)
    return {'roomId': room, 'invitationId': null, 'battleId': null};
  final target = room == aRoom ? bRoom : aRoom;
  Map<String, Object?> side(String id) => {
    'roomId': id,
    'roomCode': id,
    'roomName': id,
    'score': 0,
    'supporters': [],
  };
  return {
    'roomId': room,
    'targetRoomId': target,
    'invitationId': invitationId,
    'invitationDirection': room == aRoom ? 'OUTGOING' : 'INCOMING',
    'invitationStatus': status,
    'inviterRoomId': aRoom,
    'inviteeRoomId': bRoom,
    'opponentRoom': {
      'roomId': target,
      'roomCode': target,
      'roomName': target,
      'onlineNum': 1,
      'hasActivePk': false,
    },
    'createdAt': '2026-09-10T12:00:00Z',
    'expiresAt': '2026-09-10T12:01:00Z',
    'punishmentTheme': '分享今天',
    'durationMinutes': 5,
    'battleId': status == 'ACCEPTED' ? battleId : null,
    if (status == 'ACCEPTED') ...{
      'battleStatus': 'IN_PROGRESS',
      'countdownSeconds': 300,
      'startedAt': '2026-09-10T12:00:10Z',
      'endsAt': '2026-09-10T12:05:10Z',
      'leftRoomId': aRoom,
      'rightRoomId': bRoom,
      'leftRoom': side(aRoom),
      'rightRoom': side(bRoom),
      'resultCode': 'UNDECIDED',
    },
  };
}

void main() {
  for (final phase in ['open', 'response', '401']) {
    test('explicit invitation POST rejects stale identity at $phase', () async {
      final identity = TestMediaIdentity();
      final generation = identity.generation;
      var refreshes = 0;
      void change() {
        identity.change(2);
        identity.change(1);
      }

      final http = MediaFakeHttp((_) {
        change();
        return MediaFakeResponse.json(
          pkProjection(aRoom, 'PENDING'),
          status: phase == '401' ? 401 : 200,
          code: phase == '401' ? 401 : 200,
        );
      });
      if (phase == 'open') http.beforeOpen = (_) async => change();
      final repository = BackendRoomPkRepository(
        apiClient: http.api(
          identity,
          refresh: () async {
            refreshes++;
            return true;
          },
        ),
        routes: const BackendRouteCatalog(),
      );
      await expectLater(
        repository.sendInvitation(
          roomId: aRoom,
          inviterUserId: 1,
          opponent: const RoomPkOpponent(
            roomId: bRoom,
            roomCode: bRoom,
            roomName: bRoom,
          ),
          punishmentTheme: '分享今天',
          durationMinutes: 5,
          requireCurrent: () {
            if (identity.generation != generation)
              throw const ApiException(
                kind: ApiFailureKind.conflict,
                message: 'stale actor',
              );
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(refreshes, 0);
      expect(
        http.requests.where((r) => r.closes != 0).length,
        phase == 'open' ? 0 : 1,
      );
    });
  }

  test(
    'real HTTP repositories observe shared invite, explicit accept and both current battles in one GET each',
    () async {
      String? status;
      final a = TestMediaIdentity(), b = TestMediaIdentity()..change(2);
      final http = MediaFakeHttp((request) {
        final actor = request.headers.value('Authorization') == a.token
            ? aRoom
            : bRoom;
        if (request.method == 'POST') {
          final body =
              jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
          if (request.uri.path.endsWith('inviteRoomPk')) {
            expect(actor, aRoom);
            expect(body['targetRoomId'], bRoom);
            status = 'PENDING';
          } else {
            expect(request.uri.path.endsWith('acceptRoomPkInvitation'), isTrue);
            expect(actor, bRoom);
            expect(body, {'invitationId': invitationId});
            status = 'ACCEPTED';
          }
        } else {
          expect(request.uri.path, '/app-api/activityPk/queryRoomPkProcess');
          expect(request.uri.queryParameters, {'roomId': actor});
        }
        return MediaFakeResponse.json(pkProjection(actor, status));
      });
      final left = BackendRoomPkRepository(
        apiClient: http.api(a),
        routes: const BackendRouteCatalog(),
      );
      final right = BackendRoomPkRepository(
        apiClient: http.api(b),
        routes: const BackendRouteCatalog(),
      );
      expect(
        (await right.fetchProcess(
          roomId: bRoom,
          requireCurrent: () {},
        )).invitation,
        isNull,
      );
      await left.sendInvitation(
        roomId: aRoom,
        inviterUserId: 1,
        opponent: const RoomPkOpponent(
          roomId: bRoom,
          roomCode: bRoom,
          roomName: bRoom,
        ),
        punishmentTheme: '分享今天',
        durationMinutes: 5,
        requireCurrent: () {},
      );
      final incoming = await right.fetchProcess(
        roomId: bRoom,
        requireCurrent: () {},
      );
      expect(
        incoming.invitation!.direction,
        RoomPkInvitationDirection.incoming,
      );
      expect(incoming.battle, isNull);
      expect(status, 'PENDING');
      await right.acceptInvitation(incoming.invitation!, requireCurrent: () {});
      for (final (repository, room) in [(left, aRoom), (right, bRoom)]) {
        final before = http.requests.length;
        final process = await repository.fetchProcess(
          roomId: room,
          requireCurrent: () {},
        );
        expect(http.requests.length, before + 1);
        expect(process.invitation!.status, RoomPkInvitationStatus.accepted);
        expect(process.battle!.invitationId, process.invitation!.id);
        expect(process.battle!.id, battleId);
        expect(process.battle!.currentRoomId, room);
      }
      expect(http.requests.where((r) => r.method == 'POST').length, 2);
    },
  );

  for (final phase in [
    'open',
    'response',
    '401',
    'refresh',
    'retry-open',
    'same-token-refresh',
    'room-ABA',
    'read-ABA',
  ]) {
    test('process bound identity and read scope: $phase', () async {
      final identity = TestMediaIdentity();
      final captured = identity.generation;
      var roomGeneration = 0, readGeneration = 0, refreshes = 0;
      void invalidate() {
        if (phase == 'room-ABA') {
          roomGeneration += 2;
        } else if (phase == 'read-ABA') {
          readGeneration += 2;
        } else {
          identity.change(2);
          identity.change(1);
        }
      }

      void requireCurrent() {
        if (identity.generation != captured ||
            roomGeneration != 0 ||
            readGeneration != 0) {
          throw const ApiException(
            kind: ApiFailureKind.conflict,
            message: 'stale scope',
          );
        }
      }

      late MediaFakeHttp http;
      http = MediaFakeHttp((request) {
        final first = http.requests.length == 1;
        if (first &&
            ['response', '401', 'room-ABA', 'read-ABA'].contains(phase))
          invalidate();
        final unauthorized =
            first &&
            [
              '401',
              'refresh',
              'retry-open',
              'same-token-refresh',
            ].contains(phase);
        return MediaFakeResponse.json(
          pkProjection(aRoom, 'PENDING'),
          status: unauthorized ? 401 : 200,
          code: unauthorized ? 401 : 200,
        );
      });
      http.beforeOpen = (number) async {
        if (phase == 'open' || phase == 'retry-open' && number == 2)
          invalidate();
      };
      final api = http.api(
        identity,
        refresh: () async {
          refreshes++;
          if (phase == 'refresh')
            invalidate();
          else
            identity.refreshToken();
          return true;
        },
      );
      final repository = BackendRoomPkRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
      );
      final result = repository.fetchProcess(
        roomId: aRoom,
        requireCurrent: requireCurrent,
      );
      if (phase == 'same-token-refresh') {
        expect((await result).invitation!.id, invitationId);
        expect(http.requests.length, 2);
        expect(
          http.requests[0].headers.value('X-Request-Id'),
          http.requests[1].headers.value('X-Request-Id'),
        );
      } else {
        await expectLater(result, throwsA(isA<ApiException>()));
        expect(
          http.requests.where((r) => r.closes != 0).length,
          phase == 'open' ? 0 : 1,
        );
      }
      if (phase == '401') expect(refreshes, 0);
      expect(
        http.requests.any(
          (r) => r.headers.value('Authorization') == 'Bearer contract-2',
        ),
        isFalse,
      );
    });
  }

  test(
    'process projects terminal invitation states without inventing a battle',
    () async {
      for (final status in ['REJECTED', 'EXPIRED', 'CANCELED']) {
        final http = MediaFakeHttp(
          (_) => MediaFakeResponse.json(pkProjection(aRoom, status)),
        );
        final repository = BackendRoomPkRepository(
          apiClient: http.api(TestMediaIdentity()),
          routes: const BackendRouteCatalog(),
        );
        final process = await repository.fetchProcess(
          roomId: aRoom,
          requireCurrent: () {},
        );
        expect(process.invitation!.status.name.toUpperCase(), status);
        expect(process.battle, isNull);
      }
    },
  );

  test(
    'wrong room, direction, invitation and pending battle projections fail closed',
    () async {
      for (final invalid in [
        {'roomId': bRoom},
        {'invitationDirection': 'INCOMING'},
        {'inviteeRoomId': aRoom},
        {'invitationStatus': 'PENDING'},
        {
          'opponentRoom': {'roomId': aRoom},
        },
      ]) {
        final http = MediaFakeHttp(
          (_) => MediaFakeResponse.json({
            ...pkProjection(aRoom, 'ACCEPTED'),
            ...invalid,
          }),
        );
        final repository = BackendRoomPkRepository(
          apiClient: http.api(TestMediaIdentity()),
          routes: const BackendRouteCatalog(),
        );
        await expectLater(
          repository.fetchProcess(roomId: aRoom, requireCurrent: () {}),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
}
