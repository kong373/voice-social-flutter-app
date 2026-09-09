import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';
import 'package:voice_social_app/features/room/presentation/platform_rooms_page.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  testWidgets(
    'legacy empty roomCode displays explicit roomId, not a fabricated code',
    (tester) async {
      final repository = _Repository();
      addTearDown(repository.notifier.dispose);
      repository.read = () async => const PlatformRoomPageResult(
        [
          PlatformRoom(
            roomId: '22222222-2222-4222-8222-222222222222',
            roomCode: '',
            roomName: 'Legacy closed room',
            ownerUserId: 42,
            status: 'CLOSED',
            version: 7,
            accessMode: 'PASSWORD',
          ),
        ],
        1,
        false,
      );
      await tester.pumpWidget(
        MaterialApp(home: PlatformRoomsPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Legacy closed room'), findsOneWidget);
      expect(
        find.text('ID 22222222-2222-4222-8222-222222222222 · 已关闭'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'staff closed runtime exposes only reopen and exit, no owner editor or transport',
    (tester) async {
      final dependencies = AppDependencies.mock();
      final rtc = MockRtcAdapter();
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: 'closed',
        title: 'closed',
        currentUserId: 10,
        accessToken: 'test',
        repository: _ClosedStaff(),
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
        dependencies.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('房间已关闭 · 平台管理视图'), findsOneWidget);
      expect(find.text('重新开放房间'), findsOneWidget);
      expect(find.text('退出管理视图'), findsOneWidget);
      expect(find.text('管理房间 / 重新开放'), findsNothing);
      for (final key in [
        'video-room-seat-grid',
        'video-room-public-screen',
        'video-room-composer',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      expect(rtc.joined, isFalse);
      expect(controller.snapshot!.roomLease, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('private entry requires authority; identity clears late grants', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.notifier.dispose);
    final first = Completer<bool>();
    repository.grant = () => first.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlatformRoomsEntry(repository: repository)),
      ),
    );
    expect(find.text('平台房间管理'), findsNothing);
    repository.grant = () async => false;
    repository.notifier.value = (2, 2);
    first.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('平台房间管理'), findsNothing);
    repository.grant = () async => true;
    repository.notifier.value = (1, 3);
    await tester.pumpAndSettle();
    expect(find.text('平台房间管理'), findsOneWidget);
    repository.grant = () async => false;
    repository.notifier.value = (2, 4);
    await tester.pumpAndSettle();
    expect(find.text('平台房间管理'), findsNothing);
  });
  testWidgets('old directory rejects revoked access and clears A rows on B', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlatformRoomsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('A private room'), findsOneWidget);
    repository.grant = () async => false;
    repository.notifier.value = (2, 2);
    await tester.pumpAndSettle();
    expect(find.text('A private room'), findsNothing);
    expect(find.textContaining('无法读取平台房间'), findsOneWidget);
  });
  testWidgets('late directory response cannot restore A content', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.notifier.dispose);
    final response = Completer<PlatformRoomPageResult>();
    repository.read = () => response.future;
    await tester.pumpWidget(
      MaterialApp(home: PlatformRoomsPage(repository: repository)),
    );
    repository.read = () async => const PlatformRoomPageResult([], 1, false);
    repository.notifier.value = (2, 2);
    response.complete(repository.result);
    await tester.pumpAndSettle();
    expect(find.text('A private room'), findsNothing);
  });
  testWidgets(
    'confirmation freezes room/version; reopen never claims automatic entry',
    (tester) async {
      final repository = _Repository();
      addTearDown(repository.notifier.dispose);
      var completed = 0;
      Widget view(int version) => MaterialApp(
        home: Scaffold(
          body: PlatformRoomLifecycleButton(
            repository: repository,
            roomId: 'room-A',
            version: version,
            reopen: true,
            onCompleted: () async {
              completed++;
            },
          ),
        ),
      );
      await tester.pumpWidget(view(7));
      await tester.tap(find.text('重新开放房间'));
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      expect(find.textContaining('不会自动连接语音'), findsOneWidget);
      await tester.pumpWidget(view(9));
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(repository.writes.single, ('room-A', 7, true));
      expect(completed, 1);
    },
  );
  testWidgets(
    'unknown preserves original command on remount; repeat click does not submit twice',
    (tester) async {
      final repository = _Repository();
      addTearDown(repository.notifier.dispose);
      var completed = 0;
      repository.send = () async => throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'unknown',
      );
      Widget view() => MaterialApp(
        home: Scaffold(
          body: PlatformRoomLifecycleButton(
            repository: repository,
            roomId: 'room-A',
            version: 9,
            reopen: false,
            onCompleted: () async {
              completed++;
            },
          ),
        ),
      );
      await tester.pumpWidget(view());
      await tester.tap(find.text('关闭房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      final pending = repository.pending;
      expect(find.textContaining('结果尚未确认'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view());
      expect(repository.pending, same(pending));
      final release = Completer<void>();
      repository.send = () => release.future;
      await tester.tap(find.text('重试原房间操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.tap(find.text('重试原房间操作'));
      await tester.pump();
      expect(repository.writes.length, 2);
      expect(repository.writes[0], repository.writes[1]);
      release.complete();
      await tester.pumpAndSettle();
      expect(completed, 1);
    },
  );
  testWidgets('switch identity after confirm prevents late success UI', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.notifier.dispose);
    final release = Completer<void>();
    repository.send = () => release.future;
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformRoomLifecycleButton(
            repository: repository,
            roomId: 'room-A',
            version: 7,
            reopen: true,
            onCompleted: () async {
              completed++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('重新开放房间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pump();
    repository.notifier.value = (2, 2);
    await tester.pump();
    release.complete();
    await tester.pumpAndSettle();
    expect(completed, 0);
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('switch during confirmation sends nothing', (tester) async {
    final repository = _Repository();
    addTearDown(repository.notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformRoomLifecycleButton(
            repository: repository,
            roomId: 'room-A',
            version: 7,
            reopen: false,
            onCompleted: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('关闭房间'));
    await tester.pumpAndSettle();
    repository.notifier.value = (2, 2);
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.writes, isEmpty);
  });
}

class _ClosedStaff extends MockRoomRepository {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => RoomSnapshot(
    roomId: roomId,
    roomCode: roomId,
    title: 'closed',
    topic: '',
    ownerId: 42,
    role: RoomRole.listener,
    seats: const [],
    rtc: const RtcCredentials(token: '', channelId: ''),
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: 0,
    transportMode: RoomTransportMode.snapshotOnly,
    platformStaff: true,
    closedRoomAccess: true,
    canControlRoomLifecycle: true,
    version: 7,
  );
}

/// Deliberate asynchronous test double, not the app's demo repository.
class _Repository implements PlatformRoomRepository {
  final notifier = ValueNotifier((1, 1));
  Future<bool> Function() grant = () async => true;
  Future<PlatformRoomPageResult> Function()? read;
  Future<void> Function() send = () async {};
  final writes = <(String, int, bool)>[];
  final Map<int, PendingRoomLifecycle> _pending = {};
  final result = const PlatformRoomPageResult(
    [
      PlatformRoom(
        roomId: 'room-A',
        roomCode: '1',
        roomName: 'A private room',
        ownerUserId: 42,
        status: 'CLOSED',
        version: 7,
        accessMode: 'PASSWORD',
      ),
    ],
    1,
    false,
  );
  @override
  (int, int) get identity => notifier.value;
  @override
  Listenable get identityChanges => notifier;
  @override
  PendingRoomLifecycle? get pending => _pending[identity.$1];
  @override
  Future<bool> authority() => grant();
  @override
  Future<PlatformRoomPageResult> list({
    int page = 1,
    String keyword = '',
  }) async {
    if (!await authority())
      throw const ApiException(
        kind: ApiFailureKind.business,
        httpStatus: 403,
        message: 'denied',
      );
    return read == null ? result : await read!();
  }

  @override
  Future<void> control({
    required String roomId,
    required int version,
    required bool reopen,
  }) async {
    final original = identity;
    writes.add((roomId, version, reopen));
    _pending.putIfAbsent(
      original.$1,
      () => PendingRoomLifecycle(roomId, version, reopen),
    );
    await send();
    if (identity == original) _pending.remove(original.$1);
  }
}
