import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/presentation/third_party_authorization_page.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const FlutterSecureStorage secureStorage = FlutterSecureStorage();
  _installLinuxSecureStorageTestStub();

  testWidgets('mock app launches and keeps core navigation usable offline', (
    WidgetTester tester,
  ) async {
    await secureStorage.deleteAll();
    final dependencies = await launchAndAuthenticate(tester);
    expect(dependencies.environment.isLive, isFalse);

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.text('下班后终于松下来。今晚想听听大家最近遇到的温柔小事。'), findsOneWidget);

    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    expect(find.text('晚星'), findsOneWidget);

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('此刻适合你的房间'), findsOneWidget);

    await captureQaScreenshot(
      tester,
      binding,
      'FLOW-001-offline-mock-home-$qaAvdId',
    );
  });

  testWidgets(
    'FLOW-002 unregistered account completes the ordinary registration path',
    (WidgetTester tester) async {
      if (Platform.isLinux) {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      await secureStorage.deleteAll();
      final AppDependencies dependencies = AppDependencies.fromEnvironment();
      await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      expect(find.text('同意并继续'), findsOneWidget);
      await tester.tap(find.text('同意并继续'));
      await tester.pumpAndSettle();

      expect(find.text('手机号登录'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '手机号码'),
        '13900000000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '短信验证码'),
        '123456',
      );
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('登录 / 注册'));

      expect(find.text('完善资料'), findsOneWidget);
      expect(find.text('手机号 13900000000'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, '昵称'), '星河测试');
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('女'));
      await _scrollToAndTap(tester, find.text('完成注册'));

      expect(dependencies.sessionManager.session?.mobile, '13900000000');
      expect(find.text('此刻适合你的房间'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-002-unregistered-registration-home-$qaAvdId',
      );
    },
  );

  testWidgets(
    'FLOW-011 account compliance boundaries stay usable in mock mode',
    (WidgetTester tester) async {
      await launchAndAuthenticate(tester);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('个人与关系'));
      await _scrollToAndTap(tester, find.text('账号与安全'));
      await pumpUntilVisible(tester, find.text('账号状态正常'));

      // AC-004 must remain reachable from the ordinary account-security hub;
      // the QA catalog entry alone is not sufficient regression evidence.
      await _scrollToAndTap(tester, find.text('第三方账号绑定与分享授权'));
      await pumpUntilVisible(tester, find.text('第三方账号绑定与分享授权'));
      expect(find.byType(ThirdPartyAuthorizationPage), findsOneWidget);
      expect(find.text('VENDOR_BLOCKED'), findsWidgets);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-001-ordinary-AC-004-$qaAvdId',
      );
      await _pageBackTo(tester, find.text('账号与安全'));

      // Permission center: preserve honest platform-boundary copy while the
      // mock adapter exercises a not-determined -> granted transition.
      await _scrollToAndTap(tester, find.text('系统权限中心'));
      await pumpUntilVisible(tester, find.text('尚未请求'));
      expect(
        find.text('权限只在具体功能需要时请求。Live 模式必须由原生系统适配器返回真实状态。'),
        findsOneWidget,
      );
      _expectListTileState('麦克风', '已允许');
      _expectListTileState('通知', '尚未请求');
      _expectListTileState('照片', '已拒绝');
      await tester.tap(find.text('通知'));
      await tester.pumpAndSettle();
      _expectListTileState('通知', '已允许');
      await _pageBackTo(tester, find.text('账号与安全'));

      // Real-name verification uses the actual form and repository result.
      await _scrollToAndTap(tester, find.text('实名认证'));
      await pumpUntilVisible(tester, find.text('未认证'));
      await tester.enterText(
        find.widgetWithText(TextFormField, '真实姓名'),
        '测试用户',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '身份证号'),
        '110101199001011234',
      );
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('提交认证'));
      expect(find.text('已认证'), findsOneWidget);
      await _pageBackTo(tester, find.text('账号与安全'));

      // Submit an appeal and verify the authoritative mock progress state.
      await _scrollToAndTap(tester, find.text('处罚申诉'));
      await pumpUntilVisible(tester, find.text('可提交申诉'));
      await tester.enterText(
        find.widgetWithText(TextField, '申诉说明'),
        '这是账号安全申诉说明测试内容',
      );
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('提交申诉'));
      await pumpUntilVisible(tester, find.text('申诉审核中'));
      expect(find.text('申诉审核中'), findsOneWidget);
      expect(find.text('平台审核中'), findsOneWidget);
      await _pageBackTo(tester, find.text('账号与安全'));

      // FLOW-011 checks cancellation eligibility, not account deletion. Open
      // the real high-risk confirmation and cancel it to preserve the session.
      await _scrollToAndTap(tester, find.text('账号注销'));
      await pumpUntilVisible(tester, find.text('可以申请注销'));
      expect(find.text('账号满足注销条件。注销后资料、关系与钱包记录将按平台规则处理。'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '短信验证码'), '123456');
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('申请注销'));
      expect(find.text('确认申请注销？'), findsOneWidget);
      expect(find.text('确认提交'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('可以申请注销'), findsOneWidget);
      await _pageBackTo(tester, find.text('账号与安全'));

      // Enable youth mode through its real form.
      await _scrollToAndTap(tester, find.text('青少年模式'));
      await pumpUntilVisible(tester, find.text('青少年模式未开启'));
      await tester.enterText(
        find.widgetWithText(TextField, '设置 4 位密码'),
        '1234',
      );
      _dismissKeyboard();
      await _scrollToAndTap(tester, find.text('开启青少年模式'));
      expect(find.text('青少年模式已开启'), findsOneWidget);
      await _pageBackTo(tester, find.text('账号与安全'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('账号与安全'));

      // The recharge page reads the same compliance repository. Its primary
      // action must be disabled while wallet queries remain available.
      await _scrollToAndTap(tester, find.text('钱包、订单与收益'), scrollDelta: -180);
      await pumpUntilVisible(tester, find.text('钱包与商业化'));
      await _scrollToAndTap(tester, find.text('充值商品目录'));
      await pumpUntilVisible(
        tester,
        find.text('青少年模式已开启，只限制创建新的充值订单；进房、消息、社交、钱包查询和其他正常功能不受影响。'),
      );
      await _scrollToFinder(tester, find.text('选择支付方式'));
      final FilledButton rechargeButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '选择支付方式'),
      );
      expect(rechargeButton.onPressed, isNull);

      await _pageBackTo(tester, find.text('钱包与商业化'));
      await _scrollToAndTap(tester, find.text('钱包与流水'), scrollDelta: -180);
      await pumpUntilVisible(tester, find.text('普通礼物收益'));
      expect(find.text('礼物币余额'), findsOneWidget);
      expect(find.text('收入'), findsOneWidget);
      expect(find.text('普通礼物收益'), findsOneWidget);

      // Re-open the blocked recharge surface so the single FLOW-011 capture
      // records the restriction after all "other functions" assertions ran.
      await _pageBackTo(tester, find.text('钱包与商业化'));
      await _scrollToAndTap(tester, find.text('充值商品目录'));
      await pumpUntilVisible(
        tester,
        find.text('青少年模式已开启，只限制创建新的充值订单；进房、消息、社交、钱包查询和其他正常功能不受影响。'),
      );
      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-011-account-compliance-boundaries-$qaAvdId',
      );
    },
  );
}

void _dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
}

void _installLinuxSecureStorageTestStub() {
  if (!Platform.isLinux) {
    return;
  }
  // `flutter test` has no desktop plugin registrar. Keep Linux-only local
  // validation meaningful without changing Android, where the real secure
  // storage plugin must persist FLOW-002 for the FLOW-003 process restart.
  final Map<String, String> values = <String, String>{};
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
            return key == null ? null : values[key];
          case 'write':
            if (key != null) {
              values[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              values.remove(key);
            }
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(values);
          case 'containsKey':
            return key != null && values.containsKey(key);
        }
        throw MissingPluginException('Unsupported secure storage test call');
      });
}

Future<void> _scrollToFinder(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 180,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      scrollDelta,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _scrollToAndTap(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 180,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await _scrollToFinder(tester, finder, scrollDelta: scrollDelta);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _pageBackTo(WidgetTester tester, Finder expected) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await pumpUntilVisible(tester, expected);
}

void _expectListTileState(String title, String state) {
  final Finder tile = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  expect(tile, findsOneWidget);
  expect(find.descendant(of: tile, matching: find.text(state)), findsOneWidget);
}
