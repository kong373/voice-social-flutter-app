import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'support/golden_font_gate.dart';

// Native widget renders with synthetic fixtures, never live/device evidence.
// This exporter does not read, update or relax any committed golden baseline.
const _output = String.fromEnvironment('UI_OUTPUT');
const _phase = String.fromEnvironment('UI_PHASE', defaultValue: 'inspect');
const _matrix = bool.fromEnvironment('UI_MATRIX');
const _only = String.fromEnvironment('UI_ONLY');
const _capture = bool.fromEnvironment('UI_CAPTURE', defaultValue: true);
const _safeInsets = bool.fromEnvironment('UI_SAFE_INSETS');
const _keyboard = bool.fromEnvironment('UI_KEYBOARD');
const _keyboardField = int.fromEnvironment(
  'UI_KEYBOARD_FIELD',
  defaultValue: 0,
);
const _reduceMotion = bool.fromEnvironment('UI_REDUCE_MOTION');
void main() {
  setUpAll(loadGoldenFonts);
  final variants = _matrix
      ? <(Size, double)>[
          for (final size in const [
            Size(375, 667),
            Size(390, 844),
            Size(402, 874),
          ])
            for (final scale in [1.0, 1.3]) (size, scale),
        ]
      : <(Size, double)>[(const Size(390, 844), 1.0)];
  final activeIds = appPageManifest.map((page) => page.id).toSet();
  for (final entry in qaPageCatalog.where(
    (entry) => activeIds.contains(entry.id),
  )) {
    if (_only.isNotEmpty && !_only.split(',').contains(entry.id)) continue;
    for (final variant in variants) {
      testWidgets('UI ${entry.id} ${variant.$1} text=${variant.$2}', (
        tester,
      ) async {
        await _render(
          tester,
          id: entry.id,
          size: variant.$1,
          scale: variant.$2,
          builder: (dependencies) => entry.builder(
            dependencies,
            const QaScenario(
              role: QaRole.registeredUser,
              state: QaPageState.normal,
              mockScenario: QaMockScenario.defaultData,
              network: QaNetworkScenario.normal,
            ),
          ),
        );
      });
    }
  }
  for (var tab = 0; tab < 4; tab++) {
    final selected = tab;
    final id =
        'runtime-${const ['home', 'discovery', 'messages', 'account'][selected]}';
    if (_only.isNotEmpty && !_only.split(',').contains(id)) continue;
    for (final variant in variants) {
      testWidgets('UI $id ${variant.$1} text=${variant.$2}', (tester) async {
        await _render(
          tester,
          id: id,
          size: variant.$1,
          scale: variant.$2,
          selectedTab: selected,
          builder: (dependencies) =>
              MainShell(dependencies: dependencies, onSignOut: () async {}),
        );
      });
    }
  }
}

Future<void> _render(
  WidgetTester tester, {
  required String id,
  required Size size,
  required double scale,
  required Widget Function(AppDependencies) builder,
  int? selectedTab,
  Future<void> Function(AppDependencies)? prepare,
  Future<void> Function(WidgetTester, AppDependencies)? exercise,
  void Function()? release,
  Map<String, Object> annotations = const {},
  bool useProductionHostTheme = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  void progress(String stage) {
    if (_output.isEmpty) return;
    final directory = Directory('$_output/$_phase/progress');
    directory.createSync(recursive: true);
    File(
      '${directory.path}/$id-${size.width.toInt()}-text$scale.json',
    ).writeAsStringSync(jsonEncode({'id': id, 'stage': stage}));
  }

  progress('creating-synthetic-dependencies');
  // QA preparation uses a real delayed future before there is a widget to pump.
  final dependencies = (await tester.runAsync(
    () => createQaDependencies().timeout(const Duration(seconds: 15)),
  ))!;
  progress('dependencies-ready');
  final key = GlobalKey();
  final failures = <String>[];
  Object? interactionFailure;
  StackTrace? interactionStack;
  final keyboardInset = ValueNotifier<double>(0);
  try {
    if (prepare != null) await tester.runAsync(() => prepare(dependencies));
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: useProductionHostTheme
                ? AppTheme.room(fontFamily: kGoldenFontFamily)
                : AppTheme.social(fontFamily: kGoldenFontFamily),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: keyboardInset,
              builder: (context, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: _reduceMotion,
                  viewInsets: EdgeInsets.only(bottom: inset),
                  viewPadding: _safeInsets
                      ? const EdgeInsets.only(top: 44, bottom: 34)
                      : null,
                  padding: _safeInsets
                      ? EdgeInsets.only(top: 44, bottom: inset > 0 ? 0 : 34)
                      : null,
                ),
                child: child!,
              ),
            ),
            home: builder(dependencies),
          ),
        ),
      ),
    );
    await _drain(tester, failures);
    progress('precache');
    await _precache(tester, key);
    progress('images-ready');
    await _drain(tester, failures);
    if (selectedTab != null && selectedTab > 0) {
      final tabLabel = const ['首页', '发现', '消息', '我的'][selectedTab];
      expect(
        find.text(tabLabel).last,
        findsOneWidget,
        reason: 'Actual runtime navigation must exist',
      );
      await tester.tap(find.text(tabLabel).last);
      await _drain(tester, failures);
    }
    if (exercise != null) {
      try {
        await exercise(tester, dependencies);
      } catch (error, stack) {
        interactionFailure = error;
        interactionStack = stack;
      }
      await _drain(tester, failures);
    }
    if (_keyboard) {
      // Widget-test keyboard and media insets, not a real OS keyboard capture.
      final inputs = find.byType(EditableText);
      expect(
        inputs,
        findsWidgets,
        reason: 'Requested keyboard case must expose a real input',
      );
      expect(_keyboardField, inInclusiveRange(0, inputs.evaluate().length - 1));
      final input = inputs.at(_keyboardField);
      await tester.showKeyboard(input);
      keyboardInset.value = 280;
      await _drain(tester, failures);
      final bounds = tester.getRect(input);
      expect(
        bounds.bottom,
        lessThanOrEqualTo(size.height - 280 + 1),
        reason: '$id focused input must remain above the keyboard inset',
      );
    }
    if (_output.isNotEmpty) {
      final directory = Directory(
        '$_output/$_phase/${size.width.toInt()}x${size.height.toInt()}-text$scale',
      );
      directory.createSync(recursive: true);
      if (_capture) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        progress('rasterizing');
        await tester.runAsync(() async {
          final image = await boundary
              .toImage(pixelRatio: 1)
              .timeout(const Duration(seconds: 15));
          try {
            final bytes = await image
                .toByteData(format: ui.ImageByteFormat.png)
                .timeout(const Duration(seconds: 15));
            File(
              '${directory.path}/$id.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        progress('capture-saved');
      }
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toList();
      File('${directory.path}/$id.json').writeAsStringSync(
        jsonEncode({
          'id': id,
          'scenario': annotations,
          'productionHostTheme': useProductionHostTheme,
          'phase': _phase,
          'platform': Platform.operatingSystem,
          'size': [size.width, size.height],
          'textScale': scale,
          'simulatedSafeInsets': _safeInsets,
          'simulatedKeyboardInset': keyboardInset.value,
          'keyboardFieldIndex': _keyboard ? _keyboardField : null,
          'reduceMotion': _reduceMotion,
          'font': kGoldenFontFamily,
          'data': 'SYNTHETIC_QA_FIXTURE',
          'deviceValidation': false,
          'goldenUpdated': false,
          'visibleText': visible,
          'renderExceptions': failures,
          'interactionFailure': interactionFailure?.toString(),
          'visibleSpinners': find
              .byType(CircularProgressIndicator)
              .evaluate()
              .length,
        }),
      );
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    keyboardInset.dispose();
    release?.call();
    dependencies.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    final error = tester.takeException();
    if (error != null) failures.add(error.toString());
  }
  if (interactionFailure != null) {
    Error.throwWithStackTrace(interactionFailure, interactionStack!);
  }
  expect(
    failures,
    isEmpty,
    reason: '$id layout/renderer errors; not a device or business PASS',
  );
}

Future<void> _drain(WidgetTester tester, List<String> failures) async {
  // Drain the real image/stream event loop and the existing 35ms mock delay.
  // Never pumpAndSettle indefinitely on intentional loading/room animations.
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final error = tester.takeException();
    if (error != null) failures.add(error.toString());
  }
}

Future<void> _precache(WidgetTester tester, GlobalKey key) async {
  final context = key.currentContext!;
  const paths = [
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
      paths.map((path) => precacheImage(AssetImage(path), context)),
    ).timeout(const Duration(seconds: 15)),
  );
}

// Reuse the same native capture and layout checks for actual attached panels.
// All preparation stays in test-only fixtures; no live commands or devices.
Future<void> renderDazidaoScenario(
  WidgetTester tester, {
  required String id,
  required Size size,
  required double scale,
  required Widget Function(AppDependencies) builder,
  required Future<void> Function(WidgetTester, AppDependencies) exercise,
  Future<void> Function(AppDependencies)? prepare,
  void Function()? release,
  Map<String, Object> annotations = const {},
  bool useProductionHostTheme = false,
}) => _render(
  tester,
  id: id,
  size: size,
  scale: scale,
  builder: builder,
  prepare: prepare,
  exercise: exercise,
  release: release,
  annotations: annotations,
  useProductionHostTheme: useProductionHostTheme,
);
