import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/golden_font_gate.dart';

void main() {
  setUpAll(loadGoldenFonts);
  const matrix = bool.fromEnvironment('UI_MATRIX');
  for (final size
      in matrix
          ? const [Size(375, 667), Size(390, 844), Size(402, 874)]
          : const [Size(390, 844)]) {
    for (final scale in matrix ? [1.0, 1.3] : [1.0]) {
      for (final gift in [false, true]) {
        testWidgets(
          'actual room ${gift ? 'gift' : 'expression'} $size x$scale',
          (tester) async {
            await renderDazidaoScenario(
              tester,
              id: gift ? 'runtime-gift' : 'runtime-expression',
              size: size,
              scale: scale,
              useProductionHostTheme: true,
              builder: (dependencies) =>
                  MainShell(dependencies: dependencies, onSignOut: () async {}),
              exercise: (tester, _) async {
                final room = find.byKey(const Key('live-room-880217'));
                await tester.ensureVisible(room);
                await tester.pumpAndSettle();
                expect(room.hitTestable(), findsOneWidget);
                await tester.tap(room.hitTestable());
                await tester.pumpAndSettle();
                await tester.tap(
                  gift
                      ? find.text('礼物').hitTestable()
                      : find.byKey(const Key('room-expression-button')),
                );
                await tester.pumpAndSettle();
                expect(find.byType(BottomSheet), findsOneWidget);
                expect(
                  gift
                      ? find.text('送礼物')
                      : find.byKey(const Key('room-expression-sheet')),
                  findsOneWidget,
                );
                if (gift) {
                  final grid = find.descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(GridView),
                  );
                  expect(grid, findsOneWidget);
                  expect(
                    tester.getSize(grid).height,
                    greaterThanOrEqualTo(140),
                    reason:
                        'Show a complete gift row, including name and price',
                  );
                }
              },
              annotations: {
                'actualRoomModal': true,
                'syntheticRepositories': true,
                'businessWrite': false,
              },
            );
          },
        );
      }
    }
  }
}
