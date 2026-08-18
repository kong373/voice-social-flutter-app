import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/main.dart' as app;

import 'm2_4_test_support.dart';

const double _expectedWidth = double.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_WIDTH',
  defaultValue: 390,
);
const double _expectedHeight = double.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_HEIGHT',
  defaultValue: 844,
);
const double _expectedDpr = double.fromEnvironment(
  'QA_EXPECTED_DPR',
  defaultValue: 3,
);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M3.2 live public-client flow reaches the vendor integration boundary',
    (WidgetTester tester) async {
      await app.main();
      await _waitFor(
        tester,
        () => find.text('同意并继续').evaluate().isNotEmpty,
        description: 'consent gate',
      );
      _expectExactViewport(tester);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-01-consent',
      );
      await announceQaEvidence(tester, 'M32_CONSENT_READY');

      await tester.tap(find.text('同意并继续').hitTestable());
      await _waitFor(
        tester,
        () => find.text('登录 / 注册').evaluate().isNotEmpty,
        description: 'login page',
      );

      final Finder phoneField = find.widgetWithText(
        TextFormField,
        '手机号码',
      );
      final Finder codeField = find.widgetWithText(
        TextFormField,
        '短信验证码',
      );
      await tester.enterText(phoneField, '13800138000');
      await dismissQaImeAndWait(tester);
      await tester.ensureVisible(find.text('获取验证码'));
      await tester.tap(find.text('获取验证码').hitTestable());
      await _waitFor(
        tester,
        () {
          final Iterable<TextFormField> fields =
              tester.widgetList<TextFormField>(codeField);
          return fields.isNotEmpty &&
              fields.first.controller?.text == '123456';
        },
        description: 'development SMS outbox autofill',
      );
      expect(find.textContaining('仅开发环境可见：验证码 123456'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-02-public-client-login',
      );
      await announceQaEvidence(tester, 'M32_SMS_OUTBOX_READY');

      await tester.ensureVisible(find.text('登录 / 注册'));
      await tester.tap(find.text('登录 / 注册').hitTestable());
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'live read-only home',
      );
      _expectExactViewport(tester);
      expect(find.text('实时后端 · 只读验收'), findsOneWidget);
      expect(find.textContaining('HTTP_SNAPSHOT_ONLY'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-03-live-home',
      );
      await announceQaEvidence(tester, 'M32_LIVE_HOME_READY');

      await tester.tap(find.byTooltip('搜索').hitTestable());
      await _waitFor(
        tester,
        () => find.text('搜索用户与房间').evaluate().isNotEmpty,
        description: 'global search page',
      );
      final Finder searchField = find.widgetWithText(
        TextField,
        '输入昵称、ID、房间名或房间号',
      );
      await tester.enterText(searchField, '深夜');
      await dismissQaImeAndWait(tester);
      final Finder searchAction = find.widgetWithText(TextButton, '搜索');
      await tester.tap(searchAction.hitTestable());
      await _waitFor(
        tester,
        () => find.text('“深夜”的搜索结果').evaluate().isNotEmpty,
        description: 'search results',
      );
      expect(find.text('深夜陪伴电台'), findsOneWidget);
      expect(find.text('南风'), findsWidgets);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-04-search-contract',
      );
      await announceQaEvidence(tester, 'M32_SEARCH_READY');
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pageBack();
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'home after search',
      );

      await tester.ensureVisible(find.byKey(const Key('live-room-880217')));
      await tester.tap(find.byKey(const Key('live-room-880217')).hitTestable());
      await _waitFor(
        tester,
        () => find.byType(RoomPage).evaluate().isNotEmpty &&
            find.textContaining('HTTP_SNAPSHOT_ONLY').evaluate().isNotEmpty,
        description: 'authoritative room snapshot',
      );
      expect(find.text('当前不可发送公屏消息'), findsOneWidget);
      expect(find.text('礼物'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-05-room-snapshot-only',
      );
      await announceQaEvidence(tester, 'M32_ROOM_SNAPSHOT_READY');
      await tester.tap(find.byTooltip('离开房间').first.hitTestable());
      await _waitFor(
        tester,
        () => find.text('离开房间？').evaluate().isNotEmpty,
        description: 'leave-room confirmation',
      );
      await tester.tap(find.text('确认离开').hitTestable());
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'home after room snapshot',
      );

      await tester.tap(find.text('接入').hitTestable());
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('vendor-readiness-summary'))
            .evaluate()
            .isNotEmpty,
        description: 'server-authoritative vendor readiness',
      );
      expect(find.text('READY_FOR_PROVIDER_INTEGRATION'), findsOneWidget);
      expect(find.text('运行状态：VENDOR_BLOCKED'), findsOneWidget);
      expect(find.byKey(const Key('vendor-sms-status')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-06-vendor-readiness-top',
      );
      final Finder vendorPayment = find.byKey(
        const Key('vendor-payment-status'),
      );
      await tester.scrollUntilVisible(
        vendorPayment,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('vendor-im-status')), findsOneWidget);
      expect(vendorPayment, findsOneWidget);
      final Finder secretBoundary = find.byKey(
        const Key('vendor-secret-boundary'),
      );
      await tester.scrollUntilVisible(
        secretBoundary,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(secretBoundary, findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-06-vendor-readiness',
      );
      await announceQaEvidence(tester, 'M32_VENDOR_BOUNDARY_READY');

      await tester.tap(find.text('消息').hitTestable());
      await _waitFor(
        tester,
        () => find.byKey(const Key('im-vendor-blocked')).evaluate().isNotEmpty,
        description: 'IM fail-closed page',
      );
      expect(find.textContaining('腾讯 IM · VENDOR_BLOCKED'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-07-im-blocked',
      );
      await announceQaEvidence(tester, 'M32_IM_FAIL_CLOSED');

      await tester.tap(find.text('我的').hitTestable());
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('current-user-contract-ready'))
            .evaluate()
            .isNotEmpty,
        description: 'current-user wallet and order overview',
      );
      expect(find.byKey(const Key('wallet-contract-ready')), findsOneWidget);
      final Finder paymentBlocked = find.byKey(
        const Key('payment-initiation-blocked'),
      );
      await tester.scrollUntilVisible(
        paymentBlocked,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(paymentBlocked, findsOneWidget);
      expect(find.text('P202608180001'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-08-wallet-orders-payment-blocked',
      );
      await announceQaEvidence(tester, 'M32_PAYMENT_READ_ONLY_READY');

      await tester.ensureVisible(find.text('退出登录'));
      await tester.tap(find.text('退出登录').hitTestable());
      await _waitFor(
        tester,
        () => find.text('登录 / 注册').evaluate().isNotEmpty,
        description: 'server logout and local session deletion',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm32-${qaAvdId.toLowerCase()}-09-logout-complete',
      );
      await announceQaEvidence(tester, 'M32_ACCEPTANCE_COMPLETE');

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['m32Acceptance'] = <String, Object?>{
        'avd': qaAvdId,
        'logicalViewport': '${_expectedWidth.toInt()}x${_expectedHeight.toInt()}',
        'devicePixelRatio': _expectedDpr,
        'publicClientSecretPresent': false,
        'providerCallsMade': false,
        'vendorIntegrationStatus': 'READY_FOR_PROVIDER_INTEGRATION',
        'vendorRuntimeStatus': 'VENDOR_BLOCKED',
        'result': 'PASS',
      };
    },
  );
}

void _expectExactViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logicalSize = Size(
    tester.view.physicalSize.width / dpr,
    tester.view.physicalSize.height / dpr,
  );
  expect(dpr, closeTo(_expectedDpr, 0.01));
  expect(logicalSize.width, closeTo(_expectedWidth, 0.1));
  expect(logicalSize.height, closeTo(_expectedHeight, 0.1));
  final BuildContext context = tester.element(find.byType(Scaffold).first);
  final Size mediaQuerySize = MediaQuery.sizeOf(context);
  expect(mediaQuerySize.width, closeTo(_expectedWidth, 0.1));
  expect(mediaQuerySize.height, closeTo(_expectedHeight, 0.1));
  debugPrint(
    'M32_EXACT_VIEWPORT::$qaAvdId::'
    '${logicalSize.width.toStringAsFixed(0)}x'
    '${logicalSize.height.toStringAsFixed(0)}::'
    '${dpr.toStringAsFixed(2)}',
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 300; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('Timed out waiting for $description.');
}
