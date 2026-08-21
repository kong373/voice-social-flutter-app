import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

import 'support/golden_font_gate.dart';
import 'support/golden_baseline_path.dart';

void main() {
  late GoldenFileComparator originalGoldenComparator;

  setUpAll(() async {
    originalGoldenComparator = goldenFileComparator;
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.file(
        '${Directory.current.path}/test/m33_all_pages_visual_golden_test.dart',
      ),
      precisionTolerance: 0.001,
    );
    await loadGoldenFonts();
  });

  tearDownAll(() {
    goldenFileComparator = originalGoldenComparator;
  });

  for (final QaPageEntry entry in qaPageCatalog) {
    testWidgets('${entry.id} ${entry.name} visual contract at 390x844', (
      WidgetTester tester,
    ) async {
      _configureGoldenView(tester);
      final AppDependencies dependencies = await createQaDependencies();
      const QaScenario scenario = QaScenario(
        role: QaRole.registeredUser,
        state: QaPageState.normal,
        mockScenario: QaMockScenario.defaultData,
        network: QaNetworkScenario.normal,
      );
      final Key captureKey = Key('m3-all-page-${entry.id}');
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.social(fontFamily: kGoldenFontFamily),
              home: entry.builder(dependencies, scenario),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await _precacheGoldenAssets(tester, captureKey);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull, reason: entry.id);
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          m33GoldenPath(
            'goldens/m3_3_all/${entry.id.toLowerCase()}_390x844.png',
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  test(
    'M3.3 golden font gate fails closed when the baseline font is absent',
    () async {
      final Directory emptyFontDirectory = await Directory.systemTemp
          .createTemp('m33-empty-golden-fonts-');
      addTearDown(() => emptyFontDirectory.delete(recursive: true));

      await expectLater(
        loadGoldenFonts(goldenFontDirectory: emptyFontDirectory),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('M3.3 golden font gate failed'),
          ),
        ),
      );
    },
  );
}

void _configureGoldenView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _precacheGoldenAssets(WidgetTester tester, Key captureKey) async {
  final BuildContext assetContext = tester.element(find.byKey(captureKey));
  const List<String> assetPaths = <String>[
    'assets/runtime/social-sky.png',
    'assets/runtime/room-cosmos.png',
    'assets/runtime/room-cover-ruby.png',
    'assets/runtime/room-cover-island.png',
    'assets/runtime/room-cover-festival.png',
    'assets/runtime/room-cover-moon.png',
    'assets/runtime/avatar-rose.png',
    'assets/runtime/avatar-night.png',
    'assets/runtime/avatar-copper.png',
    'assets/runtime/avatar-silver.png',
    'assets/runtime/gift-blossom.png',
    'assets/runtime/gift-ticket.png',
    'assets/runtime/gift-whale.png',
    'assets/runtime/gift-celebration-banner.png',
  ];
  await tester.runAsync(
    () => Future.wait<void>(
      assetPaths.map(
        (String path) => precacheImage(AssetImage(path), assetContext),
      ),
    ),
  );
}

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         precisionTolerance >= 0 && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final bool passed =
        result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
