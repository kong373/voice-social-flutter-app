import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  test(
    'room snapshot contract preserves request shape and authoritative data',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'POST');
        expect(request.path, '/app-room-api/room/com/v1/enterRoom');
        expect(request.query, isEmpty);
        expect(request.body, <String, Object?>{'roomId': '9527', 'source': 10});
        return _Reply(
          data: <String, Object?>{
            'roomIdStr': '9527',
            'roomCode': 'R9527',
            'roomName': '夜航电台',
            'topicContent': '今晚聊电影',
            'ownerId': '10001',
            'onlineNum': '18',
            'coverImgUrl': 'https://cdn.example/room.png',
            'seats': <Map<String, Object?>>[
              <String, Object?>{
                'index': 1,
                'occupied': true,
                'userId': 10001,
                'userName': '晚星',
                'avatarUrl': 'https://cdn.example/u.png',
              },
              <String, Object?>{'index': 2, 'occupied': false},
            ],
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final RoomSnapshot snapshot = await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.discoveryPost,
        currentUserId: 10001,
      );

      expect(snapshot.roomId, '9527');
      expect(snapshot.roomCode, 'R9527');
      expect(snapshot.title, '夜航电台');
      expect(snapshot.topic, '今晚聊电影');
      expect(snapshot.ownerId, 10001);
      expect(snapshot.role, RoomRole.owner);
      expect(snapshot.onlineCount, 18);
      expect(snapshot.coverUrl, 'https://cdn.example/room.png');
      expect(snapshot.transportMode, RoomTransportMode.snapshotOnly);
      expect(snapshot.rtc.solution, RtcSolution.unknown);
      expect(snapshot.rtc.token, isEmpty);
      expect(snapshot.isSnapshotOnly, isTrue);
      expect(snapshot.seats, hasLength(8));
      expect(snapshot.seats[0].state, MicSeatState.occupied);
      expect(snapshot.seats[0].userId, 10001);
      expect(snapshot.seats[0].avatarUrl, 'https://cdn.example/u.png');
      expect(snapshot.seats[0].userRole, RoomRole.owner);
      expect(snapshot.seats[1].state, MicSeatState.available);
      expect(snapshot.seats[7].backendIndex, 8);
    },
  );

  test('legacy numeric seat statuses map to the frozen five states', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'roomId': '9527',
          'roomName': '数字麦位房',
          'seats': <Map<String, Object?>>[
            <String, Object?>{'index': 1, 'status': 0},
            <String, Object?>{'index': 2, 'status': 1},
            <String, Object?>{'index': 3, 'status': 2},
            <String, Object?>{'index': 4, 'status': 3},
            <String, Object?>{'index': 5, 'status': 4},
          ],
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final RoomSnapshot snapshot = await repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );

    expect(
      snapshot.seats.take(5).map((MicSeat seat) => seat.state),
      <MicSeatState>[
        MicSeatState.available,
        MicSeatState.locked,
        MicSeatState.mutedAvailable,
        MicSeatState.occupied,
        MicSeatState.occupiedMuted,
      ],
    );
  });

  test('numeric seat status aliases must agree or fail closed', () async {
    final List<Map<String, Object?>> conflicts = <Map<String, Object?>>[
      <String, Object?>{'index': 1, 'status': 0, 'occupied': true},
      <String, Object?>{'index': 1, 'status': 1, 'locked': false},
      <String, Object?>{'index': 1, 'status': 2, 'muted': false},
      <String, Object?>{'index': 1, 'status': 3, 'occupied': false},
      <String, Object?>{'index': 1, 'status': 4, 'muted': false},
      <String, Object?>{'index': 1, 'status': 0, 'userId': 10002},
      <String, Object?>{'index': 1, 'status': 5},
    ];

    for (final Map<String, Object?> seat in conflicts) {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: <String, Object?>{
            'roomId': '9527',
            'roomName': '数字别名冲突房',
            'seats': <Map<String, Object?>>[seat],
          },
        ),
      );
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );
      try {
        await expectLater(
          repository.enterRoom(
            roomId: '9527',
            password: null,
            source: RoomEntrySource.home,
            currentUserId: 10001,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await server.close();
      }
    }
  });

  test(
    'room snapshots never pass local or non-http avatar values to live UI',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'roomId': '9527',
            'roomName': '安全头像房',
            'ownerId': 10001,
            'seats': <Map<String, Object?>>[
              <String, Object?>{
                'index': 1,
                'occupied': true,
                'userId': 10001,
                'headImageUrl': 'assets/runtime/avatar-rose.png',
              },
              <String, Object?>{
                'index': 2,
                'occupied': true,
                'userId': 10002,
                'avatarUrl': 'data:image/png;base64,unsafe',
              },
            ],
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final RoomSnapshot snapshot = await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );

      expect(snapshot.seats[0].avatarUrl, isNull);
      expect(snapshot.seats[1].avatarUrl, isNull);
    },
  );

  test('missing room capability flags fail closed', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'roomId': '9527',
          'roomName': '夜航电台',
          'ownerId': 10001,
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final RoomSnapshot snapshot = await repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );

    expect(snapshot.publicScreenEnabled, isFalse);
    expect(snapshot.giftCatalogAvailable, isFalse);
  });

  test('room capabilities authorize only strict boolean values', () async {
    int callCount = 0;
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      callCount += 1;
      return _Reply(
        data: <String, Object?>{
          'roomId': '9527',
          'roomName': '严格能力房',
          'ownerId': 10001,
          'publicScreenEnabled': callCount == 1 ? 1 : true,
          'giftCatalogAvailable': callCount == 1 ? 'yes' : false,
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final RoomSnapshot malformed = await repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );
    expect(malformed.publicScreenEnabled, isFalse);
    expect(malformed.giftCatalogAvailable, isFalse);

    final RoomSnapshot strict = await repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );
    expect(strict.publicScreenEnabled, isTrue);
    expect(strict.giftCatalogAvailable, isFalse);
  });

  test('snapshot identity aliases must agree when repeated', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'roomId': '9527',
          'roomName': '别名冲突房',
          'ownerId': 10001,
          'ownerUserId': 10001,
          'userId': 10002,
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
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

  test('snapshot member role aliases must agree when repeated', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'roomId': '9527',
          'roomName': '角色冲突房',
          'ownerId': 10001,
          'memberRole': 'OWNER',
          'role': 'MEMBER',
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
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

  test('reconnect uses the same read-only snapshot contract', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      expect(request.method, 'POST');
      expect(request.path, '/app-room-api/room/com/v1/reConnectRoomInfo');
      expect(request.query, isEmpty);
      expect(request.body, <String, Object?>{'roomId': 'room-abc'});
      return const _Reply(
        data: <String, Object?>{
          'roomId': 'room-abc',
          'roomName': '回声房',
          'topic': '重连快照',
          'ownerUserId': 20002,
          'onlineNum': 2,
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final RoomSnapshot snapshot = await repository.reconnectRoom(
      roomId: 'room-abc',
      currentUserId: 10001,
    );

    expect(snapshot.roomId, 'room-abc');
    expect(snapshot.title, '回声房');
    expect(snapshot.topic, '重连快照');
    expect(snapshot.role, RoomRole.listener);
    expect(snapshot.onlineCount, 2);
    expect(server.requests, hasLength(1));
    expect(server.requests.single.body, <String, Object?>{
      'roomId': 'room-abc',
    });
  });

  test('empty snapshot envelope is rejected as a protocol error', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(data: <String, Object?>{}),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
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

  test(
    'error envelope is surfaced without manufacturing a room snapshot',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 40901,
          message: '房间状态已变化',
          data: null,
          httpStatus: 409,
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.enterRoom(
          roomId: '9527',
          password: null,
          source: RoomEntrySource.search,
          currentUserId: 10001,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                '房间状态已变化',
              ),
        ),
      );
    },
  );

  test(
    'first-party room writes use canonical body contracts and exit membership',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-room-api/room/com/v1/enterRoom':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'source': 0,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'roomName': '夜航电台',
                'ownerUserId': 10001,
                'memberRole': 'OWNER',
              },
            );
          case '/app-api/micUserBase/userInitiativeUpMic':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'seatNumber': 4,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'userId': 10001,
                'occupied': true,
                'muted': false,
              },
            );
          case '/app-api/micUserBase/leaveMic':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'roomId': '9527'});
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'leftMic': true,
                'previousSeat': 4,
              },
            );
          case '/app-api/micBase/closedMike':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'userId': 10001,
              'seatNumber': 4,
              'muted': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'userId': 10001,
                'muted': true,
                'occupied': true,
              },
            );
          case '/app-room-api/room/com/v1/roomScreenChat':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'content': 'hello',
            });
            return const _Reply(
              data: <String, Object?>{
                'messageId': 'message-3',
                'roomId': '9527',
                'senderUserId': 10001,
                'content': 'hello',
                'createdAt': '2026-08-22T12:03:00Z',
                'deliveryMode': 'HTTP_PERSISTED_NO_REALTIME',
                'realtimeStatus': 'VENDOR_BLOCKED',
              },
            );
          case '/app-room-api/room/com/v1/sendGift':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'giftId': '550e8400-e29b-41d4-a716-446655440000',
              'receiverUserId': 10002,
              'quantity': 2,
              'source': 'WALLET',
            });
            return const _Reply(
              data: <String, Object?>{
                'transferId': 'transfer-1',
                'roomId': '9527',
                'senderUserId': 10001,
                'receiverUserId': 10002,
                'giftId': '550e8400-e29b-41d4-a716-446655440000',
                'giftName': '玫瑰',
                'quantity': 2,
                'source': 'WALLET',
                'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
                'providerInvocation': false,
                'status': 'SUCCEEDED',
                'remainingBalance': 880,
              },
            );
          case '/app-room-api/room/com/v1/exitRoom':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'roomId': '9527'});
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'exited': true,
                'status': 'EXITED',
              },
            );
          default:
            fail('unexpected room write route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );
      await repository.requestMic(4);
      await repository.leaveMic();
      await repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: true);
      await repository.sendPublicMessage(roomId: '9527', content: 'hello');
      final GiftReceipt receipt = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 2,
        giftFrom: 0,
      );
      expect(receipt.success, isTrue);
      expect(receipt.remainingBalance, 880);
      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 1,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      await repository.exitRoom('9527');
      expect(server.requests, hasLength(7));
    },
  );

  test(
    'HTTP 200 gift response without transfer authority fails closed',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-room-api/room/com/v1/sendGift');
        return const _Reply(data: <String, Object?>{});
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('transferId'),
              ),
        ),
      );
    },
  );

  test(
    'gift send rejects non-UUID catalog identifiers before network',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(data: <String, Object?>{}),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '101',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      expect(server.requests, isEmpty);
    },
  );

  test('success boolean without full gift authority fails closed', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) =>
          const _Reply(data: <String, Object?>{'success': true}),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'blank transferId without an explicit success field fails closed',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) =>
            const _Reply(data: <String, Object?>{'transferId': '   '}),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('provider or backpack gift responses remain fail closed', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'transferId': 'transfer-third-party',
          'roomId': '9527',
          'senderUserId': 10001,
          'receiverUserId': 10002,
          'giftId': '550e8400-e29b-41d4-a716-446655440000',
          'giftName': '玫瑰',
          'quantity': 1,
          'source': 'WALLET',
          'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
          'providerInvocation': true,
          'status': 'SUCCEEDED',
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
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
    'explicit authoritative gift failure never becomes a successful receipt',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'success': false,
            'transferId': 'transfer-failed',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 1,
            'source': 'WALLET',
            'deliveryMode': 'HTTP_PERSISTED_NO_REALTIME',
            'providerInvocation': false,
            'status': 'FAILED',
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final GiftReceipt receipt = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      );

      expect(receipt.success, isFalse);
    },
  );

  test('concurrent identical gifts are one repository write', () async {
    int sendGiftCalls = 0;
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      if (request.path != '/app-room-api/room/com/v1/sendGift') {
        fail('unexpected room route: ${request.path}');
      }
      sendGiftCalls += 1;
      return const _Reply(
        data: <String, Object?>{
          'transferId': 'gift-concurrent',
          'roomId': '9527',
          'senderUserId': 10001,
          'receiverUserId': 10002,
          'giftId': '550e8400-e29b-41d4-a716-446655440000',
          'giftName': '玫瑰',
          'quantity': 1,
          'source': 'WALLET',
          'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
          'providerInvocation': false,
          'status': 'SUCCEEDED',
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final List<GiftReceipt> receipts = await Future.wait(<Future<GiftReceipt>>[
      repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      ),
      repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      ),
    ]);

    expect(receipts, hasLength(2));
    expect(receipts[0].transferId, 'gift-concurrent');
    expect(receipts[1].transferId, 'gift-concurrent');
    expect(sendGiftCalls, 1);
    expect(
      server.requests
          .where(
            (_CapturedRequest request) =>
                request.path == '/app-room-api/room/com/v1/sendGift',
          )
          .map((_CapturedRequest request) => request.requestId)
          .toSet(),
      hasLength(1),
    );
  });

  test(
    'ambiguous gift retry keeps the same request ID while a later completed send is fresh',
    () async {
      int sendGiftCalls = 0;
      final List<String> requestIds = <String>[];
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-room-api/room/com/v1/sendGift');
        sendGiftCalls += 1;
        requestIds.add(request.requestId);
        if (sendGiftCalls == 1) {
          return const _Reply(
            code: 50001,
            message: 'response lost after commit',
            httpStatus: 500,
          );
        }
        return const _Reply(
          data: <String, Object?>{
            'transferId': 'gift-retried',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 1,
            'source': 'WALLET',
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'status': 'SUCCEEDED',
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
        ),
        throwsA(isA<ApiException>()),
      );
      final GiftReceipt retried = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      );
      final GiftReceipt completedNewSend = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 1,
        giftFrom: 0,
      );

      expect(retried.transferId, 'gift-retried');
      expect(completedNewSend.transferId, 'gift-retried');
      expect(requestIds, hasLength(3));
      expect(requestIds[0], requestIds[1]);
      expect(requestIds[1], isNot(requestIds[2]));
    },
  );

  test(
    'an explicit gift request ID cannot be reused for a different fingerprint',
    () async {
      int sendGiftCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        sendGiftCalls += 1;
        return const _Reply(
          code: 50001,
          message: 'response lost after commit',
          httpStatus: 500,
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      const String requestId = 'explicit-gift-request-id';
      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
          requestId: requestId,
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 2,
          giftFrom: 0,
          requestId: requestId,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
      expect(sendGiftCalls, 1);
      expect(server.requests.single.requestId, requestId);
    },
  );

  test(
    'public message history uses the paged GET contract and restores UI order',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'GET');
        expect(request.path, '/app-mini-api/mini/v1/rooms/public-messages');
        expect(request.query, <String, String>{
          'roomId': '9527',
          'pageNum': '1',
          'pageSize': '50',
        });
        return const _Reply(
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'total': 2,
            'pages': 1,
            'list': <Map<String, Object?>>[
              <String, Object?>{
                'messageId': 'message-2',
                'senderUserId': 10002,
                'senderName': '南风',
                'type': 'TEXT',
                'content': '后发的消息',
                'createdAt': '2026-08-22T12:02:00Z',
              },
              <String, Object?>{
                'messageId': 'message-1',
                'senderUserId': 10001,
                'senderName': '晚星',
                'type': 'TEXT',
                'content': '先发的消息',
                'createdAt': '2026-08-22T12:01:00Z',
              },
            ],
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final List<RoomMessage> messages = await repository.fetchPublicMessages(
        '9527',
      );

      expect(messages, hasLength(2));
      expect(messages[0].messageId, 'message-1');
      expect(messages[0].senderId, 10001);
      expect(messages[0].sender, '晚星');
      expect(messages[0].type, 'TEXT');
      expect(messages[0].content, '先发的消息');
      expect(messages[0].createdAt, DateTime.parse('2026-08-22T12:01:00Z'));
      expect(messages[1].messageId, 'message-2');
    },
  );

  test(
    'public message history rejects divergent list and records fields',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'current': 1,
            'size': 50,
            'total': 1,
            'pages': 1,
            'list': <Map<String, Object?>>[
              <String, Object?>{'messageId': 'message-list'},
            ],
            'records': <Map<String, Object?>>[
              <String, Object?>{'messageId': 'message-records'},
            ],
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('list 与 records'),
              ),
        ),
      );
    },
  );

  test(
    'public message send parses the persisted authority and request id',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'POST');
        expect(request.path, '/app-room-api/room/com/v1/roomScreenChat');
        expect(request.requestId, 'room-chat-fixed-id');
        return const _Reply(
          data: <String, Object?>{
            'messageId': 'message-3',
            'roomId': '9527',
            'senderUserId': 10001,
            'content': '服务端内容',
            'createdAt': '2026-08-22T12:03:00Z',
            'deliveryMode': 'HTTP_PERSISTED_NO_REALTIME',
            'realtimeStatus': 'VENDOR_BLOCKED',
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final RoomMessage message = await repository.sendPublicMessage(
        roomId: '9527',
        content: '服务端内容',
        requestId: 'room-chat-fixed-id',
      );
      expect(message.messageId, 'message-3');
      expect(message.roomId, '9527');
      expect(message.senderId, 10001);
      expect(message.sender, '我');
      expect(message.type, 'TEXT');
      expect(message.content, '服务端内容');
      expect(message.createdAt, DateTime.parse('2026-08-22T12:03:00Z'));
      expect(message.deliveryMode, 'HTTP_PERSISTED_NO_REALTIME');
      expect(message.realtimeStatus, 'VENDOR_BLOCKED');
    },
  );

  test('public message history rejects incomplete server authority', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      return const _Reply(
        data: <String, Object?>{
          'current': 1,
          'size': 50,
          'total': 1,
          'pages': 1,
          'list': <Map<String, Object?>>[
            <String, Object?>{
              'messageId': 'message-1',
              'senderId': 10001,
              'senderName': '晚星',
              'content': '缺时间',
            },
          ],
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.fetchPublicMessages('9527'),
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
    'public message history exhausts every b709 page and restores UI order',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int page = int.parse(request.query['pageNum']!);
        expect(request.query['roomId'], '9527');
        expect(request.query['pageSize'], '50');
        return _Reply(
          data: _historyPage(
            current: page,
            pageSize: 50,
            total: 51,
            pages: 2,
            messages: page == 1
                ? <Map<String, Object?>>[
                    for (int id = 51; id >= 2; id -= 1)
                      _historyMessage(
                        id: 'message-$id',
                        senderId: 10000 + id,
                        senderName: '用户$id',
                        content: '第$id条',
                        createdAt:
                            '2026-08-22T12:${id.toString().padLeft(2, '0')}:00Z',
                      ),
                  ]
                : <Map<String, Object?>>[
                    _historyMessage(
                      id: 'message-1',
                      senderId: 10001,
                      senderName: '晚星',
                      content: '第一条',
                      createdAt: '2026-08-22T12:01:00Z',
                    ),
                  ],
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final List<RoomMessage> messages = await repository.fetchPublicMessages(
        '9527',
      );

      expect(
        server.requests.map((request) => request.query['pageNum']),
        <String?>['1', '2'],
      );
      expect(messages, hasLength(51));
      expect(messages.first.messageId, 'message-1');
      expect(messages.last.messageId, 'message-51');
      expect(messages.first.senderId, 10001);
      expect(messages.last.senderId, 10051);
    },
  );

  test(
    'public message history requires current to equal each requested page',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int requestedPage = int.parse(request.query['pageNum']!);
        return _Reply(
          data: _historyPage(
            current: requestedPage == 1 ? 2 : requestedPage,
            pageSize: 50,
            total: 1,
            pages: 1,
            messages: <Map<String, Object?>>[
              _historyMessage(
                id: 'message-current-mismatch',
                senderId: 10001,
                senderName: '晚星',
                content: '页码不可信',
                createdAt: '2026-08-22T12:01:00Z',
              ),
            ],
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'public message history rejects page-size and total-pages drift',
    () async {
      final List<Map<String, Object?>> responses = <Map<String, Object?>>[
        _historyPage(
          current: 1,
          pageSize: 25,
          total: 3,
          pages: 1,
          messages: <Map<String, Object?>>[
            _historyMessage(
              id: 'message-page-size',
              senderId: 10001,
              senderName: '晚星',
              content: 'pageSize 错误',
              createdAt: '2026-08-22T12:01:00Z',
            ),
          ],
        ),
        _historyPage(
          current: 1,
          pageSize: 50,
          total: 51,
          pages: 1,
          messages: <Map<String, Object?>>[
            _historyMessage(
              id: 'message-pages-mismatch',
              senderId: 10001,
              senderName: '晚星',
              content: 'pages 错误',
              createdAt: '2026-08-22T12:01:00Z',
            ),
          ],
        ),
      ];
      for (final Map<String, Object?> response in responses) {
        final _RunningServer server = await _RunningServer.start(
          (_CapturedRequest request) => _Reply(data: response),
        );
        addTearDown(server.close);
        final BackendRoomRepository repository = BackendRoomRepository(
          apiClient: server.client,
        );

        await expectLater(
          repository.fetchPublicMessages('9527'),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'public message history rejects an empty page when more pages remain',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        return _Reply(
          data: _historyPage(
            current: int.parse(request.query['pageNum']!),
            pageSize: 50,
            total: 51,
            pages: 2,
            messages: <Map<String, Object?>>[],
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test('public message history rejects metadata drift between pages', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      final int page = int.parse(request.query['pageNum']!);
      return _Reply(
        data: _historyPage(
          current: page,
          pageSize: 50,
          total: page == 1 ? 51 : 52,
          pages: 2,
          messages: <Map<String, Object?>>[
            _historyMessage(
              id: 'message-drift-$page',
              senderId: 1000 + page,
              senderName: '用户$page',
              content: 'metadata drift',
              createdAt: '2026-08-22T12:0${page}:00Z',
            ),
          ],
        ),
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.fetchPublicMessages('9527'),
      throwsA(isA<ApiException>()),
    );
    expect(server.requests, hasLength(2));
  });

  test(
    'public message history rejects backward, repeated, and skipped pages',
    () async {
      final List<int> reportedPages = <int>[1, 1, 3];
      int callCount = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int call = callCount++;
        final int reportedPage = reportedPages[call];
        return _Reply(
          data: _historyPage(
            current: reportedPage,
            pageSize: 50,
            total: 101,
            pages: 3,
            messages: <Map<String, Object?>>[
              _historyMessage(
                id: 'message-progress-$call',
                senderId: 10001,
                senderName: '晚星',
                content: '页码进度',
                createdAt: '2026-08-22T12:0$call:00Z',
              ),
            ],
          ),
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests, hasLength(2));
    },
  );

  test(
    'public message history rejects duplicates across pages and count gaps',
    () async {
      final _RunningServer duplicateServer = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int page = int.parse(request.query['pageNum']!);
        return _Reply(
          data: _historyPage(
            current: page,
            pageSize: 50,
            total: 51,
            pages: 2,
            messages: <Map<String, Object?>>[
              _historyMessage(
                id: 'message-same',
                senderId: 10001,
                senderName: '晚星',
                content: '重复消息',
                createdAt: '2026-08-22T12:01:00Z',
              ),
            ],
          ),
        );
      });
      addTearDown(duplicateServer.close);
      final BackendRoomRepository duplicateRepository = BackendRoomRepository(
        apiClient: duplicateServer.client,
      );
      await expectLater(
        duplicateRepository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );

      final _RunningServer countServer = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        final int page = int.parse(request.query['pageNum']!);
        return _Reply(
          data: _historyPage(
            current: page,
            pageSize: 50,
            total: 3,
            pages: 1,
            messages: <Map<String, Object?>>[
              _historyMessage(
                id: 'message-count-gap',
                senderId: 10001,
                senderName: '晚星',
                content: '少一条',
                createdAt: '2026-08-22T12:01:00Z',
              ),
            ],
          ),
        );
      });
      addTearDown(countServer.close);
      final BackendRoomRepository countRepository = BackendRoomRepository(
        apiClient: countServer.client,
      );
      await expectLater(
        countRepository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'public message history rejects an unsafe page count before fetching',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _historyPage(
            current: 1,
            pageSize: 50,
            total: 5051,
            pages: 101,
            messages: <Map<String, Object?>>[
              _historyMessage(
                id: 'message-unsafe-pages',
                senderId: 10001,
                senderName: '晚星',
                content: '页数过大',
                createdAt: '2026-08-22T12:01:00Z',
              ),
            ],
          ),
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'zero-message public history is a valid empty authoritative result',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _historyPage(
            current: 1,
            pageSize: 50,
            total: 0,
            pages: 0,
            messages: <Map<String, Object?>>[],
          ),
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final Future<List<RoomMessage>> result = repository.fetchPublicMessages(
        '9527',
      );
      await expectLater(result, completion(isEmpty));
    },
  );

  test(
    'public message history requires all authoritative message fields',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _historyPage(
            current: 1,
            pageSize: 50,
            total: 1,
            pages: 1,
            messages: <Map<String, Object?>>[
              <String, Object?>{
                'messageId': 'message-incomplete',
                'senderUserId': 10001,
                'senderName': '晚星',
                'type': 'TEXT',
                'content': '缺 createdAt',
              },
            ],
          ),
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.fetchPublicMessages('9527'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'gift rejects blocked provider status and incomplete authority',
    () async {
      final _RunningServer blocked = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        return const _Reply(
          data: <String, Object?>{
            'transferId': 'transfer-blocked',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 1,
            'source': 'WALLET',
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'providerStatus': 'VENDOR_BLOCKED',
            'status': 'SUCCEEDED',
          },
        );
      });
      addTearDown(blocked.close);
      final BackendRoomRepository blockedRepository = BackendRoomRepository(
        apiClient: blocked.client,
      );
      await expectLater(
        blockedRepository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
          requestId: 'room-gift-fixed-id',
        ),
        throwsA(isA<ApiException>()),
      );

      final _RunningServer incomplete = await _RunningServer.start(
        (_CapturedRequest request) =>
            const _Reply(data: <String, Object?>{'success': true}),
      );
      addTearDown(incomplete.close);
      final BackendRoomRepository incompleteRepository = BackendRoomRepository(
        apiClient: incomplete.client,
      );
      await expectLater(
        incompleteRepository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 1,
          giftFrom: 0,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'b709 first-party gift succeeds without optional status fields',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'transferId': 'transfer-b709',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 2,
            'source': 'WALLET',
            'costs': <String, Object?>{
              'unitCostMinor': 10,
              'totalCostMinor': 20,
            },
            'animationKey': 'rose',
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final GiftReceipt receipt = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 2,
        giftFrom: 0,
        requestId: 'b709-gift-no-status',
      );

      expect(receipt.success, isTrue);
      expect(receipt.status, isNull);
      expect(receipt.remainingBalance, isNull);
      expect(receipt.transferId, 'transfer-b709');
    },
  );

  test(
    'gift amount authority must be non-negative and arithmetically consistent',
    () async {
      int callCount = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        callCount += 1;
        final Map<String, Object?> costs = callCount == 1
            ? <String, Object?>{
                'unitCostMinor': 10,
                'totalCostMinor': 20,
                'currency': 'GIFT_COIN',
                'quantity': 2,
                'giftId': '550e8400-e29b-41d4-a716-446655440000',
              }
            : <String, Object?>{
                'unitCostMinor': -10,
                'totalCostMinor': -20,
                'currency': 'GIFT_COIN',
                'quantity': 2,
                'giftId': '550e8400-e29b-41d4-a716-446655440000',
              };
        return _Reply(
          data: <String, Object?>{
            'transferId': 'transfer-cost-$callCount',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 2,
            'source': 'WALLET',
            'costs': costs,
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'status': 'SUCCEEDED',
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final GiftReceipt receipt = await repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 2,
        giftFrom: 0,
      );
      expect(receipt.success, isTrue);

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 2,
          giftFrom: 0,
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

  test(
    'frozen giftCoinCost authority rejects negative ledger totals',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'transferId': 'transfer-negative-gift-coin-cost',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 2,
            'source': 'WALLET',
            'giftCoinCost': -20,
            'creatorIncomeMinor': 10,
            'charmValue': 4,
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'status': 'SUCCEEDED',
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 2,
          giftFrom: 0,
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

  test('gift side-effect summaries must be non-negative integers', () async {
    int callCount = 0;
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      callCount += 1;
      return _Reply(
        data: <String, Object?>{
          'transferId': 'transfer-negative-summary-$callCount',
          'roomId': '9527',
          'senderUserId': 10001,
          'receiverUserId': 10002,
          'giftId': '550e8400-e29b-41d4-a716-446655440000',
          'giftName': '玫瑰',
          'quantity': 2,
          'source': 'WALLET',
          'giftCoinCost': 20,
          'creatorIncomeMinor': callCount == 1 ? -1 : 10,
          'charmValue': callCount == 1 ? 4 : -1,
          'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
          'providerInvocation': false,
          'status': 'SUCCEEDED',
        },
      );
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    for (int index = 0; index < 2; index += 1) {
      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: '550e8400-e29b-41d4-a716-446655440000',
          receiverUserIds: <int>[10002],
          quantity: 2,
          giftFrom: 0,
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
  });

  test(
    'gift amount aliases and currency cannot contradict the ledger',
    () async {
      int callCount = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        callCount += 1;
        return _Reply(
          data: <String, Object?>{
            'transferId': 'transfer-ledger-conflict-$callCount',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
            'giftName': '玫瑰',
            'quantity': 2,
            'source': 'WALLET',
            'giftCoinCost': callCount == 1 ? 21 : 20,
            'creatorIncomeMinor': 10,
            'charmValue': 4,
            'costs': <String, Object?>{
              'unitCostMinor': 10,
              'totalCostMinor': 20,
              'currency': callCount == 1 ? 'GIFT_COIN' : 'USD',
            },
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'status': 'SUCCEEDED',
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      for (int index = 0; index < 2; index += 1) {
        await expectLater(
          repository.sendGift(
            roomId: '9527',
            giftId: '550e8400-e29b-41d4-a716-446655440000',
            receiverUserIds: <int>[10002],
            quantity: 2,
            giftFrom: 0,
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
    },
  );

  test('gift amount identity and currency aliases must agree', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'transferId': 'transfer-cost-conflict',
          'roomId': '9527',
          'senderUserId': 10001,
          'receiverUserId': 10002,
          'giftId': '550e8400-e29b-41d4-a716-446655440000',
          'giftName': '玫瑰',
          'quantity': 2,
          'source': 'WALLET',
          'currency': 'GIFT_COIN',
          'costs': <String, Object?>{
            'unitCostMinor': 10,
            'totalCostMinor': 20,
            'currency': 'CASH_CNY',
            'quantity': 1,
            'giftId': '550e8400-e29b-41d4-a716-446655440000',
          },
          'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
          'providerInvocation': false,
          'status': 'SUCCEEDED',
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.sendGift(
        roomId: '9527',
        giftId: '550e8400-e29b-41d4-a716-446655440000',
        receiverUserIds: <int>[10002],
        quantity: 2,
        giftFrom: 0,
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

  test(
    'approval entry fails closed and does not replace the active membership',
    () async {
      int enterCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-room-api/room/com/v1/enterRoom':
            enterCalls += 1;
            if (enterCalls == 1) {
              return const _Reply(
                data: <String, Object?>{
                  'roomId': '9527',
                  'roomName': '公开房',
                  'ownerUserId': 10001,
                  'memberRole': 'OWNER',
                },
              );
            }
            return const _Reply(
              data: <String, Object?>{
                'roomId': 'approval-room',
                'joined': false,
                'status': 'PENDING_APPROVAL',
                'joinRequestId': 'join-request-1',
              },
            );
          case '/app-api/micBase/closedMike':
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'userId': 10001,
              'seatNumber': 4,
              'muted': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'seatNumber': 4,
                'userId': 10001,
                'muted': true,
                'occupied': true,
              },
            );
          default:
            fail('unexpected room route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );
      await expectLater(
        repository.enterRoom(
          roomId: 'approval-room',
          password: null,
          source: RoomEntrySource.home,
          currentUserId: 10001,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.business,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                '申请已提交，等待审核',
              ),
        ),
      );
      await repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: true);
    },
  );

  test('reconnect updates the active user and exit clears it', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      switch (request.path) {
        case '/app-room-api/room/com/v1/enterRoom':
          return const _Reply(
            data: <String, Object?>{
              'roomId': '9527',
              'roomName': '公开房',
              'ownerUserId': 10001,
              'memberRole': 'OWNER',
            },
          );
        case '/app-room-api/room/com/v1/reConnectRoomInfo':
          return const _Reply(
            data: <String, Object?>{
              'roomId': '9527',
              'roomName': '公开房',
              'ownerUserId': 10002,
              'memberRole': 'MEMBER',
            },
          );
        case '/app-api/micBase/openMike':
          expect(request.body, <String, Object?>{
            'roomId': '9527',
            'userId': 10002,
            'seatNumber': 4,
            'muted': false,
          });
          return const _Reply(
            data: <String, Object?>{
              'roomId': '9527',
              'seatNumber': 4,
              'userId': 10002,
              'muted': false,
              'occupied': true,
            },
          );
        case '/app-room-api/room/com/v1/exitRoom':
          expect(request.body, <String, Object?>{'roomId': '9527'});
          return const _Reply(
            data: <String, Object?>{
              'roomId': '9527',
              'exited': true,
              'status': 'EXITED',
            },
          );
        default:
          fail('unexpected room route: ${request.path}');
      }
    });
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );
    await repository.reconnectRoom(roomId: '9527', currentUserId: 10002);
    await repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: false);
    await repository.exitRoom('9527');
    await expectLater(
      repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: true),
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
    'enter rejects a response for a different room and does not activate it',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-room-api/room/com/v1/enterRoom');
        expect(request.body, <String, Object?>{
          'roomId': 'requested-room',
          'source': 0,
        });
        return const _Reply(
          data: <String, Object?>{
            'roomId': 'different-room',
            'roomName': '错误房间',
            'ownerUserId': 10001,
            'memberRole': 'OWNER',
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.enterRoom(
          roomId: '  requested-room ',
          password: null,
          source: RoomEntrySource.home,
          currentUserId: 10001,
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
        repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'reconnect rejects a different room while preserving the prior active room',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-room-api/room/com/v1/enterRoom':
            return const _Reply(
              data: <String, Object?>{
                'roomId': 'requested-room',
                'roomName': '原房间',
                'ownerUserId': 10001,
                'memberRole': 'OWNER',
              },
            );
          case '/app-room-api/room/com/v1/reConnectRoomInfo':
            return const _Reply(
              data: <String, Object?>{
                'roomId': 'different-room',
                'roomName': '错误房间',
                'ownerUserId': 10002,
                'memberRole': 'MEMBER',
              },
            );
          case '/app-api/micBase/closedMike':
            expect(request.body, <String, Object?>{
              'roomId': 'requested-room',
              'userId': 10001,
              'seatNumber': 4,
              'muted': true,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': 'requested-room',
                'seatNumber': 4,
                'userId': 10001,
                'muted': true,
                'occupied': true,
              },
            );
          default:
            fail('unexpected room route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await repository.enterRoom(
        roomId: 'requested-room',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );
      await expectLater(
        repository.reconnectRoom(
          roomId: ' requested-room ',
          currentUserId: 10002,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await repository.setSelfMicrophoneMuted(backendMicIndex: 4, muted: true);
      expect(server.requests, hasLength(3));
      expect(server.requests.last.path, '/app-api/micBase/closedMike');
    },
  );
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
        authorization: captureContractAuthorization(request),
        requestId: request.headers.value('X-Request-Id') ?? '',
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

Map<String, Object?> _historyMessage({
  required String id,
  required int senderId,
  required String senderName,
  required String content,
  required String createdAt,
}) => <String, Object?>{
  'messageId': id,
  'senderUserId': senderId,
  'senderName': senderName,
  'type': 'TEXT',
  'content': content,
  'createdAt': createdAt,
};

Map<String, Object?> _historyPage({
  required int current,
  required int pageSize,
  required int total,
  required int pages,
  required List<Map<String, Object?>> messages,
}) => <String, Object?>{
  'current': current,
  'size': pageSize,
  'total': total,
  'pages': pages,
  'list': messages,
};
