import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

void main() {
  late bool goldenFontsAvailable;
  late GoldenFileComparator originalGoldenComparator;

  setUpAll(() async {
    originalGoldenComparator = goldenFileComparator;
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.file(
        '${Directory.current.path}/test/m33_all_pages_visual_golden_test.dart',
      ),
      precisionTolerance: 0.001,
    );
    goldenFontsAvailable = await _loadGoldenFonts();
  });

  tearDownAll(() {
    goldenFileComparator = originalGoldenComparator;
  });

  for (final QaPageEntry entry in qaPageCatalog) {
    testWidgets('${entry.id} ${entry.name} visual contract at 390x844', (
      WidgetTester tester,
    ) async {
      if (!goldenFontsAvailable) return;
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
              theme: AppTheme.social(fontFamily: 'M3GoldenCjk'),
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
          'goldens/m3_3_all/${entry.id.toLowerCase()}_390x844.png',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

Future<bool> _loadGoldenFonts() async {
  final File fallbackFont = File(
    '${Directory.current.parent.path}/artifacts/m3-3/fonts/M3GoldenCjk.ttf',
  );
  if (!fallbackFont.existsSync()) return false;
  final File regularFont = File(
    '${Directory.current.parent.path}/artifacts/m3-3/fonts/M3GoldenCjkRegular.ttf',
  );
  final File boldFont = File(
    '${Directory.current.parent.path}/artifacts/m3-3/fonts/M3GoldenCjkBold.ttf',
  );
  final File visualFont = regularFont.existsSync() ? regularFont : fallbackFont;
  final Uint8List regularBytes = visualFont.readAsBytesSync();
  final FontLoader loader = FontLoader('M3GoldenCjk')
    ..addFont(
      Future<ByteData>.value(
        regularBytes.buffer.asByteData(
          regularBytes.offsetInBytes,
          regularBytes.lengthInBytes,
        ),
      ),
    );
  if (boldFont.existsSync()) {
    final Uint8List boldBytes = boldFont.readAsBytesSync();
    loader.addFont(
      Future<ByteData>.value(
        boldBytes.buffer.asByteData(
          boldBytes.offsetInBytes,
          boldBytes.lengthInBytes,
        ),
      ),
    );
  }
  await loader.load();

  final Directory flutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent.parent;
  final Uint8List iconBytes = File(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  final FontLoader iconLoader = FontLoader('MaterialIcons')
    ..addFont(
      Future<ByteData>.value(
        iconBytes.buffer.asByteData(
          iconBytes.offsetInBytes,
          iconBytes.lengthInBytes,
        ),
      ),
    );
  await iconLoader.load();
  return true;
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
