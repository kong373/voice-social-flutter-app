import 'dart:async';

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
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

const _roomId = '11111111-1111-4111-8111-111111111111';
const _sessionId = '22222222-2222-4222-8222-222222222222';
const _applicant = 10001;
const _owner = 20001;
const _deadline = Duration(seconds: 5);

void main() {
  for (final holdPostSubmitQueue in [false, true]) {
    testWidgets(
      holdPostSubmitQueue
          ? 'approved seat syncs within 5s while only the post-submit queue GET is pending'
          : 'closed approval sheet automatically receives seat 2 within 5s at the default 3s cadence',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final room = _AuthorityRoom();
        final operations = _MicOperations(room, holdPostSubmitQueue);
        final dependencies = AppDependencies.mock();
        final started = tester.binding.clock.now();
        final controller = RoomController(
          roomId: _roomId,
          title: 'Automatic approval sync',
          currentUserId: _applicant,
          accessToken: 'fixture',
          repository: room,
          roomOperationsRepository: operations,
          rtcAdapter: const SnapshotOnlyRtcAdapter(),
          realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
          lifecycleBinding: tester.binding,
          activeUserId: () => _applicant,
          identityGeneration: () => 1,
          leaseElapsed: () => tester.binding.clock.now().difference(started),
          allowSyntheticPublicMessages: false,
          // Deliberately do not override the production 3-second interval.
        );
        try {
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
          expect(tester.takeException(), isNull);
          expect(controller.status, RoomSessionStatus.joined);
          expect(controller.snapshot!.accessMode, 'PUBLIC');
          expect(controller.role, RoomRole.listener);
          expect(controller.isSnapshotOnly, isTrue);
          expect(controller.snapshot!.roomLease!.isValid, isTrue);
          expect(controller.isOnMic, isFalse);
          expect(controller.micCoordinationMode, MicCoordinationMode.approval);

          await tester.tap(find.text('上麦').hitTestable());
          await tester.pumpAndSettle();
          expect(find.text('审批上麦'), findsOneWidget);
          expect(find.byKey(const Key('approval-mic-seat-1')), findsNothing);
          await tester.tap(
            find.byKey(const Key('approval-mic-seat-2')).hitTestable(),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
          expect(operations.submissions, 1);
          expect(operations.request!.type, MicRequestType.request);
          expect(operations.request!.status, MicRequestStatus.pending);
          expect(operations.request!.subjectUserId, _applicant);
          expect(operations.request!.requestedByUserId, _applicant);
          expect(operations.request!.member.role, RoomRole.listener);
          expect(operations.request!.seatNumber, 2);
          expect(operations.heldRead != null, holdPostSubmitQueue);

          // Simulate the owner's committed server approval. This changes only
          // repository response data: no controller refresh, re-entry or event.
          operations.approveOnServer();
          expect(operations.request!.status, MicRequestStatus.approved);
          expect(operations.request!.assignedSeatNumber, 2);
          expect(operations.request!.resolvedByUserId, _owner);
          expect(room.state.seats[1].userId, _applicant);
          expect(controller.isOnMic, isFalse);
          if (holdPostSubmitQueue) {
            // Independent reads succeed, like the dual test's direct queue
            // evidence. Neither applies the projection to the controller.
            expect(
              (await operations.fetchMicRequests(_roomId)).single.status,
              MicRequestStatus.approved,
            );
            final reachable = await room.fetchRoomAuthority(
              roomId: _roomId,
              currentUserId: _applicant,
            );
            expect(reachable.memberActive, isTrue);
            expect(reachable.snapshot.sessionId, _sessionId);
            expect(reachable.snapshot.seats[1].userId, _applicant);
            expect(operations.heldRead!.isCompleted, isFalse);
          }

          final readsBefore = room.authorityReads;
          final approvedAt = tester.binding.clock.now();
          while (!controller.isOnMic &&
              tester.binding.clock.now().difference(approvedAt) < _deadline) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
          expect(controller.status, RoomSessionStatus.joined);
          expect(controller.snapshot!.sessionId, _sessionId);
          expect(controller.role, RoomRole.listener);
          expect(room.enters, 1);
          expect(room.reconnects, 0);
          expect(room.directMicWrites, 0);
          expect(operations.submissions, 1);
          expect(
            controller.isOnMic,
            isTrue,
            reason:
                'APPROVED seat 2 must reach the closed-sheet controller '
                'within 5s; holdPostSubmitQueue=$holdPostSubmitQueue, '
                'authorityReadsAfterApproval=${room.authorityReads - readsBefore}, '
                'micRequestPending=${controller.micRequestPending}, '
                'elapsed=${tester.binding.clock.now().difference(approvedAt)}',
          );
          expect(room.authorityReads, greaterThan(readsBefore));
          final ownSeat = controller.seats.singleWhere(
            (seat) => seat.isOccupied && seat.userId == _applicant,
          );
          expect(ownSeat.number, 2);
        } finally {
          // Run before Flutter's pending-timer invariant, even on RED. Stop
          // the controller before releasing the slow read so cleanup cannot
          // make the product deadline assertion pass.
          controller.dispose();
          operations.releaseHeldRead();
          await tester.pumpWidget(const SizedBox.shrink());
          dependencies.dispose();
          await tester.pump();
        }
      },
    );
  }
}

// In-memory first-party repository boundaries only: no HTTP server, database,
// device or audio provider. The production controller and page are unchanged.
class _AuthorityRoom extends MockRoomRepository
    implements RoomAuthorityRepository {
  RoomSnapshot state = RoomSnapshot(
    roomId: _roomId,
    sessionId: _sessionId,
    roomLease: RoomSessionLease(
      sessionId: _sessionId,
      sequence: 0,
      serverTime: DateTime.utc(2026, 9, 11),
      expiresAt: DateTime.utc(2026, 9, 11).add(const Duration(seconds: 90)),
      heartbeatIntervalSeconds: 20,
      leaseDurationSeconds: 90,
    ),
    roomCode: '952700',
    title: 'Automatic approval sync',
    topic: 'Ordinary member request',
    ownerId: _owner,
    role: RoomRole.listener,
    seats: [
      for (var number = 1; number <= 9; number++)
        MicSeat(
          number: number,
          backendIndex: number,
          state: MicSeatState.available,
        ),
    ],
    rtc: const RtcCredentials(
      solution: RtcSolution.unknown,
      token: '',
      channelId: _roomId,
      userId: _applicant,
    ),
    accessMode: 'PUBLIC',
    transportMode: RoomTransportMode.snapshotOnly,
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: 0,
  );
  int enters = 0, authorityReads = 0, reconnects = 0, directMicWrites = 0;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    enters++;
    return state;
  }

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    authorityReads++;
    return RoomAuthorityProjection(
      snapshot: state,
      viewerUserId: _applicant,
      memberActive: true,
      roomMuted: false,
      version: 1,
    );
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    reconnects++;
    return state;
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    directMicWrites++;
    throw StateError('An ordinary applicant must not use direct self-up');
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
}

class _MicOperations extends MockRoomOperationsRepository {
  _MicOperations(this.room, this.holdPostSubmitQueue);
  final _AuthorityRoom room;
  final bool holdPostSubmitQueue;
  MicAccessRequest? request;
  int submissions = 0;
  bool _holdNextRead = false;
  Completer<List<MicAccessRequest>>? heldRead;

  @override
  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    submissions++;
    request = MicAccessRequest(
      id: '33333333-3333-4333-8333-333333333333',
      roomId: roomId,
      member: RoomMember(
        userId: userId,
        name: 'Applicant',
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
      ),
      seatNumber: seatNumber,
      status: MicRequestStatus.pending,
      createdAt: DateTime.utc(2026, 9, 11),
      requestedByUserId: userId,
      subjectUserId: userId,
      targetAction: MicRequestTargetAction.cancel,
    );
    _holdNextRead = holdPostSubmitQueue;
  }

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    if (_holdNextRead) {
      _holdNextRead = false;
      heldRead = Completer<List<MicAccessRequest>>();
      return heldRead!.future;
    }
    return request == null ? [] : [request!];
  }

  void approveOnServer() {
    final pending = request!;
    request = MicAccessRequest(
      id: pending.id,
      roomId: pending.roomId,
      member: pending.member,
      seatNumber: pending.seatNumber,
      status: MicRequestStatus.approved,
      createdAt: pending.createdAt,
      requestedByUserId: pending.requestedByUserId,
      subjectUserId: pending.subjectUserId,
      assignedSeatNumber: 2,
      resolvedByUserId: _owner,
      resolvedAt: DateTime.utc(2026, 9, 11, 0, 0, 1),
      version: 1,
    );
    room.state = room.state.copyWith(
      seats: [
        for (final seat in room.state.seats)
          if (seat.number == 2)
            seat.copyWith(
              state: MicSeatState.occupied,
              userId: _applicant,
              userName: 'Applicant',
              audioMute: const RoomAudioMuteState(
                selfMuted: false,
                forcedMuted: false,
                legacyMuted: false,
              ),
              occupantJoinedAt: request!.resolvedAt!.toIso8601String(),
            )
          else
            seat,
      ],
    );
  }

  void releaseHeldRead() {
    final pending = heldRead;
    if (pending != null && !pending.isCompleted) pending.complete([]);
  }
}
