import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  for (final exit in ['button', 'close', 'back', 'identity']) {
    testWidgets('closed owner management has no live controls: $exit', (
      tester,
    ) async {
      final dependencies = AppDependencies.mock();
      await tester.runAsync(
        () => dependencies.roomLifecycleRepository.closeRoom('952700'),
      );
      final repository = _ClosedOwnerRepository();
      final realtime = MockRoomRealtimeGateway();
      final rtc = MockRtcAdapter();
      final identity = ValueNotifier<int?>(10);
      final controller = RoomController(
        roomId: '952700',
        title: '关闭房间',
        currentUserId: 10,
        accessToken: 'test',
        repository: repository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
        sessionChanges: identity,
        activeUserId: () => identity.value,
      );
      addTearDown(() async {
        controller.dispose();
        identity.dispose();
        await realtime.dispose();
        dependencies.dispose();
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('test home')),
          ),
        ),
      );
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => VideoRuntimeRoomPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('房间已关闭 · 房主管理视图'), findsOneWidget);
      expect(controller.snapshot?.ownerClosedAccess, isTrue);
      expect(controller.snapshot?.sessionId, isNull);
      expect(controller.snapshot?.roomLease, isNull);
      expect(rtc.joined, isFalse);
      for (final key in [
        'video-room-seat-grid',
        'video-room-public-screen',
        'video-room-composer',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      for (final text in ['礼物', '成员', '上麦', '查看申请状态', '入房申请状态', '继续进入']) {
        expect(find.text(text), findsNothing);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.text('管理房间 / 重新开放'), findsOneWidget);
      if (exit == 'button') {
        await tester.tap(find.text('管理房间 / 重新开放'));
        await tester.pumpAndSettle();
        expect(find.byType(EditRoomPage), findsOneWidget);
        expect(repository.entries, 1);
        expect(rtc.joined, isFalse);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '退出管理视图'));
      } else if (exit == 'close') {
        await tester.tap(find.byTooltip('退出管理视图'));
      } else if (exit == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        identity.value = 11;
        await tester.pumpAndSettle();
        expect(find.text('管理房间 / 重新开放'), findsNothing);
        expect(find.text('重新进入'), findsNothing);
        expect(controller.snapshot, isNull);
        await controller.join();
        expect(repository.entries, 1);
        await tester.tap(find.text('返回首页'));
      }
      await tester.pumpAndSettle();
      expect(find.text('test home'), findsOneWidget);
      expect(
        repository.exits,
        0,
        reason: 'management has no membership to exit',
      );
      expect(repository.entries, 1);
      expect(rtc.joined, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _ClosedOwnerRepository extends MockRoomRepository {
  int entries = 0;
  int exits = 0;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    entries++;
    return RoomSnapshot(
      roomId: roomId,
      roomCode: roomId,
      title: '关闭房间',
      topic: '',
      ownerId: 10,
      role: RoomRole.owner,
      seats: const [],
      rtc: const RtcCredentials(token: '', channelId: ''),
      publicScreenEnabled: false,
      pictureMessagesAllowed: false,
      autoLockMic: false,
      giftCatalogAvailable: false,
      giftBalance: 0,
      transportMode: RoomTransportMode.snapshotOnly,
      ownerClosedAccess: true,
    );
  }

  @override
  Future<void> exitRoom(String roomId) async {
    exits++;
  }
}
