import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

Future<void> runM24VisualSuite(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  const QaScenario scenario = QaScenario(
    role: QaRole.registeredUser,
    state: QaPageState.normal,
    mockScenario: QaMockScenario.defaultData,
    network: QaNetworkScenario.normal,
  );

  for (final QaPageEntry entry in qaPageCatalog) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final AppDependencies dependencies = await createQaDependencies();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData media = MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale));
            return MediaQuery(data: media, child: child!);
          },
          home: entry.builder(dependencies, scenario),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.takeException(),
      isNull,
      reason:
          '${entry.id} must render at ${size.width}×${size.height}, ${textScale}× text',
    );
    expect(find.byType(Scaffold), findsWidgets, reason: entry.id);
  }

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
