import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

void main() {
  _touchAndContrastTests();
  for (final reduced in [false, true]) {
    testWidgets('reduced motion=$reduced never delays an enabled action', (
      tester,
    ) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: GestureDetector(
                    onTap: () => actions++,
                    child: AnimatedContainer(
                      key: const Key('motion-probe'),
                      duration: AppMotion.forContext(
                        context,
                        AppMotion.navigation,
                      ),
                      width: 48,
                      height: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final control = tester.widget<AnimatedContainer>(
        find.byKey(const Key('motion-probe')),
      );
      expect(control.duration, reduced ? Duration.zero : AppMotion.navigation);
      await tester.tap(find.byKey(const Key('motion-probe')));
      // No animation pumping is needed before the command callback is observed.
      expect(actions, 1);
    });
  }

  testWidgets(
    'a changed system preference updates the mounted visual duration',
    (tester) async {
      final preference = ValueNotifier(false);
      addTearDown(preference.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: preference,
            builder: (_, reduced, __) => MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Builder(
                builder: (context) => AnimatedContainer(
                  key: const Key('dynamic-motion-probe'),
                  duration: AppMotion.forContext(context, AppMotion.press),
                  width: 48,
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      );
      final finder = find.byKey(const Key('dynamic-motion-probe'));
      expect(
        tester.widget<AnimatedContainer>(finder).duration,
        AppMotion.press,
      );
      preference.value = true;
      await tester.pump();
      expect(tester.widget<AnimatedContainer>(finder).duration, Duration.zero);
      preference.value = false;
      await tester.pump();
      expect(
        tester.widget<AnimatedContainer>(finder).duration,
        AppMotion.press,
      );
    },
  );
}

void _touchAndContrastTests() {
  for (final enabled in [false, true]) {
    testWidgets(
      'room action enabled=$enabled has a separate 44px hit surface',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.room(),
            home: Scaffold(
              body: Center(
                child: RoomOxygenPill(
                  label: '上麦',
                  enabled: enabled,
                  onTap: () => calls++,
                ),
              ),
            ),
          ),
        );
        final parent = find.byType(RoomOxygenPill);
        final hit = find.descendant(of: parent, matching: find.byType(InkWell));
        final painted = find.descendant(
          of: parent,
          matching: find.byType(AnimatedContainer),
        );
        expect(hit, findsOneWidget);
        expect(tester.getSize(hit).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(hit).width, greaterThanOrEqualTo(44));
        expect(
          tester.getSize(painted).height,
          lessThan(44),
          reason: 'Do not enlarge the painted pill',
        );
        await tester.tap(hit);
        expect(calls, enabled ? 1 : 0);
      },
    );
  }
  test(
    'authored semantic text and filled controls satisfy flat-surface contrast',
    () {
      final pairs = <(Color, Color)>[
        (SocialColors.textPrimary, SocialColors.card),
        (SocialColors.textSecondary, SocialColors.cardSoft),
        (SocialColors.textTertiary, SocialColors.cardSoft),
        (Colors.white, SocialColors.primary),
        (SocialColors.success, SocialColors.cardSoft),
        (SocialColors.warning, SocialColors.cardSoft),
        (SocialColors.error, SocialColors.cardSoft),
        (RoomColors.background, RoomColors.primary),
      ];
      final light = AppTheme.social().colorScheme;
      pairs.addAll([
        (light.onSecondary, light.secondary),
        (light.onTertiary, light.tertiary),
      ]);
      for (final pair in pairs) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
      final colors = SocialColors.brandGradient.colors;
      for (var stop = 0; stop < colors.length - 1; stop++) {
        for (var sample = 0; sample <= 20; sample++) {
          expect(
            _contrast(
              Colors.white,
              Color.lerp(colors[stop], colors[stop + 1], sample / 20)!,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}
