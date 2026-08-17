import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';

void main() {
  testWidgets('home to room, gift sheet, and leave flow work', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const VoiceSocialApp());
    expect(find.text('此刻适合你的房间'), findsOneWidget);

    await tester.tap(find.text('进入房间'));
    await tester.pumpAndSettle();
    expect(find.text('深夜温柔陪伴'), findsOneWidget);
    expect(find.text('实时公屏'), findsOneWidget);

    await tester.tap(find.text('礼物'));
    await tester.pumpAndSettle();
    expect(find.text('送礼物'), findsOneWidget);
    expect(find.text('普通礼物'), findsOneWidget);
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('离开房间'));
    await tester.pumpAndSettle();
    expect(find.text('离开房间？'), findsOneWidget);
    await tester.tap(find.text('确认离开'));
    await tester.pumpAndSettle();
    expect(find.text('此刻适合你的房间'), findsOneWidget);
  });
}
