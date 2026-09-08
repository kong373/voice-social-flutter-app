import 'room_lease_contract_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_rtc_token_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';

Map<String, Object?> _fixture() => <String, Object?>{
  'roomId': 'room-1',
  'viewerUserId': 42,
  'memberActive': true,
  'roomMuted': true,
  'version': 7,
  'activeSession': true,
  'sessionId': roomLeaseSessionId,
  'roomLease': roomLeaseWireFixture(),
  'status': 'OPEN',
  'ownerUserId': 9,
  'memberRole': 'MODERATOR',
  'roomName': 'Authority room',
  'topic': 'Topic',
  'publicScreenEnabled': true,
  'autoLockMic': true,
  'giftCatalogAvailable': true,
  'accessMode': 'APPROVAL',
  'onlineNum': 3,
  'seats': <Object?>[
    <String, Object?>{
      'index': 0,
      'userId': 42,
      'userName': 'Self',
      'status': 4,
    },
  ],
};

final Matcher _protocol = throwsA(
  isA<ApiException>().having(
    (ApiException e) => e.kind,
    'kind',
    ApiFailureKind.protocol,
  ),
);

void main() {
  test(
    'one authenticated GET projects full authority without activating room',
    () async {
      final _Api api = _Api(_fixture());
      final _Tokens tokens = _Tokens();
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: api,
        rtcTokenRepository: tokens,
      );
      final RoomAuthorityRepository capability = repository;
      final RoomAuthorityProjection result = await capability
          .fetchRoomAuthority(roomId: 'room-1', currentUserId: 42);
      expect(result.viewerUserId, 42);
      expect(result.memberActive, isTrue);
      expect(result.roomMuted, isTrue);
      expect(result.version, 7);
      expect(result.snapshot.sessionId, roomLeaseSessionId);
      expect(
        result.snapshot.copyWith(title: 'Changed').sessionId,
        roomLeaseSessionId,
      );
      expect(result.snapshot.title, 'Authority room');
      expect(result.snapshot.topic, 'Topic');
      expect(result.snapshot.role, RoomRole.moderator);
      expect(result.snapshot.publicScreenEnabled, isTrue);
      expect(result.snapshot.autoLockMic, isTrue);
      expect(result.snapshot.giftCatalogAvailable, isTrue);
      expect(result.snapshot.accessMode, 'APPROVAL');
      expect(result.snapshot.onlineCount, 3);
      expect(result.snapshot.seats.first.userId, 42);
      expect(result.snapshot.seats.first.state, MicSeatState.occupiedMuted);
      expect(result.snapshot.rtc.token, isEmpty);
      expect(result.snapshot.isSnapshotOnly, isTrue);
      expect(repository.lastTencentImRoomSession, isNull);
      await expectLater(
        repository.requestMic(0),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      expect(api.calls, <String>['GET']);
      expect(tokens.calls, 0);
    },
  );

  test(
    'read preserves established active room, user and IM session cache',
    () async {
      final data = _fixture()
        ..['realtimeGroup'] = <String, Object?>{
          'provider': 'tencent-im',
          'type': 'AVCHATROOM',
          'groupId': 'room-group-1',
          'groupType': 'AVChatRoom',
          'status': 'READY',
          'messageMode': 'METADATA_HINT',
          'contentAuthority': 'HTTP',
        };
      final api = _Api(data, allowEntry: true);
      final repository = BackendRoomRepository(apiClient: api);
      await repository.enterRoom(
        roomId: 'room-1',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 9,
      );
      final cached = repository.lastTencentImRoomSession;
      expect(cached, isNotNull);
      data['sessionId'] = '22222222-2222-4222-8222-222222222222';
      data['roomLease'] = roomLeaseWireFixture(
        sessionId: data['sessionId']! as String,
      );
      final result = await repository.fetchRoomAuthority(
        roomId: 'room-1',
        currentUserId: 42,
      );
      expect(result.snapshot.sessionId, '22222222-2222-4222-8222-222222222222');
      expect(repository.lastTencentImRoomSession, same(cached));
      expect(repository.takeTencentImRoomSession('room-1'), same(cached));
      expect(api.calls, <String>['POST', 'GET']);
      // A subsequent explicit write must still use the entered viewer, not 42.
      api.allowMic = true;
      await repository.setSelfMicrophoneMuted(backendMicIndex: 0, muted: true);
      expect(api.lastBody, <String, Object?>{
        'sessionId': roomLeaseSessionId,
        'roomId': 'room-1',
        'userId': 9,
        'seatNumber': 0,
        'muted': true,
      });
    },
  );

  test('inactive read rejects a present null session identifier', () async {
    final api = _Api(
      _fixture()..addAll(<String, Object?>{
        'memberActive': false,
        'activeSession': false,
        'sessionId': null,
      }),
    );
    await expectLater(
      BackendRoomRepository(
        apiClient: api,
      ).fetchRoomAuthority(roomId: 'room-1', currentUserId: 42),
      _protocol,
    );
  });

  test('invalid request identity fails before any API call', () async {
    final api = _Api(_fixture());
    final repository = BackendRoomRepository(apiClient: api);
    for (final (String, int) input in <(String, int)>[
      ('', 42),
      (' ', 42),
      ('room-1', 0),
    ]) {
      await expectLater(
        repository.fetchRoomAuthority(
          roomId: input.$1,
          currentUserId: input.$2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
    }
    expect(api.calls, isEmpty);
  });

  for (final String status in <String>['OPEN', 'CLOSED', 'PENDING_APPROVAL']) {
    test(
      'inactive $status remains inactive without session or join fallback',
      () async {
        final Map<String, Object?> data = _fixture()
          ..remove('sessionId')
          ..remove('roomLease')
          ..addAll(<String, Object?>{
            'status': status,
            'joined': false,
            'memberActive': false,
            'activeSession': false,
            'roomMuted': false,
            'version': 0,
          });
        final _Api api = _Api(data);
        final result = await BackendRoomRepository(
          apiClient: api,
        ).fetchRoomAuthority(roomId: 'room-1', currentUserId: 42);
        expect(result.memberActive, isFalse);
        expect(result.roomMuted, isFalse);
        expect(result.snapshot.sessionId, isNull);
        expect(result.version, 0);
        expect(api.calls, <String>['GET']);
      },
    );
  }

  final Map<String, List<Object?>> invalid = <String, List<Object?>>{
    'roomId': <Object?>[null, '', 'other', ' room-1 ', 1],
    'viewerUserId': <Object?>[null, 43, '42', 42.0, false],
    'memberActive': <Object?>[null, 0, 1, 'true', 'false'],
    'roomMuted': <Object?>[null, 0, 1, 'true', 'false'],
    'version': <Object?>[null, -1, 7.0, '7', false],
    'activeSession': <Object?>[null, false, 'true', 1],
    'sessionId': <Object?>[null, '', ' ', 1, false, ' session-1', 'a\nb'],
    'roomIdStr': <Object?>['other', ' room-1 ', 1],
  };
  for (final entry in invalid.entries) {
    for (int i = 0; i < entry.value.length; i++) {
      test('rejects invalid ${entry.key} case $i', () async {
        final _Api api = _Api(_fixture()..[entry.key] = entry.value[i]);
        await expectLater(
          BackendRoomRepository(
            apiClient: api,
          ).fetchRoomAuthority(roomId: 'room-1', currentUserId: 42),
          _protocol,
        );
        expect(api.calls, <String>['GET']);
      });
    }
  }
  for (final String key in <String>[
    'roomId',
    'viewerUserId',
    'memberActive',
    'roomMuted',
    'version',
    'activeSession',
    'sessionId',
  ]) {
    test('rejects missing $key', () async {
      final _Api api = _Api(_fixture()..remove(key));
      await expectLater(
        BackendRoomRepository(
          apiClient: api,
        ).fetchRoomAuthority(roomId: 'room-1', currentUserId: 42),
        _protocol,
      );
    });
  }

  for (final bool reconnect in <bool>[false, true]) {
    test(
      '${reconnect ? 'reconnect' : 'enter'} rejects present null session',
      () async {
        final repository = BackendRoomRepository(
          leaseBinding: admittedRoomFixture(roomId: 'room-1', userId: 42),
          apiClient: _Api(_fixture()..['sessionId'] = null, allowEntry: true),
        );
        await expectLater(
          reconnect
              ? repository.reconnectRoom(roomId: 'room-1', currentUserId: 42)
              : repository.enterRoom(
                  roomId: 'room-1',
                  password: null,
                  source: RoomEntrySource.home,
                  currentUserId: 42,
                ),
          _protocol,
        );
      },
    );
    for (final Object? session in <Object?>[
      roomLeaseSessionId,
      null,
      '',
      2,
      false,
      ' bad',
    ]) {
      test('${reconnect ? 'reconnect' : 'enter'} session $session', () async {
        final data = _fixture()..remove('sessionId');
        if (session != null) data['sessionId'] = session;
        final repository = BackendRoomRepository(
          leaseBinding: admittedRoomFixture(roomId: 'room-1', userId: 42),
          apiClient: _Api(data, allowEntry: true),
        );
        final Future<RoomSnapshot> future = reconnect
            ? repository.reconnectRoom(roomId: 'room-1', currentUserId: 42)
            : repository.enterRoom(
                roomId: 'room-1',
                password: null,
                source: RoomEntrySource.home,
                currentUserId: 42,
              );
        if (session == roomLeaseSessionId) {
          final snapshot = await future;
          expect(snapshot.sessionId, session);
          expect(snapshot.copyWith().sessionId, session);
        } else {
          await expectLater(future, _protocol);
        }
      });
    }
  }
}

class _Api implements ApiClient {
  _Api(this.data, {this.allowEntry = false});
  final Map<String, Object?> data;
  final bool allowEntry;
  bool allowMic = false;
  Map<String, Object?>? lastBody;
  final List<String> calls = <String>[];

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    calls.add('GET');
    expect(path, const BackendRouteCatalog().queryRoomOtherInfo);
    expect(query, <String, String>{'roomId': 'room-1'});
    expect(headers, isNull);
    expect(authenticated, isTrue);
    return ApiResponse(code: 200, message: 'OK', data: data);
  }

  @override
  Future<ApiResponse> postWithoutUnauthorizedRecovery(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    calls.add('POST');
    if (allowMic) {
      lastBody = body;
      return ApiResponse(
        code: 200,
        message: 'OK',
        data: <String, Object?>{...body!, 'occupied': true},
      );
    }
    if (!allowEntry) fail('Read invoked POST');
    expect(<String>[
      const BackendRouteCatalog().enterRoom,
      const BackendRouteCatalog().reconnectRoom,
    ], contains(path));
    return ApiResponse(code: 200, message: 'OK', data: data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API call: ${invocation.memberName}');
}

class _Tokens implements RtcTokenRepository {
  int calls = 0;

  @override
  Future<RtcCredentials> buildRtcToken({
    required String roomId,
    required int currentUserId,
    String? requestId,
  }) async {
    calls++;
    throw StateError('Authority reads must not request RTC credentials');
  }
}
