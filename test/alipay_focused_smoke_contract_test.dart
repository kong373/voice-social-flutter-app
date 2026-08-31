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
  final File successRunner = File(
    'tool/qa/run_alipay_focused_success.sh',
  ).absolute;

  test('focused Alipay runner and integration target are present', () {
    expect(runner.existsSync(), isTrue);
    expect(integration.existsSync(), isTrue);
    expect(successRunner.existsSync(), isTrue);
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
    expect(source, isNot(contains('voice-social-mobile-public')));
    expect(source, contains('QA_OAUTH_CLIENT_ID'));
    expect(source, contains('oauth_client_dart_define'));
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
    expect(source, contains('--keep-app-running'));
    expect(source, isNot(contains('--no-keep-app-running')));
    expect(source, contains('EXPECTED_LAUNCH_MARKER'));
    expect(source, contains('DEFAULT_PRE_LAUNCH_TIMEOUT_SECONDS=300'));
    expect(source, contains('DEFAULT_POST_LAUNCH_TIMEOUT_SECONDS'));
    expect(source, contains('POST_LAUNCH_TIMEOUT_SECONDS'));
    expect(source, contains('record_launch_marker_baseline'));
    expect(source, contains('wait_for_native_launcher_start'));
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

  test(
    'Flutter drive preserves the authenticated package and starts cashier timeout after launch',
    () {
      final String source = runner.readAsStringSync();
      final int driveInvocation = source.indexOf(
        '"\$FLUTTER_BIN" drive --no-pub',
      );
      final int keepAppRunning = source.indexOf(
        '--keep-app-running',
        driveInvocation,
      );
      expect(driveInvocation, greaterThan(-1));
      expect(keepAppRunning, greaterThan(driveInvocation));
      expect(
        source.substring(driveInvocation, keepAppRunning),
        isNot(contains('--no-keep-app-running')),
      );
      expect(source, isNot(contains('adb uninstall')));
      expect(source, isNot(contains('pm clear')));
      expect(source, contains('force_stop_flutter_app'));
      expect(
        source,
        contains(
          r'"$ADB_BIN" -s "$SERIAL_VALUE" shell am force-stop "$APP_PACKAGE"',
        ),
      );
      expect(source, contains("APP_PACKAGE='com.kong373.voice_social_app'"));
      expect(source, contains('FAKE_ADB_CALLS'));
      expect(source, contains('forbidden_verb in clear uninstall'));

      final int launchBaseline = source.lastIndexOf(
        'record_launch_marker_baseline || fail_timeout',
      );
      final int walletPreflight = source.lastIndexOf(
        'wallet_health_preflight\n',
      );
      final int forceStop = source.lastIndexOf('force_stop_flutter_app\n');
      final int hostPreparation = source.lastIndexOf('prepare_android_host\n');
      final int flutterBackground = source.lastIndexOf('run_flutter_target &');
      final int launchWait = source.lastIndexOf(
        'if ! wait_for_native_launcher_start; then',
      );
      expect(walletPreflight, greaterThan(-1));
      expect(forceStop, greaterThan(walletPreflight));
      expect(forceStop, lessThan(hostPreparation));
      final int operatorStart = source.lastIndexOf(
        'if ! start_cancel_operator; then',
      );
      expect(launchBaseline, greaterThan(-1));
      expect(flutterBackground, greaterThan(launchBaseline));
      expect(launchWait, greaterThan(flutterBackground));
      expect(operatorStart, greaterThan(launchWait));
      expect(source, contains('--target-timeout "\$CASHIER_TIMEOUT_SECONDS"'));
      expect(
        source.substring(launchWait, operatorStart),
        isNot(contains('start_cancel_operator')),
      );
      expect(source, contains('FLUTTER_REAP_TIMEOUT_SECONDS=10'));
      expect(source, contains('FLUTTER_TOOL_PID_PATH'));
      expect(source, contains('os.setsid()'));
      expect(source, contains('process_start_time'));
      expect(source, contains('process_identity_is_current'));
      expect(source, contains(r'kill -"$signal" "-$expected_group"'));
      expect(source, isNot(contains('kill "\$OPERATOR_PID"')));
      expect(source, contains('terminate_flutter_target'));
      expect(source, contains('terminate_cancel_operator'));
      expect(source, contains('signal_flutter_target TERM'));
      expect(source, contains('signal_flutter_target KILL'));
      expect(source, contains('wait_for_post_launch_completion'));
      expect(source, contains('post_launch_watchdog_timeout'));
      expect(source, contains('POST_LAUNCH_WATCHDOG_TIMEOUT'));
      expect(
        source.substring(launchWait, operatorStart),
        isNot(contains('wait "\$FLUTTER_PID"')),
      );
      final int postLaunchWatchdog = source.lastIndexOf(
        'wait_for_post_launch_completion',
      );
      expect(postLaunchWatchdog, greaterThan(operatorStart));
      expect(
        source.substring(operatorStart, postLaunchWatchdog),
        isNot(contains('wait "\$FLUTTER_PID"')),
      );

      // Exercise the launch wait with a delayed marker. This proves the
      // pre-launch build window is independent from the operator's cashier
      // timeout rather than merely checking source text.
      final ProcessResult selfTest = Process.runSync(
        '/bin/bash',
        <String>[runner.path, '--self-test'],
        environment: <String, String>{
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'QA_OAUTH_CLIENT_ID': 'fixture-public-client',
        },
        includeParentEnvironment: false,
      );
      expect(
        selfTest.exitCode,
        0,
        reason: 'stdout:\n${selfTest.stdout}\nstderr:\n${selfTest.stderr}',
      );
      expect(selfTest.stdout, contains('NATIVE_LAUNCHER_START_PASS'));
      expect(selfTest.stdout, contains('NATIVE_LAUNCHER_START_TIMEOUT'));
      expect(selfTest.stdout, contains('FORCE_STOP_PASS'));
      expect(selfTest.stdout, contains('SELF_TEST::PASS'));
    },
  );

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
    expect(
      source,
      contains(
        r'"$ADB_BIN" -s "$SERIAL_VALUE" shell rm -f "$DEVICE_WALLET_UI_DUMP_PATH"',
      ),
    );
    expect(source, contains('clear_wallet_ui_dump'));
    expect(source, contains('foreground_package_is_target'));
    final int preflightFunction = source.indexOf('wallet_health_preflight()');
    final int staleRemoteRemoval = source.indexOf(
      r'shell rm -f "$DEVICE_WALLET_UI_DUMP_PATH"',
      preflightFunction,
    );
    final int freshDump = source.indexOf(
      'shell uiautomator dump',
      preflightFunction,
    );
    expect(staleRemoteRemoval, greaterThan(preflightFunction));
    expect(freshDump, greaterThan(staleRemoteRemoval));
    for (final String phrase in <String>[
      'Please wait a minute',
      'Reload',
      'Server busy',
      'try again later',
      "visible_value not in ('', 'true')",
    ]) {
      expect(source, contains(phrase));
    }
    final int preflight = source.lastIndexOf('wallet_health_preflight\n');
    final int hostPreparation = source.lastIndexOf('prepare_android_host\n');
    final int flutterTarget = source.lastIndexOf('run_flutter_target &');
    expect(preflight, greaterThan(-1));
    expect(hostPreparation, greaterThan(-1));
    expect(flutterTarget, greaterThan(-1));
    expect(preflight, lessThan(hostPreparation));
    expect(preflight, lessThan(flutterTarget));
  });

  test('only cancel smoke permits the audited lower-feed degradation', () {
    final String cancelSource = runner.readAsStringSync();
    final String successSource = successRunner.readAsStringSync();
    expect(cancelSource, contains('allowed_degraded_labels'));
    expect(cancelSource, contains('allowed_degraded_markers'));
    expect(cancelSource, contains('please wait a minute. will be back soon.'));
    expect(cancelSource, contains('1200 <= y1 < y2 <= 1920'));
    expect(cancelSource, contains("node.attrib.get('enabled') != 'true'"));
    expect(cancelSource, contains("visible_value not in ('', 'true')"));
    expect(
      cancelSource,
      contains('API-29 uiautomator may omit visible-to-user'),
    );
    expect(successSource, isNot(contains('allowed_degraded_labels')));
    for (final String phrase in <String>[
      'please wait a minute',
      'reload',
      'server busy',
      'try again later',
    ]) {
      expect(successSource, contains(phrase));
    }
  });

  test(
    'runner self-test covers stale, invalid, timeout, wallet health, and BACK bounds',
    () {
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[runner.path, '--self-test'],
        environment: <String, String>{
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'QA_OAUTH_CLIENT_ID': 'fixture-public-client',
        },
        includeParentEnvironment: false,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stdout, contains('SELF_TEST::PASS'));
      expect(result.stdout, contains('WALLET_VISIBILITY_PASS'));
      expect(result.stdout, contains('WALLET_BASE_DEGRADED_LABEL_PASS'));
      expect(result.stdout, contains('SUMMARY_WALLET_HEALTH_PASS'));
      expect(result.stdout, contains('POST_LAUNCH_WATCHDOG_PASS'));
    },
  );

  test(
    'failed summary preserves unique marker evidence while remaining fail-closed',
    () {
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[runner.path, '--self-test'],
        environment: <String, String>{
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'QA_OAUTH_CLIENT_ID': 'fixture-public-client',
        },
        includeParentEnvironment: false,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(
        result.stdout,
        contains(
          'SUMMARY_PARTIAL_EVIDENCE::conclusion=FAIL::catalog=PASS::'
          'order=PASS::native_launcher=STARTED::native_result=ACCEPTED::'
          'query_reconcile=NOT_PROVEN',
        ),
      );
      expect(
        result.stdout,
        contains(
          'SUMMARY_MISSING_NATIVE::conclusion=FAIL::catalog=PASS::'
          'order=PASS::native_launcher=STARTED::native_result=NOT_ACCEPTED::'
          'query_reconcile=NOT_PROVEN',
        ),
      );
      expect(result.stdout, isNot(contains('orderStr')));
      expect(result.stdout, isNot(contains('secret')));
    },
  );

  test('public OAuth client is protected, dynamic, and fail-closed', () {
    final String source = runner.readAsStringSync();
    expect(source, contains('printenv QA_OAUTH_CLIENT_ID'));
    expect(
      source,
      contains(r'"$(oauth_client_dart_define "$PUBLIC_OAUTH_CLIENT_ID")"'),
    );
    final String path = Platform.environment['PATH'] ?? '/usr/bin:/bin';

    ProcessResult runWith(Map<String, String> values) {
      return Process.runSync(
        '/bin/bash',
        <String>[runner.path, '--confirm-cancel'],
        environment: <String, String>{'PATH': path, ...values},
        includeParentEnvironment: false,
      );
    }

    final ProcessResult missing = runWith(<String, String>{});
    expect(missing.exitCode, 64);
    expect(missing.stderr, contains('QA_OAUTH_CLIENT_ID'));

    for (final String invalid in <String>[
      'public client',
      'public=client',
      'public-client-secret',
      'public_token',
      'Bearer-client',
    ]) {
      final ProcessResult result = runWith(<String, String>{
        'QA_OAUTH_CLIENT_ID': invalid,
      });
      expect(result.exitCode, 64, reason: invalid);
      expect(result.stdout, isNot(contains(invalid)), reason: invalid);
      expect(result.stderr, isNot(contains(invalid)), reason: invalid);
    }

    final ProcessResult secretEnvironment = runWith(<String, String>{
      'QA_OAUTH_CLIENT_ID': 'fixture-public-client',
      'QA_OAUTH_CLIENT_SECRET': 'must-not-be-accepted',
    });
    expect(secretEnvironment.exitCode, 64);
    expect(secretEnvironment.stdout, isNot(contains('must-not-be-accepted')));
    expect(secretEnvironment.stderr, isNot(contains('must-not-be-accepted')));

    final ProcessResult accepted = Process.runSync(
      '/bin/bash',
      <String>[runner.path, '--self-test'],
      environment: <String, String>{
        'PATH': path,
        'QA_OAUTH_CLIENT_ID': 'fixture-public-client',
      },
      includeParentEnvironment: false,
    );
    expect(
      accepted.exitCode,
      0,
      reason: '${accepted.stdout}\n${accepted.stderr}',
    );
    expect(accepted.stdout, isNot(contains('fixture-public-client')));
  });

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
