import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/presentation/room_share_page.dart';

void main() {
  testWidgets(
    'RM-009 keeps clipboard sharing first-party and native sharing fail-closed',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: const RoomSharePage(
            roomId: 'room-10001',
            roomCode: '10001',
            roomTitle: '晚风陪伴厅',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rm-009-copy-room-code')), findsOneWidget);
      expect(find.byKey(const Key('rm-009-copy-room-invite')), findsOneWidget);
      expect(find.text('系统分享：VENDOR_BLOCKED'), findsOneWidget);
      expect(find.textContaining('复制房间号和房间邀请仍可用'), findsOneWidget);
    },
  );
}
