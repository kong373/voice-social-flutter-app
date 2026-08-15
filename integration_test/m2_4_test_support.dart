import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';

const String qaAvdId = String.fromEnvironment(
  'QA_AVD_ID',
  defaultValue: 'AVD-A',
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
  await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
  await tester.pumpAndSettle();

  if (find.text('同意并继续').evaluate().isNotEmpty) {
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
  }
  if (find.text('登录 / 注册').evaluate().isNotEmpty) {
    await tester.enterText(
      find.widgetWithText(TextFormField, '手机号码'),
      '13800138000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '短信验证码'),
      '123456',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('登录 / 注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 / 注册'));
    await tester.pumpAndSettle();
  }
  expect(find.text('此刻适合你的房间'), findsOneWidget);
  return dependencies;
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
  // Android needs a rendered frame after swapping FlutterSurfaceView for
  // FlutterImageView, otherwise the captured frame can be blank or stale.
  await tester.pump();
  await binding.takeScreenshot(
    name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'),
  );
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
