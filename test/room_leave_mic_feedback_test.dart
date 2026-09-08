import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

const _feedback = '下麦未完成，请稍后重试';

void main() {
  for (final scenario in [
    'gate',
    'success',
    'failure',
    'account',
    'unmounted',
    'authority',
  ]) {
    testWidgets('leave mic $scenario reports the actual result', (
      tester,
    ) async {
      final dependencies = AppDependencies.mock();
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'test',
          tokenType: 'Bearer',
          expiresAt: DateTime(2030),
          userId: 10001,
          mobile: '',
          roles: 'USER',
        ),
      );
      final delayed = scenario == 'account' || scenario == 'unmounted';
      final repository = _Repository()
        ..failLeave = scenario == 'failure' || delayed
        ..pendingLeave = delayed ? Completer<void>() : null;
      final controller = RoomController(
        roomId: 'room',
        title: '房间',
        currentUserId: 10001,
        accessToken: 'test',
        sessionChanges: scenario == 'authority'
            ? dependencies.sessionManager
            : null,
        activeUserId: () => dependencies.sessionManager.session?.userId,
        identityGeneration: () =>
            dependencies.sessionManager.identityGeneration,
        repository: repository,
        rtcAdapter: const SnapshotOnlyRtcAdapter(),
        realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
      );
      addTearDown(() {
        controller.dispose();
        dependencies.dispose();
      });
      await controller.join();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('首页')),
          ),
        ),
      );
      final roomRoute = MaterialPageRoute<void>(
        builder: (_) => VideoRuntimeRoomPage(controller: controller),
      );
      unawaited(navigator.currentState!.push(roomRoute));
      await tester.pumpAndSettle();
      if (scenario == 'authority') {
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'other',
            tokenType: 'Bearer',
            expiresAt: DateTime(2030),
            userId: 10002,
            mobile: '',
            roles: 'USER',
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.status, RoomSessionStatus.left);
        expect(repository.leaveCalls, 0);
        final message = find.text('登录状态已变化，请重新进入房间').hitTestable();
        expect(roomRoute.isCurrent, isTrue);
        expect(message, findsOneWidget);
        expect(ModalRoute.of(tester.element(message)), same(roomRoute));
        return;
      }
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      expect(find.text('主动下麦'), findsOneWidget);

      Future<void>? reconnect;
      if (scenario == 'gate') {
        repository.pendingReconnect = Completer<RoomSnapshot>();
        reconnect = controller.reconnect();
        await tester.pump();
        expect(controller.status, RoomSessionStatus.reconnecting);
      }
      await tester.tap(find.text('主动下麦'));
      if (scenario == 'account') {
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'other',
            tokenType: 'Bearer',
            expiresAt: DateTime(2030),
            userId: 10002,
            mobile: '',
            roles: 'USER',
          ),
        );
      } else if (scenario == 'unmounted') {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      }
      repository.pendingLeave?.complete();
      await tester.pumpAndSettle();
      expect(find.text('房间功能'), findsNothing);
      expect(repository.leaveCalls, scenario == 'gate' ? 0 : 1);
      if (delayed) {
        expect(find.text(_feedback), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } else if (scenario == 'success') {
        expect(controller.isOnMic, isFalse);
        expect(find.text(_feedback), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      } else {
        expect(controller.isOnMic, isTrue);
        expect(roomRoute.isCurrent, isTrue);
        expect(find.text(_feedback).hitTestable(), findsOneWidget);
        expect(
          ModalRoute.of(tester.element(find.text(_feedback).hitTestable())),
          same(roomRoute),
        );
      }
      if (reconnect != null) {
        repository.pendingReconnect!.complete(repository.snapshot);
        await reconnect;
        await tester.pumpAndSettle();
      }
    });
  }
}

class _Repository extends MockRoomRepository {
  int leaveCalls = 0;
  bool failLeave = false;
  Completer<void>? pendingLeave;
  Completer<RoomSnapshot>? pendingReconnect;
  RoomSnapshot snapshot = const RoomSnapshot(
    roomId: 'room',
    roomCode: 'room',
    title: '房间',
    topic: '',
    ownerId: 20001,
    role: RoomRole.listener,
    seats: [
      MicSeat(
        number: 1,
        backendIndex: 1,
        state: MicSeatState.occupied,
        userId: 10001,
        userName: '我',
      ),
    ],
    rtc: RtcCredentials(
      solution: RtcSolution.unknown,
      token: '',
      channelId: '',
      userId: 10001,
    ),
    transportMode: RoomTransportMode.snapshotOnly,
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
  );

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => snapshot;

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async =>
      pendingReconnect == null ? snapshot : await pendingReconnect!.future;

  @override
  Future<void> leaveMic() async {
    leaveCalls++;
    if (pendingLeave != null) await pendingLeave!.future;
    if (failLeave) throw StateError('request failed');
    snapshot = snapshot.copyWith(seats: const []);
  }
}
