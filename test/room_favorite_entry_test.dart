import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  testWidgets('ordinary room has favorite entry and authoritative add/remove', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.open(tester);
    expect(h.discovery.writes, isEmpty);
    await tester.tap(find.text('收藏当前房间'));
    await tester.pumpAndSettle();
    expect(h.discovery.writes, [true]);
    expect(find.text('已收藏此房间'), findsOneWidget);
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    expect(h.discovery.writes, [true, false]);
    expect(find.text('尚未收藏此房间'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'favorite read failure cannot assume uncollected; retry reads again',
    (tester) async {
      final h = _Harness();
      h.discovery.readFailure = true;
      addTearDown(h.dispose);
      await h.open(tester);
      expect(find.text('收藏当前房间'), findsNothing);
      expect(find.text('收藏读取失败'), findsOneWidget);
      h.discovery.readFailure = false;
      h.discovery.favorite = true;
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('取消收藏'), findsOneWidget);
      expect(h.discovery.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'favorite pending write coalesces taps and never claims early success',
    (tester) async {
      final h = _Harness();
      h.discovery.pendingWrite = Completer<bool>();
      addTearDown(h.dispose);
      await h.open(tester);
      final action = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '收藏当前房间'))
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(h.discovery.writes, [true]);
      expect(find.text('已收藏此房间'), findsNothing);
      h.discovery.pendingWrite!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('已收藏此房间'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('favorite write failure preserves last confirmed state', (
    tester,
  ) async {
    final h = _Harness();
    h.discovery.writeFailure = true;
    addTearDown(h.dispose);
    await h.open(tester);
    await tester.tap(find.text('收藏当前房间'));
    await tester.pumpAndSettle();
    expect(find.text('收藏保存失败'), findsOneWidget);
    expect(find.text('已收藏此房间'), findsNothing);
    expect(find.text('收藏当前房间'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late favorite completion after removal has no stale UI or exception',
    (tester) async {
      final h = _Harness();
      h.discovery.pendingWrite = Completer<bool>();
      addTearDown(h.dispose);
      await h.open(tester);
      await tester.tap(find.text('收藏当前房间'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      h.discovery.pendingWrite!.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(h.discovery.writes, [true]);
    },
  );

  testWidgets(
    'room closure invalidates a pending favorite read and disables writes',
    (tester) async {
      final h = _Harness();
      h.discovery.pendingRead = Completer<RoomCollectionSnapshot>();
      addTearDown(h.dispose);
      await h.mount(tester);
      await tester.tap(find.text('更多').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏房间'));
      await tester.pump(const Duration(milliseconds: 400));
      h.realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.roomBanned,
          payload: {},
        ),
      );
      await tester.pump();
      expect(h.controller.status, RoomSessionStatus.closed);
      h.discovery.pendingRead!.complete(
        const RoomCollectionSnapshot(favorites: [], ownedRooms: []),
      );
      await tester.pumpAndSettle();
      expect(find.text('收藏当前房间'), findsNothing);
      expect(h.discovery.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Harness {
  final discovery = _Discovery();
  final realtime = MockRoomRealtimeGateway();
  final rtc = MockRtcAdapter();
  final room = MockRoomRepository()..seedEntryRoleForQa(RoomRole.listener);
  late final dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    discoveryRepository: discovery,
  );
  late final controller = RoomController(
    roomId: '880217',
    title: '收藏测试房',
    currentUserId: 10001,
    accessToken: 'test',
    repository: room,
    rtcAdapter: rtc,
    realtimeGateway: realtime,
  );
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('更多').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('收藏房间').hitTestable(), findsOneWidget);
    await tester.tap(find.text('收藏房间'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    controller.dispose();
    await realtime.dispose();
    dependencies.dispose();
  }
}

class _Discovery extends MockDiscoveryRepository {
  bool favorite = false;
  bool readFailure = false;
  bool writeFailure = false;
  final writes = <bool>[];
  Completer<bool>? pendingWrite;
  Completer<RoomCollectionSnapshot>? pendingRead;
  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async {
    if (pendingRead != null) return pendingRead!.future;
    if (readFailure)
      throw const ApiException(kind: ApiFailureKind.network, message: '收藏读取失败');
    final existing = await super.fetchRoomCollections(
      page: page,
      pageSize: pageSize,
    );
    return RoomCollectionSnapshot(
      favorites: favorite
          ? existing.favorites.where((room) => room.id == '880217').toList()
          : [],
      ownedRooms: existing.ownedRooms,
    );
  }

  @override
  Future<bool> setFavorite({
    required String roomId,
    required bool favorite,
  }) async {
    expect(roomId, '880217');
    writes.add(favorite);
    if (writeFailure)
      throw const ApiException(kind: ApiFailureKind.network, message: '收藏保存失败');
    return this.favorite = pendingWrite == null
        ? favorite
        : await pendingWrite!.future;
  }
}
