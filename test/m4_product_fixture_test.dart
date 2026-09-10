import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

import '../integration_test/m4_first_party_live_integration_test.dart' as m4;

const _roomA = '11111111-1111-4111-8111-111111111111';
const _roomB = '22222222-2222-4222-8222-222222222222';
const _ordinaryRoom = '33333333-3333-4333-8333-333333333333';
const _user = 41;

void main() {
  testWidgets(
    'M4 explicit choices submit actual preset and sex, never auto-submit',
    (tester) async {
      final controller = _RegistrationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(controller: controller)),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '昵称'),
        'm4-fixture',
      );
      await tester.tap(find.text('完成注册'));
      await tester.pump();
      expect(controller.profiles, isEmpty);
      await m4.selectM4RegistrationChoices(tester);
      expect(controller.profiles, isEmpty);
      await tester.ensureVisible(find.text('完成注册'));
      await tester.tap(find.text('完成注册'));
      await tester.pump();
      final profile = controller.profiles.single;
      expect(profile.nickname, 'm4-fixture');
      expect(profile.avatar?.reference, 'avatar-preset-sea');
      expect(profile.sex, 0);
      expect(profile.birthday, isNull);
    },
  );

  test(
    'two owned PUBLIC/PASSWORD rooms selected and both admissions cleaned',
    () async {
      final exits = <String>[];
      final pair = await m4.selectM4OwnedRooms(
        rooms: [_room(_roomA), _room(_roomA), _room(_roomB, locked: true)],
        currentUserId: _user,
        enter: (room) async =>
            _snapshot(room.id, mode: room.isLocked ? 'PASSWORD' : 'PUBLIC'),
        exit: (id) async => exits.add(id),
      );
      expect(pair.moderation.id, _roomA);
      expect(pair.pkRecovery.id, _roomB);
      expect(exits, [_roomA, _roomB]);
    },
  );

  for (final mode in ['APPROVAL', 'DIRECT', '', 'UNKNOWN']) {
    test('owned legacy/unknown $mode fails and still exits', () async {
      final exits = <String>[];
      await expectLater(
        m4.selectM4OwnedRooms(
          rooms: [_room(_roomA), _room(_roomB)],
          currentUserId: _user,
          enter: (room) async => _snapshot(room.id, mode: mode),
          exit: (id) async => exits.add(id),
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(exits, [_roomA]);
    });
  }

  test(
    'duplicate, closed and foreign owned projections cannot form a pair',
    () async {
      final entries = <String>[];
      await expectLater(
        m4.selectM4OwnedRooms(
          rooms: [
            _room(_roomA),
            _room(_roomA),
            _room(_roomB, closed: true),
            _room(_ordinaryRoom, owner: 99),
          ],
          currentUserId: _user,
          enter: (room) async {
            entries.add(room.id);
            return _snapshot(room.id);
          },
          exit: (_) async {},
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(entries, [_roomA]);
    },
  );

  test(
    'closed management snapshot is not OPEN even if stale card says open',
    () {
      expect(
        () => m4.requireM4OwnedRoom(
          _room(_roomA),
          _snapshot(_roomA, closed: true),
          _user,
        ),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test(
    'ordinary selection uses home candidate and skips current moderator',
    () async {
      final exits = <String>[];
      final selected = await m4.selectM4OrdinaryRoom(
        candidates: [
          _room(_roomA),
          _room(_roomB, owner: 99),
          _room(_ordinaryRoom, owner: 99),
        ],
        currentUserId: _user,
        enter: (room) async => _snapshot(
          room.id,
          owner: 99,
          role: room.id == _roomB ? RoomRole.moderator : RoomRole.listener,
        ),
        exit: (id) async => exits.add(id),
      );
      expect(selected.id, _ordinaryRoom);
      expect(exits, [_roomB, _ordinaryRoom]);
    },
  );

  for (final role in [
    RoomRole.owner,
    RoomRole.moderator,
    RoomRole.platformModerator,
    RoomRole.guest,
    RoomRole.speaker,
  ]) {
    test('non-ordinary $role cannot trigger submit or cancel', () async {
      var writes = 0;
      await expectLater(
        m4.exerciseM4OrdinaryMicQueue(
          room: _room(_ordinaryRoom, owner: 99),
          currentUserId: _user,
          entered: _snapshot(_ordinaryRoom, owner: 99, role: role),
          reconnect: () async => _ordinary(),
          fetch: () async => [],
          submit: (_) async => writes++,
          cancel: (_) async => writes++,
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(writes, 0);
    });
  }

  test(
    'role changed on reconnect cannot use earlier ordinary authority',
    () async {
      var writes = 0;
      await expectLater(
        m4.exerciseM4OrdinaryMicQueue(
          room: _room(_ordinaryRoom, owner: 99),
          currentUserId: _user,
          entered: _ordinary(),
          reconnect: () async =>
              _snapshot(_ordinaryRoom, owner: 99, role: RoomRole.moderator),
          fetch: () async => [],
          submit: (_) async => writes++,
          cancel: (_) async => writes++,
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(writes, 0);
    },
  );

  test(
    'staff flag, password and wrong room cannot count as ordinary PUBLIC',
    () {
      for (final snapshot in [
        _snapshot(
          _ordinaryRoom,
          owner: 99,
          role: RoomRole.listener,
          staff: true,
        ),
        _snapshot(
          _ordinaryRoom,
          owner: 99,
          role: RoomRole.listener,
          mode: 'PASSWORD',
        ),
        _snapshot(_roomB, owner: 99, role: RoomRole.listener),
      ]) {
        expect(
          () => m4.requireM4OrdinaryApplicant(
            _room(_ordinaryRoom, owner: 99),
            snapshot,
            _user,
          ),
          throwsA(isA<TestFailure>()),
        );
      }
    },
  );

  test(
    'ordinary seat excludes special 1, occupied/offline, locked, and out-of-range',
    () {
      final snapshot = _ordinary().copyWith(
        seats: [
          _seat(1),
          _seat(2, state: MicSeatState.occupied, user: 7),
          _seat(3, state: MicSeatState.locked),
          _seat(10),
          _seat(9),
        ],
      );
      expect(m4.selectM4OrdinarySeat(snapshot, _user), 9);
      expect(
        () => m4.selectM4OrdinarySeat(
          _ordinary().copyWith(seats: [_seat(1)]),
          _user,
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => m4.selectM4OrdinarySeat(
          _ordinary().copyWith(
            seats: [_seat(9, state: MicSeatState.occupied, user: _user)],
          ),
          _user,
        ),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test(
    'ordinary sequence requires exact GET after submit and cancel',
    () async {
      final events = <String>[];
      var rows = <MicAccessRequest>[];
      await m4.exerciseM4OrdinaryMicQueue(
        room: _room(_ordinaryRoom, owner: 99),
        currentUserId: _user,
        entered: _ordinary(),
        reconnect: () async {
          events.add('reconnect');
          return _ordinary();
        },
        fetch: () async {
          events.add('GET');
          return rows;
        },
        submit: (seat) async {
          events.add('submit:$seat');
          rows = [_request()];
        },
        cancel: (request) async {
          events.add('cancel:${request.id}');
          rows = [_request(status: MicRequestStatus.cancelled)];
        },
      );
      expect(events, [
        'reconnect',
        'GET',
        'submit:2',
        'GET',
        'cancel:request',
        'GET',
      ]);
    },
  );

  for (final status in [
    MicRequestStatus.pending,
    MicRequestStatus.approved,
    MicRequestStatus.expired,
  ]) {
    test(
      'cancel HTTP success with $status readback is not compensation',
      () async {
        var rows = <MicAccessRequest>[];
        await expectLater(
          m4.exerciseM4OrdinaryMicQueue(
            room: _room(_ordinaryRoom, owner: 99),
            currentUserId: _user,
            entered: _ordinary(),
            reconnect: () async => _ordinary(),
            fetch: () async => rows,
            submit: (_) async {
              rows = [_request()];
            },
            cancel: (_) async {
              rows = [_request(status: status)];
            },
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );
  }

  test(
    'wrong actor or room pending receipt is never cancelled as own submission',
    () async {
      for (final invalid in [_request(user: 7), _request(room: _roomB)]) {
        var rows = <MicAccessRequest>[];
        var cancels = 0;
        await expectLater(
          m4.exerciseM4OrdinaryMicQueue(
            room: _room(_ordinaryRoom, owner: 99),
            currentUserId: _user,
            entered: _ordinary(),
            reconnect: () async => _ordinary(),
            fetch: () async => rows,
            submit: (_) async {
              rows = [invalid];
            },
            cancel: (_) async {
              cancels++;
            },
          ),
          throwsA(isA<TestFailure>()),
        );
        expect(cancels, 0);
      }
    },
  );
}

DiscoveryRoom _room(
  String id, {
  int owner = _user,
  bool closed = false,
  bool locked = false,
}) => DiscoveryRoom(
  id: id,
  code: '10001',
  title: 'fixture',
  topic: '',
  occupiedSeats: 0,
  isSpeaking: false,
  isFavorite: false,
  ownerUserId: owner,
  isClosed: closed,
  isLocked: locked,
);

RoomSnapshot _ordinary() =>
    _snapshot(_ordinaryRoom, owner: 99, role: RoomRole.listener);
RoomSnapshot _snapshot(
  String id, {
  int owner = _user,
  RoomRole role = RoomRole.owner,
  String mode = 'PUBLIC',
  bool closed = false,
  bool staff = false,
}) => RoomSnapshot(
  roomId: id,
  roomCode: '10001',
  title: 'fixture',
  topic: '',
  ownerId: owner,
  role: role,
  seats: [_seat(1), _seat(2)],
  rtc: const RtcCredentials(
    solution: RtcSolution.unknown,
    token: '',
    channelId: '',
  ),
  publicScreenEnabled: true,
  pictureMessagesAllowed: false,
  autoLockMic: false,
  giftCatalogAvailable: false,
  giftBalance: null,
  accessMode: mode,
  transportMode: RoomTransportMode.snapshotOnly,
  sessionId: _roomA,
  closedRoomAccess: closed,
  platformStaff: staff,
);
MicSeat _seat(
  int number, {
  MicSeatState state = MicSeatState.available,
  int? user,
}) => MicSeat(
  number: number,
  backendIndex: number,
  state: state,
  userId: user,
  isOnline: false,
);
MicAccessRequest _request({
  MicRequestStatus status = MicRequestStatus.pending,
  int user = _user,
  String room = _ordinaryRoom,
}) => MicAccessRequest(
  id: 'request',
  roomId: room,
  requestedByUserId: user,
  subjectUserId: user,
  member: RoomMember(
    userId: user,
    name: 'fixture',
    role: RoomRole.listener,
    presence: RoomMemberPresence.listener,
  ),
  seatNumber: 2,
  status: status,
  createdAt: DateTime.utc(2026, 9, 10),
);

class _RegistrationController extends AuthController {
  factory _RegistrationController() {
    final manager = AuthSessionManager(MemoryKeyValueStore());
    return _RegistrationController._(manager);
  }
  _RegistrationController._(AuthSessionManager manager)
    : super(
        repository: const MockAuthRepository(),
        sessionManager: manager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: manager,
        ),
      );
  final profiles = <RegistrationProfile>[];
  @override
  Future<bool> completeRegistration(RegistrationProfile profile) async {
    profiles.add(profile);
    return false;
  }
}
