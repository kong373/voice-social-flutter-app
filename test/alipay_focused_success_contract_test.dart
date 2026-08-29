import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File runner = File('tool/qa/run_alipay_focused_success.sh').absolute;
  final File fullRunner = File('tool/qa/run_m5_vendor_live_avd.sh').absolute;
  final File integration = File(
    'integration_test/alipay_focused_success_test.dart',
  ).absolute;
  final File fullIntegration = File(
    'integration_test/m5_vendor_live_integration_test.dart',
  ).absolute;
  final File operator = File(
    'tool/qa/m5_alipay_action_confirmation_operator.py',
  ).absolute;

  test('focused success lane files and syntax are present', () {
    expect(runner.existsSync(), isTrue);
    expect(integration.existsSync(), isTrue);
    expect(operator.existsSync(), isTrue);
    expect(runner.statSync().mode & 73, isNonZero);
    final ProcessResult syntax = Process.runSync('/bin/bash', <String>[
      '-n',
      runner.path,
    ]);
    expect(
      syntax.exitCode,
      0,
      reason: syntax.stdout.toString() + syntax.stderr.toString(),
    );
  });

  test('success lane is Alipay-only and binds one exact serial', () {
    final String source = runner.readAsStringSync();
    final String fullRunnerSource = fullRunner.readAsStringSync();
    expect(source, contains("DEFAULT_SERIAL='emulator-5554'"));
    expect(source, contains('focused success target serial is frozen'));
    expect(source, contains('ENABLE_TENCENT_IM=false'));
    expect(source, contains('avd_b=NOT_RUN'));
    expect(source, contains('sms=NOT_RUN'));
    expect(source, contains('tencent=NOT_RUN'));
    expect(source, contains('wallet_health_preflight'));
    expect(source, contains('exact_marker_count()'));
    expect(source, isNot(contains('|| printf 0)')));
    expect(source, contains('M5_ACTION_GATE_PORT'));
    expect(source, contains('/m5/alipay/action-confirmation/pending'));
    expect(source, contains('ACTION_GATE::armed'));
    expect(source, contains('ACTION_GATE::waiting_for_order'));
    expect(
      source,
      contains('ACTION_GATE_STATE_PARENT="\$(cd /tmp && pwd -P)"'),
    );
    expect(
      source,
      contains(
        'mktemp -d "\$ACTION_GATE_STATE_PARENT/voice-social-alipay-success-gate.XXXXXX"',
      ),
    );
    expect(source, isNot(contains('ACTION_GATE::awaiting_user_confirmation')));
    expect(source, contains("action_confirmation='not_requested'"));
    expect(source, contains("action_confirmation='required_not_granted'"));
    expect(
      source,
      isNot(
        contains(
          "printf 'action_confirmation=required_then_operator_granted\\n'",
        ),
      ),
    );
    expect(source, isNot(contains('adb devices')));
    expect(source, isNot(contains('pm clear')));
    expect(source, isNot(contains('input tap')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    final int armed = source.indexOf('ACTION_GATE::armed');
    final int waiting = source.indexOf('ACTION_GATE::waiting_for_order');
    expect(armed, greaterThan(-1));
    expect(waiting, greaterThan(armed));
    expect(fullRunnerSource, contains('ACTION_GATE::armed'));
    expect(fullRunnerSource, contains('ACTION_GATE::waiting_for_order'));
    expect(
      fullRunnerSource,
      contains(
        'ACTION_GATE_STATE_PARENT="\$(cd "\$requested_gate_parent" && pwd -P)"',
      ),
    );
    expect(source, contains('M5_SCAN_ACTION_OPERATOR'));
    expect(source, contains('if path.is_symlink():'));
    expect(fullRunnerSource, contains('M5_SCAN_ACTION_OPERATOR'));
    expect(
      fullRunnerSource,
      contains('/m5/alipay/action-confirmation/pending'),
    );
    expect(
      fullRunnerSource,
      isNot(contains('ACTION_GATE::awaiting_user_confirmation')),
    );
    expect(
      source,
      contains('http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)'),
    );
    expect(
      fullRunnerSource,
      contains('http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)'),
    );
    expect(source, contains('write_ready(server)'));
    expect(fullRunnerSource, contains('write_ready(server)'));
    expect(
      source,
      contains('class NoRedirect(urllib.request.HTTPRedirectHandler)'),
    );
    expect(
      fullRunnerSource,
      contains('class NoRedirect(urllib.request.HTTPRedirectHandler)'),
    );
    expect(
      fullRunnerSource.indexOf('ACTION_GATE::armed'),
      lessThan(fullRunnerSource.indexOf('ACTION_GATE::waiting_for_order')),
    );
  });

  test('focused success target requests approval before native PayTask', () {
    final String source = integration.readAsStringSync();
    final String fullSource = fullIntegration.readAsStringSync();
    for (final String required in <String>[
      'AuthFlowStage.signedIn',
      'fetchRechargeProducts',
      'createRechargeOrder',
      '/m5/alipay/action-confirmation/request',
      '/m5/alipay/action-confirmation/consume',
      'M5_ALIPAY_FOCUSED',
      'invokePayment',
      'queryRechargeOrder',
      'M5_ALIPAY_NATIVE_RESULT::',
      'resultStatus == \'9000\'',
      "'account': order.account",
      "'productId': order.product.id",
      "'amountMinor': amountMinor",
      "'giftCoinAmount': order.product.totalGiftCoins",
      "'provider': 'ALIPAY'",
      "'status': 'CREATED'",
      "'account=\${order.account}'",
      "'product=\${order.product.id}'",
      "'amount=\${order.product.amountMinor}'",
      "'giftCoin=\${order.product.totalGiftCoins}'",
    ]) {
      expect(source, contains(required));
    }
    for (final String required in <String>[
      "'account': order.account",
      "'productId': order.product.id",
      "'amountMinor': amountMinor",
      "'giftCoinAmount': order.product.totalGiftCoins",
      "'provider': 'ALIPAY'",
      "'status': 'CREATED'",
    ]) {
      expect(fullSource, contains(required));
    }
    final int requestFunction = source.indexOf(
      'Future<Map<String, Object?>> _requestConfirmation',
    );
    final int requestAccepted = source.indexOf("response['accepted'] != true");
    final int requestReturn = source.indexOf(
      "return <String, Object?>{...identity, '_token': token};",
    );
    final int requiredMarker = source.indexOf(
      "_focusedMarker('action_confirmation', 'REQUIRED')",
    );
    final int authoritativeOrderCheck = source.indexOf(
      'if (order.orderNo.trim().isEmpty ||',
    );
    final int requestCall = source.indexOf('await _requestConfirmation(order)');
    final int invoke = source.indexOf('repository.invokePayment(order)');
    expect(requestFunction, greaterThan(-1));
    expect(requestAccepted, greaterThan(requestFunction));
    expect(requestReturn, greaterThan(requestAccepted));
    expect(authoritativeOrderCheck, greaterThan(-1));
    expect(requestCall, greaterThan(authoritativeOrderCheck));
    expect(requiredMarker, greaterThan(-1));
    expect(invoke, greaterThan(requiredMarker));
    expect(source, isNot(contains('sendSmsCode')));
    expect(source, isNot(contains('signInWithSms')));
    expect(source, contains('request.followRedirects = false;'));
    expect(fullSource, contains('request.followRedirects = false;'));
  });

  test('operator rejects redirects and focused runner rejects AVD-B', () {
    final String operatorSource = operator.readAsStringSync();
    expect(operatorSource, contains('Wait for the runner'));
    expect(operatorSource, contains('ACTION_CONFIRMATION_REQUIRED marker'));
    expect(operatorSource, contains('through this TTY prompt'));
    expect(operatorSource, contains('def _get_pending'));
    expect(operatorSource, contains('def approve_pending'));
    expect(operatorSource, isNot(contains('order_no = ask')));
    expect(operatorSource, contains('class _NoRedirectHandler'));
    expect(operatorSource, contains('return None'));
    expect(operatorSource, isNot(contains('HTTPRedirectHandler(),')));
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>[runner.path, '--self-test', '--serial', 'emulator-5556'],
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      },
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 64);
    expect(result.stderr, contains('emulator-5554'));
    expect(result.stdout, isNot(contains('SELF_TEST::PASS')));
  });

  test(
    'focused runner offline self-test proves healthy and unhealthy wallet pages',
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
        reason: result.stdout.toString() + result.stderr.toString(),
      );
      expect(result.stdout, contains('SELF_TEST::PASS'));
    },
  );
}
