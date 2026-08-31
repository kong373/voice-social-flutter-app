import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File probe = File('tool/qa/m5_alipay_error_dialog_probe.sh').absolute;
  const String serial = 'R58PHYSICAL001';
  const String packageName = 'com.eg.android.AlipayGphoneRC';
  const String bridgeMarker =
      'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned';
  const String successMarker =
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000';

  Directory sandbox(String prefix) {
    final Directory value = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (value.existsSync()) value.deleteSync(recursive: true);
    });
    return value;
  }

  File fakeAdb(
    Directory root, {
    required String uiXml,
    required String activity,
    List<String> markersAfterTap = const <String>[],
  }) {
    final File fake = File('${root.path}/adb');
    File('${root.path}/adb.calls').writeAsStringSync('');
    File('${root.path}/tap.count').writeAsStringSync('0');
    File('${root.path}/remote-ui.xml').writeAsStringSync('');
    File('${root.path}/fixture-ui.xml').writeAsStringSync(uiXml);
    File('${root.path}/fixture-activity.txt').writeAsStringSync(activity);
    File('${root.path}/fixture-markers.txt')
      ..writeAsStringSync(markersAfterTap.join('\n'));
    fake.writeAsStringSync('''#!/usr/bin/env python3
import os
import pathlib
import sys

calls = pathlib.Path(os.environ["FAKE_CALLS"])
calls.write_text(calls.read_text() + " ".join(sys.argv[1:]) + "\\n")
if len(sys.argv) < 3 or sys.argv[1] != "-s" or sys.argv[2] != "$serial":
    raise SystemExit(91)
args = sys.argv[3:]
if not args:
    raise SystemExit(92)
if args[0] == "get-state":
    print("device")
    raise SystemExit(0)
if args[0] != "shell":
    raise SystemExit(93)
args = args[1:]
if not args:
    raise SystemExit(94)
command = args[0]
if command == "getprop":
    values = {
        "ro.kernel.qemu": "0",
        "ro.boot.qemu": "0",
        "ro.hardware": "qcom",
        "ro.product.model": "Physical Phone",
        "ro.product.name": "physical",
        "ro.product.device": "physical",
        "ro.product.board": "physical",
    }
    print(values.get(args[1], ""))
elif command == "wm" and args[1] == "size":
    print("Physical size: 1080x1920")
elif command == "dumpsys" and args[1:3] == ["activity", "activities"]:
    print(pathlib.Path(os.environ["FAKE_ACTIVITY"]).read_text())
elif command == "uiautomator" and args[1] == "dump":
    pathlib.Path(os.environ["FAKE_REMOTE_UI"]).write_text(
        pathlib.Path(os.environ["FAKE_FIXTURE_UI"]).read_text()
    )
elif command == "cat":
    print(pathlib.Path(os.environ["FAKE_REMOTE_UI"]).read_text(), end="")
elif command in ("chmod", "rm"):
    pass
elif command == "input" and len(args) >= 2 and args[1] == "tap":
    tap_file = pathlib.Path(os.environ["FAKE_TAPS"])
    count = int(tap_file.read_text()) + 1
    tap_file.write_text(str(count))
    marker_file = pathlib.Path(os.environ["FAKE_MARKERS"])
    markers = marker_file.read_text()
    if markers:
        with pathlib.Path(os.environ["FAKE_LOG"]).open("a") as output:
            output.write(markers + "\\n")
else:
    raise SystemExit(95)
''');
    Process.runSync('/bin/chmod', <String>['0755', fake.path]);
    return fake;
  }

  ProcessResult runProbe(
    Directory root, {
    required String uiXml,
    required String activity,
    List<String> markersAfterTap = const <String>[bridgeMarker],
    String logContents = '',
    String? androidSerial,
    String selectedSerial = serial,
    int markerTimeout = 1,
  }) {
    final File log = File('${root.path}/flutter.log')
      ..writeAsStringSync(logContents);
    final File fake = fakeAdb(
      root,
      uiXml: uiXml,
      activity: activity,
      markersAfterTap: markersAfterTap,
    );
    final String inheritedPath =
        Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return Process.runSync(
      '/bin/bash',
      <String>[
        probe.path,
        '--adb',
        fake.path,
        '--serial',
        selectedSerial,
        '--flutter-log',
        log.path,
        '--dialog-timeout',
        '1',
        '--marker-timeout',
        '$markerTimeout',
        '--poll-interval',
        '0',
      ],
      environment: <String, String>{
        'PATH': inheritedPath,
        if (androidSerial != null) 'ANDROID_SERIAL': androidSerial,
        'FAKE_LOG': log.path,
        'FAKE_CALLS': '${root.path}/adb.calls',
        'FAKE_TAPS': '${root.path}/tap.count',
        'FAKE_REMOTE_UI': '${root.path}/remote-ui.xml',
        'FAKE_FIXTURE_UI': '${root.path}/fixture-ui.xml',
        'FAKE_ACTIVITY': '${root.path}/fixture-activity.txt',
        'FAKE_MARKERS': '${root.path}/fixture-markers.txt',
      },
      includeParentEnvironment: false,
    );
  }

  const String defaultUi =
      '<hierarchy package="com.eg.android.AlipayGphoneRC">'
      '<node package="com.eg.android.AlipayGphoneRC" class="android.widget.TextView" '
      'text="人气太旺啦，稍候再试试。(6)" visible-to-user="true" />'
      '<node package="com.eg.android.AlipayGphoneRC" class="android.widget.Button" '
      'text="确定" enabled="true" visible-to-user="true" clickable="true" '
      'bounds="[400,900][680,1020]" />'
      '</hierarchy>';
  const String defaultActivity =
      'mResumedActivity: ActivityRecord{com.eg.android.AlipayGphoneRC/'
      'com.alipay.android.msp.ui.views.MspContainerActivity}';

  test('probe is shell-valid and exposes only the narrow operation', () {
    expect(probe.existsSync(), isTrue);
    expect(probe.statSync().mode & 73, isNonZero);
    final ProcessResult syntax = Process.runSync('/bin/bash', <String>[
      '-n',
      probe.path,
    ]);
    expect(syntax.exitCode, 0, reason: '${syntax.stdout}\n${syntax.stderr}');
    final String source = probe.readAsStringSync();
    expect(source, contains('--serial'));
    expect(source, contains('--flutter-log'));
    expect(source, contains("TARGET_PACKAGE='com.eg.android.AlipayGphoneRC'"));
    expect(source, contains('人气太旺啦，稍候再试试。(6)'));
    expect(source, contains('Server busy, please try again later. (6)'));
    expect(source, contains('uiautomator dump'));
    expect(source, contains('input tap'));
    expect(source, contains('CLICK_COUNT=0'));
    expect(source, contains(bridgeMarker));
    expect(source, isNot(contains('input keyevent')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    expect(source, isNot(contains('flutter drive')));
    expect(source, isNot(contains('run_m5_vendor_live_avd')));
    expect(source, isNot(contains('payV2')));
  });

  test('offline self-test covers parser and marker fail-closed behavior', () {
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>[probe.path, '--self-test'],
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      },
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('PARSER_FAIL_CLOSED_PASS'));
    expect(result.stdout, contains('MARKER_FAIL_CLOSED_PASS'));
    expect(result.stdout, contains('SELF_TEST::PASS'));
  });

  test(
    'valid physical error dialog taps exactly once and waits for marker',
    () {
      final Directory root = sandbox('alipay-error-dialog-valid-');
      final ProcessResult result = runProbe(
        root,
        uiXml: defaultUi,
        activity: defaultActivity,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('ERROR_DIALOG_MATCHED'));
      expect(result.stdout, contains('DISMISS_BUTTON_TAPPED::count=1'));
      expect(result.stdout, contains('PAYTASK_RETURNED'));
      expect(result.stdout, contains('PASS'));
      expect(File('${root.path}/tap.count').readAsStringSync(), '1');
      final String calls = File('${root.path}/adb.calls').readAsStringSync();
      expect(calls, contains('-s $serial'));
      expect(calls, contains('input tap 540 960'));
      expect(calls, isNot(contains('input keyevent')));
    },
  );

  test(
    'wrong package, mismatched text, multiple buttons, unsafe payment, and bad bounds reject before tap',
    () {
      final Directory root = sandbox('alipay-error-dialog-reject-');
      final List<String> fixtures = <String>[
        defaultUi.replaceAll(packageName, 'com.other.wallet'),
        defaultUi.replaceFirst('人气太旺啦，稍候再试试。(6)', '其他提示'),
        defaultUi.replaceFirst(
          '</hierarchy>',
          '<node package="$packageName" class="android.widget.Button" text="关闭" enabled="true" visible-to-user="true" clickable="true" bounds="[400,1100][680,1220]" /></hierarchy>',
        ),
        defaultUi.replaceFirst(
          '</hierarchy>',
          '<node package="$packageName" class="android.widget.Button" text="确认支付" enabled="true" visible-to-user="true" clickable="true" bounds="[400,1100][680,1220]" /></hierarchy>',
        ),
        defaultUi.replaceFirst('[400,900][680,1020]', '[0,0][1200,2100]'),
      ];
      for (final String fixture in fixtures) {
        final ProcessResult result = runProbe(
          root,
          uiXml: fixture,
          activity: defaultActivity,
          markerTimeout: 0,
        );
        expect(
          result.exitCode,
          isNonZero,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(File('${root.path}/tap.count').readAsStringSync(), '0');
      }
    },
  );

  test('stale, success, and missing markers never become a pass', () {
    final Directory root = sandbox('alipay-error-dialog-markers-');
    final ProcessResult stale = runProbe(
      root,
      uiXml: defaultUi,
      activity: defaultActivity,
      logContents: '$bridgeMarker\n',
    );
    expect(stale.exitCode, isNonZero);
    expect(File('${root.path}/tap.count').readAsStringSync(), '0');

    final ProcessResult success = runProbe(
      root,
      uiXml: defaultUi,
      activity: defaultActivity,
      markersAfterTap: const <String>[successMarker],
    );
    expect(success.exitCode, isNonZero);
    expect(File('${root.path}/tap.count').readAsStringSync(), '1');

    final ProcessResult missing = runProbe(
      root,
      uiXml: defaultUi,
      activity: defaultActivity,
      markersAfterTap: const <String>[],
      markerTimeout: 0,
    );
    expect(missing.exitCode, isNonZero);
    expect(File('${root.path}/tap.count').readAsStringSync(), '1');
  });

  test('serial mismatch is rejected before any adb call', () {
    final Directory root = sandbox('alipay-error-dialog-serial-');
    final ProcessResult result = runProbe(
      root,
      uiXml: defaultUi,
      activity: defaultActivity,
      androidSerial: 'different-serial',
    );
    expect(result.exitCode, isNonZero);
    expect(File('${root.path}/adb.calls').readAsStringSync(), isEmpty);
  });
}
