import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String acceptanceScript = File(
    'tool/qa/run_m33_android_acceptance.sh',
  ).absolute.path;

  test('checked-in acceptance script produces fail-closed AVD evidence', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'm33-android-acceptance-',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final Directory workspace = Directory('${sandbox.path}/workspace')
      ..createSync();
    final Directory appRoot = Directory('${workspace.path}/ci_app')
      ..createSync();
    File('${appRoot.path}/pubspec.yaml').writeAsStringSync('name: fake_app\n');

    final Directory fakeBin = Directory('${sandbox.path}/bin')..createSync();
    final File adbCalls = File('${sandbox.path}/adb-calls.txt');
    final File fakeAdb = File('${fakeBin.path}/adb')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
set -eu
: "${FAKE_ADB_CALLS_FILE:?FAKE_ADB_CALLS_FILE is required}"
printf '%s\n' "$*" >>"$FAKE_ADB_CALLS_FILE"
case "${1:-}" in
  logcat)
    if [[ "${FAKE_EMPTY_LOGCAT:-false}" != true ]]; then
      printf '%s\n' '08-21 11:04:00.000 I/M33Acceptance: logcat ready'
    fi
    exit 0
    ;;
  shell)
    exit 0
    ;;
  pull)
    destination="${3:?destination is required}"
    mkdir -p "$(dirname "$destination")"
    printf 'video-evidence' >"$destination"
    ;;
  *)
    exit 0
    ;;
esac
''');
    final File fakeFlutter = File('${fakeBin.path}/flutter')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
set -eu
test "${1:-}" = drive
: "${QA_SCREENSHOT_DIR:?QA_SCREENSHOT_DIR is required}"
mkdir -p "$QA_SCREENSHOT_DIR"
for index in 1 2 3 4 5 6 7 8; do
  printf 'screenshot-%s' "$index" >"$QA_SCREENSHOT_DIR/$index.png"
done
printf '%s\n' \
  'M33_PROVIDER_CALLS_MADE=false' \
  'M33_PROVIDER_GRAPH_PROVEN=true' \
  'M33_PROVIDER_EVIDENCE_SCOPE=m33_video_runtime_mock_graph_and_http_outbound_guard' \
  'M33_PROVIDER_GUARD_CONNECTION_ATTEMPTS=0'
''');
    final ProcessResult chmod = Process.runSync('/bin/chmod', <String>[
      '0755',
      fakeAdb.path,
      fakeFlutter.path,
    ]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

    final Directory evidence = Directory('${sandbox.path}/evidence');
    final String systemPath = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    final Map<String, String> environment = <String, String>{
      'PATH': '${fakeBin.path}:$systemPath',
      'FAKE_ADB_CALLS_FILE': adbCalls.path,
      'EVIDENCE_ROOT': evidence.path,
      'QA_AVD_ID': 'AVD-A',
      'QA_API_LEVEL': '36',
      'QA_VIEWPORT': '390x844',
      'QA_WIDTH': '390',
      'QA_HEIGHT': '844',
      'QA_PHYSICAL': '1170x2532',
      'QA_DENSITY': '480',
      'QA_DPR': '3',
      'GITHUB_SHA': '5ad3923043c673313a5c1f5c5f4323f22fae5a34',
      'GITHUB_RUN_ID': '32484420387',
      'GITHUB_RUN_ATTEMPT': '1',
    };
    ProcessResult runScript(
      Map<String, String> runEnvironment,
      Directory runEvidence,
    ) => Process.runSync(
      '/bin/bash',
      <String>[acceptanceScript],
      workingDirectory: workspace.path,
      environment: <String, String>{
        ...runEnvironment,
        'EVIDENCE_ROOT': runEvidence.path,
      },
      includeParentEnvironment: false,
    );
    final ProcessResult result = runScript(environment, evidence);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final File summaryFile = File('${evidence.path}/summary.txt');
    expect(summaryFile.existsSync(), isTrue);
    final File progressFile = File('${evidence.path}/runner-progress.txt');
    expect(progressFile.existsSync(), isTrue);
    expect(progressFile.readAsStringSync(), contains('state=STARTED'));
    final String summary = summaryFile.readAsStringSync();
    for (final String marker in <String>[
      'conclusion=PASS',
      'run_id=32484420387',
      'git_sha=5ad3923043c673313a5c1f5c5f4323f22fae5a34',
      'avd=AVD-A',
      'api=36',
      'viewport=390x844',
      'dpr=3',
      'screenshots=8',
      'videos=1',
      'hard_errors=0',
      'provider_calls_made=false',
      'provider_dependency_graph=true',
      'provider_guard_connection_attempts=0',
    ]) {
      expect(summary, contains(marker), reason: 'missing $marker');
    }
    expect(
      Directory(
        '${evidence.path}/screenshots',
      ).listSync().whereType<File>().length,
      8,
    );
    expect(
      File('${evidence.path}/videos/AVD-A.mp4').lengthSync(),
      greaterThan(0),
    );
    final String adbInvocationLog = adbCalls.readAsStringSync();
    for (final String command in <String>[
      'shell wm size 1170x2532',
      'shell wm density 480',
      'shell screenrecord --size 390x844 --bit-rate 4000000 --time-limit 180 /data/local/tmp/m33-AVD-A.mp4',
      'pull /data/local/tmp/m33-AVD-A.mp4 ${evidence.path}/videos/AVD-A.mp4',
    ]) {
      expect(
        adbInvocationLog,
        contains(command),
        reason: 'missing adb invocation: $command',
      );
    }

    final Directory emptyLogcatEvidence = Directory(
      '${sandbox.path}/empty-logcat-evidence',
    );
    final ProcessResult emptyLogcatResult = runScript(<String, String>{
      ...environment,
      'FAKE_EMPTY_LOGCAT': 'true',
    }, emptyLogcatEvidence);
    expect(emptyLogcatResult.exitCode, isNot(0));
    expect(File('${emptyLogcatEvidence.path}/logcat.txt').lengthSync(), 0);
    expect(
      File('${emptyLogcatEvidence.path}/summary.txt').existsSync(),
      isFalse,
    );
  });

  test('checked-in acceptance script rejects missing environment inputs', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'm33-android-acceptance-missing-env-',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>[acceptanceScript],
      workingDirectory: sandbox.path,
      environment: <String, String>{
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      },
      includeParentEnvironment: false,
    );

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('EVIDENCE_ROOT is required'));
  });
}
