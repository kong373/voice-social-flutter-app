import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

void main() {
  final List<QaPageEntry> entries = qaPageCatalog
      .where(
        (QaPageEntry entry) =>
            entry.id.startsWith('US-') || entry.id.startsWith('MS-'),
      )
      .toList(growable: false);

  for (final QaPageEntry entry in entries) {
    testWidgets('${entry.id} stays overflow-free at 360x800 and 1.3x text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AppDependencies dependencies = await createQaDependencies();
      const QaScenario scenario = QaScenario(
        role: QaRole.registeredUser,
        state: QaPageState.normal,
        mockScenario: QaMockScenario.defaultData,
        network: QaNetworkScenario.normal,
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.social(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: entry.builder(dependencies, scenario),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull, reason: entry.id);
    });
  }
}
