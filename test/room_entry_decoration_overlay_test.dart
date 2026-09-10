import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/room_entry_decoration_overlay.dart';
import 'room_lease_controller_test.dart' as lease;
import 'room_entry_decoration_gate_test.dart' show entryMember;

void main() {
  testWidgets(
    'authoritative member joinedAt animates once across polls, token refresh and page recreation',
    (tester) async {
      final h = await _Harness.create(tester);
      final joined = DateTime.utc(2020);
      h.reads.load = (_) async => _page([entryMember(1, joined)]);
      await h.show(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_entry(1), findsOneWidget);
      await h.deps.sessionManager.save(_session(1, token: 'rotated'));
      await tester.pump();
      expect(_entry(1), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 5));
      expect(_entry(1), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await h.show(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_entry(1), findsNothing);
      expect(h.reads.calls, greaterThanOrEqualTo(3));
      await h.close(tester);
    },
  );
  for (final loss in ['ABA', 'leave', 'lease', 'binding', 'lateError']) {
    testWidgets(
      'pending member ${loss == "lateError" ? "error" : "reply"} after $loss cannot produce any entry or restart reads',
      (tester) async {
        final h = await _Harness.create(tester, bound: loss == 'binding');
        final reply = Completer<RoomMemberPage>();
        h.reads.load = (_) => reply.future;
        await h.show(tester);
        if (loss == 'ABA' || loss == 'lateError') {
          await h.deps.sessionManager.save(_session(2));
          await h.deps.sessionManager.save(_session(1));
        } else if (loss == 'leave') {
          await h.controller.leaveRoom();
        } else if (loss == 'lease') {
          h.elapsed = const Duration(seconds: 90);
          h.controller.setForeground(false);
          h.controller.setForeground(true);
        } else {
          (h.deps.roomOperationsRepository as BackendRoomOperationsRepository)
              .leaseBinding
              .beginEntry('replacement');
        }
        if (loss == 'lateError')
          reply.completeError(StateError('OLD-ERROR'));
        else
          reply.complete(_page([entryMember(1, DateTime.utc(2020))]));
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        expect(_entry(1), findsNothing);
        expect(h.reads.calls, 1);
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
    );
  }
  testWidgets(
    'replacing a room rejects the old room reply without suppressing the new current entry',
    (tester) async {
      final h = await _Harness.create(tester);
      final old = Completer<RoomMemberPage>();
      h.reads.load = (_) => h.reads.calls == 1
          ? old.future
          : Future.value(
              _page([entryMember(1, DateTime.utc(2020), name: 'NewRoom')]),
            );
      await h.show(tester);
      h.controller = h.makeController('other');
      await h.controller.join();
      await h.show(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('NewRoom 进入房间'), findsOneWidget);
      old.complete(
        _page([entryMember(1, DateTime.utc(2021), name: 'OldRoom')]),
      );
      await tester.pump();
      expect(find.text('OldRoom 进入房间'), findsNothing);
      expect(find.text('NewRoom 进入房间'), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'new membership after baseline animates, copied seat changes do not',
    (tester) async {
      final h = await _Harness.create(tester);
      var member = entryMember(2, DateTime.utc(2020));
      h.reads.load = (_) async => _page([member]);
      await h.show(tester);
      expect(_entry(2), findsNothing);
      member = entryMember(2, DateTime.utc(2020, 1, 2));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_entry(2), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      member = member.copyWith(seatNumber: 3, isMuted: true);
      await tester.pump(const Duration(seconds: 5));
      expect(_entry(2), findsNothing);
      await h.close(tester);
    },
  );
  testWidgets(
    'a partial multi-page read never marks or animates a membership',
    (tester) async {
      final h = await _Harness.create(tester);
      h.reads.load = (page) async {
        if (page == 2) throw StateError('unavailable');
        return RoomMemberPage(
          items: [entryMember(1, DateTime.utc(2020))],
          page: 1,
          pages: 2,
          total: 2,
        );
      };
      await h.show(tester);
      expect(_entry(1), findsNothing);
      h.reads.load = (_) async => _page([entryMember(1, DateTime.utc(2020))]);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_entry(1), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'background pauses member reads and returning does not replay the active entry',
    (tester) async {
      final h = await _Harness.create(tester);
      h.reads.load = (_) async => _page([entryMember(1, DateTime.utc(2020))]);
      await h.show(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_entry(1), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 6));
      expect(_entry(1), findsNothing);
      expect(h.reads.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_entry(1), findsNothing);
      await h.close(tester);
    },
  );
}

Finder _entry(int id) => find.byKey(ValueKey('entry-decoration-$id'));
RoomMemberPage _page(List<RoomMember> members) => RoomMemberPage(
  items: members,
  page: 1,
  total: members.length,
  pages: members.isEmpty ? 0 : 1,
);

class _Reads extends Fake implements RoomOperationsRepository {
  late Future<RoomMemberPage> Function(int) load;
  int calls = 0;
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) {
    calls++;
    expect(pageSize, 50);
    return load(page);
  }
}

class _Dependencies extends Fake implements AppDependencies {
  _Dependencies(this.backing, this.reads, {this.boundReads});
  final AppDependencies backing;
  final _Reads reads;
  final RoomOperationsRepository? boundReads;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  RoomOperationsRepository get roomOperationsRepository => boundReads ?? reads;
}

class _Api extends Fake implements ApiClient {}

class _BoundReads extends BackendRoomOperationsRepository {
  _BoundReads(this.reads) : super(apiClient: _Api());
  final _Reads reads;
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) =>
      reads.fetchOnlineMembers(roomId: roomId, page: page, pageSize: pageSize);
}

class _Harness {
  _Harness(this.deps, this.reads);
  final _Dependencies deps;
  final _Reads reads;
  late RoomController controller;
  final _controllers = <RoomController>[];
  Duration elapsed = Duration.zero;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (final controller in _controllers) {
      controller.dispose();
    }
  }

  static Future<_Harness> create(
    WidgetTester tester, {
    bool bound = false,
  }) async {
    final backing = AppDependencies.mock();
    final reads = _Reads();
    final h = _Harness(
      _Dependencies(
        backing,
        reads,
        boundReads: bound ? _BoundReads(reads) : null,
      ),
      reads,
    );
    await h.deps.sessionManager.save(_session(1));
    h.controller = h.makeController('r');
    await h.controller.join();
    addTearDown(() async {
      await h.close(tester);
      backing.dispose();
    });
    return h;
  }

  RoomController makeController(String roomId) {
    final value = RoomController(
      roomId: roomId,
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: lease.Repo(),
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
      sessionChanges: deps.sessionManager,
      activeUserId: () => deps.sessionManager.session?.userId,
      identityGeneration: () => deps.sessionManager.identityGeneration,
      leaseElapsed: () => elapsed,
    );
    _controllers.add(value);
    return value;
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [RoomEntryDecorationOverlay(controller: controller)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

AuthSession _session(int id, {String token = 'test'}) => AuthSession(
  accessToken: token,
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: id,
  mobile: '',
  roles: 'USER',
);
