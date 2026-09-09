import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'ordinary mic request expires exactly one minute after creation',
    () async {
      final repository = MockRoomOperationsRepository();
      await repository.submitMicRequest(
        roomId: 'room',
        userId: 10001,
        seatNumber: 6,
      );
      final request = (await repository.fetchMicRequests('room')).single;
      expect(
        request.expiresAt?.difference(request.createdAt),
        const Duration(minutes: 1),
      );
    },
  );

  test(
    'rejected requests block retries for a minute without another row',
    () async {
      final repository = MockRoomOperationsRepository();
      await repository.submitMicRequest(
        roomId: 'room',
        userId: 10001,
        seatNumber: 6,
      );
      final request = (await repository.fetchMicRequests('room')).single;
      await repository.resolveMicRequest(
        requestId: request.id,
        accepted: false,
        expectedVersion: request.version,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          repository.submitMicRequest(
            roomId: 'room',
            userId: 10001,
            seatNumber: 7,
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              '上麦申请被拒绝后，请等待1分钟再申请',
            ),
          ),
        );
      }
      final rows = await repository.fetchMicRequests('room');
      expect(rows, hasLength(1));
      expect(rows.single.status, MicRequestStatus.rejected);
      expect(rows.single.resolvedAt, isNotNull);
    },
  );

  test(
    'a rejection older than a minute allows a distinct new request',
    () async {
      final repository = MockRoomOperationsRepository();
      repository.seedMicRequestForQa(
        _request(
          status: MicRequestStatus.rejected,
          resolvedAt: DateTime.now().subtract(const Duration(seconds: 61)),
        ),
      );
      await repository.submitMicRequest(
        roomId: 'room',
        userId: 10001,
        seatNumber: 6,
      );
      final rows = await repository.fetchMicRequests('room');
      expect(rows, hasLength(2));
      expect(rows.first.status, MicRequestStatus.rejected);
      expect(rows.last.status, MicRequestStatus.pending);
      expect(rows.last.id, isNot(rows.first.id));
    },
  );

  test(
    'expired requests cannot be approved or remain a pending UI row',
    () async {
      final repository = MockRoomOperationsRepository();
      repository.seedMicRequestForQa(
        _request(status: MicRequestStatus.pending),
      );
      await expectLater(
        repository.resolveMicRequest(
          requestId: 'old-request',
          accepted: true,
          expectedVersion: 0,
        ),
        throwsA(isA<ApiException>()),
      );
      final row = (await repository.fetchMicRequests('room')).single;
      expect(row.status, MicRequestStatus.expired);
      expect(row.targetAction, MicRequestTargetAction.none);
    },
  );
}

MicAccessRequest _request({
  required MicRequestStatus status,
  DateTime? resolvedAt,
}) {
  final now = DateTime.now();
  return MicAccessRequest(
    id: 'old-request',
    roomId: 'room',
    member: const RoomMember(
      userId: 10001,
      name: '我',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
    seatNumber: 6,
    status: status,
    createdAt: now.subtract(const Duration(minutes: 2)),
    expiresAt: now.subtract(const Duration(minutes: 1)),
    resolvedAt: resolvedAt,
    requestedByUserId: 10001,
    subjectUserId: 10001,
    targetAction: status == MicRequestStatus.pending
        ? MicRequestTargetAction.cancel
        : MicRequestTargetAction.none,
  );
}
