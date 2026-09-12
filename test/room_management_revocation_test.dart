import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  testWidgets(
    'revoked manager loses the lock action after the visible authority refresh',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: RoomManagementPage(
            roomId: 'room-1',
            currentUserId: 20004,
            currentRole: RoomRole.moderator,
            coordinationMode: MicCoordinationMode.approval,
            seats: repository.seats,
            repositoryOverride: repository,
            authorityRepositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      repository.role = RoomRole.listener;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, '锁定'), findsNothing);
      expect(find.text('房间治理权限已变化，请退出后重新打开'), findsOneWidget);
      expect(find.text('房管'), findsNothing);
      expect(find.text('成员'), findsOneWidget);

      repository.role = RoomRole.moderator;
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      expect(find.text('房管'), findsOneWidget);
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      final lockChip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, '锁定'),
      );
      expect(lockChip.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('queue governance denial clears stale queue and seat controls', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    final previousReads = repository.queueReads;
    repository.queueError = const ApiException(
      kind: ApiFailureKind.forbidden,
      httpStatus: 403,
      code: 40335,
      message: '仅房主或管理员可执行该操作',
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(repository.queueReads, greaterThan(previousReads));
    expect(find.text('房间治理权限已变化，请退出后重新打开'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('房管'), findsNothing);
    expect(find.text('上麦申请'), findsNothing);
    expect(find.widgetWithText(ActionChip, '锁定'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late queue response cannot restore revoked management state', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    final delayedQueue = Completer<List<MicAccessRequest>>();
    repository.nextQueueRead = delayedQueue;

    await tester.pump(const Duration(seconds: 3));
    expect(repository.queueReads, greaterThan(1));
    repository.role = RoomRole.listener;
    await tester.tap(find.byTooltip('刷新权威状态'));
    await tester.pumpAndSettle();

    delayedQueue.complete([_lateRequest]);
    await tester.pumpAndSettle();
    expect(find.text('晚到申请'), findsNothing);
    expect(find.text('房管'), findsNothing);
    expect(find.text('房间治理权限已变化，请退出后重新打开'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lock governance denial clears the visible management page', (
    tester,
  ) async {
    final repository = _Repository()
      ..lockError = const ApiException(
        kind: ApiFailureKind.forbidden,
        httpStatus: 403,
        code: 40335,
        message: '仅房主或管理员可执行该操作',
      );
    await _open(tester, repository);
    await tester.tap(find.text('麦位管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '锁定'));
    await tester.pumpAndSettle();

    expect(repository.lockWrites, 1);
    expect(find.text('房间治理权限已变化，请退出后重新打开'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('房管'), findsNothing);
    expect(find.widgetWithText(ActionChip, '锁定'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('authority loss drops the pending retry intent before recovery', (
    tester,
  ) async {
    final repository = _Repository()
      ..queue = [_lateRequest]
      ..resolveError = const ApiException(
        kind: ApiFailureKind.timeout,
        message: '处理结果待确认',
      );
    await _open(tester, repository);
    await tester.tap(find.textContaining('上麦申请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(repository.resolveWrites, 1);
    expect(find.text('重试原处理'), findsOneWidget);

    repository.role = RoomRole.listener;
    await tester.tap(find.byTooltip('刷新权威状态'));
    await tester.pumpAndSettle();
    expect(find.text('重试原处理'), findsNothing);
    expect(find.text('房间治理权限已变化，请退出后重新打开'), findsOneWidget);

    repository.role = RoomRole.moderator;
    repository.resolveError = null;
    await tester.tap(find.byTooltip('刷新权威状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('上麦申请'));
    await tester.pumpAndSettle();
    expect(find.text('重试原处理'), findsNothing);
    expect(find.text('同意'), findsOneWidget);
    expect(repository.resolveWrites, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoomManagementPage(
        roomId: 'room-1',
        currentUserId: 20004,
        currentRole: repository.role,
        coordinationMode: MicCoordinationMode.approval,
        seats: repository.seats,
        repositoryOverride: repository,
        authorityRepositoryOverride: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository extends MockRoomOperationsRepository
    implements RoomAuthorityRepository {
  RoomRole role = RoomRole.moderator;
  List<MicAccessRequest> queue = <MicAccessRequest>[];
  Object? queueError;
  Completer<List<MicAccessRequest>>? nextQueueRead;
  int queueReads = 0;
  Object? resolveError;
  int resolveWrites = 0;
  Object? lockError;
  int lockWrites = 0;

  List<MicSeat> seats = const <MicSeat>[
    MicSeat(number: 2, backendIndex: 2, state: MicSeatState.available),
  ];

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    queueReads++;
    if (queueError != null) throw queueError!;
    final delayed = nextQueueRead;
    nextQueueRead = null;
    return delayed == null ? List.of(queue) : delayed.future;
  }

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
    required int expectedVersion,
    int? targetSeatNumber,
  }) async {
    resolveWrites++;
    if (resolveError != null) throw resolveError!;
    queue = [];
  }

  @override
  Future<void> setSeatLocked({
    required String roomId,
    required int backendMicIndex,
    required bool locked,
  }) async {
    lockWrites++;
    if (lockError != null) throw lockError!;
  }

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    return RoomAuthorityProjection(
      snapshot: RoomSnapshot(
        roomId: roomId,
        roomCode: roomId,
        title: '房间',
        topic: '',
        ownerId: 20001,
        role: role,
        seats: List<MicSeat>.of(seats),
        rtc: const RtcCredentials(token: '', channelId: ''),
        publicScreenEnabled: false,
        pictureMessagesAllowed: false,
        autoLockMic: false,
        giftCatalogAvailable: false,
        giftBalance: 0,
      ),
      viewerUserId: currentUserId,
      memberActive: true,
      roomMuted: false,
      version: 1,
    );
  }
}

final _lateRequest = MicAccessRequest(
  id: 'late-request',
  roomId: 'room-1',
  member: const RoomMember(
    userId: 20005,
    name: '晚到申请',
    role: RoomRole.listener,
    presence: RoomMemberPresence.listener,
  ),
  seatNumber: 2,
  status: MicRequestStatus.pending,
  createdAt: DateTime(2026),
);
