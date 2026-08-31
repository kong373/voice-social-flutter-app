import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File runner = File(
    'tool/qa/run_alipay_physical_device_diagnostic.sh',
  ).absolute;
  final File operator = File(
    'tool/qa/m5_alipay_physical_device_cancel_operator.sh',
  ).absolute;
  final File evidenceValidator = File(
    'tool/qa/m5_alipay_physical_zero_mutation_validator.py',
  ).absolute;

  const String serial = 'R58PHYSICAL001';
  const String targetPackage = 'com.eg.android.AlipayGphoneRC';
  const String nativeCancel =
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001';
  const String bridgeReturned =
      'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned';

  Directory sandbox(String prefix) {
    final Directory value = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (value.existsSync()) {
        value.deleteSync(recursive: true);
      }
    });
    return value;
  }

  File fakeAdb(
    Directory root, {
    String state = 'online',
    String package = targetPackage,
    String? reverseMapping = 'tcp:18080 tcp:18080',
    String qemuKernel = '0',
    int cashierDumps = 3,
    List<String> markersAfterBack = const <String>[],
  }) {
    File('${root.path}/adb.calls').writeAsStringSync('');
    File('${root.path}/dumpsys.count').writeAsStringSync('0');
    File('${root.path}/ui.count').writeAsStringSync('0');
    File('${root.path}/back.count').writeAsStringSync('0');
    File('${root.path}/remote-ui.xml').writeAsStringSync('');
    final String markerScript = markersAfterBack
        .map(
          (String marker) =>
              "printf '%s\\n' '${marker.replaceAll("'", "'\\\"'\\\"'")}' >>\"\${FAKE_LOG}\"",
        )
        .join('\n');
    final File script = File('${root.path}/adb');
    script.writeAsStringSync('''#!/usr/bin/env bash
set -Eeuo pipefail
: "\${FAKE_LOG:?}"
: "\${FAKE_CALLS:?}"
: "\${FAKE_DUMPSYS:?}"
: "\${FAKE_UI:?}"
: "\${FAKE_BACK:?}"
: "\${FAKE_REMOTE_UI:?}"
printf '%s\\n' "\$*" >>"\${FAKE_CALLS}"
[[ "\${1:-}" == '-s' && "\${2:-}" == '$serial' ]] || exit 91
shift 2
case "\${1:-}" in
  get-state)
    [[ '$state' == 'online' ]] && printf '%s\\n' device || printf '%s\\n' offline
    ;;
  reverse)
    if [[ "\${2:-}" == '--list' ]]; then
      printf '%s\\n' '${reverseMapping ?? ''}'
    else
      [[ '${reverseMapping ?? ''}' == 'tcp:18080 tcp:18080' ]]
    fi
    ;;
  shell)
    shift
    case "\${1:-}" in
      getprop)
        case "\${2:-}" in
          ro.kernel.qemu) printf '%s\\n' '$qemuKernel' ;;
          ro.boot.qemu) printf '0\\n' ;;
          ro.hardware) printf 'qcom\\n' ;;
          ro.product.model) printf 'Pixel Physical\\n' ;;
          ro.product.device|ro.product.name|ro.product.board) printf 'physical\\n' ;;
          *) printf '\\n' ;;
        esac
        ;;
      wm)
        [[ "\${2:-}" == 'size' ]] && printf 'Physical size: 1440x3200\\n'
        ;;
      dumpsys)
        [[ "\${2:-}" == 'activity' && "\${3:-}" == 'activities' ]] || exit 92
        count=\$(<"\${FAKE_DUMPSYS}"); count=\$((count + 1)); printf '%s' "\$count" >"\${FAKE_DUMPSYS}"
        if (( count <= $cashierDumps )); then
          printf '%s\\n' 'mResumedActivity: ActivityRecord{${package}/com.alipay.android.msp.ui.views.MspContainerActivity}'
        else
          printf '%s\\n' 'mResumedActivity: ActivityRecord{com.kong373.voice_social_app/.MainActivity}'
        fi
        ;;
      uiautomator)
        [[ "\${2:-}" == 'dump' ]] || exit 93
        count=\$(<"\${FAKE_UI}"); count=\$((count + 1)); printf '%s' "\$count" >"\${FAKE_UI}"
        printf '%s' '<hierarchy package="${package}"><node package="${package}" class="com.alipay.android.msp.ui.views.MspContainerActivity" text="Cancel" content-desc="Cancel" enabled="true" visible-to-user="true" clickable="true" bounds="[40,2800][1400,3000]" /></hierarchy>' >"\${FAKE_REMOTE_UI}"
        ;;
      cat)
        cat "\${FAKE_REMOTE_UI}"
        ;;
      chmod|rm)
        ;;
      input)
        [[ "\${2:-}" == 'keyevent' && "\${3:-}" == 'KEYCODE_BACK' ]] || exit 94
        count=\$(<"\${FAKE_BACK}"); count=\$((count + 1)); printf '%s' "\$count" >"\${FAKE_BACK}"
        $markerScript
        ;;
      *) exit 95 ;;
    esac
    ;;
  *) exit 96 ;;
esac
''');
    Process.runSync('/bin/chmod', <String>['0755', script.path]);
    return script;
  }

  ProcessResult runOperator(
    Directory root, {
    required File adb,
    String selectedSerial = serial,
    String logContents = '',
    String? serialEnvironment,
    int markerTimeout = 1,
    int cashierTimeout = 1,
  }) {
    final File log = File('${root.path}/flutter.log')
      ..writeAsStringSync(logContents);
    return Process.runSync(
      '/bin/bash',
      <String>[
        operator.path,
        '--adb',
        adb.path,
        '--serial',
        selectedSerial,
        '--flutter-log',
        log.path,
        '--cashier-timeout',
        '$cashierTimeout',
        '--after-back-timeout',
        '1',
        '--marker-timeout',
        '$markerTimeout',
        '--poll-interval',
        '0',
        '--stable-polls',
        '3',
      ],
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        if (serialEnvironment != null) 'ANDROID_SERIAL': serialEnvironment,
        'FAKE_LOG': log.path,
        'FAKE_CALLS': '${root.path}/adb.calls',
        'FAKE_DUMPSYS': '${root.path}/dumpsys.count',
        'FAKE_UI': '${root.path}/ui.count',
        'FAKE_BACK': '${root.path}/back.count',
        'FAKE_REMOTE_UI': '${root.path}/remote-ui.xml',
      },
      includeParentEnvironment: false,
    );
  }

  test('physical runner and operator are present and shell-valid', () {
    expect(runner.existsSync(), isTrue);
    expect(operator.existsSync(), isTrue);
    expect(runner.statSync().mode & 73, isNonZero);
    expect(operator.statSync().mode & 73, isNonZero);
    expect(evidenceValidator.existsSync(), isTrue);
    for (final File script in <File>[runner, operator]) {
      final ProcessResult result = Process.runSync('/bin/bash', <String>[
        '-n',
        script.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason: '${script.path}\n${result.stdout}\n${result.stderr}',
      );
    }
  });

  test(
    'zero-mutation evidence is bound to this run and one canceled sandbox order',
    () {
      final Directory root = sandbox('alipay-physical-evidence-');
      final String flutterSha = List<String>.filled(40, 'a').join();
      final String backendSha = List<String>.filled(40, 'b').join();
      const String runId = 'physical-contract';
      final int runStartedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      Map<String, Object?> validEvidence() => <String, Object?>{
        'schema': 'alipay-physical-cancel-v1',
        'status': 'OK',
        'serial': serial,
        'flutterSha': flutterSha,
        'backendSha': backendSha,
        'runId': runId,
        'runStartedAt': runStartedAt,
        'observedAt': runStartedAt + 1,
        'evidenceSource': 'read-only-db',
        'payment': <String, Object?>{
          'provider': 'alipay-sandbox',
          'status': 'CANCELED',
          'databaseStatus': 'CANCELLED',
          'canceledOrderCount': 1,
        },
        'writeCounters': <String, Object?>{
          'payment_provider_events': 0,
          'wallet_transactions': 0,
          'ledger_journals': 0,
          'ledger_entries': 0,
        },
        'secrets': false,
      };

      ProcessResult runValidator(Map<String, Object?> evidence) {
        final File evidenceFile = File('${root.path}/evidence.json')
          ..writeAsStringSync(jsonEncode(evidence));
        return Process.runSync(
          'python3',
          <String>[
            evidenceValidator.path,
            evidenceFile.path,
            serial,
            runId,
            '$runStartedAt',
            flutterSha,
            backendSha,
          ],
          environment: <String, String>{
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          },
          includeParentEnvironment: false,
        );
      }

      final ProcessResult valid = runValidator(validEvidence());
      expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
      expect((valid.stdout as String).trim(), '0 0 0 0');

      final Map<String, Object?> oldStatic = <String, Object?>{
        'schemaVersion': 'm5-vendor-db-evidence-v1',
        'secrets': false,
        'writeCounters': <String, Object?>{
          'payment_provider_events': 0,
          'wallet_transactions': 0,
          'ledger_journals': 0,
          'ledger_entries': 0,
        },
      };
      expect(runValidator(oldStatic).exitCode, isNot(0));

      for (final MapEntry<String, Object?> mutation
          in <MapEntry<String, Object?>>[
            MapEntry<String, Object?>('serial', 'R58OTHER001'),
            MapEntry<String, Object?>('flutterSha', backendSha),
            MapEntry<String, Object?>('backendSha', flutterSha),
            MapEntry<String, Object?>('runId', 'different-run'),
            MapEntry<String, Object?>('runStartedAt', runStartedAt - 1),
            MapEntry<String, Object?>('observedAt', runStartedAt - 1),
          ]) {
        final Map<String, Object?> evidence = validEvidence();
        evidence[mutation.key] = mutation.value;
        expect(runValidator(evidence).exitCode, isNot(0), reason: mutation.key);
      }

      for (final MapEntry<String, Object?> paymentMutation
          in <MapEntry<String, Object?>>[
            MapEntry<String, Object?>('status', 'SUCCEEDED'),
            MapEntry<String, Object?>('databaseStatus', 'SUCCEEDED'),
            MapEntry<String, Object?>('canceledOrderCount', 2),
          ]) {
        final Map<String, Object?> evidence = validEvidence();
        final Map<String, Object?> payment = Map<String, Object?>.from(
          evidence['payment']! as Map,
        );
        payment[paymentMutation.key] = paymentMutation.value;
        evidence['payment'] = payment;
        expect(
          runValidator(evidence).exitCode,
          isNot(0),
          reason: paymentMutation.key,
        );
      }

      final Map<String, Object?> nonZero = validEvidence();
      final Map<String, Object?> counters = Map<String, Object?>.from(
        nonZero['writeCounters']! as Map,
      );
      counters['ledger_entries'] = 1;
      nonZero['writeCounters'] = counters;
      expect(runValidator(nonZero).exitCode, isNot(0));
    },
  );

  test('source contract is physical, cancellation-only, and fail-closed', () {
    final String runnerSource = runner.readAsStringSync();
    final String operatorSource = operator.readAsStringSync();
    expect(runnerSource, contains('PHYSICAL_DEVICE_DIAGNOSTIC'));
    expect(operatorSource, contains('PHYSICAL_DEVICE_DIAGNOSTIC'));
    expect(runnerSource, contains("EXPECTED_FLUTTER_VERSION='3.44.7'"));
    expect(runnerSource, contains("API_BASE_URL='http://127.0.0.1:18080/'"));
    expect(runnerSource, contains('adb reverse tcp:18080 tcp:18080'));
    expect(operatorSource, contains('adb reverse tcp:18080 tcp:18080'));
    expect(operatorSource, contains('wm size'));
    expect(runnerSource, contains('wm size'));
    expect(
      operatorSource,
      contains("TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'"),
    );
    expect(operatorSource, contains(nativeCancel));
    expect(operatorSource, contains(bridgeReturned));
    expect(runnerSource, contains('MAX_BACK_ATTEMPTS=2'));
    expect(operatorSource, contains('MAX_BACK_ATTEMPTS=2'));
    for (final String field in <String>[
      'payment_provider_events',
      'wallet_transactions',
      'ledger_journals',
      'ledger_entries',
      'redacted',
    ]) {
      expect(runnerSource, contains(field));
    }
    for (final String forbidden in <String>[
      'adb devices',
      'input tap',
      'KEYCODE_ENTER',
      'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT',
      '10.0.2.2:18080',
    ]) {
      expect(runnerSource, isNot(contains(forbidden)));
      expect(operatorSource, isNot(contains(forbidden)));
    }
    expect(runnerSource, contains('9000'));
    expect(runnerSource, contains('resultStatus=none'));
    expect(runnerSource, contains('recharge_order.status=CANCELLED'));
    expect(runnerSource, contains('canceledOrderCount'));
    expect(
      runnerSource.lastIndexOf('run_db_evidence_hook start'),
      lessThan(runnerSource.lastIndexOf('adb_get_state')),
    );
    expect(
      runnerSource.lastIndexOf('run_db_evidence_hook collect'),
      greaterThan(runnerSource.lastIndexOf('evaluate_marker_contract ||')),
    );
    expect(operatorSource, contains('stale'));
  });

  test(
    'runner self-test is offline and exercises zero-mutation/redaction gates',
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
      expect(result.stdout, contains('DB_START_BEFORE_FLUTTER_PASS'));
      expect(result.stdout, contains('DB_COLLECT_AFTER_CANCEL_PASS'));
      expect(result.stdout, contains('DB_HOOK_FAILURE_FAIL_CLOSED_PASS'));
      expect(result.stdout, contains('DB_ZERO_MUTATIONS_PASS'));
      expect(result.stdout, contains('ARTIFACT_REDACTION_PASS'));
      expect(result.stdout, contains('PHYSICAL_DEVICE_DIAGNOSTIC'));
    },
  );

  test(
    'failed run summary reflects none/watchdog/operator failure and never claims cancellation',
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
      expect(result.stdout, contains('SUMMARY_FAIL_CLOSED_PASS'));
      expect(
        result.stdout,
        contains(
          'native_result=sdkCompleted=0,resultStatus=none,bridge=dart_watchdog_timeout',
        ),
      );
      expect(result.stdout, contains('flutter_failure=dart_watchdog_timeout'));
      expect(result.stdout, contains('operator_failure=unsafe_cashier_ui'));
      expect(result.stdout, contains('payment_status=NOT_PROVEN'));
      expect(result.stdout, contains('canceled_order_count=NOT_PROVEN'));
      expect(result.stdout, contains('payment_provider_events=NOT_PROVEN'));
      expect(result.stdout, contains('wallet_transactions=NOT_PROVEN'));
      expect(result.stdout, contains('ledger_journals=NOT_PROVEN'));
      expect(result.stdout, contains('ledger_entries=NOT_PROVEN'));
      expect(
        result.stdout,
        isNot(contains('native_cancel=sdkCompleted=0,resultStatus=6001')),
      );
      expect(result.stdout, isNot(contains('payment_status=CANCELED')));
      expect(result.stdout, isNot(contains('canceled_order_count=1')));
      expect(result.stdout, isNot(contains('db_zero_mutations=PASS')));
    },
  );

  test(
    'operator accepts only a selected physical serial and exact cancel pair',
    () {
      final Directory root = sandbox('alipay-physical-operator-pass-');
      final File adb = fakeAdb(
        root,
        markersAfterBack: <String>[nativeCancel, bridgeReturned],
      );
      final ProcessResult result = runOperator(root, adb: adb);
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect(result.stdout, contains('PHYSICAL_DEVICE_DIAGNOSTIC::PASS'));
      expect(File('${root.path}/back.count').readAsStringSync(), '1');
      final String calls = File('${root.path}/adb.calls').readAsStringSync();
      expect(calls, contains('-s $serial'));
      expect(calls, isNot(contains('emulator-5554')));
      expect(calls, isNot(contains('devices')));
    },
  );

  test(
    'wrong serial, qemu/emulator, missing reverse, and wrong package fail before BACK',
    () {
      final Directory wrongSerialRoot = sandbox(
        'alipay-physical-wrong-serial-',
      );
      final File wrongSerialAdb = fakeAdb(wrongSerialRoot);
      final ProcessResult wrongSerial = runOperator(
        wrongSerialRoot,
        adb: wrongSerialAdb,
        selectedSerial: 'R58OTHER001',
        serialEnvironment: serial,
      );
      expect(wrongSerial.exitCode, 64);
      expect(
        File('${wrongSerialRoot.path}/adb.calls').readAsStringSync(),
        isEmpty,
      );

      for (final String invalidSerial in <String>[
        'emulator-5554',
        'qemu-1234',
      ]) {
        final Directory root = sandbox('alipay-physical-invalid-serial-');
        final File adb = fakeAdb(root);
        final ProcessResult result = runOperator(
          root,
          adb: adb,
          selectedSerial: invalidSerial,
        );
        expect(result.exitCode, 64, reason: invalidSerial);
        expect(File('${root.path}/adb.calls').readAsStringSync(), isEmpty);
      }

      final Directory qemuRoot = sandbox('alipay-physical-qemu-prop-');
      final File qemuAdb = fakeAdb(qemuRoot, qemuKernel: '1');
      final ProcessResult qemu = runOperator(qemuRoot, adb: qemuAdb);
      expect(qemu.exitCode, 69);
      expect(File('${qemuRoot.path}/back.count').readAsStringSync(), '0');

      final Directory reverseRoot = sandbox('alipay-physical-no-reverse-');
      final File reverseAdb = fakeAdb(reverseRoot, reverseMapping: null);
      final ProcessResult reverse = runOperator(reverseRoot, adb: reverseAdb);
      expect(reverse.exitCode, isNot(0));
      expect(File('${reverseRoot.path}/back.count').readAsStringSync(), '0');

      final Directory packageRoot = sandbox('alipay-physical-wrong-package-');
      final File packageAdb = fakeAdb(packageRoot, package: 'com.other.wallet');
      final ProcessResult wrongPackage = runOperator(
        packageRoot,
        adb: packageAdb,
      );
      expect(wrongPackage.exitCode, isNot(0));
      expect(File('${packageRoot.path}/back.count').readAsStringSync(), '0');
    },
  );

  test('stale, 9000, none, and timeout markers fail closed', () {
    final List<String> staleValues = <String>[nativeCancel, bridgeReturned];
    for (final String stale in staleValues) {
      final Directory root = sandbox('alipay-physical-stale-');
      final File adb = fakeAdb(root);
      final ProcessResult result = runOperator(
        root,
        adb: adb,
        logContents: '$stale\n',
      );
      expect(result.exitCode, 65, reason: stale);
      expect(File('${root.path}/adb.calls').readAsStringSync(), isEmpty);
    }

    for (final String invalid in <String>[
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000',
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none',
    ]) {
      final Directory root = sandbox('alipay-physical-invalid-marker-');
      final File adb = fakeAdb(
        root,
        markersAfterBack: <String>[invalid, bridgeReturned],
      );
      final ProcessResult result = runOperator(root, adb: adb);
      expect(result.exitCode, 65, reason: invalid);
      expect(File('${root.path}/back.count').readAsStringSync(), '1');
      expect(result.stdout, isNot(contains('::PASS')));
    }

    final Directory timeoutRoot = sandbox('alipay-physical-marker-timeout-');
    final File timeoutAdb = fakeAdb(timeoutRoot);
    final ProcessResult timeout = runOperator(timeoutRoot, adb: timeoutAdb);
    expect(timeout.exitCode, 70);
    expect(File('${timeoutRoot.path}/back.count').readAsStringSync(), '1');
  });
}
