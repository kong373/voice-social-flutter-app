import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File runner = File('tool/qa/run_alipay_focused_smoke.sh').absolute;
  final File integration = File(
    'integration_test/alipay_focused_smoke_test.dart',
  ).absolute;
  final File cancelOperator = File(
    'tool/qa/m5_alipay_cancel_operator.sh',
  ).absolute;

  test('focused Alipay runner and integration target are present', () {
    expect(runner.existsSync(), isTrue);
    expect(integration.existsSync(), isTrue);
    expect(runner.statSync().mode & 73, isNonZero);
  });

  test('focused runner is a cancellation-only single-device contract', () {
    final String source = runner.readAsStringSync();
    expect(source, contains('set -Eeuo pipefail'));
    expect(source, contains('--self-test'));
    expect(source, contains('--serial'));
    expect(source, contains("DEFAULT_SERIAL='emulator-5554'"));
    expect(source, contains('serial_matches_focused_target'));
    expect(source, contains('focused Alipay smoke target serial is frozen'));
    expect(source, contains("TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'"));
    expect(source, contains("TARGET_ACTIVITY='MspContainerActivity'"));
    expect(
      source,
      contains('M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'),
    );
    expect(
      source,
      contains('M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned'),
    );
    expect(source, contains('MAX_BACK_ATTEMPTS=2'));
    expect(cancelOperator.readAsStringSync(), contains('--target-serial'));
    expect(source, contains('stale'));
    expect(source, contains('query_reconcile'));
    expect(source, isNot(contains('adb devices')));
    expect(source, isNot(contains('input tap')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    expect(source, isNot(contains('ENABLE_TENCENT_IM=true')));
    expect(source, isNot(contains('I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT')));
    expect(source, isNot(contains('successConfirmation')));
    expect(source, isNot(contains('pm clear')));
    final ProcessResult syntax = Process.runSync('/bin/bash', <String>[
      '-n',
      runner.path,
    ]);
    expect(syntax.exitCode, 0, reason: '${syntax.stdout}\n${syntax.stderr}');
  });

  test('focused runner rejects AVD-B serial before any live setup', () {
    for (final List<String> arguments in <List<String>>[
      <String>['--serial', 'emulator-5556', '--confirm-cancel'],
      <String>['--self-test', '--serial', 'emulator-5556'],
    ]) {
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[runner.path, ...arguments],
        environment: <String, String>{
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
        includeParentEnvironment: false,
      );
      expect(
        result.exitCode,
        64,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stderr, contains('emulator-5554'));
      expect(result.stdout, isNot(contains('ALIPAY_FOCUSED_SMOKE::START')));
      expect(result.stdout, isNot(contains('SELF_TEST::PASS')));
    }
  });

  test('cancel operator rejects AVD-B target serial before adb access', () {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'alipay-focused-serial-contract-',
    );
    final File log = File('${tempDirectory.path}/flutter.log')
      ..writeAsStringSync('');
    try {
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[
          cancelOperator.path,
          '--target-serial',
          'emulator-5556',
          '--flutter-log',
          log.path,
        ],
        environment: <String, String>{
          'ANDROID_SERIAL': 'emulator-5556',
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
        includeParentEnvironment: false,
      );
      expect(
        result.exitCode,
        64,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stderr, contains('emulator-5554'));
      expect(result.stderr, contains('frozen'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('wallet health preflight precedes any host or order activity', () {
    final String source = runner.readAsStringSync();
    expect(source, contains('wallet_health_preflight'));
    expect(source, contains('wallet_ui_is_healthy'));
    expect(source, contains("'scan'"));
    expect(source, contains("'pay'"));
    expect(source, contains("'home'"));
    expect(source, contains('target_package'));
    expect(source, contains('content-desc'));
    expect(
      source,
      contains(
        "DEVICE_WALLET_UI_DUMP_PATH='/data/local/tmp/voice-social-alipay-focused-wallet-ui.xml'",
      ),
    );
    expect(source, contains('uiautomator dump'));
    expect(source, contains('clear_wallet_ui_dump'));
    expect(source, contains('foreground_package_is_target'));
    for (final String phrase in <String>[
      'Please wait a minute',
      'Reload',
      'Server busy',
      'try again later',
    ]) {
      expect(source, contains(phrase));
    }
    final int preflight = source.lastIndexOf('wallet_health_preflight\n');
    final int hostPreparation = source.lastIndexOf('prepare_android_host\n');
    final int flutterTarget = source.lastIndexOf('run_flutter_target\n');
    expect(preflight, greaterThan(-1));
    expect(hostPreparation, greaterThan(-1));
    expect(flutterTarget, greaterThan(-1));
    expect(preflight, lessThan(hostPreparation));
    expect(preflight, lessThan(flutterTarget));
  });

  test(
    'runner self-test covers stale, invalid, timeout, wallet health, and BACK bounds',
    () {
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[runner.path, '--self-test'],
        environment: <String, String>{
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
        includeParentEnvironment: false,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stdout, contains('SELF_TEST::PASS'));
    },
  );

  test('integration target does not authenticate by SMS or run Tencent', () {
    final String source = integration.readAsStringSync();
    expect(source, contains('AppDependencies.fromEnvironment'));
    expect(source, contains('fetchRechargeProducts'));
    expect(source, contains('createRechargeOrder'));
    expect(source, contains('selectLowestPositiveEnabledRechargeProduct'));
    expect(source, contains('amountMinor'));
    expect(source, contains('alipayAppPayAdapter'));
    expect(source, contains('.pay(orderNo:'));
    expect(source, contains('queryRechargeOrder'));
    expect(source, contains('M5_ALIPAY_NATIVE_RESULT::'));
    expect(source, contains('M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::'));
    expect(source, isNot(contains('sendSmsCode')));
    expect(source, isNot(contains('signInWithSms')));
    expect(source, isNot(contains('ENABLE_TENCENT_IM=true')));
    expect(source, isNot(contains('I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT')));
    expect(source, isNot(contains('confirmSuccess')));
  });
}
