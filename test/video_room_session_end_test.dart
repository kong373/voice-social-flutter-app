import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  for (final snapshotOnly in [false, true]) {
    testWidgets(
      'expired room is durable and explicitly reenters ($snapshotOnly)',
      (tester) async {
        final h = _Harness(snapshotOnly: snapshotOnly);
        addTearDown(h.dispose);
        await h.mount(tester);
        expect(h.repository.entries, 1);
        expect(
          find.byKey(const Key('video-room-public-screen')),
          findsOneWidget,
        );
        if (!snapshotOnly) {
          await tester.enterText(
            find.byKey(const Key('video-room-composer')),
            'old unsent draft',
          );
        }
        h.expire();
        await tester.pumpAndSettle();
        h.controller.clearError();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(h.controller.status, RoomSessionStatus.left);
        expect(h.controller.snapshot, isNotNull);
        expect(find.text('房间会话已结束'), findsOneWidget);
        expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
        expect(find.byKey(const Key('video-room-composer')), findsNothing);
        expect(find.text('礼物'), findsNothing);
        expect(h.repository.entries, 1, reason: 'expiry cannot auto-rejoin');

        await tester.tap(find.text('重新进入'));
        await tester.pumpAndSettle();
        expect(h.repository.entries, 2);
        expect(h.repository.lastSource, RoomEntrySource.discoveryPost);
        expect(h.controller.status, RoomSessionStatus.joined);
        expect(
          find.byKey(const Key('video-room-public-screen')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('video-room-composer')))
              .controller!
              .text,
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        h.controller.dispose();
      },
    );
  }

  testWidgets('expiry while a child route is open remains visible on return', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    h.navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('child'))),
    );
    await tester.pumpAndSettle();
    h.expire();
    await tester.pumpAndSettle();
    h.controller.clearError();
    await tester.pump(const Duration(seconds: 5));
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('房间会话已结束'), findsOneWidget);
    expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('test home'), findsOneWidget);
    expect(h.repository.entries, 1);
    expect(h.repository.exits, 0, reason: 'ended session needs no exit write');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed reentry never exposes the retained snapshot', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    h.expire();
    await tester.pumpAndSettle();
    h.repository.refuseEntry = true;
    await tester.tap(find.text('重新进入'));
    await tester.pumpAndSettle();
    expect(h.controller.status, RoomSessionStatus.failed);
    expect(h.controller.snapshot, isNotNull);
    expect(find.text('暂时无法进入房间'), findsOneWidget);
    expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
    expect(find.byKey(const Key('video-room-composer')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('identity change cannot reenter with the old controller', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.mount(tester);
    h.identity.value = 11;
    await tester.pumpAndSettle();
    expect(h.controller.status, RoomSessionStatus.left);
    expect(h.controller.snapshot, isNull);
    expect(find.text('房间会话已结束'), findsOneWidget);
    expect(find.text('重新进入'), findsNothing);
    expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(find.text('test home'), findsOneWidget);
    expect(h.repository.entries, 1);
    expect(h.repository.exits, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final terminal in [
    (RoomRealtimeEventCodes.kickedOut, RoomSessionStatus.kicked, '你已被移出房间'),
    (RoomRealtimeEventCodes.roomBanned, RoomSessionStatus.closed, '房间当前不可用'),
  ]) {
    testWidgets('${terminal.$2} is explicit, cannot minimize or auto-rejoin', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = _Harness(snapshotOnly: false);
      addTearDown(h.dispose);
      await h.mount(tester, textScale: 1.3);
      h.realtime.emit(RoomRealtimeEvent(code: terminal.$1, payload: const {}));
      await tester.pumpAndSettle();
      h.controller.clearError();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(h.controller.status, terminal.$2);
      expect(find.text(terminal.$3), findsOneWidget);
      expect(find.text('重新进入'), findsNothing);
      expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('test home'), findsOneWidget);
      expect(find.text('收起房间'), findsNothing);
      expect(h.repository.entries, 1);
      expect(h.repository.exits, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Harness {
  _Harness({bool snapshotOnly = true}) {
    repository = _Repository(snapshotOnly: snapshotOnly);
    controller = RoomController(
      roomId: 'room-session-end',
      title: 'Session end test',
      currentUserId: 10,
      accessToken: 'fixture',
      repository: repository,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: realtime,
      leaseElapsed: () => elapsed,
      sessionChanges: identity,
      activeUserId: () => identity.value,
    );
  }

  final dependencies = AppDependencies.mock();
  final identity = ValueNotifier<int?>(10);
  final navigator = GlobalKey<NavigatorState>();
  final realtime = MockRoomRealtimeGateway();
  late final _Repository repository;
  late final RoomController controller;
  Duration elapsed = Duration.zero;

  Future<void> mount(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: Text('test home')),
        ),
      ),
    );
    navigator.currentState!.push<VideoRoomExit>(
      MaterialPageRoute(
        builder: (_) => VideoRuntimeRoomPage(
          controller: controller,
          entrySource: RoomEntrySource.discoveryPost,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expire() {
    controller.setForeground(false);
    elapsed += const Duration(seconds: 91);
    controller.setForeground(true);
  }

  Future<void> dispose() async {
    controller.dispose();
    identity.dispose();
    await realtime.dispose();
    dependencies.dispose();
  }
}

class _Repository extends MockRoomRepository implements RoomLeaseRepository {
  _Repository({required this.snapshotOnly});
  final bool snapshotOnly;
  int entries = 0;
  int exits = 0;
  bool refuseEntry = false;
  RoomEntrySource? lastSource;
  String get sessionId =>
      '00000000-0000-4000-8000-${entries.toString().padLeft(12, '0')}';

  RoomSessionLease lease(int sequence) => RoomSessionLease(
    sessionId: sessionId,
    sequence: sequence,
    serverTime: DateTime.utc(2026),
    expiresAt: DateTime.utc(2026).add(const Duration(seconds: 90)),
    heartbeatIntervalSeconds: 20,
    leaseDurationSeconds: 90,
  );

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    entries++;
    lastSource = source;
    if (refuseEntry) throw Exception('entry refused');
    final snapshot = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    return snapshot.copyWith(
      transportMode: snapshotOnly
          ? RoomTransportMode.snapshotOnly
          : RoomTransportMode.interactive,
      sessionId: sessionId,
      roomLease: lease(0),
    );
  }

  @override
  Future<void> exitRoom(String roomId) async {
    exits++;
  }

  @override
  Future<RoomSessionLease> renewRoomLease({
    required String roomId,
    required String sessionId,
    required int sequence,
    required String requestId,
    required int currentUserId,
  }) async => lease(sequence);
}
