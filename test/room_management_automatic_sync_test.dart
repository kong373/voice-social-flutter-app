import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  testWidgets(
    'unknown initial queue shows loading only on requests until read completes',
    (tester) async {
      final delayed = Completer<List<MicAccessRequest>>();
      final repository = _Repository()..nextRead = delayed;
      await tester.pumpWidget(
        MaterialApp(
          home: RoomManagementPage(
            roomId: 'approval-room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            seats: const [],
            coordinationMode: MicCoordinationMode.approval,
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.ensureVisible(find.textContaining('上麦申请'));
      await tester.tap(find.textContaining('上麦申请'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('当前没有待处理的上麦申请'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      delayed.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('当前没有待处理的上麦申请'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final changeRoom in [false, true]) {
    testWidgets(
      'widget identity change drops previous queue response room=$changeRoom',
      (tester) async {
        final repository = _Repository();
        final room = ValueNotifier<bool>(false);
        addTearDown(room.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: room,
              builder: (_, changed, _) => RoomManagementPage(
                roomId: changed && changeRoom ? 'next-room' : 'approval-room',
                currentUserId: changed && !changeRoom ? 20002 : 20001,
                currentRole: RoomRole.owner,
                seats: const [],
                coordinationMode: MicCoordinationMode.approval,
                repositoryOverride: repository,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final delayed = Completer<List<MicAccessRequest>>();
        repository.nextRead = delayed;
        await tester.pump(const Duration(seconds: 3));
        room.value = true;
        await tester.pumpAndSettle();
        delayed.complete([_request]);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.textContaining('上麦申请'));
        await tester.tap(find.textContaining('上麦申请'));
        await tester.pumpAndSettle();
        expect(find.text('远端申请人'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'background invalidates pending results and dispose ignores completion',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final delayed = Completer<List<MicAccessRequest>>();
      repository.nextRead = delayed;
      await tester.pump(const Duration(seconds: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      delayed.complete([_request]);
      await tester.pump();
      expect(find.text('远端申请人'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final disposedRead = Completer<List<MicAccessRequest>>();
      repository.nextRead = disposedRead;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      disposedRead.complete([_request]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final reads = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, reads);
    },
  );

  testWidgets('initial pending is visible and remote resolution removes it', (
    tester,
  ) async {
    final repository = _Repository()..queue = [_request];
    await _open(tester, repository);
    expect(find.text('远端申请人'), findsOneWidget);
    repository.queue = [
      MicAccessRequest(
        id: _request.id,
        roomId: _request.roomId,
        member: _request.member,
        seatNumber: 4,
        status: MicRequestStatus.accepted,
        createdAt: _request.createdAt,
      ),
    ];
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('当前没有待处理的上麦申请'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'open manager queue automatically shows remote pending and resolved requests',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.queue = [_request];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('远端申请人'), findsOneWidget);
      repository.queue = [];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('远端申请人'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hidden route and background pause reads, resume catches up, dispose stops',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      );
      await tester.pumpAndSettle();
      final coveredReads = repository.reads;
      repository.queue = [_request];
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, coveredReads);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('远端申请人'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final pausedReads = repository.reads;
      repository.queue = [];
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, pausedReads);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('远端申请人'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final disposedReads = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, disposedReads);
    },
  );

  testWidgets(
    'slow reads stay single flight and stale read cannot undo approval',
    (tester) async {
      final repository = _Repository()..queue = [_request];
      await _open(tester, repository);
      final delayed = Completer<List<MicAccessRequest>>();
      repository.nextRead = delayed;
      await tester.pump(const Duration(seconds: 3));
      final reads = repository.reads;
      await tester.pump(const Duration(seconds: 9));
      expect(repository.reads, reads);
      await tester.tap(find.text('同意'));
      await tester.pump();
      expect(repository.resolves, 1);
      delayed.complete([_request]);
      await tester.pumpAndSettle();
      expect(find.text('当前没有待处理的上麦申请'), findsOneWidget);
      expect(repository.maxActive, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reads do not replace an in-progress approval and write errors stay visible',
    (tester) async {
      final repository = _Repository()..queue = [_request];
      await _open(tester, repository);
      repository.write = Completer<void>();
      repository.writeError = const ApiException(
        kind: ApiFailureKind.business,
        message: '审批权限已撤销',
      );
      await tester.tap(find.text('同意'));
      await tester.pump();
      final reads = repository.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, reads);
      repository.write!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('审批权限已撤销'), findsOneWidget);
      expect(find.text('远端申请人'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'queue read failure exposes actual error and automatically recovers',
    (tester) async {
      final repository = _Repository()..queue = [_request];
      await _open(tester, repository);
      repository.readError = const ApiException(
        kind: ApiFailureKind.business,
        message: '无权读取申请列表',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('无权读取申请列表'), findsOneWidget);
      expect(find.text('同意'), findsNothing);
      repository.readError = null;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('远端申请人'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoomManagementPage(
        roomId: 'approval-room',
        currentUserId: 20001,
        currentRole: RoomRole.owner,
        seats: const [],
        coordinationMode: MicCoordinationMode.approval,
        repositoryOverride: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.textContaining('上麦申请'));
  await tester.tap(find.textContaining('上麦申请'));
  await tester.pumpAndSettle();
}

final _request = MicAccessRequest(
  id: 'remote-request',
  roomId: 'approval-room',
  member: RoomMember(
    userId: 20005,
    name: '远端申请人',
    role: RoomRole.listener,
    presence: RoomMemberPresence.listener,
  ),
  seatNumber: 4,
  status: MicRequestStatus.pending,
  createdAt: DateTime(2026),
);

class _Repository extends MockRoomOperationsRepository {
  List<MicAccessRequest> queue = [];
  Completer<List<MicAccessRequest>>? nextRead;
  Completer<void>? write;
  Object? readError;
  Object? writeError;
  int reads = 0;
  int resolves = 0;
  int active = 0;
  int maxActive = 0;
  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    reads++;
    active++;
    if (active > maxActive) maxActive = active;
    final pending = nextRead;
    nextRead = null;
    try {
      if (readError != null) throw readError!;
      return pending != null ? await pending.future : List.of(queue);
    } finally {
      active--;
    }
  }

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  }) async {
    resolves++;
    if (write != null) await write!.future;
    if (writeError != null) throw writeError!;
    queue = [];
  }
}
