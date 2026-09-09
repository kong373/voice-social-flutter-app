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
  for (final role in [RoomRole.owner, RoomRole.moderator, RoomRole.listener]) {
    testWidgets('room profile tool follows authoritative role $role', (
      tester,
    ) async {
      final deps = AppDependencies.mock();
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: '952700',
        title: '工具入口',
        currentUserId: 10001,
        accessToken: 'test-token',
        repository: MockRoomRepository()..seedEntryRoleForQa(role),
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
        deps.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多').hitTestable());
      await tester.pumpAndSettle();
      if (role == RoomRole.listener) {
        expect(find.text('房间资料'), findsNothing);
      } else {
        expect(find.text('房间资料'), findsOneWidget);
        await tester.tap(find.text('房间资料'));
        await tester.pumpAndSettle();
        expect(find.byType(EditRoomPage), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
