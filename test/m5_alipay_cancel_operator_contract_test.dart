import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File operator = File('tool/qa/m5_alipay_cancel_operator.sh').absolute;

  Directory createSandbox(String prefix) {
    final Directory sandbox = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (sandbox.existsSync()) {
        sandbox.deleteSync(recursive: true);
      }
    });
    return sandbox;
  }

  File createFakeAdb(
    Directory sandbox, {
    required String stateMode,
    required int targetCalls,
    required String marker,
    required int markerAfterBack,
    bool appendMarker = true,
  }) {
    File('${sandbox.path}/dumpsys-count.txt').writeAsStringSync('0');
    File('${sandbox.path}/keyevent-count.txt').writeAsStringSync('0');
    final File fakeAdb = File('${sandbox.path}/adb');
    fakeAdb.writeAsStringSync('''#!/usr/bin/env bash
set -Eeuo pipefail
: "\${FAKE_ADB_CALLS:?}"
: "\${FAKE_DUMPSYS_COUNT:?}"
: "\${FAKE_KEYEVENT_COUNT:?}"
: "\${FAKE_LOG_PATH:?}"
printf '%s\\n' "\$*" >>"\$FAKE_ADB_CALLS"
if [[ "\${1:-}" == '-s' ]]; then
  [[ "\${2:-}" == 'emulator-5554' ]]
  shift 2
fi
case "\${1:-}" in
  get-state)
    if [[ '$stateMode' == 'offline' ]]; then
      printf '%s\\n' 'offline'
      exit 0
    fi
    printf '%s\\n' 'device'
    ;;
  shell)
    shift
    if [[ "\${1:-}" == 'dumpsys' && "\${2:-}" == 'activity' && "\${3:-}" == 'activities' ]]; then
      count=\"\$(<\"\$FAKE_DUMPSYS_COUNT\")\"
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"\$FAKE_DUMPSYS_COUNT\"
      if (( count <= $targetCalls )); then
        printf '%s\\n' 'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity}'
      else
        printf '%s\\n' 'mResumedActivity: ActivityRecord{com.kong373.voice_social_app/.MainActivity}'
      fi
    elif [[ "\${1:-}" == 'input' && "\${2:-}" == 'keyevent' && "\${3:-}" == 'KEYCODE_BACK' ]]; then
      count=\"\$(<\"\$FAKE_KEYEVENT_COUNT\")\"
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"\$FAKE_KEYEVENT_COUNT\"
      if [[ '$appendMarker' == 'true' && \"\$count\" == '$markerAfterBack' ]]; then
        printf '%s\\n' '$marker' >>\"\$FAKE_LOG_PATH\"
      fi
    else
      exit 91
    fi
    ;;
  *)
    exit 92
    ;;
esac
''');
    final ProcessResult chmod = Process.runSync('/bin/chmod', <String>[
      '0755',
      fakeAdb.path,
    ]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    return fakeAdb;
  }

  ProcessResult runOperator(
    Directory sandbox, {
    required File fakeAdb,
    required File flutterLog,
    String serial = 'emulator-5554',
    String? avdBSerial,
    int afterBackTimeout = 0,
  }) {
    final File calls = File('${sandbox.path}/adb-calls.txt');
    final File dumpsysCount = File('${sandbox.path}/dumpsys-count.txt');
    final File keyeventCount = File('${sandbox.path}/keyevent-count.txt');
    final String inheritedPath =
        Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return Process.runSync(
      '/bin/bash',
      <String>[
        operator.path,
        '--adb',
        fakeAdb.path,
        '--target-timeout',
        '1',
        '--after-back-timeout',
        '$afterBackTimeout',
        '--marker-timeout',
        '1',
        '--poll-interval',
        '0',
        '--stable-polls',
        '3',
      ],
      environment: <String, String>{
        'PATH': inheritedPath,
        'ANDROID_SERIAL': serial,
        'FLUTTER_LOG_PATH': flutterLog.path,
        'FAKE_ADB_CALLS': calls.path,
        'FAKE_DUMPSYS_COUNT': dumpsysCount.path,
        'FAKE_KEYEVENT_COUNT': keyeventCount.path,
        'FAKE_LOG_PATH': flutterLog.path,
        if (avdBSerial != null) 'QA_AVD_B_SERIAL': avdBSerial,
      },
      includeParentEnvironment: false,
    );
  }

  test('operator shell has strict bounded and no-tap source contract', () {
    final String source = operator.readAsStringSync();
    expect(source, contains('set -Eeuo pipefail'));
    expect(source, contains("TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'"));
    expect(source, contains("TARGET_ACTIVITY='MspContainerActivity'"));
    expect(source, contains("TARGET_SERIAL='emulator-5554'"));
    expect(
      source,
      contains('M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001'),
    );
    expect(source, contains('ANDROID_SERIAL'));
    expect(source, contains('FLUTTER_LOG_PATH'));
    expect(source, contains('KEYCODE_BACK'));
    expect(source, isNot(contains('input tap')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    expect(source, isNot(contains('adb devices')));
    final ProcessResult syntax = Process.runSync('/bin/bash', <String>[
      '-n',
      operator.path,
    ]);
    expect(syntax.exitCode, 0, reason: '${syntax.stdout}\n${syntax.stderr}');
  });

  test('exact 6001 marker sends one BACK and leaves AVD-B untouched', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-pass-');
    final File log = File('${sandbox.path}/flutter-drive.log')
      ..writeAsStringSync('');
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 3,
      marker:
          'I/flutter (12345): '
          'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 1,
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
      avdBSerial: 'emulator-5556',
      afterBackTimeout: 1,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stdout,
      contains('NATIVE_RESULT_ACCEPTED::resultStatus=6001'),
    );
    final String calls = File(
      '${sandbox.path}/adb-calls.txt',
    ).readAsStringSync();
    expect(calls, isNot(contains('emulator-5556')));
    expect(calls, isNot(contains('devices')));
    expect(
      calls,
      contains('-s emulator-5554 shell input keyevent KEYCODE_BACK'),
    );
    expect(
      calls
          .split('\n')
          .where((String line) => line.contains('input keyevent KEYCODE_BACK'))
          .length,
      1,
    );
  });

  test('bounded retry sends exactly one second BACK when cashier remains', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-retry-');
    final File log = File('${sandbox.path}/flutter-drive.log')
      ..writeAsStringSync('');
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      // With after-back-timeout=0, one target observation keeps the cashier
      // present and exercises the explicitly capped second BACK.
      targetCalls: 10000,
      marker: 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 2,
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final String calls = File(
      '${sandbox.path}/adb-calls.txt',
    ).readAsStringSync();
    expect(
      calls
          .split('\n')
          .where((String line) => line.contains('input keyevent KEYCODE_BACK'))
          .length,
      2,
    );
    expect(result.stdout, contains('TARGET_STILL_PRESENT_AFTER_BOUNDED_WAIT'));
  });

  test('stale pre-existing 6001 marker is rejected before any BACK', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-stale-');
    final File log = File('${sandbox.path}/flutter-drive.log')
      ..writeAsStringSync(
        'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001\n',
      );
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 3,
      marker: 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 1,
      appendMarker: false,
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
    );
    expect(result.exitCode, 65);
    expect(result.stdout, isNot(contains('KEYCODE_BACK_SENT')));
    expect(File('${sandbox.path}/adb-calls.txt').existsSync(), isFalse);
  });

  test('none, non-6001, offline, and missing serial fail closed', () {
    final List<String> invalidMarkers = <String>[
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none',
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000',
    ];
    for (final String marker in invalidMarkers) {
      final Directory sandbox = createSandbox('m5-alipay-cancel-marker-');
      final File log = File('${sandbox.path}/flutter-drive.log')
        ..writeAsStringSync('');
      final File fakeAdb = createFakeAdb(
        sandbox,
        stateMode: 'online',
        targetCalls: 3,
        marker: marker,
        markerAfterBack: 1,
      );
      final ProcessResult result = runOperator(
        sandbox,
        fakeAdb: fakeAdb,
        flutterLog: log,
      );
      expect(result.exitCode, 65, reason: marker);
      expect(result.stdout, isNot(contains('PASS')));
    }

    final Directory offlineSandbox = createSandbox('m5-alipay-cancel-offline-');
    final File offlineLog = File('${offlineSandbox.path}/flutter-drive.log')
      ..writeAsStringSync('');
    final File offlineAdb = createFakeAdb(
      offlineSandbox,
      stateMode: 'offline',
      targetCalls: 3,
      marker: 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 1,
    );
    final ProcessResult offline = runOperator(
      offlineSandbox,
      fakeAdb: offlineAdb,
      flutterLog: offlineLog,
    );
    expect(offline.exitCode, 69);
    expect(
      File('${offlineSandbox.path}/adb-calls.txt').readAsStringSync(),
      isNot(contains('input keyevent KEYCODE_BACK')),
    );

    final Directory noSerialSandbox = createSandbox('m5-alipay-cancel-config-');
    final File noSerialLog = File('${noSerialSandbox.path}/flutter-drive.log')
      ..writeAsStringSync(
        'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001\n',
      );
    final File noSerialAdb = createFakeAdb(
      noSerialSandbox,
      stateMode: 'online',
      targetCalls: 3,
      marker: 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 1,
    );
    final ProcessResult noSerial = Process.runSync(
      '/bin/bash',
      <String>[
        operator.path,
        '--adb',
        noSerialAdb.path,
        '--poll-interval',
        '0',
      ],
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'FLUTTER_LOG_PATH': noSerialLog.path,
        'FAKE_ADB_CALLS': '${noSerialSandbox.path}/adb-calls.txt',
        'FAKE_DUMPSYS_COUNT': '${noSerialSandbox.path}/dumpsys-count.txt',
        'FAKE_KEYEVENT_COUNT': '${noSerialSandbox.path}/keyevent-count.txt',
      },
      includeParentEnvironment: false,
    );
    expect(noSerial.exitCode, 64);
    expect(File('${noSerialSandbox.path}/adb-calls.txt').existsSync(), isFalse);

    final Directory wrongSerialSandbox = createSandbox(
      'm5-alipay-cancel-wrong-serial-',
    );
    final File wrongSerialLog = File(
      '${wrongSerialSandbox.path}/flutter-drive.log',
    )..writeAsStringSync('');
    final File wrongSerialAdb = createFakeAdb(
      wrongSerialSandbox,
      stateMode: 'online',
      targetCalls: 3,
      marker: 'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001',
      markerAfterBack: 1,
    );
    final ProcessResult wrongSerial = runOperator(
      wrongSerialSandbox,
      fakeAdb: wrongSerialAdb,
      flutterLog: wrongSerialLog,
      serial: 'emulator-5556',
    );
    expect(wrongSerial.exitCode, 64);
    expect(
      File('${wrongSerialSandbox.path}/adb-calls.txt').existsSync(),
      isFalse,
    );
  });
}
