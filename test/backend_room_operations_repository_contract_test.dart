import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'room operations use the documented HTTP shape and parse responses',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/getRoomOnlinePersonnel':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'pageNum': 2,
              'pageSize': 10,
              'isSearchCount': true,
            });
            return _Reply(
              data: _memberPage(
                current: 2,
                pageSize: 10,
                total: 21,
                pages: 3,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'userId': '10001',
                    'nickName': '晚星',
                    'headImgUrl': 'https://cdn.example/late.png',
                    'userRoomRole': 1,
                    'seatNumber': 5,
                    'wealthLevel': '9',
                    'charmLevel': 7,
                  },
                  for (int userId = 10010; userId < 10019; userId++)
                    <String, Object?>{
                      'userId': userId,
                      'nickName': '成员$userId',
                    },
                ],
              ),
            );
          case '/app-api/rooms/getRoomMicDownOnlinePersonnel':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'pageNum': 1,
              'pageSize': 50,
            });
            return _Reply(
              data: _memberPage(
                current: 1,
                pageSize: 50,
                total: 1,
                pages: 1,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'userId': 10002,
                    'nickName': '南风',
                    'headImgUrl': 'https://cdn.example/nan.png',
                    'presence': 'ONLINE',
                  },
                ],
              ),
            );
          case '/app-api/roomUsers/getRoomManagers':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'roomId': '9527',
              'pageNum': '1',
              'pageSize': '50',
            });
            return _Reply(
              data: _memberPage(
                current: 1,
                pageSize: 50,
                total: 1,
                pages: 1,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'id': '10003',
                    'nickName': '青禾',
                    'role': 'MANAGER',
                  },
                ],
              ),
            );
          case '/app-api/roomUsers/getRoomMuteds':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'roomId': '9527',
              'pageNum': '1',
              'pageSize': '50',
            });
            return _Reply(
              data: _memberPage(
                current: 1,
                pageSize: 50,
                total: 1,
                pages: 1,
                items: <Map<String, Object?>>[
                  <String, Object?>{
                    'id': '10004',
                    'niceName': '白露',
                    'headImgUrl': 'https://cdn.example/bai.png',
                    'muted': true,
                  },
                ],
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '今晚话题',
                'topic': '聊聊最近看的电影',
                'version': 1,
              },
            );
          case '/app-api/rooms/setRoomTopics':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'topic': '新内容',
              'expectedVersion': 1,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topic': '新内容',
                'welcomeText': '',
                'version': 2,
              },
            );
          case '/app-api/roomUsers/setMuted':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'targetUserId': 10002,
              'muted': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'userId': 10002,
                'muted': true,
              },
            );
          case '/app-api/roomUsers/setRole':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'targetUserId': 10002,
              'role': 'MEMBER',
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'userId': 10002,
                'role': 'MEMBER',
              },
            );
          case '/app-api/room/com/kickout':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'targetUserId': 10002,
              'ban': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'userId': 10002,
                'kicked': true,
                'banned': true,
              },
            );
          case '/app-api/micUserBase/hugUserDownMic':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'targetUserId': 10002,
              'seatNumber': 3,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'userId': 10002,
                'offMic': true,
              },
            );
          case '/app-api/micBase/lockMike':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'seatNumber': 4,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'locked': true,
                'occupied': false,
                'userId': '',
              },
            );
          case '/app-api/micBase/unlockMike':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'seatNumber': 4,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'locked': false,
                'occupied': false,
                'userId': '',
              },
            );
          case '/app-api/micBase/openMike':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'userId': 10001,
              'seatNumber': 4,
              'muted': false,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'userId': 10001,
                'muted': false,
                'occupied': true,
              },
            );
          case '/app-api/micBase/closedMike':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'userId': 10001,
              'seatNumber': 5,
              'muted': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 5,
                'userId': 10001,
                'muted': true,
                'occupied': true,
              },
            );
          default:
            fail('unexpected room operation route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final RoomMemberPage online = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 2,
        pageSize: 10,
      );
      expect(online.page, 2);
      expect(online.total, 21);
      expect(online.pages, 3);
      expect(online.hasMore, isTrue);
      final RoomMember onlineOwner = online.items.firstWhere(
        (RoomMember member) => member.userId == 10001,
      );
      expect(onlineOwner.name, '晚星');
      expect(onlineOwner.role, RoomRole.moderator);
      expect(onlineOwner.wealthLevel, 9);
      expect(onlineOwner.charmLevel, 7);

      final List<RoomMember> listeners = await repository.fetchOffMicListeners(
        '9527',
      );
      expect(listeners.single.name, '南风');
      expect(listeners.single.presence, RoomMemberPresence.listener);

      final List<RoomMember> managers = await repository.fetchManagers('9527');
      expect(managers.single.userId, 10003);
      expect(managers.single.role, RoomRole.moderator);

      final List<RoomMember> muted = await repository.fetchMutedUsers('9527');
      expect(muted.single.name, '白露');
      expect(muted.single.isMuted, isTrue);

      final RoomTopic topic = await repository.fetchTopic('9527');
      expect(topic.title, '今晚话题');
      expect(topic.content, '聊聊最近看的电影');
      expect(topic.version, 1);
      await repository.updateTopic(
        roomId: '9527',
        topic: const RoomTopic(title: '新标题', content: '新内容', version: 1),
      );
      await repository.setUserMuted(roomId: '9527', userId: 10002, muted: true);
      await repository.setUserRole(
        roomId: '9527',
        userId: 10002,
        manager: false,
      );
      await repository.kickUser(roomId: '9527', userId: 10002);
      await repository.takeUserOffMic(
        roomId: '9527',
        backendMicIndex: 3,
        userId: 10002,
      );
      await repository.setSeatLocked(
        roomId: '9527',
        backendMicIndex: 4,
        locked: true,
      );
      await repository.setSeatLocked(
        roomId: '9527',
        backendMicIndex: 4,
        locked: false,
      );
      await repository.setSeatMuted(
        roomId: '9527',
        backendMicIndex: 5,
        muted: true,
      );

      expect(server.requests, hasLength(13));
      // Live capability is unknown until the server returns its authoritative
      // room/queue projection; the client must not guess DIRECT.
      expect(repository.micCoordinationMode, MicCoordinationMode.unavailable);
    },
  );

  test(
    'approval mic queue uses canonical routes and header-only idempotency',
    () async {
      String status = 'PENDING';
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-mini-api/mini/v1/rooms/mic-requests':
            if (request.method == 'GET') {
              final Map<String, Object?> record = _micRequestRecord(
                id: 'request-1',
                type: 'REQUEST',
                status: status,
                requestedByUserId: 10001,
                subjectUserId: 10001,
                seatNumber: 3,
              );
              return _Reply(
                data: <String, Object?>{
                  'list': <Object?>[record],
                  'records': <Object?>[record],
                  'total': 1,
                  'roomId': '9527',
                  'coordinationMode': 'APPROVAL',
                  'providerInvocation': false,
                },
              );
            }
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'seatNumber': 3,
            });
            expect(
              request.body is Map &&
                  (request.body! as Map).containsKey('requestId'),
              isFalse,
            );
            status = 'PENDING';
            return _Reply(
              data: _micRequestRecord(
                id: 'request-1',
                type: 'REQUEST',
                status: 'PENDING',
                requestedByUserId: 10001,
                subjectUserId: 10001,
                seatNumber: 3,
              ),
            );
          case '/app-mini-api/mini/v1/rooms/mic-requests/cancel':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'requestId': 'request-1'});
            status = 'CANCELLED';
            return _Reply(
              data: _micRequestRecord(
                id: 'request-1',
                type: 'REQUEST',
                status: 'CANCELLED',
                requestedByUserId: 10001,
                subjectUserId: 10001,
                seatNumber: 3,
                resolvedByUserId: 10001,
              ),
            );
          case '/app-mini-api/mini/v1/rooms/mic-requests/resolve':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'requestId': 'request-1',
              'accepted': true,
            });
            status = 'APPROVED';
            return _Reply(
              data: <String, Object?>{
                ..._micRequestRecord(
                  id: 'request-1',
                  type: 'REQUEST',
                  status: 'APPROVED',
                  requestedByUserId: 10001,
                  subjectUserId: 10001,
                  seatNumber: 3,
                  resolvedByUserId: 20001,
                ),
                'seatAssigned': true,
              },
            );
          case '/app-mini-api/mini/v1/rooms/mic-requests/invite':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'userId': 10002,
              'seatNumber': 4,
            });
            return _Reply(
              data: _micRequestRecord(
                id: 'invite-1',
                type: 'INVITE',
                status: 'PENDING',
                requestedByUserId: 20001,
                subjectUserId: 10002,
                seatNumber: 4,
              ),
            );
          default:
            fail('unexpected queue route ${request.method} ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      expect(repository.micCoordinationMode, MicCoordinationMode.unavailable);
      expect(
        (await repository.fetchMicRequests('9527')).single.isRequest,
        isTrue,
      );
      expect(repository.micCoordinationMode, MicCoordinationMode.approval);
      await repository.submitMicRequest(
        roomId: '9527',
        userId: 10001,
        seatNumber: 3,
      );
      await repository.cancelMicRequest(requestId: 'request-1');
      await repository.resolveMicRequest(
        requestId: 'request-1',
        accepted: true,
      );
      await repository.inviteUserToMic(
        roomId: '9527',
        userId: 10002,
        seatNumber: 4,
      );
      expect(
        server.requests
            .where((_CapturedRequest request) => request.method == 'POST')
            .every((_CapturedRequest request) => request.requestId.isNotEmpty),
        isTrue,
      );
    },
  );

  test('approval queue rejects provider invocation', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      final Map<String, Object?> record = _micRequestRecord(
        id: 'request-1',
        type: 'REQUEST',
        status: 'PENDING',
        requestedByUserId: 10001,
        subjectUserId: 10001,
        seatNumber: 3,
      );
      return _Reply(
        data: <String, Object?>{
          'list': <Object?>[record],
          'records': <Object?>[record],
          'total': 1,
          'roomId': '9527',
          'coordinationMode': 'APPROVAL',
          'providerInvocation': true,
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomOperationsRepository repository =
        BackendRoomOperationsRepository(apiClient: server.client);
    await expectLater(
      repository.fetchMicRequests('9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('approval queue rejects list and records DTO mismatch', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      final Map<String, Object?> first = _micRequestRecord(
        id: 'request-1',
        type: 'REQUEST',
        status: 'PENDING',
        requestedByUserId: 10001,
        subjectUserId: 10001,
        seatNumber: 3,
      );
      final Map<String, Object?> second = _micRequestRecord(
        id: 'request-2',
        type: 'REQUEST',
        status: 'PENDING',
        requestedByUserId: 10001,
        subjectUserId: 10001,
        seatNumber: 4,
      );
      return _Reply(
        data: <String, Object?>{
          'list': <Object?>[first],
          'records': <Object?>[second],
          'total': 1,
          'roomId': '9527',
          'coordinationMode': 'APPROVAL',
          'providerInvocation': false,
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomOperationsRepository repository =
        BackendRoomOperationsRepository(apiClient: server.client);
    await expectLater(
      repository.fetchMicRequests('9527'),
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
    'approval queue accepts naturally expired records without a resolver',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final Map<String, Object?> record = _micRequestRecord(
          id: 'expired-1',
          type: 'REQUEST',
          status: 'EXPIRED',
          requestedByUserId: 10001,
          subjectUserId: 10001,
          seatNumber: 3,
        );
        record['resolvedAt'] = '';
        record['resolvedByUserId'] = 0;
        return _Reply(
          data: <String, Object?>{
            'list': <Object?>[record],
            'records': <Object?>[record],
            'total': 1,
            'roomId': '9527',
            'coordinationMode': 'APPROVAL',
            'providerInvocation': false,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final List<MicAccessRequest> requests = await repository.fetchMicRequests(
        '9527',
      );
      expect(requests.single.status, MicRequestStatus.expired);
      expect(requests.single.resolvedAt, isNull);
      expect(requests.single.resolvedByUserId, isNull);
    },
  );

  test('delayed room A reads cannot overwrite room B seat identity', () async {
    final Completer<void> roomAStarted = Completer<void>();
    final Completer<void> releaseRoomA = Completer<void>();
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) async {
      if (request.path == '/app-api/rooms/getRoomOnlinePersonnel') {
        final Map<String, Object?> body = request.body! as Map<String, Object?>;
        final String roomId = body['roomId']! as String;
        final int userId = roomId == 'room-a' ? 10001 : 20002;
        if (roomId == 'room-a') {
          roomAStarted.complete();
          await releaseRoomA.future;
        }
        final Map<String, Object?> member = _memberRecord(userId)
          ..['seatNumber'] = 4;
        return _Reply(
          data: _memberPage(
            current: 1,
            pageSize: 20,
            total: 1,
            pages: 1,
            items: <Map<String, Object?>>[member],
          ),
        );
      }
      if (request.path == '/app-api/micBase/closedMike') {
        final Map<String, Object?> body = request.body! as Map<String, Object?>;
        return _Reply(
          data: <String, Object?>{
            'roomId': body['roomId'],
            'seatNumber': body['seatNumber'],
            'userId': body['userId'],
            'muted': body['muted'],
            'occupied': true,
          },
        );
      }
      fail('unexpected delayed room operation route: ${request.path}');
    });
    addTearDown(server.close);
    final BackendRoomOperationsRepository repository =
        BackendRoomOperationsRepository(apiClient: server.client);

    final Future<RoomMemberPage> roomARead = repository.fetchOnlineMembers(
      roomId: 'room-a',
      page: 1,
    );
    await roomAStarted.future;

    try {
      final RoomMemberPage roomBPage = await repository.fetchOnlineMembers(
        roomId: 'room-b',
        page: 1,
      );
      expect(roomBPage.items.single.userId, 20002);

      releaseRoomA.complete();
      final RoomMemberPage roomAPage = await roomARead;
      expect(roomAPage.items.single.userId, 10001);

      await repository.setSeatMuted(
        roomId: 'room-a',
        backendMicIndex: 4,
        muted: true,
      );
      await repository.setSeatMuted(
        roomId: 'room-b',
        backendMicIndex: 4,
        muted: true,
      );

      final List<_CapturedRequest> writes = server.requests
          .where(
            (_CapturedRequest request) =>
                request.path == '/app-api/micBase/closedMike',
          )
          .toList(growable: false);
      expect(writes, hasLength(2));
      expect(writes[0].body, <String, Object?>{
        'roomId': 'room-a',
        'userId': 10001,
        'seatNumber': 4,
        'muted': true,
      });
      expect(writes[1].body, <String, Object?>{
        'roomId': 'room-b',
        'userId': 20002,
        'seatNumber': 4,
        'muted': true,
      });
    } finally {
      if (!releaseRoomA.isCompleted) {
        releaseRoomA.complete();
      }
      await roomARead;
    }
  });

  test(
    'operation error envelopes preserve server failure classification',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 42201,
          message: '话题内容不合法',
          data: null,
          httpStatus: 422,
        ),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      await expectLater(
        repository.fetchTopic('9527'),
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
                '话题内容不合法',
              ),
        ),
      );
    },
  );

  test('HTTP 400/403/409/422/500 errors remain typed and unmodified', () async {
    final List<({int status, int code, ApiFailureKind kind})> cases =
        <({int status, int code, ApiFailureKind kind})>[
          (status: 400, code: 40042, kind: ApiFailureKind.validation),
          (status: 403, code: 40335, kind: ApiFailureKind.forbidden),
          (status: 409, code: 40943, kind: ApiFailureKind.conflict),
          (status: 422, code: 42201, kind: ApiFailureKind.validation),
          (status: 500, code: 50001, kind: ApiFailureKind.server),
        ];
    for (final ({int status, int code, ApiFailureKind kind}) item in cases) {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          code: item.code,
          message: 'error-${item.status}',
          data: null,
          httpStatus: item.status,
        ),
      );
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);
      await expectLater(
        repository.fetchTopic('9527'),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.kind, 'kind', item.kind)
              .having(
                (ApiException error) => error.httpStatus,
                'httpStatus',
                item.status,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                'error-${item.status}',
              ),
        ),
      );
      await server.close();
    }
  });

  test(
    'room write matrix preserves 403/409/422/500 envelopes and request ids',
    () async {
      final List<
        ({
          String name,
          String path,
          Future<void> Function(BackendRoomOperationsRepository repository)
          invoke,
        })
      >
      writes =
          <
            ({
              String name,
              String path,
              Future<void> Function(BackendRoomOperationsRepository repository)
              invoke,
            })
          >[
            (
              name: 'setTopics',
              path: '/app-api/rooms/setRoomTopics',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.updateTopic(
                  roomId: '9527',
                  topic: const RoomTopic(
                    title: '标题',
                    content: '内容',
                    version: 1,
                  ),
                );
              },
            ),
            (
              name: 'setMuted',
              path: '/app-api/roomUsers/setMuted',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.setUserMuted(
                  roomId: '9527',
                  userId: 10002,
                  muted: true,
                );
              },
            ),
            (
              name: 'setRole',
              path: '/app-api/roomUsers/setRole',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.setUserRole(
                  roomId: '9527',
                  userId: 10002,
                  manager: true,
                );
              },
            ),
            (
              name: 'kickout',
              path: '/app-api/room/com/kickout',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.kickUser(roomId: '9527', userId: 10002);
              },
            ),
            (
              name: 'hugDownMic',
              path: '/app-api/micUserBase/hugUserDownMic',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.takeUserOffMic(
                  roomId: '9527',
                  backendMicIndex: 3,
                  userId: 10002,
                );
              },
            ),
            (
              name: 'lockMic',
              path: '/app-api/micBase/lockMike',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.setSeatLocked(
                  roomId: '9527',
                  backendMicIndex: 4,
                  locked: true,
                );
              },
            ),
            (
              name: 'unlockMic',
              path: '/app-api/micBase/unlockMike',
              invoke: (BackendRoomOperationsRepository repository) async {
                await repository.setSeatLocked(
                  roomId: '9527',
                  backendMicIndex: 4,
                  locked: false,
                );
              },
            ),
            (
              name: 'closeMic',
              path: '/app-api/micBase/closedMike',
              invoke: (BackendRoomOperationsRepository repository) async {
                await _primeSeatOccupant(repository);
                await repository.setSeatMuted(
                  roomId: '9527',
                  backendMicIndex: 4,
                  muted: true,
                );
              },
            ),
            (
              name: 'openMic',
              path: '/app-api/micBase/openMike',
              invoke: (BackendRoomOperationsRepository repository) async {
                await _primeSeatOccupant(repository);
                await repository.setSeatMuted(
                  roomId: '9527',
                  backendMicIndex: 4,
                  muted: false,
                );
              },
            ),
          ];
      final List<({int status, int code, ApiFailureKind kind})> failures =
          <({int status, int code, ApiFailureKind kind})>[
            (status: 403, code: 40335, kind: ApiFailureKind.forbidden),
            (status: 409, code: 40943, kind: ApiFailureKind.conflict),
            (status: 422, code: 42201, kind: ApiFailureKind.validation),
            (status: 500, code: 50001, kind: ApiFailureKind.server),
          ];

      for (final write in writes) {
        for (final failure in failures) {
          final _RunningServer server = await _RunningServer.start((
            _CapturedRequest request,
          ) {
            if (request.path == '/app-api/rooms/getRoomTopics') {
              return const _Reply(
                data: <String, Object?>{
                  'roomId': '9527',
                  'topicTitle': '标题',
                  'topic': '内容',
                  'version': 1,
                },
              );
            }
            if (request.path == '/app-api/rooms/getRoomOnlinePersonnel') {
              return _Reply(
                data: _memberPage(
                  current: 1,
                  pageSize: 20,
                  total: 1,
                  pages: 1,
                  items: <Map<String, Object?>>[
                    <String, Object?>{
                      'userId': 10001,
                      'nickName': '麦上成员',
                      'seatNumber': 4,
                    },
                  ],
                ),
              );
            }
            expect(request.path, write.path, reason: write.name);
            expect(request.requestId, isNotEmpty, reason: write.name);
            expect(
              request.requestId,
              matches(RegExp(r'^room-operations-[0-9a-f]{32}$')),
              reason: write.name,
            );
            return _Reply(
              code: failure.code,
              message: '${write.name}-${failure.status}',
              data: null,
              httpStatus: failure.status,
            );
          });
          final BackendRoomOperationsRepository repository =
              BackendRoomOperationsRepository(apiClient: server.client);

          await expectLater(
            write.invoke(repository),
            throwsA(
              isA<ApiException>()
                  .having(
                    (ApiException error) => error.kind,
                    'kind',
                    failure.kind,
                  )
                  .having(
                    (ApiException error) => error.code,
                    'code',
                    failure.code,
                  )
                  .having(
                    (ApiException error) => error.httpStatus,
                    'httpStatus',
                    failure.status,
                  )
                  .having(
                    (ApiException error) => error.message,
                    'message',
                    '${write.name}-${failure.status}',
                  ),
            ),
            reason: '${write.name} HTTP ${failure.status}',
          );
          final _CapturedRequest mutation = server.requests.last;
          expect(mutation.path, write.path);
          expect(mutation.requestId, isNotEmpty);
          await server.close();
        }
      }
    },
  );

  test(
    'room member pages require authoritative first-party metadata',
    () async {
      final List<String> missingFields = <String>[
        'current',
        'pageSize',
        'size',
        'total',
        'pages',
      ];
      for (final String missingField in missingFields) {
        final _RunningServer server = await _RunningServer.start((
          _CapturedRequest request,
        ) {
          final Map<String, Object?> payload = _memberPage(
            current: 1,
            pageSize: 20,
            total: 1,
            pages: 1,
            items: <Map<String, Object?>>[_memberRecord(10001)],
          );
          payload.remove(missingField);
          return _Reply(data: payload);
        });
        final BackendRoomOperationsRepository repository =
            BackendRoomOperationsRepository(apiClient: server.client);

        await expectLater(
          repository.fetchOnlineMembers(roomId: '9527', page: 1),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        expect(server.requests, hasLength(1));
        await server.close();
      }

      for (final String missingAlias in <String>['list', 'records']) {
        final _RunningServer missingListServer = await _RunningServer.start((
          _CapturedRequest request,
        ) {
          final Map<String, Object?> payload = _memberPage(
            current: 1,
            pageSize: 20,
            total: 1,
            pages: 1,
            items: <Map<String, Object?>>[_memberRecord(10001)],
          )..remove(missingAlias);
          return _Reply(data: payload);
        });
        final BackendRoomOperationsRepository missingListRepository =
            BackendRoomOperationsRepository(
              apiClient: missingListServer.client,
            );
        await expectLater(
          missingListRepository.fetchOnlineMembers(roomId: '9527', page: 1),
          throwsA(isA<ApiException>()),
        );
        await missingListServer.close();
      }
    },
  );

  test(
    'room member pages reject non-map and malformed member records',
    () async {
      final List<Object?> malformedItems = <Object?>[
        'not-a-member',
        <String, Object?>{'userId': 0, 'nickName': '缺少有效 ID'},
      ];
      for (final Object? malformedItem in malformedItems) {
        final _RunningServer server = await _RunningServer.start((
          _CapturedRequest request,
        ) {
          final Map<String, Object?> payload = _memberPage(
            current: 1,
            pageSize: 20,
            total: 1,
            pages: 1,
            items: <Object?>[malformedItem],
          );
          return _Reply(data: payload);
        });
        final BackendRoomOperationsRepository repository =
            BackendRoomOperationsRepository(apiClient: server.client);

        await expectLater(
          repository.fetchOnlineMembers(roomId: '9527', page: 1),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await server.close();
      }
    },
  );

  test(
    'room member pages reject request drift, inconsistent totals, and count gaps',
    () async {
      final List<Map<String, Object?>> malformedPages = <Map<String, Object?>>[
        _memberPage(
          current: 2,
          pageSize: 20,
          total: 1,
          pages: 1,
          items: <Map<String, Object?>>[_memberRecord(10001)],
        ),
        _memberPage(
          current: 1,
          pageSize: 10,
          total: 1,
          pages: 1,
          items: <Map<String, Object?>>[_memberRecord(10001)],
        ),
        _memberPage(
          current: 1,
          pageSize: 20,
          total: 3,
          pages: 1,
          items: <Map<String, Object?>>[_memberRecord(10001)],
        ),
        _memberPage(
          current: 1,
          pageSize: 20,
          total: 3,
          pages: 2,
          items: <Map<String, Object?>>[_memberRecord(10001)],
        ),
      ];
      for (final Map<String, Object?> malformedPage in malformedPages) {
        final _RunningServer server = await _RunningServer.start(
          (_CapturedRequest request) => _Reply(data: malformedPage),
        );
        final BackendRoomOperationsRepository repository =
            BackendRoomOperationsRepository(apiClient: server.client);
        await expectLater(
          repository.fetchOnlineMembers(roomId: '9527', page: 1, pageSize: 20),
          throwsA(isA<ApiException>()),
        );
        await server.close();
      }
    },
  );

  test(
    'single room member pages allow large totals and an empty page beyond the latest total',
    () async {
      int call = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        call += 1;
        if (call == 1) {
          return _Reply(
            data: _memberPage(
              current: 1,
              pageSize: 20,
              total: 2020,
              pages: 101,
              items: <Map<String, Object?>>[
                for (int userId = 10001; userId <= 10020; userId += 1)
                  _memberRecord(userId),
              ],
            ),
          );
        }
        return _Reply(
          data: _memberPage(
            current: 2,
            pageSize: 20,
            total: 1,
            pages: 1,
            items: const <Map<String, Object?>>[],
          ),
        );
      });
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final RoomMemberPage first = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 1,
      );
      expect(first.items, hasLength(20));
      expect(first.hasMore, isTrue);
      final RoomMemberPage stale = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 2,
      );
      expect(stale.items, isEmpty);
      expect(stale.hasMore, isFalse);
      await server.close();
    },
  );

  test(
    'room member list operations consume bounded authoritative multi-page envelopes',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-api/rooms/getRoomMicDownOnlinePersonnel');
        expect(request.method, 'POST');
        final int page =
            (request.body! as Map<String, Object?>)['pageNum']! as int;
        expect(request.body, <String, Object?>{
          'roomId': '9527',
          'pageNum': page,
          'pageSize': 50,
        });
        if (page == 1) {
          return _Reply(
            data: _memberPage(
              current: 1,
              pageSize: 50,
              total: 51,
              pages: 2,
              items: <Map<String, Object?>>[
                for (int userId = 20001; userId <= 20050; userId++)
                  _memberRecord(userId),
              ],
            ),
          );
        }
        expect(page, 2);
        return _Reply(
          data: _memberPage(
            current: 2,
            pageSize: 50,
            total: 51,
            pages: 2,
            items: <Map<String, Object?>>[_memberRecord(20051)],
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final List<RoomMember> listeners = await repository.fetchOffMicListeners(
        '9527',
      );
      expect(listeners, hasLength(51));
      expect(listeners.last.userId, 20051);
      expect(server.requests, hasLength(2));
    },
  );

  test(
    'room member list operations reject page metadata drift and unsafe bounds',
    () async {
      final _RunningServer driftServer = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int page =
            ((request.body! as Map<String, Object?>)['pageNum']! as int);
        return _Reply(
          data: _memberPage(
            current: page,
            pageSize: 50,
            total: page == 1 ? 51 : 52,
            pages: 2,
            items: <Map<String, Object?>>[
              if (page == 1)
                for (int userId = 20001; userId <= 20050; userId++)
                  _memberRecord(userId)
              else
                _memberRecord(20051),
            ],
          ),
        );
      });
      final BackendRoomOperationsRepository driftRepository =
          BackendRoomOperationsRepository(apiClient: driftServer.client);
      await expectLater(
        driftRepository.fetchOffMicListeners('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(driftServer.requests, hasLength(2));
      await driftServer.close();

      final _RunningServer unsafeServer = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _memberPage(
            current: 1,
            pageSize: 50,
            total: 5050,
            pages: 101,
            items: <Map<String, Object?>>[
              for (int userId = 20001; userId <= 20050; userId++)
                _memberRecord(userId),
            ],
          ),
        ),
      );
      final BackendRoomOperationsRepository unsafeRepository =
          BackendRoomOperationsRepository(apiClient: unsafeServer.client);
      await expectLater(
        unsafeRepository.fetchOffMicListeners('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(unsafeServer.requests, hasLength(1));
      await unsafeServer.close();
    },
  );

  test(
    'empty member payloads resolve to empty pages without fake members',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'list': <Object?>[],
            'records': <Object?>[],
            'current': 1,
            'pageSize': 20,
            'size': 20,
            'total': 0,
            'pages': 0,
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final RoomMemberPage page = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 1,
      );
      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'topic version conflict is surfaced without an automatic overwrite',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-api/rooms/setRoomTopics');
        expect(request.method, 'POST');
        expect(request.body, <String, Object?>{
          'roomId': '9527',
          'topic': '新内容',
          'expectedVersion': 4,
        });
        return const _Reply(
          code: 40945,
          message: 'ROOM_VERSION_CONFLICT',
          data: <String, Object?>{'currentVersion': 5},
          httpStatus: 409,
        );
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      await expectLater(
        repository.updateTopic(
          roomId: '9527',
          topic: const RoomTopic(title: '标题', content: '新内容', version: 4),
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.code, 'code', 40945)
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              ),
        ),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'topic writes reject a missing or negative snapshot version locally',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) =>
            fail('unexpected topic write: ${request.path}'),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      for (final int? version in <int?>[null, -1]) {
        await expectLater(
          repository.updateTopic(
            roomId: '9527',
            topic: RoomTopic(title: '标题', content: '内容', version: version),
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.validation,
            ),
          ),
        );
      }
      expect(server.requests, isEmpty);
    },
  );
}

Map<String, Object?> _memberPage({
  required int current,
  required int pageSize,
  required int total,
  required int pages,
  required List<Object?> items,
}) {
  return <String, Object?>{
    'list': items,
    'records': <Object?>[...items],
    'current': current,
    'pageSize': pageSize,
    'size': pageSize,
    'total': total,
    'pages': pages,
  };
}

Map<String, Object?> _memberRecord(int userId) => <String, Object?>{
  'userId': userId,
  'nickName': '成员$userId',
};

Map<String, Object?> _micRequestRecord({
  required String id,
  required String type,
  required String status,
  required int requestedByUserId,
  required int subjectUserId,
  required int seatNumber,
  int? resolvedByUserId,
}) {
  final bool onMic = status == 'APPROVED';
  final String now = DateTime.utc(2026, 1, 1).toIso8601String();
  final String? resolvedAt = status == 'PENDING' ? '' : now;
  final int resolver = status == 'PENDING' ? 0 : (resolvedByUserId ?? 20001);
  final Map<String, Object?> member = <String, Object?>{
    'userId': subjectUserId,
    'nickName': '成员$subjectUserId',
    'name': '成员$subjectUserId',
    'headImgUrl': '',
    'role': 'MEMBER',
    'presence': onMic ? 'ON_MIC' : 'LISTENER',
    'seatNumber': onMic ? seatNumber : 0,
    'muted': false,
  };
  return <String, Object?>{
    'id': id,
    'requestId': id,
    'roomId': '9527',
    'requestedByUserId': requestedByUserId,
    'requesterUserId': requestedByUserId,
    'subjectUserId': subjectUserId,
    'targetUserId': subjectUserId,
    'userId': subjectUserId,
    'inviterUserId': type == 'INVITE' ? requestedByUserId : 0,
    'requestType': type,
    'type': type,
    'seatNumber': seatNumber,
    'status': status,
    'createdAt': now,
    'expiresAt': DateTime.utc(2026, 1, 1, 1).toIso8601String(),
    'resolvedAt': resolvedAt,
    'resolvedByUserId': resolver,
    'member': member,
    'providerInvocation': false,
  };
}

Future<void> _primeSeatOccupant(
  BackendRoomOperationsRepository repository,
) async {
  await repository.fetchOnlineMembers(roomId: '9527', page: 1);
}

class _CapturedRequest {
  const _CapturedRequest({
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

typedef _Responder = FutureOr<_Reply> Function(_CapturedRequest request);

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
        authorization: captureContractAuthorization(request),
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: body,
      );
      requests.add(captured);
      final _Reply reply = await responder(captured);
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
