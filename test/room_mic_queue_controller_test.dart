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
    'accepting an invite cannot restore a snapshot after leave invalidates it',
    () async {
      final MockRoomOperationsRepository operations =
          MockRoomOperationsRepository();
      operations.seedMicRequestForQa(
        MicAccessRequest(
          id: 'invite-1',
          member: RoomMember(
            userId: 10001,
            name: '我',
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
          ),
          seatNumber: 4,
          status: MicRequestStatus.pending,
          createdAt: DateTime.utc(2026, 8, 25),
          type: MicRequestType.invite,
          requestedByUserId: 20001,
          subjectUserId: 10001,
          targetAction: MicRequestTargetAction.accept,
        ),
      );
      final _DelayedApprovalRoomRepository repository =
          _DelayedApprovalRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: 'approval-room',
        title: '审批房',
        currentUserId: 10001,
        accessToken: 'test-token',
        repository: repository,
        rtcAdapter: const SnapshotOnlyRtcAdapter(),
        realtimeGateway: realtime,
        roomOperationsRepository: operations,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(controller.status, RoomSessionStatus.joined);
      final Future<bool> accepting = controller.resolveMicInvite(
        requestId: 'invite-1',
        accepted: true,
      );
      await repository.reconnectStarted.future;

      expect(await controller.leaveRoom(), isTrue);
      repository.releaseReconnect.complete();

      expect(await accepting, isFalse);
      expect(controller.status, RoomSessionStatus.left);
      expect(controller.snapshot?.title, '审批房');
    },
  );
}

class _DelayedApprovalRoomRepository extends MockRoomRepository {
  final Completer<void> reconnectStarted = Completer<void>();
  final Completer<void> releaseReconnect = Completer<void>();
  RoomSnapshot? _entered;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final RoomSnapshot snapshot = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    _entered = snapshot.copyWith(
      title: '审批房',
      accessMode: 'APPROVAL',
      transportMode: RoomTransportMode.snapshotOnly,
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: roomId,
        userId: currentUserId,
      ),
    );
    return _entered!;
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    reconnectStarted.complete();
    await releaseReconnect.future;
    return _entered!.copyWith(title: '旧的恢复快照');
  }
}
