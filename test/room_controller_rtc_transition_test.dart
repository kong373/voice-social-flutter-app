import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  test(
    'mic grant and leave reconcile the authoritative RTC role and token',
    () async {
      final _RoleAwareRoomRepository repository = _RoleAwareRoomRepository();
      final _TrackingRtcAdapter rtc = _TrackingRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = _controller(
        repository: repository,
        rtc: rtc,
        realtime: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(rtc.joins.single.role, 'audience');
      expect(rtc.audioStates, isEmpty);
      expect(await controller.requestMic(4), isTrue);
      expect(rtc.reconnects.last.role, 'broadcaster');
      expect(rtc.audioStates, <bool>[true]);
      expect(controller.snapshot?.rtc.role, 'broadcaster');

      expect(await controller.leaveMic(), isTrue);
      expect(rtc.reconnects.last.role, 'audience');
      expect(rtc.audioStates, <bool>[true, false]);
      expect(controller.snapshot?.rtc.role, 'audience');
    },
  );

  test(
    'accepted mic invite reconciles RTC before exposing the new snapshot',
    () async {
      final _ApprovalRoleAwareRoomRepository repository =
          _ApprovalRoleAwareRoomRepository();
      final MockRoomOperationsRepository operations =
          MockRoomOperationsRepository();
      operations.seedMicRequestForQa(
        MicAccessRequest(
          id: 'invite-1',
          roomId: 'room-42',
          member: const RoomMember(
            userId: 10001,
            name: '我',
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
          ),
          seatNumber: 4,
          status: MicRequestStatus.pending,
          createdAt: DateTime.utc(2030, 1, 1),
          type: MicRequestType.invite,
          requestedByUserId: 20001,
          subjectUserId: 10001,
          targetAction: MicRequestTargetAction.accept,
        ),
      );
      final _TrackingRtcAdapter rtc = _TrackingRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = _controller(
        repository: repository,
        rtc: rtc,
        realtime: realtime,
        operations: operations,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(
        await controller.resolveMicInvite(
          requestId: 'invite-1',
          accepted: true,
        ),
        isTrue,
      );
      expect(rtc.reconnects.last.role, 'broadcaster');
      expect(rtc.audioStates, <bool>[true]);
      expect(controller.snapshot?.rtc.role, 'broadcaster');
    },
  );

  test(
    'authoritative mic revoke stops publication before applying audience token',
    () async {
      final _RevokingRoleAwareRoomRepository repository =
          _RevokingRoleAwareRoomRepository();
      final _TrackingRtcAdapter rtc = _TrackingRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = _controller(
        repository: repository,
        rtc: rtc,
        realtime: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(await controller.requestMic(4), isTrue);
      repository.revokeMic();
      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.takeDownMic,
          payload: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(rtc.audioStates, <bool>[true, false, false]);
      expect(rtc.reconnects.last.role, 'audience');
      expect(controller.snapshot?.rtc.role, 'audience');
      expect(controller.isOnMic, isFalse);
    },
  );

  test(
    'authoritative room mute immediately stops audio and does not republish on unmute',
    () async {
      final _RoleAwareRoomRepository repository = _RoleAwareRoomRepository();
      final _TrackingRtcAdapter rtc = _TrackingRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = _controller(
        repository: repository,
        rtc: rtc,
        realtime: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(await controller.requestMic(4), isTrue);
      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.mutedInRoom,
          payload: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rtc.audioStates, <bool>[true, false]);

      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.unmutedInRoom,
          payload: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rtc.audioStates, <bool>[true, false]);
    },
  );
}

RoomController _controller({
  required _RoleAwareRoomRepository repository,
  required _TrackingRtcAdapter rtc,
  required MockRoomRealtimeGateway realtime,
  MockRoomOperationsRepository? operations,
}) => RoomController(
  roomId: 'room-42',
  title: '房间',
  currentUserId: 10001,
  accessToken: 'test-access-token',
  repository: repository,
  rtcAdapter: rtc,
  realtimeGateway: realtime,
  roomOperationsRepository: operations,
);

class _RoleAwareRoomRepository extends MockRoomRepository {
  bool _onMic = false;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => _snapshot(role: 'audience', onMic: false);

  @override
  Future<void> requestMic(int backendMicIndex) async {
    _onMic = true;
  }

  @override
  Future<void> leaveMic() async {
    _onMic = false;
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async =>
      _snapshot(role: _onMic ? 'broadcaster' : 'audience', onMic: _onMic);

  RoomSnapshot _snapshot({required String role, required bool onMic}) {
    return RoomSnapshot(
      roomId: 'room-42',
      roomCode: 'room-42',
      title: '房间',
      topic: '',
      ownerId: 20001,
      role: onMic ? RoomRole.speaker : RoomRole.listener,
      seats: <MicSeat>[
        MicSeat(
          number: 4,
          backendIndex: 4,
          state: onMic ? MicSeatState.occupied : MicSeatState.available,
          userId: onMic ? 10001 : null,
          userName: onMic ? '我' : null,
          userRole: onMic ? RoomRole.speaker : RoomRole.listener,
        ),
      ],
      rtc: _credentials(role),
      transportMode: RoomTransportMode.interactive,
      publicScreenEnabled: true,
      pictureMessagesAllowed: false,
      autoLockMic: false,
      giftCatalogAvailable: true,
      giftBalance: 100,
      onlineCount: 1,
      accessMode: '',
    );
  }
}

class _ApprovalRoleAwareRoomRepository extends _RoleAwareRoomRepository {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => _snapshot(role: 'audience', onMic: false).copyWith(
    transportMode: RoomTransportMode.interactive,
    // Approval mode is provided by the first-party operations capability in
    // this test; the room snapshot itself remains provider-neutral.
    accessMode: 'APPROVAL',
  );

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async => _snapshot(
    role: 'broadcaster',
    onMic: true,
  ).copyWith(accessMode: 'APPROVAL');
}

class _RevokingRoleAwareRoomRepository extends _RoleAwareRoomRepository {
  void revokeMic() {
    _onMic = false;
  }
}

RtcCredentials _credentials(String role) => RtcCredentials(
  provider: 'agora',
  appId: 'test-public-app-id',
  token: '$role-token',
  channelId: 'room-42',
  uid: 10001,
  role: role,
  expiresAt: DateTime.utc(2030, 1, 1, 13),
  ttlSeconds: 3600,
);

class _TrackingRtcAdapter implements RtcAdapter {
  final List<RtcCredentials> joins = <RtcCredentials>[];
  final List<RtcCredentials> reconnects = <RtcCredentials>[];
  final List<bool> audioStates = <bool>[];

  @override
  Future<void> join(RtcCredentials credentials) async => joins.add(credentials);

  @override
  Future<void> reconnect(RtcCredentials credentials) async =>
      reconnects.add(credentials);

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async =>
      audioStates.add(enabled);

  @override
  Future<void> leave() async {}
}
