import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';

void main() {
  test('shared motion tokens stay within responsive interaction budgets', () {
    expect(AppMotion.press.inMilliseconds, inInclusiveRange(100, 160));
    expect(AppMotion.navigation.inMilliseconds, inInclusiveRange(100, 160));
    expect(AppMotion.menu.inMilliseconds, inInclusiveRange(150, 250));
    expect(AppMotion.panel.inMilliseconds, inInclusiveRange(200, 300));
  });

  testWidgets('shared social controls expose pressable semantics and targets', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SocialCard(
                  key: const Key('surface-card'),
                  onTap: () {},
                  child: const Text('房间卡'),
                ),
                SocialPill(
                  key: const Key('surface-pill'),
                  label: '推荐',
                  active: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byKey(const Key('surface-pill'))).height, 44);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.button == true,
        ),
        findsNWidgets(2),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('room glass cards retain a target when interactive', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.room(),
          home: Scaffold(
            body: RoomGlassCard(
              key: const Key('room-card'),
              onTap: () {},
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byKey(const Key('room-card'))).height, 80);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.button == true,
        ),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('minimized room exit keeps a full touch target', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: Scaffold(
          body: MinimizedRoomPill(
            title: '深夜温柔陪伴',
            onRestore: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byTooltip('退出当前房间')), const Size(44, 44));
  });
}
