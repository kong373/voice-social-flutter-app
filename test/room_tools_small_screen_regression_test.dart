import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  for (final double textScale in <double>[1.0, 1.3]) {
    testWidgets('direct mic sheet fits nine empty seats at ${textScale}x', (
      tester,
    ) async {
      _configureSmallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      final dependencies = AppDependencies.mock();
      final controller = RoomController(
        roomId: '952700',
        title: '房间',
        currentUserId: 10001,
        accessToken: 'test',
        repository: _EmptyOwnedRoomRepository(),
        rtcAdapter: const SnapshotOnlyRtcAdapter(),
        realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
      );
      addTearDown(() {
        controller.dispose();
        dependencies.dispose();
      });
      await tester.runAsync(controller.join);
      expect(controller.role, RoomRole.owner);
      expect(controller.isOnMic, isFalse);
      expect(controller.seats.where((seat) => seat.isAvailable), hasLength(9));
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social().copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester, 'nine empty seats room');
      await tester.tap(find.text('上麦').hitTestable());
      await tester.pumpAndSettle();
      _expectNoFlutterException(
        tester,
        'direct mic sheet with nine empty seats',
      );
      expect(find.text('选择麦位'), findsOneWidget);
      for (var number = 1; number <= 9; number++) {
        expect(find.text('$number 号麦').hitTestable(), findsOneWidget);
      }
    });
  }
  for (final bool ownerOnMic in <bool>[false, true]) {
    for (final double textScale in <double>[1.0, 1.3]) {
      testWidgets(
        'room page and tools sheet fit configured 375x667 viewport at ${textScale}x text with owner ${ownerOnMic ? 'on mic 1' : 'off mic'}',
        (WidgetTester tester) async {
          _configureSmallViewport(tester);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(() {
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.view.resetPadding();
            tester.view.resetViewPadding();
            tester.view.resetViewInsets();
          });

          final AppDependencies dependencies = AppDependencies.mock();
          final MockRoomLifecycleRepository lifecycle =
              MockRoomLifecycleRepository();
          final MockRoomRepository repository = ownerOnMic
              ? MockRoomRepository(lifecycleRepository: lifecycle)
              : (MockRoomRepository()..seedEntryRoleForQa(RoomRole.owner));
          final RoomController controller = RoomController(
            roomId: '952700',
            title: '房间',
            currentUserId: 10001,
            accessToken: 'test',
            repository: repository,
            rtcAdapter: const SnapshotOnlyRtcAdapter(),
            realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
          );
          addTearDown(() {
            controller.dispose();
            dependencies.dispose();
          });
          await tester.runAsync(controller.join);
          expect(controller.role, RoomRole.owner);
          expect(controller.isOnMic, ownerOnMic);
          if (ownerOnMic) {
            expect(controller.seats.first.userId, controller.currentUserId);
          }

          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: AppTheme.social().copyWith(platform: TargetPlatform.iOS),
                builder: (BuildContext context, Widget? child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: VideoRuntimeRoomPage(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectNoFlutterException(tester, 'joined room page');
          expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
          expect(find.byTooltip('更多').hitTestable(), findsOneWidget);
          final MediaQueryData media = MediaQuery.of(
            tester.element(find.byType(VideoRuntimeRoomPage)),
          );
          expect(media.size, const Size(375, 667));
          expect(media.padding, const EdgeInsets.only(top: 20));
          expect(media.viewPadding, const EdgeInsets.only(top: 20));
          expect(media.viewInsets, EdgeInsets.zero);
          expect(media.textScaler.scale(1), textScale);

          await tester.tap(find.byTooltip('更多').hitTestable());
          await tester.pumpAndSettle();
          _expectNoFlutterException(tester, 'tools sheet initial tab');
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.text('互动玩法'), findsOneWidget);
          expect(find.text('工具'), findsOneWidget);

          await tester.tap(find.text('工具').hitTestable());
          await tester.pumpAndSettle();
          _expectNoFlutterException(tester, 'tools sheet tools tab');
          expect(find.text('音频'), findsOneWidget);
          expect(find.text('重新连接'), findsOneWidget);
          expect(find.text('离开房间'), findsOneWidget);
          expect(find.text('主动下麦'), ownerOnMic ? findsOneWidget : findsNothing);
          expect(find.text('更换麦位'), ownerOnMic ? findsOneWidget : findsNothing);

          await tester.tap(find.text('互动玩法').hitTestable());
          await tester.pumpAndSettle();
          _expectNoFlutterException(
            tester,
            'tools sheet back to interactions tab',
          );
          expect(find.text('房间资料'), findsOneWidget);
          expect(find.text('房管'), findsOneWidget);
        },
      );
    }
  }
}

class _EmptyOwnedRoomRepository extends MockRoomRepository {
  _EmptyOwnedRoomRepository()
    : super(lifecycleRepository: MockRoomLifecycleRepository());

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final snapshot = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    return snapshot.copyWith(
      transportMode: RoomTransportMode.snapshotOnly,
      seats: [
        for (var number = 1; number <= 9; number++)
          MicSeat(
            number: number,
            backendIndex: number,
            state: MicSeatState.available,
          ),
      ],
    );
  }
}

void _configureSmallViewport(WidgetTester tester) {
  // Configured test values only: 750x1334 physical pixels at DPR 2, with
  // FakeViewPadding(top: 40) assigned to both viewPadding and padding. This
  // produces MediaQuery size 375x667 and top/bottom padding 20/0; it is not a
  // claim about insets observed on a real device.
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.devicePixelRatio = 2;
  tester.view.viewPadding = const FakeViewPadding(top: 40);
  tester.view.padding = const FakeViewPadding(top: 40);
}

void _expectNoFlutterException(WidgetTester tester, String phase) {
  final Object? exception = tester.takeException();
  if (exception == null) return;
  final String details = exception is FlutterError
      ? exception.toStringDeep()
      : exception.toString();
  fail('Unexpected Flutter exception during $phase:\n$details');
}
