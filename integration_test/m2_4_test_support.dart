import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';

const String qaAvdId = String.fromEnvironment(
  'QA_AVD_ID',
  defaultValue: 'AVD-A',
);

const bool qaUseFrameworkScreenshots = bool.fromEnvironment(
  'QA_FRAMEWORK_SCREENSHOTS',
);

const bool qaHostScreenshotHandshake = bool.fromEnvironment(
  'QA_HOST_SCREENSHOT_HANDSHAKE',
);

const String qaAndroidDataDirectory = String.fromEnvironment(
  'QA_ANDROID_DATA_DIR',
  defaultValue: '/data/user/0/com.kong373.voice_social_app',
);

Future<AppDependencies> pumpQaPage(
  WidgetTester tester,
  Widget page, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final AppDependencies dependencies = await createQaDependencies();
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
        },
        home: page,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return dependencies;
}

Future<AppDependencies> launchAndAuthenticate(WidgetTester tester) async {
  if (Platform.isLinux) {
    _installQaLinuxSecureStorageStub();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  // Keep the mock repositories selected by BACKEND_MODE=mock, but use the
  // same persistent secure session store as a normal app launch. This lets a
  // later force-stop/relaunch prove real session restoration (FLOW-003).
  final AppDependencies dependencies = AppDependencies.fromEnvironment();
  // The candidate APK must expose the QA console, but ordinary flow tests
  // still enter through the real consent/login/session gate. Mount AppGate
  // explicitly so ENABLE_QA_CONSOLE=true does not replace the business root
  // under test with QaConsoleHost.
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppGate(dependencies: dependencies),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await acceptConsentIfVisible(tester);
  if (find.text('登录 / 注册').evaluate().isNotEmpty) {
    await tester.enterText(
      find.widgetWithText(TextFormField, '手机号码'),
      '13800138000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '短信验证码'),
      '123456',
    );
    await dismissQaImeAndWait(tester);
    await tester.ensureVisible(find.text('登录 / 注册'));
    final Finder loginAction = find.text('登录 / 注册').hitTestable();
    expect(loginAction, findsOneWidget);
    await tester.tap(loginAction);
    await pumpQaUntil(
      tester,
      () => find.text('此刻适合你的房间').evaluate().isNotEmpty,
      description: 'authenticated home page to appear',
    );
  }
  expect(find.text('此刻适合你的房间'), findsOneWidget);
  return dependencies;
}

/// Accepts the current versioned app-owned agreement in an integration run.
/// The production gate intentionally requires both an end-of-document scroll
/// and an explicit checkbox before enabling the continue action.
Future<void> acceptConsentIfVisible(WidgetTester tester) async {
  final Finder consentSubmit = find.byKey(const Key('consent-submit'));
  if (consentSubmit.evaluate().isEmpty) {
    return;
  }
  final Finder consentScroll = find.byKey(const Key('consent-scroll'));
  final Finder consentTile = find.byKey(
    const Key('consent-agreement-checkbox'),
  );
  final Finder consentScrollable = find.descendant(
    of: consentScroll,
    matching: find.byType(Scrollable),
  );

  // The consent ListView lazily builds its children. A single large drag can
  // leave the keyed agreement tile unbuilt on short viewports (notably
  // 360x800), making ensureVisible fail before it can scroll the list.
  expect(consentScroll, findsOneWidget);
  expect(consentScrollable, findsOneWidget);
  await tester.scrollUntilVisible(
    consentTile,
    240,
    scrollable: consentScrollable,
  );
  await pumpQaUntil(
    tester,
    () => consentTile.evaluate().isNotEmpty,
    description: 'consent agreement tile to appear',
  );
  expect(consentTile, findsOneWidget);
  await tester.ensureVisible(consentTile);
  final Finder consentCheckbox = find.descendant(
    of: consentTile,
    matching: find.byType(Checkbox),
  );
  await pumpQaUntil(
    tester,
    () => consentCheckbox.evaluate().isNotEmpty,
    description: 'consent agreement checkbox to appear',
  );
  expect(consentCheckbox, findsOneWidget);
  await tester.ensureVisible(consentCheckbox);
  await tester.tap(consentCheckbox.hitTestable());
  await tester.pump();
  expect(consentSubmit, findsOneWidget);
  await tester.ensureVisible(consentSubmit);
  final Finder consentSubmitAction = consentSubmit.hitTestable();
  await pumpQaUntil(
    tester,
    () => consentSubmitAction.evaluate().isNotEmpty,
    description: 'consent submit action to become tappable',
  );
  expect(consentSubmitAction, findsOneWidget);
  await tester.tap(consentSubmitAction);
  await tester.pumpAndSettle();
  await pumpQaUntil(
    tester,
    () => find.text('登录 / 注册').evaluate().isNotEmpty,
    description: 'login page after consent acceptance',
  );
}

Future<void> showQaImeAndWait(WidgetTester tester, Finder input) async {
  await tester.tap(input);
  await tester.pump();
  await tester.showKeyboard(input);
  await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  await _waitForQaImeInsets(tester, visible: true);
  expect(_qaEditableHasFocus(tester), isTrue);
}

Future<void> dismissQaImeAndWait(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await _waitForQaImeInsets(tester, visible: false);
  expect(_qaEditableHasFocus(tester), isFalse);
}

Future<void> _waitForQaImeInsets(
  WidgetTester tester, {
  required bool visible,
}) async {
  const int requiredStableSamples = 3;
  double? previousBottom;
  int stableSamples = 0;
  double lastBottom = -1;

  for (int attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    final double devicePixelRatio = tester.view.devicePixelRatio;
    lastBottom = tester.view.viewInsets.bottom / devicePixelRatio;
    final bool editableHasFocus = _qaEditableHasFocus(tester);
    final bool matches = visible
        ? lastBottom > 0 && editableHasFocus
        : lastBottom == 0 && !editableHasFocus;
    final bool unchanged =
        previousBottom != null && (lastBottom - previousBottom).abs() < 0.5;
    stableSamples = matches && unchanged ? stableSamples + 1 : 0;
    if (stableSamples >= requiredStableSamples) {
      return;
    }
    previousBottom = lastBottom;
    // IME animation is driven by the Android platform clock, not the fake
    // widget-test clock. Poll a real condition while allowing platform frames
    // to arrive; the delay is not used as a success criterion.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  throw TestFailure(
    'Android IME did not become ${visible ? 'visible' : 'hidden'} with '
    'stable viewInsets.bottom; last logical inset was $lastBottom.',
  );
}

bool _qaEditableHasFocus(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .any((EditableText editable) => editable.focusNode.hasFocus);

Future<void> pumpQaUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TestFailure('Timed out waiting for $description.');
}

Future<void> announceQaEvidence(WidgetTester tester, String marker) async {
  await tester.pump();
  File? acknowledgment;
  if (Platform.isAndroid && qaHostScreenshotHandshake) {
    final Directory acknowledgmentDirectory = Directory(
      '$qaAndroidDataDirectory/cache/flow013-evidence-acks',
    );
    await acknowledgmentDirectory.create(recursive: true);
    final String safeMarker = marker.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]+'),
      '-',
    );
    acknowledgment = File('${acknowledgmentDirectory.path}/$safeMarker');
    if (await acknowledgment.exists()) {
      await acknowledgment.delete();
    }
  }
  debugPrint('FLOW013_EVIDENCE::$marker');
  if (acknowledgment == null) {
    return;
  }
  for (int attempt = 0; attempt < 200; attempt += 1) {
    if (await acknowledgment.exists()) {
      await acknowledgment.delete();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TestFailure('Host did not acknowledge ADB screenshot for $marker.');
}

final Map<String, String> _qaLinuxSecureValues = <String, String>{};

void _installQaLinuxSecureStorageStub() {
  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        final Map<Object?, Object?> arguments =
            (call.arguments as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};
        final String? key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return key == null ? null : _qaLinuxSecureValues[key];
          case 'write':
            if (key != null) {
              _qaLinuxSecureValues[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              _qaLinuxSecureValues.remove(key);
            }
            return null;
          case 'deleteAll':
            _qaLinuxSecureValues.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(_qaLinuxSecureValues);
          case 'containsKey':
            return key != null && _qaLinuxSecureValues.containsKey(key);
        }
        throw MissingPluginException(
          'Unsupported secure storage test call: ${call.method}',
        );
      });
}

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (
    int attempt = 0;
    attempt < attempts && finder.evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

bool _qaScreenshotSurfaceActive = false;

Future<void> captureQaScreenshot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  final String safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  // On API 24 the integration_test Android plugin can wait indefinitely for
  // FlutterImageView.acquireLatestImageViewFrame(). Capture the Flutter layer
  // directly for flow evidence on that compatibility AVD. ADB snapshots still
  // retain the system bars, keyboard, permission dialogs, and other overlays.
  if (qaUseFrameworkScreenshots) {
    await tester.pump();
    final RenderView renderView = tester.binding.renderViews.single;
    final OffsetLayer layer = renderView.debugLayer! as OffsetLayer;
    // RenderView's root TransformLayer already applies devicePixelRatio. Its
    // image bounds therefore need to be physical pixels; logical paintBounds
    // would crop a DPR>1 device to the upper-left portion of the frame.
    final Size physicalSize = renderView.configuration.toPhysicalSize(
      renderView.size,
    );
    final ui.Image image = await layer.toImage(
      Offset.zero & physicalSize,
      pixelRatio: 1,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Could not encode framework screenshot $safeName');
    }
    // Do not put API-24 PNG bytes in reportData. integrationDriver transports
    // reportData as JSON over the VM service, so a flow with many physical-size
    // screenshots can spend tens of minutes serializing integer arrays (and
    // yields no host evidence if the driver is then killed). Write each PNG to
    // the debuggable app's cache instead. The CI runner pulls this directory
    // with `run-as` after every independently bounded flutter-drive target.
    final Directory screenshotDirectory = Directory(
      '${Directory.systemTemp.path}/m24-framework-screenshots',
    );
    await screenshotDirectory.create(recursive: true);
    await File('${screenshotDirectory.path}/$safeName.png').writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      flush: true,
    );
    return;
  }

  // Local Linux widget execution validates every business assertion but has
  // no Android screenshot platform channel. Real evidence is still mandatory
  // because Android runs take the branch below in flutter drive.
  if (!Platform.isAndroid) {
    return;
  }
  if (!_qaScreenshotSurfaceActive) {
    await binding.convertFlutterSurfaceToImage();
    _qaScreenshotSurfaceActive = true;
    // The integration_test callback manager registers its Android
    // revertFlutterImage call with addTearDown during conversion. Keep our
    // process-local guard in the same lifecycle so every test starts clean.
    addTearDown(() => _qaScreenshotSurfaceActive = false);
  }
  // Android needs multiple platform-rendered frames after route, async-data,
  // and FlutterImageView transitions; a single fake-clock pump can otherwise
  // capture the immediately preceding loading frame even after assertions pass.
  for (int frame = 0; frame < 3; frame += 1) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  await tester.pump();
  await binding.takeScreenshot(safeName);
}

const List<String> qaRetiredFeatureTokens = <String>[
  '红包',
  'red packet',
  'ktv',
  '点歌',
  '演唱',
  '合唱',
  '盲盒',
  'blind box',
  '魔法球',
  'magic ball',
  '团子',
  'dango',
  '情书',
  'love letter',
  '随机遇见',
  '随机匹配',
  '附近的人',
  '附近房间',
  '扫码',
  '易票联',
];

void expectNoRetiredFeatureText({String? reason}) {
  for (final String token in qaRetiredFeatureTokens) {
    final String normalizedToken = token.toLowerCase();
    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! Text) {
          return false;
        }
        final String value =
            widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return value.toLowerCase().contains(normalizedToken);
      }),
      findsNothing,
      reason: reason == null ? token : '$reason: $token',
    );
  }
}
