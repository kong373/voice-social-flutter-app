import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File probe = File('tool/qa/m5_alipay_error_dialog_probe.sh').absolute;
  const String serial = 'R58PHYSICAL001';
  const String packageName = 'com.eg.android.AlipayGphoneRC';
  const String bridgeMarker =
      'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::pay_task_returned';
  const String nativeMarker =
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=4000';
  const String successMarker =
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=1::resultStatus=9000';

  Directory sandbox(String prefix) {
    final Directory value = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (value.existsSync()) value.deleteSync(recursive: true);
    });
    return value;
  }

  String activityFor(String component) {
    return 'mResumedActivity: ActivityRecord{$component}\n'
        'topResumedActivity: ActivityRecord{$component}';
  }

  String validUi({String? errorText, String? buttonText}) {
    final String safeError = errorText ?? '人气太旺啦，稍候再试试。(6)';
    final String safeButton = buttonText ?? '确定';
    return '<hierarchy rotation="0">'
        '<node package="$packageName" class="android.widget.FrameLayout">'
        '<node package="$packageName" class="android.widget.LinearLayout">'
        '<node package="$packageName" class="android.widget.TextView" '
        'text="$safeError" visible-to-user="true" />'
        '<node package="$packageName" class="android.widget.Button" '
        'text="$safeButton" enabled="true" visible-to-user="true" '
        'clickable="true" resource-id="$packageName:id/dialog_confirm" '
        'bounds="[400,900][680,1020]" />'
        '</node></node></hierarchy>';
  }

  String uiWith(String insertion) {
    return '<hierarchy rotation="0">'
        '<node package="$packageName" class="android.widget.FrameLayout">'
        '<node package="$packageName" class="android.widget.LinearLayout">'
        '<node package="$packageName" class="android.widget.TextView" '
        'text="人气太旺啦，稍候再试试。(6)" visible-to-user="true" />'
        '<node package="$packageName" class="android.widget.Button" '
        'text="确定" enabled="true" visible-to-user="true" '
        'clickable="true" bounds="[400,900][680,1020]" />'
        '$insertion</node></node></hierarchy>';
  }

  File fakeAdb(
    Directory root, {
    required List<String> uiFrames,
    required List<String> activityFrames,
    List<String> markersAfterTap = const <String>[],
  }) {
    final File fake = File('${root.path}/adb');
    final Directory uiDir = Directory('${root.path}/ui')..createSync();
    final Directory activityDir = Directory('${root.path}/activity')
      ..createSync();
    for (int index = 0; index < uiFrames.length; index++) {
      File('${uiDir.path}/$index.xml').writeAsStringSync(uiFrames[index]);
    }
    for (int index = 0; index < activityFrames.length; index++) {
      File(
        '${activityDir.path}/$index.txt',
      ).writeAsStringSync(activityFrames[index]);
    }
    File('${root.path}/adb.calls').writeAsStringSync('');
    File('${root.path}/tap.count').writeAsStringSync('0');
    File('${root.path}/dump.count').writeAsStringSync('0');
    File('${root.path}/activity.count').writeAsStringSync('0');
    File('${root.path}/remote-ui.xml').writeAsStringSync('');
    File(
      '${root.path}/markers.txt',
    ).writeAsStringSync(markersAfterTap.join('\n'));
    fake.writeAsStringSync('''#!/usr/bin/env python3
import os
import pathlib
import sys
import time

calls = pathlib.Path(os.environ["FAKE_CALLS"])
with calls.open("a") as stream:
    stream.write(" ".join(sys.argv[1:]) + "\\n")
if len(sys.argv) < 3 or sys.argv[1] != "-s" or sys.argv[2] != "R58PHYSICAL001":
    raise SystemExit(91)
args = sys.argv[3:]
if not args:
    raise SystemExit(92)
if args[0] == "get-state":
    hold = os.environ.get("FAKE_HOLD_FILE")
    started = os.environ.get("FAKE_STARTED_FILE")
    release = os.environ.get("FAKE_RELEASE_FILE")
    if hold and started and release and not pathlib.Path(started).exists():
        pathlib.Path(started).write_text("started")
        while not pathlib.Path(release).exists():
            time.sleep(0.01)
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
    count = pathlib.Path(os.environ["FAKE_ACTIVITY_COUNT"])
    index = int(count.read_text())
    frames = sorted(pathlib.Path(os.environ["FAKE_ACTIVITY_DIR"]).glob("*.txt"))
    frame = frames[min(index, len(frames) - 1)]
    print(frame.read_text(), end="")
    count.write_text(str(index + 1))
elif command == "uiautomator" and args[1] == "dump":
    count = pathlib.Path(os.environ["FAKE_DUMP_COUNT"])
    index = int(count.read_text())
    frames = sorted(pathlib.Path(os.environ["FAKE_UI_DIR"]).glob("*.xml"))
    frame = frames[min(index, len(frames) - 1)]
    pathlib.Path(os.environ["FAKE_REMOTE_UI"]).write_text(frame.read_text())
    count.write_text(str(index + 1))
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

  Map<String, String> fakeEnvironment(
    Directory root, {
    String? callsPath,
    String? logPath,
    String? holdFile,
    String? startedFile,
    String? releaseFile,
  }) {
    final String inheritedPath =
        Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return <String, String>{
      'PATH': inheritedPath,
      'FAKE_LOG': logPath ?? '${root.path}/flutter.log',
      'FAKE_CALLS': callsPath ?? '${root.path}/adb.calls',
      'FAKE_TAPS': '${root.path}/tap.count',
      'FAKE_REMOTE_UI': '${root.path}/remote-ui.xml',
      'FAKE_UI_DIR': '${root.path}/ui',
      'FAKE_DUMP_COUNT': '${root.path}/dump.count',
      'FAKE_ACTIVITY_DIR': '${root.path}/activity',
      'FAKE_ACTIVITY_COUNT': '${root.path}/activity.count',
      'FAKE_MARKERS': '${root.path}/markers.txt',
      if (holdFile != null) 'FAKE_HOLD_FILE': holdFile,
      if (startedFile != null) 'FAKE_STARTED_FILE': startedFile,
      if (releaseFile != null) 'FAKE_RELEASE_FILE': releaseFile,
    };
  }

  List<String> probeArgs(File fake, File log, {int markerTimeout = 1}) {
    return <String>[
      probe.path,
      '--adb',
      fake.path,
      '--serial',
      serial,
      '--flutter-log',
      log.path,
      '--dialog-timeout',
      '1',
      '--marker-timeout',
      '$markerTimeout',
      '--poll-interval',
      '0',
    ];
  }

  ProcessResult runProbe(
    Directory root, {
    required List<String> uiFrames,
    required List<String> activityFrames,
    List<String> markersAfterTap = const <String>[nativeMarker, bridgeMarker],
    String logContents = '',
    String? androidSerial,
    String selectedSerial = serial,
    int markerTimeout = 1,
  }) {
    final File log = File('${root.path}/flutter.log')
      ..writeAsStringSync(logContents);
    final File fake = fakeAdb(
      root,
      uiFrames: uiFrames,
      activityFrames: activityFrames,
      markersAfterTap: markersAfterTap,
    );
    final List<String> args = probeArgs(fake, log, markerTimeout: markerTimeout)
      ..[4] = selectedSerial;
    return Process.runSync(
      '/bin/bash',
      args,
      environment: <String, String>{
        ...fakeEnvironment(root, logPath: log.path),
        if (androidSerial != null) 'ANDROID_SERIAL': androidSerial,
      },
      includeParentEnvironment: false,
    );
  }

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
    expect(source, contains('uiautomator dump'));
    expect(source, contains('input tap'));
    expect(source, contains('CLICK_COUNT=0'));
    expect(source, contains(bridgeMarker));
    expect(source, contains('sdkCompleted=0'));
    expect(source, isNot(contains('Server busy')));
    expect(source, isNot(contains('input keyevent')));
    expect(source, isNot(contains('KEYCODE_ENTER')));
    expect(source, isNot(contains('flutter drive')));
    expect(source, isNot(contains('run_m5_vendor_live_avd')));
    expect(source, isNot(contains('payV2')));
  });

  test(
    'offline self-test covers strict parser and marker fail-closed behavior',
    () {
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
    },
  );

  test('valid dialog is stable, taps once, and has no adb after the tap', () {
    final Directory root = sandbox('alipay-error-dialog-valid-');
    final ProcessResult result = runProbe(
      root,
      uiFrames: <String>[validUi()],
      activityFrames: <String>[
        activityFor(
          '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
        ),
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('ERROR_DIALOG_MATCHED'));
    expect(result.stdout, contains('DISMISS_BUTTON_TAPPED::count=1'));
    expect(result.stdout, contains('resultStatus=4000'));
    expect(result.stdout, contains('PASS'));
    expect(File('${root.path}/tap.count').readAsStringSync(), '1');
    expect(
      int.parse(File('${root.path}/dump.count').readAsStringSync()),
      greaterThanOrEqualTo(3),
    );
    final List<String> calls = File('${root.path}/adb.calls').readAsLinesSync();
    final int tapIndex = calls.lastIndexWhere(
      (String line) => line.contains('shell input tap 540 960'),
    );
    expect(tapIndex, greaterThanOrEqualTo(0));
    expect(tapIndex, calls.length - 1);
    expect(calls.join('\n'), isNot(contains('input keyevent')));
  });

  test(
    'strict tree rejects text/content-desc normalization and unsafe surfaces',
    () {
      final List<String> fixtures = <String>[
        validUi(errorText: 'Server busy, please try again later. (6)'),
        validUi(errorText: ' 人气太旺啦，稍候再试试。(6)'),
        validUi().replaceFirst(
          'text="人气太旺啦，稍候再试试。(6)"',
          'content-desc="人气太旺啦，稍候再试试。(6)"',
        ),
        uiWith(
          '<node package="$packageName" class="android.widget.Button" '
          'text="关闭" enabled="true" clickable="true" '
          'bounds="[400,1100][680,1220]" />',
        ),
        uiWith(
          '<node package="$packageName" class="android.widget.Button" '
          'text="确认支付" enabled="true" clickable="true" '
          'bounds="[400,1100][680,1220]" />',
        ),
        uiWith(
          '<node package="$packageName" class="android.webkit.WebView" '
          'enabled="false" />',
        ),
        uiWith(
          '<node package="$packageName" class="android.widget.ImageButton" '
          'enabled="true" clickable="true" bounds="[400,1100][680,1220]" />',
        ),
        validUi()
            .replaceFirst(
              'text="确定" enabled="true"',
              'text="确定" enabled="true" content-desc="确定"',
            )
            .replaceFirst(
              '</node></node></hierarchy>',
              '<node package="$packageName" class="android.view.View" '
                  'enabled="true" clickable="true" /></node></node></hierarchy>',
            ),
      ];
      for (final String fixture in fixtures) {
        final Directory root = sandbox('alipay-error-dialog-reject-');
        final ProcessResult result = runProbe(
          root,
          uiFrames: <String>[fixture],
          activityFrames: <String>[
            activityFor(
              '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
            ),
          ],
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

  test('same-parent ancestry, bounds, and rotation are binding', () {
    final Directory root = sandbox('alipay-error-dialog-ancestry-');
    final String brothers =
        '<hierarchy package="$packageName" rotation="0">'
        '<node package="$packageName" class="android.widget.LinearLayout">'
        '<node package="$packageName" class="android.widget.TextView" '
        'text="人气太旺啦，稍候再试试。(6)" /></node>'
        '<node package="$packageName" class="android.widget.LinearLayout">'
        '<node package="$packageName" class="android.widget.Button" '
        'text="确定" enabled="true" clickable="true" '
        'bounds="[400,900][680,1020]" /></node></hierarchy>';
    final String badBounds = validUi().replaceFirst(
      '[400,900][680,1020]',
      '[0,0][1200,2100]',
    );
    final String invalidRotation = validUi().replaceFirst(
      'rotation="0"',
      'rotation="9"',
    );
    for (final String fixture in <String>[
      brothers,
      badBounds,
      invalidRotation,
    ]) {
      final ProcessResult result = runProbe(
        root,
        uiFrames: <String>[fixture],
        activityFrames: <String>[
          activityFor(
            '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
          ),
        ],
        markerTimeout: 0,
      );
      expect(result.exitCode, isNonZero);
      expect(File('${root.path}/tap.count').readAsStringSync(), '0');
    }
  });

  test('TOCTOU UI change before tap is rejected without tapping', () {
    final Directory root = sandbox('alipay-error-dialog-toctou-');
    final ProcessResult result = runProbe(
      root,
      uiFrames: <String>[
        validUi(),
        validUi().replaceFirst('[400,900][680,1020]', '[420,900][700,1020]'),
      ],
      activityFrames: <String>[
        activityFor(
          '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
        ),
      ],
      markerTimeout: 0,
    );
    expect(
      result.exitCode,
      isNonZero,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(File('${root.path}/tap.count').readAsStringSync(), '0');
    expect(
      int.parse(File('${root.path}/dump.count').readAsStringSync()),
      greaterThanOrEqualTo(2),
    );
  });

  test('conflicting foreground activities fail closed before tap', () {
    final Directory root = sandbox('alipay-error-dialog-activity-');
    final ProcessResult result = runProbe(
      root,
      uiFrames: <String>[validUi()],
      activityFrames: <String>[
        'mResumedActivity: ActivityRecord{$packageName/com.alipay.android.msp.ui.views.MspContainerActivity}\n'
            'mFocusedApp: AppWindowToken{$packageName/com.other.wallet/.PayActivity}',
      ],
      markerTimeout: 0,
    );
    expect(result.exitCode, isNonZero);
    expect(File('${root.path}/tap.count').readAsStringSync(), '0');
  });

  test('stale, duplicate, success, none, and missing markers never pass', () {
    final List<List<String>> cases = <List<String>>[
      <String>[nativeMarker],
      <String>[nativeMarker, nativeMarker, bridgeMarker],
      <String>[successMarker, bridgeMarker],
      <String>[
        'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=0::resultStatus=none',
        bridgeMarker,
      ],
      <String>[bridgeMarker],
    ];
    for (int index = 0; index < cases.length; index++) {
      final List<String> markers = cases[index];
      final bool staleBeforeTap = index == 0;
      final Directory root = sandbox('alipay-error-dialog-markers-');
      final ProcessResult result = runProbe(
        root,
        uiFrames: <String>[validUi()],
        activityFrames: <String>[
          activityFor(
            '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
          ),
        ],
        markersAfterTap: markers,
        logContents: staleBeforeTap ? '$nativeMarker\n' : '',
        markerTimeout: 0,
      );
      expect(
        result.exitCode,
        isNonZero,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(
        File('${root.path}/tap.count').readAsStringSync(),
        staleBeforeTap ? '0' : '1',
      );
    }
  });

  test('serial mismatch is rejected before any adb call', () {
    final Directory root = sandbox('alipay-error-dialog-serial-');
    final ProcessResult result = runProbe(
      root,
      uiFrames: <String>[validUi()],
      activityFrames: <String>[
        activityFor(
          '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
        ),
      ],
      androidSerial: 'different-serial',
    );
    expect(result.exitCode, isNonZero);
    expect(File('${root.path}/adb.calls').readAsStringSync(), isEmpty);
  });

  test(
    'serial lock blocks a second instance before its first adb call',
    () async {
      final Directory root = sandbox('alipay-error-dialog-lock-');
      final File logOne = File('${root.path}/flutter-one.log')
        ..writeAsStringSync('');
      final File logTwo = File('${root.path}/flutter-two.log')
        ..writeAsStringSync('');
      final File fake = fakeAdb(
        root,
        uiFrames: <String>[validUi()],
        activityFrames: <String>[
          activityFor(
            '$packageName/com.alipay.android.msp.ui.views.MspContainerActivity',
          ),
        ],
        markersAfterTap: <String>[nativeMarker, bridgeMarker],
      );
      final File hold = File('${root.path}/hold');
      final File started = File('${root.path}/started');
      final File release = File('${root.path}/release');
      final String callsOne = '${root.path}/calls-one';
      final String callsTwo = '${root.path}/calls-two';
      File(callsOne).writeAsStringSync('');
      File(callsTwo).writeAsStringSync('');
      final Map<String, String> envOne = fakeEnvironment(
        root,
        callsPath: callsOne,
        logPath: logOne.path,
        holdFile: hold.path,
        startedFile: started.path,
        releaseFile: release.path,
      );
      final Map<String, String> envTwo = fakeEnvironment(
        root,
        callsPath: callsTwo,
        logPath: logTwo.path,
      );
      final Process first = await Process.start(
        '/bin/bash',
        probeArgs(fake, logOne),
        environment: envOne,
        includeParentEnvironment: false,
      );
      Process? second;
      int? secondExit;
      int? firstExit;
      try {
        final DateTime deadline = DateTime.now().add(
          const Duration(seconds: 2),
        );
        while (!started.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(started.existsSync(), isTrue);
        second = await Process.start(
          '/bin/bash',
          probeArgs(fake, logTwo),
          environment: envTwo,
          includeParentEnvironment: false,
        );
        secondExit = await second.exitCode.timeout(const Duration(seconds: 3));
      } finally {
        if (second != null && secondExit == null) {
          second.kill(ProcessSignal.sigterm);
        }
        hold.writeAsStringSync('held');
        release.writeAsStringSync('release');
        firstExit = await first.exitCode.timeout(const Duration(seconds: 5));
      }
      expect(secondExit, isNotNull);
      expect(secondExit, isNonZero);
      expect(File(callsTwo).readAsStringSync(), isEmpty);
      expect(firstExit, 0);
    },
  );
}
