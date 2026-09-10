import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

// Two clients share server state. Reads NEVER accept an invitation; only B's
// explicit accept changes it. This is not MockRoomPkRepository's read counter.
class PkServer {
  RoomPkInvitationStatus? status;
  int accepts = 0;
  final now = DateTime.utc(2026, 9, 10);
  RoomPkInvitation invitation(String room) => RoomPkInvitation(
    id: 'invitation',
    direction: room == 'A'
        ? RoomPkInvitationDirection.outgoing
        : RoomPkInvitationDirection.incoming,
    currentRoomId: room,
    opponent: opponent(room == 'A' ? 'B' : 'A'),
    punishmentTheme: '分享今天',
    durationMinutes: 5,
    status: status!,
    createdAt: now,
  );
  static RoomPkOpponent opponent(String room) =>
      RoomPkOpponent(roomId: room, roomCode: room, roomName: '房间$room');
  RoomPkBattle battle(String room) => RoomPkBattle(
    id: 'battle',
    invitationId: 'invitation',
    currentRoomId: room,
    sender: const RoomPkSide(
      roomId: 'A',
      roomCode: 'A',
      roomName: '房间A',
      score: 1,
    ),
    receiver: const RoomPkSide(
      roomId: 'B',
      roomCode: 'B',
      roomName: '房间B',
      score: 2,
    ),
    remainingSeconds: 300,
    punishmentTheme: '分享今天',
    stage: RoomPkBattleStage.fighting,
    updatedAt: now,
  );
}

class PkClient extends MockRoomPkRepository {
  PkClient(this.server, this.room);
  final PkServer server;
  final String room;
  int reads = 0;
  Completer<RoomPkProcess>? pendingProcess;
  Completer<List<RoomPkOpponent>>? pendingHot;
  @override
  Future<RoomPkProcess> fetchProcess({
    required String roomId,
    required void Function() requireCurrent,
  }) async {
    requireCurrent();
    reads++;
    return pendingProcess?.future ??
        RoomPkProcess(
          invitation: server.status == null ? null : server.invitation(room),
          battle: server.status == RoomPkInvitationStatus.accepted
              ? server.battle(room)
              : null,
        );
  }

  @override
  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
    void Function()? requireCurrent,
  }) async =>
      pendingHot?.future ?? [PkServer.opponent(room == 'A' ? 'B' : 'A')];
  @override
  Future<List<RoomPkRecord>> fetchHistory({
    required String roomId,
    void Function()? requireCurrent,
    int pageNum = 1,
    int pageSize = 20,
  }) async => [];
  @override
  Future<RoomPkInvitation?> fetchIncomingInvitation({
    required String roomId,
  }) async {
    reads++;
    return room == 'B' && server.status == RoomPkInvitationStatus.pending
        ? server.invitation(room)
        : null;
  }

  @override
  Future<RoomPkInvitation> sendInvitation({
    required String roomId,
    required int inviterUserId,
    required RoomPkOpponent opponent,
    required String punishmentTheme,
    required int durationMinutes,
    void Function()? requireCurrent,
  }) async {
    requireCurrent?.call();
    server.status = RoomPkInvitationStatus.pending;
    return server.invitation(room);
  }

  @override
  Future<RoomPkInvitation> refreshInvitation(
    RoomPkInvitation invitation,
  ) async => server.invitation(room);
  @override
  Future<RoomPkBattle?> fetchActiveBattle({required String roomId}) async =>
      server.status == RoomPkInvitationStatus.accepted
      ? server.battle(room)
      : null;
  @override
  Future<RoomPkBattle> acceptInvitation(
    RoomPkInvitation invitation, {
    void Function()? requireCurrent,
  }) async {
    requireCurrent?.call();
    expect(room, 'B');
    expect(server.status, RoomPkInvitationStatus.pending);
    server.accepts++;
    server.status = RoomPkInvitationStatus.accepted;
    return server.battle(room);
  }

  @override
  Future<void> rejectInvitation(
    RoomPkInvitation invitation, {
    void Function()? requireCurrent,
  }) async {
    requireCurrent?.call();
    server.status = RoomPkInvitationStatus.rejected;
  }

  @override
  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  }) async => server.battle(room);
}

class PkDependencies extends Fake implements AppDependencies {
  PkDependencies(PkServer server, String room)
    : roomPkRepository = PkClient(server, room);
  final backing = AppDependencies.mock();
  @override
  final PkClient roomPkRepository;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  AppEnvironment get environment => backing.environment;
  @override
  AppImageMediaHost? get imageMediaHost => backing.imageMediaHost;
  @override
  RoomOperationsRepository get roomOperationsRepository =>
      backing.roomOperationsRepository;
}

Future<void> pumpPk(
  WidgetTester tester,
  AppDependencies dependencies,
  Widget child, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final roomId = child is RoomPkPreparationPage
      ? child.roomId
      : (child as VideoRuntimeRoomPage).controller.roomId;
  await dependencies.sessionManager.save(
    AuthSession(
      accessToken: 'test-$roomId',
      tokenType: 'Bearer',
      expiresAt: DateTime(2040),
      userId: roomId == 'A' ? 1 : 2,
      mobile: '',
      roles: '',
    ),
  );
  if (child is RoomPkPreparationPage) {
    final realtime = MockRoomRealtimeGateway();
    final room = RoomController(
      roomId: roomId,
      title: '房间$roomId',
      currentUserId: roomId == 'A' ? 1 : 2,
      accessToken: 'test',
      repository: MockRoomRepository()..seedEntryRoleForQa(RoomRole.owner),
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: realtime,
    );
    await tester.runAsync(() => room.join());
    addTearDown(() async {
      room.dispose();
      await realtime.dispose();
    });
    child = RoomPkPreparationPage(
      roomId: roomId,
      roomTitle: '房间$roomId',
      controller: room,
    );
  }
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(home: child),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'actual covered route suspends reads and resumes with immediate authoritative acceptance once',
    (tester) async {
      final server = PkServer()..status = RoomPkInvitationStatus.pending;
      final a = PkDependencies(server, 'A');
      await pumpPk(
        tester,
        a,
        const RoomPkPreparationPage(roomId: 'A', roomTitle: '房间A'),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = a.roomPkRepository.reads;
      server.status = RoomPkInvitationStatus.accepted;
      await tester.pump(const Duration(seconds: 6));
      expect(a.roomPkRepository.reads, before);
      expect(find.byType(RoomPkBattlePage, skipOffstage: false), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkBattlePage), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkPreparationPage), findsOneWidget);
      expect(find.byType(RoomPkBattlePage, skipOffstage: false), findsNothing);
    },
  );

  testWidgets(
    'explicit accept response alone never navigates; fresh GET must confirm same battle',
    (tester) async {
      final server = PkServer()..status = RoomPkInvitationStatus.pending;
      final b = PkDependencies(server, 'B');
      await pumpPk(
        tester,
        b,
        const RoomPkPreparationPage(roomId: 'B', roomTitle: '房间B'),
      );
      final pending = Completer<RoomPkProcess>();
      b.roomPkRepository.pendingProcess = pending;
      await tester.tap(find.text('接受并准备'));
      await tester.pump();
      expect(server.accepts, 1);
      expect(find.byType(RoomPkBattlePage), findsNothing);
      b.roomPkRepository.pendingProcess = null;
      pending.complete(
        RoomPkProcess(
          invitation: server.invitation('B'),
          battle: server.battle('B'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkBattlePage), findsOneWidget);
      final before = b.roomPkRepository.reads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 6));
      expect(b.roomPkRepository.reads, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(b.roomPkRepository.reads, before + 1);
    },
  );

  testWidgets(
    'initial metadata completion across background is discarded and automatically recovered',
    (tester) async {
      final b = PkDependencies(PkServer(), 'B');
      final hot = Completer<List<RoomPkOpponent>>();
      b.roomPkRepository.pendingHot = hot;
      await pumpPk(
        tester,
        b,
        const RoomPkPreparationPage(roomId: 'B', roomTitle: '房间B'),
        settle: false,
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      b.roomPkRepository.pendingHot = null;
      hot.complete([PkServer.opponent('stale')]);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('房间stale'), findsNothing);
      expect(find.text('房间A'), findsOneWidget);
      expect(find.text('发送 PK 邀请'), findsOneWidget);
    },
  );

  testWidgets('same widget room A B A cannot adopt old request or authority', (
    tester,
  ) async {
    final a = PkDependencies(PkServer(), 'A');
    await pumpPk(
      tester,
      a,
      const RoomPkPreparationPage(roomId: 'A', roomTitle: '房间A'),
    );
    final controller = tester
        .widget<RoomPkPreparationPage>(find.byType(RoomPkPreparationPage))
        .controller!;
    final before = a.roomPkRepository.reads;
    for (final room in ['B', 'A']) {
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: a,
          child: MaterialApp(
            home: RoomPkPreparationPage(
              roomId: room,
              roomTitle: '房间$room',
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(a.roomPkRepository.reads, before);
      expect(find.text('PK 登录或房间授权已变化'), findsOneWidget);
    }
  });
  testWidgets(
    'B preparation discovers A invitation without refresh and only explicit B accept changes server',
    (tester) async {
      final b = PkDependencies(PkServer(), 'B');
      final client = b.roomPkRepository;
      final a = PkClient(client.server, 'A');
      await pumpPk(
        tester,
        b,
        const RoomPkPreparationPage(roomId: 'B', roomTitle: '房间B'),
      );
      expect(find.text('接受并准备'), findsNothing);
      await a.sendInvitation(
        roomId: 'A',
        inviterUserId: 1,
        opponent: PkServer.opponent('B'),
        punishmentTheme: '分享今天',
        durationMinutes: 5,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('接受并准备'), findsOneWidget);
      expect(client.server.accepts, 0);
      await tester.tap(find.text('接受并准备'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkBattlePage), findsOneWidget);
      expect(client.server.accepts, 1);
    },
  );

  testWidgets(
    'A waiting preparation enters once after B explicitly accepts without A refresh',
    (tester) async {
      final server = PkServer();
      final a = PkDependencies(server, 'A'), b = PkClient(server, 'B');
      await pumpPk(
        tester,
        a,
        const RoomPkPreparationPage(roomId: 'A', roomTitle: '房间A'),
      );
      await tester.tap(find.text('房间B'));
      await tester.tap(find.text('发送 PK 邀请'));
      await tester.pumpAndSettle();
      expect(server.status, RoomPkInvitationStatus.pending);
      await b.acceptInvitation(server.invitation('B'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkBattlePage), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        find.byType(RoomPkBattlePage, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('B actual room home discovers invitation without reopening PK', (
    tester,
  ) async {
    final server = PkServer(), realtime = MockRoomRealtimeGateway();
    final b = PkDependencies(server, 'B');
    final controller = RoomController(
      roomId: 'B',
      title: '房间B',
      currentUserId: 2,
      accessToken: 'test',
      repository: MockRoomRepository()..seedEntryRoleForQa(RoomRole.owner),
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: realtime,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });
    await pumpPk(tester, b, VideoRuntimeRoomPage(controller: controller));
    final a = PkClient(server, 'A');
    await a.sendInvitation(
      roomId: 'A',
      inviterUserId: 1,
      opponent: PkServer.opponent('B'),
      punishmentTheme: '分享今天',
      durationMinutes: 5,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('收到 PK 邀请'), findsOneWidget);
    expect(server.accepts, 0);
    await tester.tap(find.text('收到 PK 邀请'));
    await tester.pumpAndSettle();
    expect(find.text('接受并准备'), findsOneWidget);
    expect(server.accepts, 0);
    await tester.tap(find.text('接受并准备'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomPkBattlePage), findsOneWidget);
    await tester.tap(find.text('返回房间'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(RoomPkBattlePage, skipOffstage: false), findsNothing);
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
  });
}
