import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  for (final approved in [false, true]) {
    testWidgets(
      'successful review stays fenced across slow and failed refresh $approved',
      (tester) async {
        final repo = _Repository()..items = [_request];
        await _open(tester, repo);
        final approve = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '同意'))
            .onPressed!;
        final reject = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '拒绝'))
            .onPressed!;
        final old = Completer<RoomJoinRequestPage>();
        repo.next = old;
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text(approved ? '同意' : '拒绝'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(repo.resolves, 1);
        expect(find.text('同意'), findsNothing);
        expect(find.text('拒绝'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        approve();
        reject();
        await tester.pump();
        expect(repo.resolves, 1);
        final fresh = Completer<RoomJoinRequestPage>();
        repo.next = fresh;
        old.complete(_page([_request]));
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        expect(repo.reads, 3);
        approve();
        reject();
        expect(repo.resolves, 1);
        fresh.completeError(
          const ApiException(kind: ApiFailureKind.network, message: '刷新失败'),
        );
        await tester.pump();
        expect(find.text('刷新失败'), findsOneWidget);
        approve();
        reject();
        expect(repo.resolves, 1);
        // Even a subsequent authoritative PENDING does not release the fence.
        repo.items = [_request];
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('同意'), findsNothing);
        approve();
        reject();
        expect(repo.resolves, 1);
        repo.items = [
          RoomJoinRequest(
            id: _request.id,
            member: _request.member,
            status: approved
                ? RoomJoinRequestStatus.approved
                : RoomJoinRequestStatus.rejected,
          ),
        ];
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text(approved ? '已同意' : '已拒绝'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('入房申请 0'), findsOneWidget);
        expect(repo.resolves, 1);
        expect(repo.maxActive, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('APPROVAL mic ticks never enqueue slow join catch-up reads', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo, mode: MicCoordinationMode.approval);
    expect(repo.reads, 1);
    final slow = Completer<RoomJoinRequestPage>();
    repo.next = slow;
    await tester.pump(const Duration(seconds: 2));
    expect(repo.reads, 2);
    for (var tick = 0; tick < 3; tick++) {
      await tester.pump(const Duration(seconds: 2));
      expect(repo.reads, 2);
      expect(repo.micReads, 3 + tick);
    }
    slow.complete(_page([]));
    await tester.pump();
    expect(repo.reads, 2);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(repo.reads, 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.reads, 3);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.reads, 4);
    expect(repo.maxActive, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [
    MicCoordinationMode.direct,
    MicCoordinationMode.approval,
  ]) {
    testWidgets(
      'resident join queue reads authoritative changes within 5s $mode',
      (tester) async {
        final repo = _Repository();
        await _open(tester, repo, mode: mode);
        expect(find.text('当前没有入房申请记录'), findsOneWidget);
        repo.items = [_request];
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text('新入房申请人'), findsOneWidget);
        expect(find.text('入房申请 1'), findsOneWidget);
        repo.items = [];
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.text('当前没有入房申请记录'), findsOneWidget);
        if (mode == MicCoordinationMode.direct) expect(repo.micReads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'unknown and failed join reads never show false empty and recover',
    (tester) async {
      final delayed = Completer<RoomJoinRequestPage>();
      final repo = _Repository()..next = delayed;
      await _open(tester, repo, settle: false);
      expect(find.text('当前没有入房申请记录'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      delayed.completeError(
        const ApiException(kind: ApiFailureKind.business, message: '入房列表读取失败'),
      );
      await tester.pump();
      expect(find.text('入房列表读取失败'), findsOneWidget);
      repo.items = [_request];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('新入房申请人'), findsOneWidget);
      repo.error = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('入房列表读取失败'), findsOneWidget);
      expect(find.text('当前没有入房申请记录'), findsNothing);
      repo.error = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('新入房申请人'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'covered and background stop polling and invalidate old reads; resume catches up',
    (tester) async {
      final repo = _Repository();
      await _open(tester, repo);
      final delayed = Completer<RoomJoinRequestPage>();
      repo.next = delayed;
      await tester.pump(const Duration(seconds: 2));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      );
      await tester.pumpAndSettle();
      delayed.complete(_page([_request]));
      await tester.pump();
      final reads = repo.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repo.reads, reads);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('新入房申请人'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = repo.reads;
      repo.items = [_request];
      await tester.pump(const Duration(seconds: 6));
      expect(repo.reads, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('新入房申请人'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final disposed = repo.reads;
      await tester.pump(const Duration(seconds: 6));
      expect(repo.reads, disposed);
    },
  );

  for (final approved in [false, true]) {
    testWidgets(
      'single flight and write fence reject stale pending after review $approved',
      (tester) async {
        final repo = _Repository()..items = [_request];
        await _open(tester, repo);
        final delayed = Completer<RoomJoinRequestPage>();
        repo.next = delayed;
        await tester.pump(const Duration(seconds: 2));
        final reads = repo.reads;
        await tester.pump(const Duration(seconds: 6));
        expect(repo.reads, reads);
        repo.write = Completer<void>();
        await tester.tap(find.text(approved ? '同意' : '拒绝'));
        await tester.pump();
        delayed.complete(_page([_request]));
        await tester.pump(const Duration(seconds: 6));
        expect(repo.reads, reads);
        repo.write!.complete();
        await tester.pumpAndSettle();
        expect(find.text('新入房申请人'), findsNothing);
        expect(repo.maxActive, 1);
        expect(repo.resolves, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'read completing after successful review cannot resurrect pending',
    (tester) async {
      final repo = _Repository()..items = [_request];
      await _open(tester, repo);
      final delayed = Completer<RoomJoinRequestPage>();
      repo.next = delayed;
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('同意'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.resolves, 1);
      delayed.complete(_page([_request]));
      await tester.pumpAndSettle();
      expect(find.text('新入房申请人'), findsNothing);
      expect(find.text('入房申请 0'), findsOneWidget);
      expect(repo.maxActive, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed review remains visible and polling resumes', (
    tester,
  ) async {
    final repo = _Repository()
      ..items = [_request]
      ..writeError = true;
    await _open(tester, repo);
    await tester.tap(find.text('同意'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('入房审核失败'), findsOneWidget);
    expect(find.text('新入房申请人'), findsOneWidget);
    repo.items = [];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('新入房申请人'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slow mic read does not delay join polling', (tester) async {
    final repo = _Repository()..micRead = Completer<List<MicAccessRequest>>();
    await _open(tester, repo, mode: MicCoordinationMode.approval);
    repo.items = [_request];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('新入房申请人'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.micRead!.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final changeRoom in [true, false]) {
    testWidgets(
      'identity replacement drops stale join response room=$changeRoom',
      (tester) async {
        final repo = _Repository();
        final identity = ValueNotifier(false);
        addTearDown(identity.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: identity,
              builder: (_, changed, _) => _widget(
                repo,
                room: changed && changeRoom ? 'next-room' : 'room5',
                user: changed && !changeRoom ? 8 : 7,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final delayed = Completer<RoomJoinRequestPage>();
        repo.next = delayed;
        await tester.pump(const Duration(seconds: 2));
        identity.value = true;
        await tester.pumpAndSettle();
        delayed.complete(_page([_request]));
        await tester.pumpAndSettle();
        await _select(tester);
        expect(find.text('新入房申请人'), findsNothing);
        expect(repo.rooms.last, changeRoom ? 'next-room' : 'room5');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

RoomManagementPage _widget(
  _Repository repo, {
  String room = 'room5',
  int user = 7,
  MicCoordinationMode mode = MicCoordinationMode.direct,
}) => RoomManagementPage(
  roomId: room,
  currentUserId: user,
  currentRole: RoomRole.owner,
  seats: const [],
  coordinationMode: mode,
  repositoryOverride: repo,
);
Future<void> _select(WidgetTester tester) async {
  await tester.ensureVisible(find.textContaining('入房申请'));
  await tester.tap(find.textContaining('入房申请'));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _open(
  WidgetTester tester,
  _Repository repo, {
  MicCoordinationMode mode = MicCoordinationMode.direct,
  bool settle = true,
}) async {
  await tester.pumpWidget(MaterialApp(home: _widget(repo, mode: mode)));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  await _select(tester);
}

final _request = RoomJoinRequest(
  id: 'request4',
  member: RoomMember(
    userId: 147,
    name: '新入房申请人',
    role: RoomRole.listener,
    presence: RoomMemberPresence.listener,
  ),
  status: RoomJoinRequestStatus.pending,
);
RoomJoinRequestPage _page(List<RoomJoinRequest> items) =>
    RoomJoinRequestPage(items: items, page: 1, total: items.length, pages: 1);

class _Repository extends MockRoomOperationsRepository {
  List<RoomJoinRequest> items = [];
  Completer<RoomJoinRequestPage>? next;
  Completer<void>? write;
  Completer<List<MicAccessRequest>>? micRead;
  bool writeError = false;
  bool error = false;
  int reads = 0, micReads = 0, active = 0, maxActive = 0, resolves = 0;
  final rooms = <String>[];
  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    micReads++;
    return micRead != null ? await micRead!.future : [];
  }

  @override
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    reads++;
    rooms.add(roomId);
    active++;
    if (active > maxActive) maxActive = active;
    final pending = next;
    next = null;
    try {
      if (error)
        throw const ApiException(
          kind: ApiFailureKind.business,
          message: '入房列表读取失败',
        );
      return pending != null ? await pending.future : _page(List.of(items));
    } finally {
      active--;
    }
  }

  @override
  Future<void> resolveJoinRequest({
    required String joinRequestId,
    required bool approved,
    String? requestId,
  }) async {
    resolves++;
    if (write != null) await write!.future;
    if (writeError)
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '入房审核失败',
      );
    items = [];
  }
}
