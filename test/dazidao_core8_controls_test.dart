import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'support/golden_font_gate.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final size in [const Size(375, 667), const Size(390, 844)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('room dock edge taps and single handles $size x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dependencies = AppDependencies.mock(
          mockNow: DateTime(2026, 8, 20, 18, 12),
        );
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.room(fontFamily: kGoldenFontFamily),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: MainShell(
                dependencies: dependencies,
                onSignOut: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('live-room-880217')));
        await tester.pumpAndSettle();
        final expression = find.byKey(const Key('room-expression-button'));
        final rect = tester.getRect(expression);
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        final mic = find.ancestor(
          of: find.text('上麦').hitTestable(),
          matching: find.byType(InkWell),
        );
        expect(mic, findsOneWidget);
        expect(tester.getSize(mic).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(mic).width, greaterThanOrEqualTo(44));
        for (final label in ['礼物', '成员', '更多']) {
          final action = find.ancestor(
            of: find.text(label).hitTestable(),
            matching: find.byType(InkResponse),
          );
          expect(action, findsOneWidget);
          expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
        }
        await tester.tapAt(rect.bottomRight - const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('room-expression-sheet')), findsOneWidget);
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
          false,
        );
        Navigator.of(
          tester.element(find.byKey(const Key('room-expression-sheet'))),
        ).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('礼物').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('送礼物'), findsOneWidget);
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
          false,
        );
        // Dismiss and reopen without issuing a gift or microphone command.
        final sheet = tester.element(find.byType(BottomSheet));
        Navigator.of(sheet).pop();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        await tester.tap(find.text('礼物').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('送礼物'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
