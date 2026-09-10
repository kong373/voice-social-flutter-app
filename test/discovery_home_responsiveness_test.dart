import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/room/presentation/room_cover_artwork.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets('DS-001 keeps nine seats and full count at $size / 1.3x', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = await createQaDependencies();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        dependencies.dispose();
      });
      final rooms = dependencies.discoveryRepository.fetchHomeRooms();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const Scaffold(body: HomePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final room = (await rooms).first;
      expect(tester.takeException(), isNull);
      final hero = find.byType(RoomCoverArtwork);
      final indicators = find.descendant(
        of: hero,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              [Icons.person_rounded, Icons.add_rounded].contains(widget.icon),
        ),
      );
      final count = find.descendant(
        of: hero,
        matching: find.text('${room.occupiedSeats}/9 麦'),
      );
      expect(indicators, findsNWidgets(9));
      expect(count, findsOneWidget);
      final countBounds = tester.getRect(count);
      for (final indicator in indicators.evaluate()) {
        final bounds = tester.getRect(find.byWidget(indicator.widget));
        expect(bounds.right, lessThan(countBounds.left));
        expect((indicator.widget as Icon).size, 12);
      }
      expect(tester.getRect(hero).contains(countBounds.bottomRight), isTrue);
      for (final text in [room.title, room.topic, '进入房间']) {
        expect(
          find.descendant(of: hero, matching: find.text(text)),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('收藏与我的房间'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedRoomsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
