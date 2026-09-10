import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/display/domain/equipped_decoration.dart';
import 'package:voice_social_app/features/commerce/display/presentation/equipped_decoration_view.dart';

void main() {
  testWidgets(
    'finite wear disappears at its exact expiry without another HTTP read',
    (tester) async {
      var now = DateTime.utc(2026, 9, 10);
      final expiry = now.add(const Duration(seconds: 2));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: EquippedDecorationView(
            decorations: [_frame(expiry)],
            product: DecorationProduct.starRingFrame,
            now: () => now,
            child: const SizedBox.square(dimension: 72, child: Text('avatar')),
          ),
        ),
      );
      expect(_art, findsOneWidget);
      now = expiry;
      await tester.pump(const Duration(seconds: 2));
      expect(_art, findsNothing);
      expect(find.text('avatar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unknown, expired, ambiguous, disabled and removed metadata never paints a frame',
    (tester) async {
      final now = DateTime.utc(2026, 9, 10);
      for (final items in <List<EquippedDecoration>>[
        [_frame(null)],
        [],
        [_frame(now)],
        [_frame(null, key: 'decoration/unknown')],
        [_frame(null), _frame(null)],
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: EquippedDecorationView(
              decorations: items,
              product: DecorationProduct.starRingFrame,
              now: () => now,
            ),
          ),
        );
        expect(
          _art,
          items.length == 1 &&
                  items.single.assetKey == 'decoration/star-ring-frame' &&
                  items.single.expiresAt == null
              ? findsOneWidget
              : findsNothing,
        );
      }
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: EquippedDecorationView(
            decorations: [_frame(null)],
            enabled: false,
            product: DecorationProduct.starRingFrame,
          ),
        ),
      );
      expect(_art, findsNothing);
    },
  );
}

final _art = find.byKey(
  const ValueKey('decoration-art-decoration/star-ring-frame'),
);
EquippedDecoration _frame(
  DateTime? expiresAt, {
  String key = 'decoration/star-ring-frame',
}) => EquippedDecoration(
  decorationId: '00000000-0000-0000-0000-000000000001',
  type: 'AVATAR_FRAME',
  assetKey: key,
  expiresAt: expiresAt,
);
