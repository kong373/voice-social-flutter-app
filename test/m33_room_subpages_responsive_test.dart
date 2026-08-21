import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

void main() {
  const List<String> roomSubpageIds = <String>[
    'RM-001',
    'RM-002',
    'RM-003',
    'RM-006',
    'RM-007',
    'RM-008',
    'RM-009',
    'RM-010',
    'RM-011',
    'RM-012',
    'RM-013',
    'RM-014',
  ];

  for (final double textScale in <double>[1, 1.3]) {
    testWidgets('room subpages fit 360x800 at ${textScale}x text', (
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

      for (final String id in roomSubpageIds) {
        final QaPageEntry entry = qaPageCatalog.firstWhere(
          (QaPageEntry item) => item.id == id,
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
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: entry.builder(dependencies, scenario),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '$id at ${textScale}x');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}
