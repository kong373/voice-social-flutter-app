import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

import 'm2_4_test_support.dart';

const String _qaPageShard = String.fromEnvironment(
  'QA_PAGE_SHARD',
  defaultValue: 'all',
);
const String _qaTextScale = String.fromEnvironment(
  'QA_TEXT_SCALE',
  defaultValue: 'all',
);
const int _qaPageShardCount = 5;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'selected real pages render and emit the requested text-scale screenshots',
    (WidgetTester tester) async {
      final List<QaPageEntry> pageEntries = _selectedPageEntries();
      final List<double> textScales = _selectedTextScales();
      for (final double textScale in textScales) {
        final QaScenario scenario = QaScenario(
          role: QaRole.registeredUser,
          state: QaPageState.normal,
          mockScenario: QaMockScenario.defaultData,
          network: QaNetworkScenario.normal,
        );
        for (final QaPageEntry entry in pageEntries) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          final AppDependencies dependencies = await createQaDependencies();
          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: AppTheme.dark(),
                builder: (BuildContext context, Widget? child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: entry.builder(dependencies, scenario),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull, reason: entry.id);
          expect(find.byType(Scaffold), findsWidgets, reason: entry.id);
          expectNoRetiredFeatureText(
            reason: '${entry.id} visible page content',
          );
          final Size size = MediaQuery.of(
            tester.element(find.byType(Scaffold).first),
          ).size;
          final String viewport =
              '${size.width.round()}x${size.height.round()}';
          await captureQaScreenshot(
            tester,
            binding,
            '${entry.id}-normal-$qaAvdId-$viewport-${textScale.toStringAsFixed(1)}x',
          );
          if (textScale == 1) {
            final _PageInteractionResult interaction =
                await _exercisePageInteractions(tester, entry, scenario);
            // The host evidence script parses this exact marker. It is emitted
            // only after every initially visible button at the top, middle,
            // and bottom positions has received a real WidgetTester tap on
            // the Android emulator, and every enabled field has accepted text.
            // ignore: avoid_print
            print(
              'QA_PAGE_INTERACTION_PASS page=${entry.id} '
              'buttons=${interaction.buttonsClicked} '
              'keyboard=${interaction.textFieldsEntered} '
              'scroll=${interaction.scrolled ? 'PASS' : 'NOT_APPLICABLE'}',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

class _PageInteractionResult {
  const _PageInteractionResult({
    required this.buttonsClicked,
    required this.textFieldsEntered,
    required this.scrolled,
  });

  final int buttonsClicked;
  final int textFieldsEntered;
  final bool scrolled;
}

Future<_PageInteractionResult> _exercisePageInteractions(
  WidgetTester tester,
  QaPageEntry entry,
  QaScenario scenario,
) async {
  int buttonsClicked = 0;
  int textFieldsEntered = 0;
  bool scrolled = false;
  const List<int> scrollPasses = <int>[0, 3, 12];

  for (final int scrollPass in scrollPasses) {
    await _pumpEntry(tester, entry, scenario);
    scrolled = await _scrollPage(tester, scrollPass) || scrolled;
    final int actionCount = _enabledActions().evaluate().length;

    for (int actionIndex = 0; actionIndex < actionCount; actionIndex += 1) {
      await _pumpEntry(tester, entry, scenario);
      await _scrollPage(tester, scrollPass);
      final Finder actions = _enabledActions();
      if (actionIndex >= actions.evaluate().length) {
        continue;
      }
      await tester.tap(actions.at(actionIndex), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.id} action $actionIndex after $scrollPass scrolls',
      );
      buttonsClicked += 1;
    }

    await _pumpEntry(tester, entry, scenario);
    await _scrollPage(tester, scrollPass);
    final int fieldCount = _enabledTextFields().evaluate().length;
    for (int fieldIndex = 0; fieldIndex < fieldCount; fieldIndex += 1) {
      await _pumpEntry(tester, entry, scenario);
      await _scrollPage(tester, scrollPass);
      final Finder fields = _enabledTextFields();
      if (fieldIndex >= fields.evaluate().length) {
        continue;
      }
      final Finder field = fields.at(fieldIndex);
      await tester.tap(field, warnIfMissed: false);
      await tester.enterText(field, 'M24');
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.id} text field $fieldIndex after $scrollPass scrolls',
      );
      textFieldsEntered += 1;
    }
  }

  return _PageInteractionResult(
    buttonsClicked: buttonsClicked,
    textFieldsEntered: textFieldsEntered,
    scrolled: scrolled,
  );
}

Future<void> _pumpEntry(
  WidgetTester tester,
  QaPageEntry entry,
  QaScenario scenario,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final AppDependencies dependencies = await createQaDependencies();
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: entry.builder(dependencies, scenario),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull, reason: entry.id);
}

Finder _enabledActions() => find.byWidgetPredicate((Widget widget) {
  if (widget is ButtonStyleButton) {
    return widget.enabled;
  }
  if (widget is IconButton) {
    return widget.onPressed != null;
  }
  if (widget is FloatingActionButton) {
    return widget.onPressed != null;
  }
  if (widget is ListTile) {
    return widget.enabled && widget.onTap != null;
  }
  if (widget is RawChip) {
    return widget.isEnabled;
  }
  if (widget is DropdownButton<Object?>) {
    return widget.onChanged != null;
  }
  return false;
}).hitTestable();

Finder _enabledTextFields() => find
    .byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.enabled != false && !widget.readOnly,
    )
    .hitTestable();

Future<bool> _scrollPage(WidgetTester tester, int passes) async {
  final Finder verticalScrollable = find
      .byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.down ||
                widget.axisDirection == AxisDirection.up),
      )
      .hitTestable();
  if (verticalScrollable.evaluate().isEmpty) {
    return false;
  }
  final Finder target = verticalScrollable.first;
  final ScrollableState state = tester.state<ScrollableState>(target);
  final bool canScroll = state.position.maxScrollExtent > 0;
  for (int pass = 0; pass < passes && canScroll; pass += 1) {
    await tester.drag(target, const Offset(0, -360), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));
  }
  return canScroll;
}

List<QaPageEntry> _selectedPageEntries() {
  if (_qaPageShard == 'all') {
    return qaPageCatalog;
  }
  final int? oneBasedShard = int.tryParse(_qaPageShard);
  if (oneBasedShard == null ||
      oneBasedShard < 1 ||
      oneBasedShard > _qaPageShardCount) {
    throw ArgumentError.value(
      _qaPageShard,
      'QA_PAGE_SHARD',
      'use all or a one-based shard from 1 to $_qaPageShardCount',
    );
  }
  final int shardSize = (qaPageCatalog.length / _qaPageShardCount).ceil();
  final int start = (oneBasedShard - 1) * shardSize;
  final int proposedEnd = start + shardSize;
  final int end = proposedEnd < qaPageCatalog.length
      ? proposedEnd
      : qaPageCatalog.length;
  return qaPageCatalog.sublist(start, end);
}

List<double> _selectedTextScales() => switch (_qaTextScale) {
  'all' => const <double>[1, 1.3],
  '1' || '1.0' => const <double>[1],
  '1.3' => const <double>[1.3],
  _ => throw ArgumentError.value(
    _qaTextScale,
    'QA_TEXT_SCALE',
    'use all, 1.0, or 1.3',
  ),
};
