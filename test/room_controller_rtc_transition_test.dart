import 'dart:async';

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

  test('occupied-muted direct grant never publishes audio', () async {
    final _OccupiedMutedRoleAwareRoomRepository repository =
        _OccupiedMutedRoleAwareRoomRepository();
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
    expect(rtc.reconnects.last.role, 'broadcaster');
    expect(rtc.audioStates, <bool>[false]);
    expect(controller.snapshot?.seats.single.state, MicSeatState.occupiedMuted);
    expect(controller.micMuted, isTrue);
  });

  test('occupied-muted invite acceptance never publishes audio', () async {
    final _OccupiedMutedApprovalRoleAwareRoomRepository repository =
        _OccupiedMutedApprovalRoleAwareRoomRepository();
    final MockRoomOperationsRepository operations =
        MockRoomOperationsRepository();
    operations.seedMicRequestForQa(
      MicAccessRequest(
        id: 'invite-occupied-muted',
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
        requestId: 'invite-occupied-muted',
        accepted: true,
      ),
      isTrue,
    );
    expect(rtc.reconnects.last.role, 'broadcaster');
    expect(rtc.audioStates, <bool>[false]);
    expect(controller.snapshot?.seats.single.state, MicSeatState.occupiedMuted);
    expect(controller.micMuted, isTrue);
  });

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

  test(
    'authoritative mute arriving during local unmute keeps native audio disabled',
    () async {
      final _RoleAwareRoomRepository repository = _RoleAwareRoomRepository();
      final _DeferredTrackingRtcAdapter rtc = _DeferredTrackingRtcAdapter();
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
      expect(await controller.toggleMicrophone(), isTrue);
      expect(rtc.audioStates, <bool>[true, false]);

      final Completer<void> pendingEnable = Completer<void>();
      rtc.pendingEnable = pendingEnable;
      final Future<bool> unmute = controller.toggleMicrophone();
      for (
        int attempt = 0;
        attempt < 3 && rtc.audioStates.length < 3;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(rtc.audioStates, <bool>[true, false, true]);

      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.mutedInRoom,
          payload: <String, Object?>{},
        ),
      );
      expect(controller.mutedInRoom, isTrue);
      pendingEnable.complete();
      expect(await unmute, isTrue);
      for (int attempt = 0; attempt < 3 && rtc.audioStates.last; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(rtc.audioStates.last, isFalse);
      expect(rtc.audioStates.where((bool enabled) => enabled), <bool>[
        true,
        true,
      ]);
      expect(controller.mutedInRoom, isTrue);
      expect(controller.snapshot?.seats.single.state, MicSeatState.occupied);
    },
  );

  test(
    'dispose cancels a pending RTC reconcile and queues final leave',
    () async {
      final _RoleAwareRoomRepository repository = _RoleAwareRoomRepository();
      final _DeferredTrackingRtcAdapter rtc = _DeferredTrackingRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = _controller(
        repository: repository,
        rtc: rtc,
        realtime: realtime,
      );

      await controller.join();
      expect(await controller.requestMic(4), isTrue);
      expect(rtc.audioStates, <bool>[true]);

      final Completer<void> pendingReconnect = Completer<void>();
      rtc.pendingReconnect = pendingReconnect;
      final Future<void> reconnect = controller.reconnect();
      for (
        int attempt = 0;
        attempt < 5 && rtc.reconnects.length < 2;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(rtc.reconnects, hasLength(2));

      final int audioCallsBeforeDispose = rtc.audioStates.length;
      controller.dispose();
      pendingReconnect.complete();
      await reconnect;
      for (int attempt = 0; attempt < 5 && rtc.leaveCalls == 0; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(rtc.leaveCalls, 1);
      expect(rtc.audioStates.length, audioCallsBeforeDispose);
      expect(rtc.audioStates.where((bool enabled) => enabled), <bool>[true]);
      await realtime.dispose();
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
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {}

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

class _OccupiedMutedRoleAwareRoomRepository extends _RoleAwareRoomRepository {
  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    final RoomSnapshot snapshot = await super.reconnectRoom(
      roomId: roomId,
      currentUserId: currentUserId,
    );
    return snapshot.copyWith(
      seats: <MicSeat>[
        for (final MicSeat seat in snapshot.seats)
          seat.userId == currentUserId
              ? seat.copyWith(state: MicSeatState.occupiedMuted)
              : seat,
      ],
    );
  }
}

class _OccupiedMutedApprovalRoleAwareRoomRepository
    extends _ApprovalRoleAwareRoomRepository {
  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    final RoomSnapshot snapshot = await super.reconnectRoom(
      roomId: roomId,
      currentUserId: currentUserId,
    );
    return snapshot.copyWith(
      seats: <MicSeat>[
        for (final MicSeat seat in snapshot.seats)
          seat.userId == currentUserId
              ? seat.copyWith(state: MicSeatState.occupiedMuted)
              : seat,
      ],
    );
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
  int leaveCalls = 0;

  @override
  Future<void> join(RtcCredentials credentials) async => joins.add(credentials);

  @override
  Future<void> reconnect(RtcCredentials credentials) async =>
      reconnects.add(credentials);

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async =>
      audioStates.add(enabled);

  @override
  Future<void> leave() async {
    leaveCalls += 1;
  }
}

class _DeferredTrackingRtcAdapter extends _TrackingRtcAdapter {
  Completer<void>? pendingEnable;
  Completer<void>? pendingReconnect;

  @override
  Future<void> reconnect(RtcCredentials credentials) {
    reconnects.add(credentials);
    final Completer<void>? pending = pendingReconnect;
    if (pending != null) {
      return pending.future;
    }
    return Future<void>.value();
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) {
    audioStates.add(enabled);
    if (enabled && pendingEnable != null) {
      return pendingEnable!.future;
    }
    return Future<void>.value();
  }
}
