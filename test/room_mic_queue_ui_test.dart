import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  testWidgets(
    'member mic sheet only exposes requests targeted at the authenticated member',
    (WidgetTester tester) async {
      final MockRoomOperationsRepository operations =
          MockRoomOperationsRepository();
      operations.seedMicRequestForQa(
        _request(
          id: 'request-other',
          userId: 20005,
          name: '其他申请人',
          seatNumber: 4,
        ),
      );
      operations.seedMicRequestForQa(
        _request(id: 'request-self', userId: 10001, name: '我', seatNumber: 5),
      );
      final _ApprovalRoomRepository roomRepository = _ApprovalRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: 'approval-room',
        title: '审批房',
        currentUserId: 10001,
        accessToken: 'test-token',
        repository: roomRepository,
        rtcAdapter: const SnapshotOnlyRtcAdapter(),
        realtimeGateway: realtime,
        roomOperationsRepository: operations,
      );
      final AppDependencies dependencies = AppDependencies.mock();
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.status, RoomSessionStatus.joined);

      await tester.tap(find.text('上麦'));
      await tester.pumpAndSettle();

      expect(find.text('你正在等待 5 号麦审批'), findsOneWidget);
      expect(
        find.byKey(const Key('approval-mic-request-cancel')),
        findsOneWidget,
      );
      expect(find.text('其他申请人'), findsNothing);
      expect(find.text('你正在等待 4 号麦审批'), findsNothing);
    },
  );

  testWidgets(
    'manager queue renders REQUEST actions but never treats INVITE as a manager request',
    (WidgetTester tester) async {
      final MockRoomOperationsRepository repository =
          MockRoomOperationsRepository();
      repository.seedMicRequestForQa(
        _request(
          id: 'request-member',
          userId: 20005,
          name: '申请成员',
          seatNumber: 4,
        ),
      );
      repository.seedMicRequestForQa(
        _request(
          id: 'invite-member',
          userId: 20006,
          name: '被邀请成员',
          seatNumber: 5,
          type: MicRequestType.invite,
          requestedByUserId: 20001,
          targetAction: MicRequestTargetAction.accept,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: RoomManagementPage(
            roomId: 'approval-room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            seats: const <MicSeat>[
              MicSeat(
                number: 4,
                backendIndex: 4,
                state: MicSeatState.available,
              ),
              MicSeat(
                number: 5,
                backendIndex: 5,
                state: MicSeatState.available,
              ),
            ],
            roomTitle: '审批房',
            coordinationMode: MicCoordinationMode.approval,
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('上麦申请'));
      await tester.pumpAndSettle();

      expect(find.text('申请成员'), findsOneWidget);
      expect(find.text('被邀请成员'), findsNothing);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('同意'), findsOneWidget);
      expect(find.text('接受邀请'), findsNothing);

      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();
      expect(find.text('当前没有待处理的上麦申请'), findsOneWidget);
      final List<MicAccessRequest> requests = await repository.fetchMicRequests(
        'approval-room',
      );
      expect(
        requests.where(
          (MicAccessRequest request) => request.isRequest && request.isPending,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'explicit DIRECT room mode overrides a repository approval response from another room',
    (WidgetTester tester) async {
      final MockRoomOperationsRepository repository =
          MockRoomOperationsRepository();
      repository.seedMicRequestForQa(
        _request(
          id: 'stale-approval-request',
          userId: 20005,
          name: '上一间房的申请',
          seatNumber: 4,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: RoomManagementPage(
            roomId: 'direct-room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            seats: const <MicSeat>[],
            roomTitle: '直通房',
            coordinationMode: MicCoordinationMode.direct,
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('上麦申请'), findsNothing);
      expect(find.text('成员治理'), findsOneWidget);
      expect(find.text('上一间房的申请'), findsNothing);
    },
  );
}

MicAccessRequest _request({
  required String id,
  required int userId,
  required String name,
  required int seatNumber,
  MicRequestType type = MicRequestType.request,
  int? requestedByUserId,
  MicRequestTargetAction targetAction = MicRequestTargetAction.cancel,
}) {
  return MicAccessRequest(
    id: id,
    member: RoomMember(
      userId: userId,
      name: name,
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
    seatNumber: seatNumber,
    status: MicRequestStatus.pending,
    createdAt: DateTime.utc(2026, 8, 25),
    type: type,
    requestedByUserId: requestedByUserId ?? userId,
    subjectUserId: userId,
    targetAction: targetAction,
  );
}

class _ApprovalRoomRepository extends MockRoomRepository {
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
    return snapshot.copyWith(
      accessMode: 'APPROVAL',
      transportMode: RoomTransportMode.snapshotOnly,
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: roomId,
        userId: currentUserId,
      ),
    );
  }

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
      accessMode: 'APPROVAL',
      transportMode: RoomTransportMode.snapshotOnly,
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: roomId,
        userId: currentUserId,
      ),
    );
  }
}
