import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  for (final mode in RoomTransportMode.values) {
    for (final role in [
      RoomRole.moderator,
      RoomRole.listener,
      RoomRole.platformModerator,
    ]) {
      testWidgets('$role PK entry in $mode uses current room authority', (
        tester,
      ) async {
        final dependencies = AppDependencies.mock();
        final repository = _RoleRoom(mode)..seedEntryRoleForQa(role);
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: '880217',
          title: 'Room',
          currentUserId: 10,
          accessToken: 'test',
          repository: repository,
          rtcAdapter: MockRtcAdapter(),
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
        await tester.tap(find.text('更多').hitTestable());
        await tester.pumpAndSettle();
        if (role == RoomRole.moderator) {
          expect(find.text('房间 PK'), findsOneWidget);
          await tester.tap(find.text('房间 PK'));
          await tester.pumpAndSettle();
          expect(find.byType(RoomPkPreparationPage), findsOneWidget);
        } else {
          expect(find.text('房间 PK'), findsNothing);
          expect(find.byType(RoomPkPreparationPage), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

class _RoleRoom extends MockRoomRepository {
  _RoleRoom(this.mode);
  final RoomTransportMode mode;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => (await super.enterRoom(
    roomId: roomId,
    password: password,
    source: source,
    currentUserId: currentUserId,
  )).copyWith(transportMode: mode);
}
