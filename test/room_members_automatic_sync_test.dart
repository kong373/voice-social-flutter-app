import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';

class _Dependencies extends Fake implements AppDependencies {
  final backing = AppDependencies.mock();
  @override
  final _Repository roomOperationsRepository = _Repository();
  @override
  AppEnvironment get environment => const AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'http://localhost/',
    clientType: 'test',
    clientInnerVersion: '1',
    oauthClientId: '',
    realtimeEndpoint: '',
    allowInsecureHttp: true,
  );
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
}

class _Api extends Fake implements ApiClient {}

class _LeaseRepository extends BackendRoomOperationsRepository {
  _LeaseRepository() : super(apiClient: _Api());
  final reads = _Repository();
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) =>
      reads.fetchOnlineMembers(roomId: roomId, page: page, pageSize: pageSize);
}

class _LeaseDependencies extends Fake implements AppDependencies {
  _LeaseDependencies(this.base);
  final _Dependencies base;
  @override
  final _LeaseRepository roomOperationsRepository = _LeaseRepository();
  @override
  AppEnvironment get environment => base.environment;
  @override
  AuthSessionManager get sessionManager => base.sessionManager;
}

const _listener = RoomMember(
  userId: 2,
  name: '远端成员',
  role: RoomRole.listener,
  presence: RoomMemberPresence.listener,
);

class _Repository extends MockRoomOperationsRepository {
  List<RoomMember> members = [_listener];
  Completer<RoomMemberPage>? pending;
  bool fail = false;
  int reads = 0;
  final requestedPages = <int>[];
  int pages = 1;
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    reads++;
    requestedPages.add(page);
    final delayed = pending;
    pending = null;
    if (delayed != null) return delayed.future;
    if (fail) throw StateError('read failed');
    return RoomMemberPage(
      items: List.of(members),
      page: page,
      total: members.length,
      pages: pages,
    );
  }
}

Future<void> _open(WidgetTester tester, _Dependencies deps) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: deps,
      child: const MaterialApp(
        home: RoomMembersPage(
          roomId: 'uuid-room',
          currentUserId: 1,
          currentRole: RoomRole.listener,
          roomCode: '808080',
          seats: [
            MicSeat(
              number: 1,
              backendIndex: 1,
              state: MicSeatState.occupiedMuted,
              userId: 2,
              userRole: RoomRole.owner,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    deps.backing.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

void main() {
  testWidgets('lease change rejects old room response and stops polling', (
    tester,
  ) async {
    final base = _Dependencies();
    final deps = _LeaseDependencies(base);
    final repo = deps.roomOperationsRepository;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: const MaterialApp(
          home: RoomMembersPage(
            roomId: 'room',
            currentUserId: 1,
            currentRole: RoomRole.listener,
            seats: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('远端成员'), findsOneWidget);
    final pending = Completer<RoomMemberPage>();
    repo.reads.pending = pending;
    await tester.pump(const Duration(seconds: 2));
    repo.leaseBinding.beginEntry('another-room');
    pending.complete(
      const RoomMemberPage(items: [_listener], page: 1, total: 1, pages: 1),
    );
    await tester.pump();
    expect(find.text('远端成员'), findsNothing);
    final reads = repo.reads.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(repo.reads.reads, reads);
    await tester.pumpWidget(const SizedBox());
    base.backing.dispose();
  });
  for (final changeRoom in [false, true]) {
    testWidgets(
      'widget identity change rejects old response room=$changeRoom',
      (tester) async {
        final deps = _Dependencies();
        final identity = ValueNotifier(false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: deps,
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: identity,
                builder: (_, changed, _) => RoomMembersPage(
                  roomId: changed && changeRoom ? 'new-room' : 'old-room',
                  currentUserId: changed && !changeRoom ? 3 : 1,
                  currentRole: RoomRole.listener,
                  seats: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final repo = deps.roomOperationsRepository;
        final pending = Completer<RoomMemberPage>();
        repo.pending = pending;
        await tester.pump(const Duration(seconds: 2));
        identity.value = true;
        await tester.pump();
        expect(find.text('远端成员'), findsNothing);
        repo.members = [];
        pending.complete(
          const RoomMemberPage(items: [_listener], page: 1, total: 1, pages: 1),
        );
        await tester.pumpAndSettle();
        expect(find.text('远端成员'), findsNothing);
        expect(repo.reads, 3);
        await tester.pumpWidget(const SizedBox());
        identity.dispose();
        deps.backing.dispose();
      },
    );
  }
  testWidgets(
    'live server listener is not overwritten by stale occupied seat',
    (tester) async {
      final deps = _Dependencies();
      await _open(tester, deps);
      expect(find.text('麦上 0'), findsOneWidget);
      expect(find.text('听众 1'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('麦上 0'), findsOneWidget);
    },
  );
  testWidgets('visible page refreshes remote membership within five seconds', (
    tester,
  ) async {
    final deps = _Dependencies();
    await _open(tester, deps);
    deps.roomOperationsRepository.members = [];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('远端成员'), findsNothing);
    expect(deps.roomOperationsRepository.reads, greaterThan(1));
  });
  testWidgets('room code is shown instead of internal UUID', (tester) async {
    await _open(tester, _Dependencies());
    expect(find.textContaining('房间号 808080'), findsOneWidget);
    expect(find.textContaining('uuid-room'), findsNothing);
  });
  testWidgets(
    'slow reads and repeated refresh stay single flight and recover from errors',
    (tester) async {
      final deps = _Dependencies();
      await _open(tester, deps);
      final repo = deps.roomOperationsRepository;
      final delayed = Completer<RoomMemberPage>();
      repo.pending = delayed;
      await tester.pump(const Duration(seconds: 2));
      final reads = repo.reads;
      await tester.tap(find.byTooltip('刷新'));
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump(const Duration(seconds: 10));
      expect(repo.reads, reads);
      repo.fail = true;
      delayed.complete(
        const RoomMemberPage(items: [_listener], page: 1, total: 1, pages: 1),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('成员更新失败'), findsOneWidget);
      repo.fail = false;
      repo.members = [];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('远端成员'), findsNothing);
      expect(find.textContaining('成员更新失败'), findsNothing);
    },
  );
  testWidgets('background rejects pending response and resumes immediately', (
    tester,
  ) async {
    final deps = _Dependencies();
    await _open(tester, deps);
    final repo = deps.roomOperationsRepository;
    final delayed = Completer<RoomMemberPage>();
    repo.pending = delayed;
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reads = repo.reads;
    delayed.complete(
      const RoomMemberPage(items: [], page: 1, total: 0, pages: 1),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(repo.reads, reads);
    expect(find.text('远端成员'), findsOneWidget);
    repo.members = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repo.reads, reads + 1);
    expect(find.text('远端成员'), findsNothing);
  });
  testWidgets(
    'covered route pauses and pop rereads; disposal ignores late completion',
    (tester) async {
      final deps = _Dependencies();
      await _open(tester, deps);
      final repo = deps.roomOperationsRepository;
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      final reads = repo.reads;
      await tester.pump(const Duration(seconds: 10));
      expect(repo.reads, reads);
      repo.members = [];
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('远端成员'), findsNothing);
      final delayed = Completer<RoomMemberPage>();
      repo.pending = delayed;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      final disposedReads = repo.reads;
      delayed.complete(
        const RoomMemberPage(items: [_listener], page: 1, total: 1, pages: 1),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(repo.reads, disposedReads);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account switch clears old members and permanently rejects old flight',
    (tester) async {
      final deps = _Dependencies();
      await _open(tester, deps);
      final repo = deps.roomOperationsRepository;
      final delayed = Completer<RoomMemberPage>();
      repo.pending = delayed;
      await tester.pump(const Duration(seconds: 2));
      final reads = repo.reads;
      await deps.sessionManager.save(
        AuthSession(
          accessToken: 'test',
          tokenType: 'Bearer',
          expiresAt: DateTime(2030),
          userId: 3,
          mobile: '',
          roles: '',
        ),
      );
      await tester.pump();
      expect(find.text('远端成员'), findsNothing);
      delayed.complete(
        const RoomMemberPage(items: [_listener], page: 1, total: 1, pages: 1),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('远端成员'), findsNothing);
      expect(repo.reads, reads);
    },
  );
  testWidgets(
    'pagination refresh replaces loaded prefix and removes departed members',
    (tester) async {
      final deps = _Dependencies();
      deps.roomOperationsRepository.pages = 2;
      await _open(tester, deps);
      final repo = deps.roomOperationsRepository;
      repo.members = [
        const RoomMember(
          userId: 3,
          name: '第二页成员',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
      ];
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(repo.requestedPages, [1, 2]);
      expect(find.text('第二页成员'), findsOneWidget);
      repo.members = [];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(repo.requestedPages, [1, 2, 1, 2]);
      expect(find.text('远端成员'), findsNothing);
      expect(find.text('第二页成员'), findsNothing);
    },
  );
}
