import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/pk/application/room_pk_sync_controller.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'room_lease_controller_test.dart' as lease;
import 'room_pk_automatic_sync_test.dart' show PkServer;

class _Room extends lease.AuthorityRepo {
  RoomRole role = RoomRole.owner;
  String sessionId = lease.session;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async =>
      (await super.enterRoom(
        roomId: roomId,
        password: password,
        source: source,
        currentUserId: currentUserId,
      )).copyWith(
        role: role,
        sessionId: sessionId,
        roomLease: lease.lease(0, id: sessionId),
      );
}

class _Pk extends MockRoomPkRepository {
  final server = PkServer();
  Completer<RoomPkProcess>? pending;
  Object? failure;
  RoomPkProcess? response;
  int reads = 0;
  void Function()? readFence;
  RoomPkProcess get value => RoomPkProcess(
    invitation: server.status == null ? null : server.invitation('A'),
    battle: server.status == RoomPkInvitationStatus.accepted
        ? server.battle('A')
        : null,
  );
  @override
  Future<RoomPkProcess> fetchProcess({
    required String roomId,
    required void Function() requireCurrent,
  }) async {
    requireCurrent();
    readFence = requireCurrent;
    reads++;
    if (failure != null) throw failure!;
    // Intentionally ignore late cancellation in this fake: controller must fence it too.
    return pending?.future ?? Future.value(response ?? value);
  }
}

class _Fixture {
  final dependencies = AppDependencies.mock();
  final roomRepository = _Room();
  final pk = _Pk();
  late RoomController room;
  late RoomPkSyncController sync;
  bool disposed = false;
  bool routeCurrent = true;
  Duration elapsed = Duration.zero;
  AuthSession account(int id, [String token = 'token']) => AuthSession(
    accessToken: token,
    tokenType: 'Bearer',
    expiresAt: DateTime(2040),
    userId: id,
    mobile: '',
    roles: '',
  );
  Future<void> start(WidgetTester tester, {String? battleId}) async {
    await dependencies.sessionManager.save(account(1));
    room = RoomController(
      roomId: 'A',
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: roomRepository,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
      activeUserId: () => dependencies.sessionManager.session?.userId,
      identityGeneration: () => dependencies.sessionManager.identityGeneration,
      sessionChanges: dependencies.sessionManager,
      leaseElapsed: () => elapsed,
    );
    await room.join();
    sync = RoomPkSyncController(
      repository: pk,
      room: room,
      session: dependencies.sessionManager,
      battleId: battleId,
      routeIsCurrent: () => routeCurrent,
    );
    sync.setVisible(true);
    await tester.pumpWidget(
      _Cleanup(() {
        if (!disposed) sync.dispose();
        room.dispose();
        dependencies.dispose();
      }),
    );
  }
}

class _Cleanup extends StatefulWidget {
  const _Cleanup(this.cleanup);
  final VoidCallback cleanup;
  @override
  State<_Cleanup> createState() => _CleanupState();
}

class _CleanupState extends State<_Cleanup> {
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  void dispose() {
    widget.cleanup();
    super.dispose();
  }
}

void main() {
  testWidgets('expired room lease rejects late PK response and stops reads', (
    tester,
  ) async {
    final f = _Fixture();
    final pending = Completer<RoomPkProcess>();
    f.pk.pending = pending;
    await f.start(tester);
    final flight = f.sync.refresh();
    final current = f.pk.readFence!;
    f.elapsed = const Duration(seconds: 90);
    expect(f.sync.canRead, isFalse);
    expect(current, throwsA(isA<ApiException>()));
    f.pk.server.status = RoomPkInvitationStatus.accepted;
    pending.complete(f.pk.value);
    await flight;
    expect(f.sync.process, isNull);
    expect(f.sync.claimAutomaticBattle(), isNull);
    final before = f.pk.reads;
    await tester.pump(const Duration(seconds: 3));
    expect(f.pk.reads, before);
  });

  testWidgets('route fence rejects a response before the visibility rebuild', (
    tester,
  ) async {
    final f = _Fixture();
    final pending = Completer<RoomPkProcess>();
    f.pk.pending = pending;
    await f.start(tester);
    final flight = f.sync.refresh();
    final current = f.pk.readFence!;
    f.routeCurrent = false;
    expect(current, throwsA(isA<ApiException>()));
    pending.complete(f.pk.value);
    await flight;
    expect(f.sync.process, isNull);
    final before = f.pk.reads;
    await tester.pump(const Duration(seconds: 6));
    expect(f.pk.reads, before);
    f.sync.setVisible(false);
    f.pk.pending = null;
    f.routeCurrent = true;
    f.sync.setVisible(true);
    await tester.pump();
    expect(f.pk.reads, before + 1);
    expect(current, throwsA(isA<ApiException>()));
  });

  testWidgets(
    'battle scope rejects a replacement and stops at authoritative result',
    (tester) async {
      final f = _Fixture();
      f.pk.server.status = RoomPkInvitationStatus.accepted;
      await f.start(tester, battleId: 'battle');
      expect(f.sync.process!.battle!.isActive, isTrue);
      f.pk.response = RoomPkProcess(
        invitation: f.pk.server.invitation('A'),
        battle: RoomPkBattle(
          id: 'replacement',
          invitationId: 'different-invitation',
          currentRoomId: 'A',
          sender: f.pk.server.battle('A').sender,
          receiver: f.pk.server.battle('A').receiver,
          remainingSeconds: 300,
          punishmentTheme: '分享今天',
          stage: RoomPkBattleStage.fighting,
          updatedAt: f.pk.server.now,
        ),
      );
      await f.sync.refresh();
      expect(f.sync.process, isNull);
      expect(f.sync.error, '当前 PK 对局已变化');
      f.pk.response = RoomPkProcess(
        invitation: f.pk.server.invitation('A'),
        battle: f.pk.server
            .battle('A')
            .copyWith(stage: RoomPkBattleStage.completed),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(f.sync.process!.battle!.isActive, isFalse);
      final before = f.pk.reads;
      await tester.pump(const Duration(seconds: 9));
      expect(f.pk.reads, before);
      expect(f.sync.claimAutomaticBattle(), isNull);
    },
  );

  testWidgets(
    'single flight, coalesced same-scope refresh, three seconds after completion',
    (tester) async {
      final f = _Fixture();
      final pending = Completer<RoomPkProcess>();
      f.pk.pending = pending;
      await f.start(tester);
      final first = f.sync.refresh(), second = f.sync.refresh();
      expect(identical(first, second), isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(f.pk.reads, 1);
      f.pk.pending = null;
      pending.complete(f.pk.value);
      await tester.pump();
      expect(f.pk.reads, 1);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(f.pk.reads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(f.pk.reads, 2);
    },
  );

  for (final stop in [
    'background',
    'covered',
    'identity-ABA',
    'room-session',
    'permission-ABA',
    'leave',
    'dispose',
  ]) {
    testWidgets(
      '$stop rejects pending response and request callback even after recovery',
      (tester) async {
        final f = _Fixture();
        await f.start(tester);
        f.pk.server.status = RoomPkInvitationStatus.pending;
        await f.sync.refresh();
        final pending = Completer<RoomPkProcess>();
        f.pk.pending = pending;
        final flight = f.sync.refresh();
        final requireOld = f.pk.readFence!;
        final before = f.pk.reads;
        if (stop == 'background')
          f.sync.didChangeAppLifecycleState(AppLifecycleState.paused);
        if (stop == 'covered') f.sync.setVisible(false);
        if (stop == 'identity-ABA') {
          await f.dependencies.sessionManager.save(f.account(2));
          await f.dependencies.sessionManager.save(f.account(1));
        }
        if (stop == 'room-session') {
          f.roomRepository.sessionId = '00000000-0000-4000-8000-000000000002';
          await f.room.refreshRoomAuthority();
        }
        if (stop == 'permission-ABA') {
          f.roomRepository.role = RoomRole.listener;
          await f.room.refreshRoomAuthority();
          f.roomRepository.role = RoomRole.owner;
          await f.room.refreshRoomAuthority();
        }
        if (stop == 'leave') await f.room.leaveRoom();
        if (stop == 'dispose') {
          f.sync.dispose();
          f.disposed = true;
        }
        expect(requireOld, throwsA(isA<ApiException>()));
        expect(f.sync.process, isNull);
        f.pk.server.status = RoomPkInvitationStatus.rejected;
        f.pk.pending = null;
        if (stop == 'background')
          f.sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
        if (stop == 'covered') f.sync.setVisible(true);
        pending.complete(
          RoomPkProcess(
            invitation: f.pk.server
                .invitation('A')
                .copyWith(status: RoomPkInvitationStatus.accepted),
            battle: f.pk.server.battle('A'),
          ),
        );
        await flight;
        await tester.pump();
        expect(f.sync.claimAutomaticBattle(), isNull);
        if (['background', 'covered', 'permission-ABA'].contains(stop)) {
          expect(f.pk.reads, before + 1);
          expect(
            f.sync.process!.invitation!.status,
            RoomPkInvitationStatus.rejected,
          );
        } else {
          expect(f.pk.reads, before);
          expect(f.sync.process, isNull);
        }
      },
    );
  }

  testWidgets(
    'foreground recovery discovers acceptance despite room notifications while background',
    (tester) async {
      final f = _Fixture();
      await f.start(tester);
      f.pk.server.status = RoomPkInvitationStatus.pending;
      await f.sync.refresh();
      f.sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      await f.room.refreshRoomAuthority();
      f.pk.server.status = RoomPkInvitationStatus.accepted;
      final before = f.pk.reads;
      await tester.pump(const Duration(seconds: 10));
      expect(f.pk.reads, before);
      f.sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(f.pk.reads, before + 1);
      expect(f.sync.claimAutomaticBattle()!.id, 'battle');
      expect(f.sync.claimAutomaticBattle(), isNull);
      await f.sync.refresh();
      expect(f.sync.claimAutomaticBattle(), isNull);
    },
  );

  for (final state in [
    RoomPkInvitationStatus.rejected,
    RoomPkInvitationStatus.expired,
    RoomPkInvitationStatus.canceled,
  ]) {
    testWidgets('$state updates automatically and never opens a battle', (
      tester,
    ) async {
      final f = _Fixture();
      await f.start(tester);
      f.pk.server.status = RoomPkInvitationStatus.pending;
      await f.sync.refresh();
      f.pk.server.status = state;
      await tester.pump(const Duration(seconds: 3));
      expect(f.sync.process!.invitation!.status, state);
      expect(f.sync.claimAutomaticBattle(), isNull);
    });
  }

  testWidgets(
    'unknown existing battle is displayed but never automatically opened',
    (tester) async {
      final f = _Fixture();
      f.pk.server.status = RoomPkInvitationStatus.accepted;
      await f.start(tester);
      expect(f.sync.process!.battle!.id, 'battle');
      expect(f.sync.claimAutomaticBattle(), isNull);
    },
  );
  testWidgets(
    'bounded retry recovers network failure; current 403 clears and stops',
    (tester) async {
      final f = _Fixture();
      f.pk.failure = Exception('offline');
      await f.start(tester);
      expect(f.sync.error, isNotNull);
      f.pk.failure = null;
      await tester.pump(const Duration(seconds: 3));
      expect(f.sync.process, isNotNull);
      f.pk.failure = const ApiException(
        kind: ApiFailureKind.business,
        httpStatus: 403,
        message: 'revoked',
      );
      await f.sync.refresh();
      final before = f.pk.reads;
      await tester.pump(const Duration(seconds: 9));
      expect(f.pk.reads, before);
      expect(f.sync.process, isNull);
    },
  );
  testWidgets(
    'same-user token refresh preserves scope; stopped explicit write cannot restore old state',
    (tester) async {
      final f = _Fixture();
      await f.start(tester);
      final valid = f.sync.captureCurrent();
      await f.dependencies.sessionManager.save(f.account(1, 'rotated'));
      valid();
      final pending = Completer<RoomPkBattle>();
      final flight = f.sync.write((current) async {
        current();
        return pending.future;
      });
      final expectation = expectLater(flight, throwsA(isA<ApiException>()));
      f.sync.setVisible(false);
      pending.complete(f.pk.server.battle('A'));
      await expectation;
      expect(f.sync.process, isNull);
      expect(f.sync.claimAutomaticBattle(), isNull);
    },
  );
}
