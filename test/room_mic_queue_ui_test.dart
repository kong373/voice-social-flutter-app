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
    'occupied requested seat requires explicit alternative and keeps request version',
    (tester) async {
      final repo = MockRoomOperationsRepository();
      repo.seedMicRequestForQa(
        MicAccessRequest(
          id: 'alternate-request',
          roomId: 'approval-room',
          member: const RoomMember(
            userId: 20005,
            name: '申请成员',
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
          ),
          seatNumber: 4,
          version: 7,
          status: MicRequestStatus.pending,
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: RoomManagementPage(
            roomId: 'approval-room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            repositoryOverride: repo,
            seats: const [
              MicSeat(
                number: 1,
                backendIndex: 1,
                state: MicSeatState.available,
              ),
              MicSeat(
                number: 4,
                backendIndex: 4,
                state: MicSeatState.occupied,
                userId: 20006,
              ),
              MicSeat(number: 8, backendIndex: 8, state: MicSeatState.locked),
              MicSeat(
                number: 9,
                backendIndex: 9,
                state: MicSeatState.available,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('上麦申请'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();
      expect(find.text('原申请麦位不可用，请选择备用空位'), findsOneWidget);
      expect(find.byKey(const Key('resolve-mic-seat-1')), findsNothing);
      expect(find.byKey(const Key('resolve-mic-seat-4')), findsNothing);
      expect(find.byKey(const Key('resolve-mic-seat-8')), findsNothing);
      expect(
        (await repo.fetchMicRequests('approval-room')).single.isPending,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('resolve-mic-seat-9')));
      await tester.pumpAndSettle();
      final receipt = (await repo.fetchMicRequests('approval-room')).single;
      expect(receipt.isApproved, isTrue);
      expect(receipt.version, 8);
      expect(receipt.seatNumber, 4);
      expect(receipt.assignedSeatNumber, 9);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'S02 nine-seat stage and ordinary picker preserve ninth, exclude first',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: '9527',
        title: '九麦',
        currentUserId: 10001,
        accessToken: 'test',
        repository: _NineEmptySeatsRepository(),
        rtcAdapter: const SnapshotOnlyRtcAdapter(),
        realtimeGateway: realtime,
        roomOperationsRepository: MockRoomOperationsRepository(),
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: AppDependencies.mock(),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 号特殊麦 · '), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('video-room-seat-grid')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(find.text('9 号麦').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('上麦'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approval-mic-seat-1')), findsNothing);
      expect(find.byKey(const Key('approval-mic-seat-9')), findsOneWidget);
      await tester.tap(find.byKey(const Key('approval-mic-seat-9')));
      await tester.pumpAndSettle();
      expect(controller.micRequests.single.seatNumber, 9);
      expect(controller.isOnMic, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  final ValueVariant<Size> viewports = ValueVariant<Size>(<Size>{
    const Size(800, 600),
    const Size(375, 667),
  });
  for (final MicRequestStatus status in <MicRequestStatus>[
    MicRequestStatus.approved,
    MicRequestStatus.rejected,
  ]) {
    testWidgets(
      'open member sheet reflects authoritative ${status.name} without reopening',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(viewports.currentValue);
        tester.platformDispatcher.textScaleFactorTestValue =
            viewports.currentValue!.width == 375 ? 1.3 : 1;
        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final MockRoomOperationsRepository operations =
            MockRoomOperationsRepository();
        operations.seedMicRequestForQa(
          _request(id: 'request-self', userId: 10001, name: '我', seatNumber: 5),
        );
        final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
        final RoomController controller = RoomController(
          roomId: 'approval-room',
          title: '审批房',
          currentUserId: 10001,
          accessToken: 'test-token',
          repository: _ApprovalRoomRepository(),
          rtcAdapter: const SnapshotOnlyRtcAdapter(),
          realtimeGateway: realtime,
          roomOperationsRepository: operations,
        );
        addTearDown(() async {
          controller.dispose();
          await realtime.dispose();
        });
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: AppDependencies.mock(),
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: VideoRuntimeRoomPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('上麦'));
        await tester.pumpAndSettle();
        expect(find.text('你正在等待 5 号麦审批'), findsOneWidget);

        operations.seedMicRequestForQa(
          _request(
            id: 'request-self',
            userId: 10001,
            name: '我',
            seatNumber: 5,
            status: status,
          ),
        );
        // Deliver a new server queue projection, not a user refresh/navigation.
        await controller.refreshMicRequests();
        await tester.pumpAndSettle();

        expect(find.text('审批上麦'), findsOneWidget);
        expect(find.text('你正在等待 5 号麦审批'), findsNothing);
        expect(
          find.byKey(const Key('approval-mic-request-cancel')),
          findsNothing,
        );
        expect(
          find.text(
            status == MicRequestStatus.approved ? '最近状态：已同意' : '最近状态：已拒绝',
          ),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.text('审批上麦'))).pop();
        await tester.pumpAndSettle();
        await controller.refreshMicRequests();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
      variant: viewports,
    );
  }

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
    'legacy DIRECT mode cannot hide current-room member mic requests from the owner',
    (WidgetTester tester) async {
      final _TrackedMicQueueRepository repository =
          _TrackedMicQueueRepository();
      repository.seedMicRequestForQa(
        _request(
          id: 'current-room-mic-request',
          userId: 20005,
          name: '当前房间申请人',
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

      expect(repository.lastMicQueueRoomId, 'direct-room');
      expect(find.text('上麦申请 1'), findsOneWidget);
      expect(find.text('成员治理'), findsOneWidget);
      await tester.tap(find.text('上麦申请 1'));
      await tester.pumpAndSettle();
      expect(find.text('当前房间申请人'), findsOneWidget);
      expect(find.text('同意'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _NineEmptySeatsRepository extends MockRoomRepository {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final snapshot = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    return snapshot.copyWith(
      seats: [
        for (var number = 1; number <= 9; number++)
          MicSeat(
            number: number,
            backendIndex: number,
            state: MicSeatState.available,
          ),
      ],
    );
  }
}

class _TrackedMicQueueRepository extends MockRoomOperationsRepository {
  String? lastMicQueueRoomId;

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    lastMicQueueRoomId = roomId;
    return super.fetchMicRequests(roomId);
  }
}

MicAccessRequest _request({
  required String id,
  required int userId,
  required String name,
  required int seatNumber,
  MicRequestType type = MicRequestType.request,
  int? requestedByUserId,
  MicRequestTargetAction targetAction = MicRequestTargetAction.cancel,
  MicRequestStatus status = MicRequestStatus.pending,
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
    status: status,
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
