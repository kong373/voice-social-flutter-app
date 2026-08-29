import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File operator = File('tool/qa/m5_alipay_cancel_operator.sh').absolute;
  const String validNativeMarker =
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=6001';
  const String validBridgeMarker =
      'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned';
  const String targetPackage = 'com.eg.android.AlipayGphoneRC';
  const String targetActivity = 'MspContainerActivity';
  const String targetActivityClass =
      'com.alipay.android.msp.ui.views.MspContainerActivity';

  String readyUi({
    String package = targetPackage,
    String activity = targetActivity,
    String controlText = 'Cancel',
    String extra = '',
  }) =>
      '<hierarchy activity="$activity">'
      '<node package="$package" class="$targetActivityClass" '
      'text="$controlText" content-desc="$controlText" enabled="true" '
      'visible-to-user="true" clickable="true" bounds="[0,0][1080,1920]" />'
      '$extra</hierarchy>';

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
    Map<int, List<String>> markersByBack = const <int, List<String>>{},
    Map<int, List<String>> markersByDumpsys = const <int, List<String>>{},
    Map<int, String> uiByDump = const <int, String>{},
    Set<int> failedUiDumps = const <int>{},
    Map<int, String> activityByDumpsys = const <int, String>{},
    String? defaultUi,
  }) {
    File('${sandbox.path}/dumpsys-count.txt').writeAsStringSync('0');
    File('${sandbox.path}/keyevent-count.txt').writeAsStringSync('0');
    File('${sandbox.path}/ui-dump-count.txt').writeAsStringSync('0');
    File('${sandbox.path}/remote-ui.xml').writeAsStringSync('');
    String shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
    String markerCases(Map<int, List<String>> markers) => markers.isEmpty
        ? ''
        : markers.entries
              .map((MapEntry<int, List<String>> entry) {
                final String markerWrites = entry.value
                    .map(
                      (String marker) =>
                          "          printf '%s\\n' " +
                          shellQuote(marker) +
                          ' >>"\$FAKE_LOG_PATH"',
                    )
                    .join('\n');
                return '        ${entry.key})\n$markerWrites\n          ;;';
              })
              .join('\n');
    final String backMarkerCases = markerCases(markersByBack);
    final String dumpsysMarkerCases = markerCases(markersByDumpsys);
    final String uiDumpCases = uiByDump.entries
        .map((MapEntry<int, String> entry) {
          return '        ${entry.key})\n'
              '          printf %s ${shellQuote(entry.value)} '
              '>"\$FAKE_REMOTE_UI_XML"\n'
              '          ;;';
        })
        .join('\n');
    final String failedUiDumpCases = failedUiDumps
        .map((int count) => '        $count)\n          exit 93;;')
        .join('\n');
    final String activityCases = activityByDumpsys.entries
        .map((MapEntry<int, String> entry) {
          return '        ${entry.key})\n'
              '          printf %s ${shellQuote(entry.value)}\n'
              '          ;;';
        })
        .join('\n');
    final String fallbackUi = shellQuote(defaultUi ?? readyUi());
    final File fakeAdb = File('${sandbox.path}/adb');
    fakeAdb.writeAsStringSync('''#!/usr/bin/env bash
set -Eeuo pipefail
: "\${FAKE_ADB_CALLS:?}"
: "\${FAKE_DUMPSYS_COUNT:?}"
: "\${FAKE_KEYEVENT_COUNT:?}"
: "\${FAKE_UI_DUMP_COUNT:?}"
: "\${FAKE_LOG_PATH:?}"
: "\${FAKE_REMOTE_UI_XML:?}"
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
      case \"\$count\" in
$dumpsysMarkerCases
        *)
          ;;
      esac
      case "\$count" in
$activityCases
        *)
          if (( count <= $targetCalls )); then
            printf '%s\\n' 'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/com.alipay.android.msp.ui.views.MspContainerActivity}'
          else
            printf '%s\\n' 'mResumedActivity: ActivityRecord{com.kong373.voice_social_app/.MainActivity}'
          fi
          ;;
      esac
    elif [[ "\${1:-}" == 'uiautomator' && "\${2:-}" == 'dump' && -n "\${3:-}" ]]; then
      count="\$(<"\$FAKE_UI_DUMP_COUNT")"
      count=\$((count + 1))
      printf '%s' "\$count" >"\$FAKE_UI_DUMP_COUNT"
      case "\$count" in
$failedUiDumpCases
$uiDumpCases
        *)
          printf '%s' $fallbackUi >"\$FAKE_REMOTE_UI_XML"
          ;;
      esac
      printf 'UI hierchary dumped to: %s\\n' "\${3}"
    elif [[ "\${1:-}" == 'cat' && "\${2:-}" == *'voice-social-alipay-cancel-ui.xml' ]]; then
      cat "\$FAKE_REMOTE_UI_XML"
    elif [[ "\${1:-}" == 'chmod' && "\${2:-}" == '600' && "\${3:-}" == *'voice-social-alipay-cancel-ui.xml' ]]; then
      :
    elif [[ "\${1:-}" == 'rm' && "\${2:-}" == '-f' && "\${3:-}" == *'voice-social-alipay-cancel-ui.xml' ]]; then
      : >"\$FAKE_REMOTE_UI_XML"
    elif [[ "\${1:-}" == 'input' && "\${2:-}" == 'keyevent' && "\${3:-}" == 'KEYCODE_BACK' ]]; then
      count=\"\$(<\"\$FAKE_KEYEVENT_COUNT\")\"
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"\$FAKE_KEYEVENT_COUNT\"
      case \"\$count\" in
$backMarkerCases
        *)
          ;;
      esac
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
    int targetTimeout = 1,
  }) {
    final File calls = File('${sandbox.path}/adb-calls.txt');
    final File dumpsysCount = File('${sandbox.path}/dumpsys-count.txt');
    final File keyeventCount = File('${sandbox.path}/keyevent-count.txt');
    final File uiDumpCount = File(sandbox.path + '/ui-dump-count.txt');
    final String inheritedPath =
        Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return Process.runSync(
      '/bin/bash',
      <String>[
        operator.path,
        '--adb',
        fakeAdb.path,
        '--target-timeout',
        '$targetTimeout',
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
        'FAKE_UI_DUMP_COUNT': uiDumpCount.path,
        'FAKE_LOG_PATH': flutterLog.path,
        'FAKE_REMOTE_UI_XML': sandbox.path + '/remote-ui.xml',
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
    expect(source, contains(validNativeMarker));
    expect(source, contains(validBridgeMarker));
    expect(source, contains('ANDROID_SERIAL'));
    expect(source, contains('FLUTTER_LOG_PATH'));
    expect(source, contains('KEYCODE_BACK'));
    expect(source, contains('uiautomator dump'));
    expect(source, contains('shell cat'));
    expect(source, contains('DEVICE_UI_DUMP_PATH'));
    expect(source, contains('UI_XML_MAX_BYTES'));
    expect(source, contains('chmod 600'));
    expect(source, contains('UI_READY'));
    expect(source, contains('UI_GATE_RESET'));
    expect(source, contains('MspContainerActivity'));
    expect(source, isNot(contains('input tap')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    expect(source, isNot(contains('input text')));
    expect(source, isNot(contains('uiautomator click')));
    expect(source, isNot(contains('adb devices')));
    final ProcessResult syntax = Process.runSync('/bin/bash', <String>[
      '-n',
      operator.path,
    ]);
    expect(syntax.exitCode, 0, reason: '${syntax.stdout}\n${syntax.stderr}');
  });

  test('exact 6001/result pair sends one BACK and leaves AVD-B untouched', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-pass-');
    final File log = File('${sandbox.path}/flutter-drive.log')
      ..writeAsStringSync('');
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 3,
      markersByBack: <int, List<String>>{
        1: <String>[
          'I/flutter (12345): $validNativeMarker',
          'I/flutter (12345): $validBridgeMarker',
        ],
      },
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
    expect(
      result.stdout,
      contains('BRIDGE_OUTCOME_ACCEPTED::pay_task_returned'),
    );
    final String calls = File(
      '${sandbox.path}/adb-calls.txt',
    ).readAsStringSync();
    expect(calls, isNot(contains('emulator-5556')));
    expect(calls, isNot(contains('devices')));
    expect(
      calls
          .split('\n')
          .where((String line) => line.contains('uiautomator dump'))
          .length,
      3,
    );
    expect(
      calls,
      contains(
        'shell chmod 600 /data/local/tmp/voice-social-alipay-cancel-ui.xml',
      ),
    );
    expect(
      calls,
      contains('shell rm -f /data/local/tmp/voice-social-alipay-cancel-ui.xml'),
    );
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
      markersByBack: <int, List<String>>{
        1: <String>[validNativeMarker],
        2: <String>[validBridgeMarker],
      },
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

  test(
    'fresh UI gate requires three consecutive ready snapshots after jitter',
    () {
      final Directory sandbox = createSandbox('m5-alipay-cancel-ui-jitter-');
      final File log = File(sandbox.path + '/flutter-drive.log')
        ..writeAsStringSync('');
      final String loadingUi = readyUi(
        extra:
            '<node package="$targetPackage" class="android.widget.ProgressBar" '
            'text="Loading" enabled="true" visible-to-user="true" />',
      );
      final File fakeAdb = createFakeAdb(
        sandbox,
        stateMode: 'online',
        targetCalls: 5,
        uiByDump: <int, String>{
          1: readyUi(),
          2: loadingUi,
          3: readyUi(),
          4: readyUi(),
          5: readyUi(),
        },
        markersByBack: <int, List<String>>{
          1: <String>[validNativeMarker, validBridgeMarker],
        },
      );
      final ProcessResult result = runOperator(
        sandbox,
        fakeAdb: fakeAdb,
        flutterLog: log,
        afterBackTimeout: 1,
      );
      expect(
        result.exitCode,
        0,
        reason:
            'stdout:\n' +
            result.stdout.toString() +
            '\nstderr:\n' +
            result.stderr.toString(),
      );
      expect(result.stdout, contains('UI_READY::polls=3'));
      expect(
        int.parse(File(sandbox.path + '/ui-dump-count.txt').readAsStringSync()),
        5,
      );
      final List<String> calls = File(
        sandbox.path + '/adb-calls.txt',
      ).readAsLinesSync();
      final int backIndex = calls.indexWhere(
        (String line) => line.contains('input keyevent KEYCODE_BACK'),
      );
      expect(backIndex, greaterThanOrEqualTo(0));
      expect(
        calls
            .take(backIndex)
            .where((String line) => line.contains('uiautomator dump'))
            .length,
        greaterThanOrEqualTo(5),
      );
    },
  );

  test('second BACK reruns and resets the three-snapshot UI gate', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-ui-second-');
    final File log = File(sandbox.path + '/flutter-drive.log')
      ..writeAsStringSync('');
    final String loadingUi = readyUi(
      extra:
          '<node package="$targetPackage" class="android.widget.ProgressBar" '
          'text="Loading" enabled="true" visible-to-user="true" />',
    );
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 10000,
      uiByDump: <int, String>{
        1: readyUi(),
        2: readyUi(),
        3: readyUi(),
        4: loadingUi,
        5: loadingUi,
        6: loadingUi,
        7: readyUi(),
        8: readyUi(),
        9: readyUi(),
      },
      markersByBack: <int, List<String>>{
        1: <String>[validNativeMarker],
        2: <String>[validBridgeMarker],
      },
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
    );
    expect(
      result.exitCode,
      0,
      reason:
          'stdout:\n' +
          result.stdout.toString() +
          '\nstderr:\n' +
          result.stderr.toString(),
    );
    expect(result.stdout, contains('UI_GATE_RESET'));
    expect(File(sandbox.path + '/keyevent-count.txt').readAsStringSync(), '2');
    expect(File(sandbox.path + '/ui-dump-count.txt').readAsStringSync(), '9');
    final List<String> calls = File(
      sandbox.path + '/adb-calls.txt',
    ).readAsLinesSync();
    expect(
      calls
          .where((String line) => line.contains('input keyevent KEYCODE_BACK'))
          .length,
      2,
    );
  });

  test('unsafe or incomplete cashier UI states fail closed without BACK', () {
    final String loadingUi = readyUi(
      extra:
          '<node package="$targetPackage" class="android.widget.ProgressBar" '
          'text="Loading" enabled="true" visible-to-user="true" />',
    );
    final String inputUi = readyUi(
      extra:
          '<node package="$targetPackage" class="android.widget.EditText" '
          'text="OTP" enabled="true" visible-to-user="true" />',
    );
    final String passwordUi = readyUi(
      extra:
          '<node package="$targetPackage" class="android.widget.TextView" '
          'text="请输入支付密码" enabled="true" visible-to-user="true" />',
    );
    final Map<String, String> unsafeUi = <String, String>{
      'loading': loadingUi,
      'busy': readyUi(
        extra: '<node package="$targetPackage" text="Server busy" />',
      ),
      'error': readyUi(
        extra: '<node package="$targetPackage" text="Payment error" />',
      ),
      'reload': readyUi(
        extra: '<node package="$targetPackage" text="Reload" />',
      ),
      'edittext': inputUi,
      'otp': readyUi(
        extra: '<node package="$targetPackage" text="Enter one-time code" />',
      ),
      'password': passwordUi,
      'wrong-package': readyUi(package: 'com.other.wallet'),
      'wrong-activity': readyUi(activity: 'OtherActivity'),
      'missing-control': readyUi(controlText: ''),
      'corrupt': '<hierarchy><node package="$targetPackage"',
      'oversized':
          '<hierarchy>' +
          List<String>.filled(300000, 'x').join() +
          '</hierarchy>',
    };

    for (final MapEntry<String, String> entry in unsafeUi.entries) {
      final Directory sandbox = createSandbox(
        'm5-alipay-cancel-ui-' + entry.key + '-',
      );
      final File log = File(sandbox.path + '/flutter-drive.log')
        ..writeAsStringSync('');
      final File fakeAdb = createFakeAdb(
        sandbox,
        stateMode: 'online',
        targetCalls: 10000,
        defaultUi: entry.value,
      );
      final ProcessResult result = runOperator(
        sandbox,
        fakeAdb: fakeAdb,
        flutterLog: log,
        targetTimeout: 0,
      );
      expect(
        result.exitCode,
        isNot(0),
        reason:
            entry.key +
            '\nstdout:\n' +
            result.stdout.toString() +
            '\nstderr:\n' +
            result.stderr.toString(),
      );
      expect(
        File(sandbox.path + '/keyevent-count.txt').readAsStringSync(),
        '0',
        reason: entry.key,
      );
      expect(result.stdout, isNot(contains('KEYCODE_BACK_SENT')));
    }
  });

  test('uiautomator dump failure fails closed before BACK', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-ui-dump-fail-');
    final File log = File(sandbox.path + '/flutter-drive.log')
      ..writeAsStringSync('');
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 10000,
      failedUiDumps: <int>{1},
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
      targetTimeout: 0,
    );
    expect(result.exitCode, 69);
    expect(File(sandbox.path + '/keyevent-count.txt').readAsStringSync(), '0');
    expect(result.stdout, isNot(contains('KEYCODE_BACK_SENT')));
  });

  test('stale pre-existing native or bridge marker rejects before adb', () {
    for (final String staleMarker in <String>[
      validNativeMarker,
      validBridgeMarker,
    ]) {
      final Directory sandbox = createSandbox('m5-alipay-cancel-stale-');
      final File log = File('${sandbox.path}/flutter-drive.log')
        ..writeAsStringSync('$staleMarker\n');
      final File fakeAdb = createFakeAdb(
        sandbox,
        stateMode: 'online',
        targetCalls: 3,
      );
      final ProcessResult result = runOperator(
        sandbox,
        fakeAdb: fakeAdb,
        flutterLog: log,
      );
      expect(result.exitCode, 65, reason: staleMarker);
      expect(result.stdout, isNot(contains('KEYCODE_BACK_SENT')));
      expect(File('${sandbox.path}/adb-calls.txt').existsSync(), isFalse);
    }
  });

  test('marker appearing after baseline but before BACK is rejected', () {
    final Directory sandbox = createSandbox('m5-alipay-cancel-early-');
    final File log = File('${sandbox.path}/flutter-drive.log')
      ..writeAsStringSync('');
    final File fakeAdb = createFakeAdb(
      sandbox,
      stateMode: 'online',
      targetCalls: 3,
      markersByDumpsys: <int, List<String>>{
        3: <String>[validBridgeMarker],
      },
    );
    final ProcessResult result = runOperator(
      sandbox,
      fakeAdb: fakeAdb,
      flutterLog: log,
    );
    expect(result.exitCode, 65);
    expect(result.stdout, isNot(contains('KEYCODE_BACK_SENT')));
    final String calls = File(
      '${sandbox.path}/adb-calls.txt',
    ).readAsStringSync();
    expect(calls, isNot(contains('input keyevent KEYCODE_BACK')));
  });

  test('missing, wrong, or duplicate bridge provenance fails closed', () {
    final List<List<String>> markerSets = <List<String>>[
      <String>[validNativeMarker],
      <String>[validBridgeMarker],
      <String>[
        validNativeMarker,
        'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::native_watchdog_timeout',
      ],
      <String>[validNativeMarker, validNativeMarker, validBridgeMarker],
      <String>[validNativeMarker, validBridgeMarker, validBridgeMarker],
      <String>['prefix-$validNativeMarker', 'prefix-$validBridgeMarker'],
    ];
    for (final List<String> markers in markerSets) {
      final Directory sandbox = createSandbox('m5-alipay-cancel-pair-');
      final File log = File('${sandbox.path}/flutter-drive.log')
        ..writeAsStringSync('');
      final File fakeAdb = createFakeAdb(
        sandbox,
        stateMode: 'online',
        targetCalls: 3,
        markersByBack: <int, List<String>>{1: markers},
      );
      final ProcessResult result = runOperator(
        sandbox,
        fakeAdb: fakeAdb,
        flutterLog: log,
        afterBackTimeout: 1,
      );
      expect(result.exitCode, isNot(0), reason: markers.join(' | '));
      expect(result.stdout, isNot(contains('::PASS')));
    }
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
        markersByBack: <int, List<String>>{
          1: <String>[marker, validBridgeMarker],
        },
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
