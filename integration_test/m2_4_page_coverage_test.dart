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
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
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
