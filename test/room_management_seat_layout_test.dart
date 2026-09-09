import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

import 'support/golden_font_gate.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final size in [
    const Size(390, 844),
    const Size(360, 800),
    const Size(375, 667),
    const Size(402, 874),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('seat controls fit ${size.width} at scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.room(fontFamily: kGoldenFontFamily),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RoomManagementPage(
              roomId: 'layout-room',
              roomCode: 'M4APV7',
              currentUserId: 20001,
              currentRole: RoomRole.owner,
              repositoryOverride: MockRoomOperationsRepository(),
              seats: List.generate(
                8,
                (index) => MicSeat(
                  number: index + 1,
                  backendIndex: index,
                  state: MicSeatState.available,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('房间号 M4APV7 · 权威状态管理'), findsOneWidget);
        expect(find.textContaining('房间号 layout-room'), findsNothing);
        await tester.tap(find.text('麦位管理'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('4 号麦'),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        final emptyCard = find.ancestor(
          of: find.text('4 号麦'),
          matching: find.byType(RoomGlassCard),
        );
        final lock = find.descendant(
          of: emptyCard,
          matching: find.widgetWithText(ActionChip, '锁定'),
        );
        final mute = find.descendant(
          of: emptyCard,
          matching: find.widgetWithText(ActionChip, '闭麦'),
        );
        final card = find
            .ancestor(of: lock, matching: find.byType(RoomGlassCard))
            .first;
        for (final control in [lock, mute]) {
          expect(control.hitTestable(), findsOneWidget);
          final cardRect = tester.getRect(card);
          final controlRect = tester.getRect(control);
          expect(cardRect.contains(controlRect.topLeft), isTrue);
          expect(cardRect.contains(controlRect.bottomRight), isTrue);
        }
        await tester.tap(lock);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ActionChip, '解锁').hitTestable(),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('8 号麦'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('8 号麦').hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
