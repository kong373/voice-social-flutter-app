import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/domain/preset_avatar.dart';
import 'package:voice_social_app/features/account/presentation/preset_avatar_view.dart';

void main() {
  testWidgets('null selection renders all six with nothing preselected', (
    tester,
  ) async {
    _enableSemantics(tester);
    final events = <String>[];

    await _pumpPicker(tester, onSelected: events.add);

    expect(events, isEmpty);
    expect(find.byType(PresetAvatarView), findsNWidgets(6));
    _expectSelection(tester, selectedId: null);

    for (final avatar in PresetAvatars.values) {
      expect(find.text(avatar.label), findsOneWidget);
      expect(_option(avatar.id).hitTestable(), findsOneWidget);

      // Search actual semantics nodes rather than descendant widget labels.
      expect(find.semantics.byLabel(avatar.label).evaluate(), hasLength(1));
      expect(find.semantics.byLabel('${avatar.label}头像').evaluate(), isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('each explicit parent choice selects exactly that option', (
    tester,
  ) async {
    _enableSemantics(tester);
    final events = <String>[];

    for (final avatar in PresetAvatars.values) {
      await _pumpPicker(tester, selectedId: avatar.id, onSelected: events.add);
      await tester.pump(const Duration(milliseconds: 160));

      _expectSelection(tester, selectedId: avatar.id);
      expect(events, isEmpty);
    }

    await _pumpPicker(tester, onSelected: events.add);
    await tester.pump(const Duration(milliseconds: 160));
    _expectSelection(tester, selectedId: null);
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taps report exact IDs once without saving selection', (
    tester,
  ) async {
    _enableSemantics(tester);
    final events = <String>[];
    final expected = <String>[];

    await _pumpPicker(tester, onSelected: events.add);

    for (final avatar in PresetAvatars.values) {
      await tester.tap(_option(avatar.id));
      await tester.pump(const Duration(milliseconds: 160));
      expected.add(avatar.id);

      expect(events, orderedEquals(expected));
      _expectSelection(tester, selectedId: null);
    }

    const selected = 'avatar-preset-moon';
    await _pumpPicker(tester, selectedId: selected, onSelected: events.add);
    await tester.pump(const Duration(milliseconds: 160));
    events.clear();

    await tester.tap(_option('avatar-preset-leaf'));
    await tester.pump(const Duration(milliseconds: 160));

    expect(events, <String>['avatar-preset-leaf']);
    _expectSelection(tester, selectedId: selected);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled options retain selection but expose no tap action', (
    tester,
  ) async {
    _enableSemantics(tester);
    final events = <String>[];
    const selected = 'avatar-preset-sea';

    await _pumpPicker(
      tester,
      selectedId: selected,
      enabled: false,
      onSelected: events.add,
    );

    _expectSelection(tester, selectedId: selected, enabled: false);

    for (final avatar in PresetAvatars.values) {
      await tester.tap(_option(avatar.id));
      await tester.pump();
    }

    expect(events, isEmpty);
    _expectSelection(tester, selectedId: selected, enabled: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown selectedId does not select or replace any preset', (
    tester,
  ) async {
    _enableSemantics(tester);
    final events = <String>[];

    await _pumpPicker(
      tester,
      selectedId: 'avatar-preset-not-real',
      onSelected: events.add,
    );

    _expectSelection(tester, selectedId: null);
    expect(find.byType(PresetAvatarView), findsNWidgets(6));
    expect(find.semantics.byLabel('头像不可用').evaluate(), isEmpty);
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown preview renders a neutral unavailable placeholder', (
    tester,
  ) async {
    _enableSemantics(tester);

    await tester.pumpWidget(
      _host(const PresetAvatarView(presetId: 'avatar-preset-not-real')),
    );

    final view = find.byType(PresetAvatarView);
    expect(view, findsOneWidget);
    expect(tester.getSize(view), const Size(64, 64));
    expect(
      tester.semantics.find(view),
      matchesSemantics(label: '头像不可用', isImage: true, children: const []),
    );
    expect(find.semantics.byLabel('头像不可用').evaluate(), hasLength(1));

    for (final avatar in PresetAvatars.values) {
      expect(find.semantics.byLabel('${avatar.label}头像').evaluate(), isEmpty);
    }

    final paint = find.descendant(of: view, matching: find.byType(CustomPaint));
    expect(paint, findsOneWidget);
    expect(tester.widget<CustomPaint>(paint).painter, isNotNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in <double>[32, 72, 96]) {
    testWidgets('all six vector previews render visibly at ${size.toInt()}px', (
      tester,
    ) async {
      _enableSemantics(tester);

      await tester.pumpWidget(
        _host(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final avatar in PresetAvatars.values)
                PresetAvatarView(
                  key: ValueKey<String>('preview:${avatar.id}'),
                  presetId: avatar.id,
                  size: size,
                ),
            ],
          ),
        ),
      );

      expect(find.byType(PresetAvatarView), findsNWidgets(6));
      for (final avatar in PresetAvatars.values) {
        final view = find.byKey(ValueKey<String>('preview:${avatar.id}'));

        expect(view.hitTestable(), findsOneWidget);
        expect(tester.getSize(view), Size.square(size));
        expect(
          tester.semantics.find(view),
          matchesSemantics(
            label: '${avatar.label}头像',
            isImage: true,
            children: const [],
          ),
        );

        final paint = find.descendant(
          of: view,
          matching: find.byType(CustomPaint),
        );
        expect(paint, findsOneWidget);
        expect(tester.widget<CustomPaint>(paint).painter, isNotNull);
      }

      expect(find.byType(Image), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[320, 375, 430]) {
    testWidgets('picker fits ${width.toInt()}px with text scale 1.3', (
      tester,
    ) async {
      _enableSemantics(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpPicker(
        tester,
        textScale: 1.3,
        selectedId: 'avatar-preset-star',
      );
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.byType(PresetAvatarView), findsNWidgets(6));
      _expectSelection(tester, selectedId: 'avatar-preset-star');

      for (final avatar in PresetAvatars.values) {
        final option = _option(avatar.id);
        final bounds = tester.getRect(option);
        final label = find.text(avatar.label);

        expect(option.hitTestable(), findsOneWidget);
        expect(label, findsOneWidget);
        expect(label.hitTestable(), findsOneWidget);
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.left, greaterThanOrEqualTo(11.99));
        expect(bounds.right, lessThanOrEqualTo(width - 11.99));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(720));

        final scaler = MediaQuery.textScalerOf(tester.element(label));
        expect(scaler.scale(14), closeTo(18.2, 0.001));
      }

      // Includes RenderFlex/paint/layout exceptions; none are suppressed.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion makes selection-border feedback immediate', (
    tester,
  ) async {
    _enableSemantics(tester);

    for (final useAccessibleNavigation in <bool>[false, true]) {
      await _pumpPicker(
        tester,
        reduceMotion: !useAccessibleNavigation,
        accessibleNavigation: useAccessibleNavigation,
      );
      await _pumpPicker(
        tester,
        selectedId: 'avatar-preset-sun',
        reduceMotion: !useAccessibleNavigation,
        accessibleNavigation: useAccessibleNavigation,
      );
      await tester.pump();

      final ringFinder = find.descendant(
        of: find.byType(PresetAvatarPicker),
        matching: find.byType(AnimatedContainer),
      );
      expect(ringFinder, findsNWidgets(6));
      for (final ring in tester.widgetList<AnimatedContainer>(ringFinder)) {
        expect(ring.duration, Duration.zero);
      }

      _expectSelection(tester, selectedId: 'avatar-preset-sun');
      expect(tester.takeException(), isNull);
    }
  });
}

Finder _option(String id) {
  return find.byKey(ValueKey<String>('preset-avatar-option:$id'));
}

void _enableSemantics(WidgetTester tester) {
  // testWidgets owns an enabled handle in Flutter 3.44.7. A second handle
  // disposed by addTearDown survives the framework's earlier leak check.
  // Assert the real semantics tree is enabled; retain every semantic assertion.
  expect(tester.binding.semanticsEnabled, isTrue);
}

void _expectSelection(
  WidgetTester tester, {
  required String? selectedId,
  bool enabled = true,
}) {
  for (final avatar in PresetAvatars.values) {
    final option = _option(avatar.id);
    expect(option, findsOneWidget);
    expect(
      tester.semantics.find(option),
      matchesSemantics(
        label: avatar.label,
        isButton: true,
        hasSelectedState: true,
        isSelected: selectedId == avatar.id,
        hasEnabledState: true,
        isEnabled: enabled,
        hasTapAction: enabled,
        children: const [],
      ),
      reason: 'Selection/action semantics for ${avatar.id}',
    );
  }
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  String? selectedId,
  ValueChanged<String>? onSelected,
  bool enabled = true,
  double textScale = 1,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
}) {
  return tester.pumpWidget(
    _host(
      PresetAvatarPicker(
        selectedId: selectedId,
        onSelected: onSelected ?? (_) {},
        enabled: enabled,
      ),
      textScale: textScale,
      reduceMotion: reduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
  );
}

Widget _host(
  Widget child, {
  double textScale = 1,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            accessibleNavigation: accessibleNavigation,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        );
      },
    ),
  );
}
