import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  // Old RM-009 share positive: REMOVED_BY_PRODUCT Q10-04.
  for (final role in [RoomRole.listener, RoomRole.owner]) {
    testWidgets('$role tools cannot share or copy; management stays scoped', (
      tester,
    ) async {
      final dependencies = AppDependencies.mock();
      final repository = MockRoomRepository()..seedEntryRoleForQa(role);
      final controller = RoomController(
        roomId: 'room',
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
      var clipboardWrites = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.runAsync(controller.join);
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsNothing);
      expect(find.text('复制房间号'), findsNothing);
      expect(find.text('复制房间邀请'), findsNothing);
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('成员')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('公告')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('房管')),
        role == RoomRole.owner ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('房间 PK')),
        role == RoomRole.owner ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsNothing);
      expect(find.text('音频'), findsOneWidget);
      expect(find.text('离开房间'), findsOneWidget);
      expect(clipboardWrites, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
