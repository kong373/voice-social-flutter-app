import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String workflow = File(
    '.github/workflows/m33-video-runtime-final.yml',
  ).readAsStringSync();
  final String integrationTest = File(
    'integration_test/m3_3_video_runtime_ui_test.dart',
  ).readAsStringSync();
  final File androidAcceptanceScriptFile = File(
    'tool/qa/run_m33_android_acceptance.sh',
  );
  final String androidAcceptanceScript =
      androidAcceptanceScriptFile.existsSync()
      ? androidAcceptanceScriptFile.readAsStringSync()
      : '';
  final String acceptanceSources = '$workflow\n$androidAcceptanceScript';

  test('quality evidence is required and verified by the verdict job', () {
    expect(workflow, contains('name: m33-final-quality-'));
    expect(workflow, contains('if-no-files-found: error'));
    expect(workflow, contains('pattern: m33-final-quality-*'));
    expect(workflow, isNot(contains('if-no-artifact-found:')));
    expect(workflow, contains('app-debug.apk'));
    expect(workflow, contains('pubspec.lock'));
    expect(workflow, contains('test -s'));
    expect(workflow, isNot(contains('echo "provider_calls_made=false"')));
  });

  test('quality failures retain golden diagnostics and bind the APK hash', () {
    expect(workflow, contains('test/failures/**'));
    expect(workflow, contains('apk-sha256.txt'));
    expect(workflow, contains('shasum -a 256 app-debug.apk'));
    expect(workflow, contains('shasum -a 256 -c apk-sha256.txt'));
    expect(workflow, contains('apk_sha256='));
  });

  test('Android jobs build through an isolated generated host', () {
    for (final String marker in <String>[
      'flutter create --platforms=android',
      '--org=com.kong373',
      '--project-name=voice_social_app',
      '--no-pub',
      'test ! -e ci_app',
      'ci_app',
      'rsync -a',
      "--exclude='.git'",
      "--exclude='.github'",
      "--exclude='.dart_tool'",
      "--exclude='ci_app'",
      "--exclude='artifacts'",
      "--exclude='build'",
      "--exclude='test/failures'",
      'flutter pub get --enforce-lockfile',
      'cd ci_app',
    ]) {
      expect(workflow, contains(marker), reason: 'missing $marker');
    }
    int occurrences(String value) => value.allMatches(workflow).length;
    expect(
      occurrences('flutter create --platforms=android'),
      greaterThanOrEqualTo(2),
    );
    expect(occurrences('rsync -a'), greaterThanOrEqualTo(2));
    expect(
      occurrences('flutter pub get --enforce-lockfile'),
      greaterThanOrEqualTo(2),
    );
    expect(occurrences('cd ci_app'), greaterThanOrEqualTo(2));
    expect(workflow, isNot(contains('rm -rf ci_app')));
    expect(workflow, isNot(contains('rsync -a --delete')));
    expect(workflow, isNot(contains('.ci_app')));
    expect(workflow, contains('ci_app/build/app/outputs/flutter-apk'));
    expect(workflow, contains('test/failures/**'));
    expect(workflow, contains('pubspec.lock'));
    expect(
      workflow,
      contains('(cd ci_app && flutter pub get --enforce-lockfile)'),
    );
    expect(workflow, contains('flutter build apk --debug'));
    expect(acceptanceSources, contains('flutter drive'));
    expect(workflow, contains('secret_roots=(ci_app/lib ci_app/android)'));
    expect(
      workflow,
      contains(r'EVIDENCE_ROOT: ${{ github.workspace }}/artifacts'),
    );
  });

  test('quality runs source-root tests before creating the Android host', () {
    final String quality = workflow.split('  avd:').first;
    expect(quality, contains('run: flutter pub get --enforce-lockfile'));
    expect(quality, contains('run: flutter analyze'));
    expect(
      quality,
      contains(
        'run: flutter test --concurrency=1 --timeout=90s --reporter=expanded',
      ),
    );
    expect(
      quality.indexOf('Create isolated Android host'),
      greaterThan(
        quality.indexOf(
          'run: flutter test --concurrency=1 --timeout=90s --reporter=expanded',
        ),
      ),
    );
    expect(
      quality,
      contains('(cd ci_app && flutter pub get --enforce-lockfile)'),
    );
    expect(quality, contains('test -s pubspec.lock'));
    expect(quality, contains('ci_app/build/app/outputs/flutter-apk'));
  });

  test('quality gate uses the executable 69-page manifest contract', () {
    expect(
      workflow,
      contains('flutter test --no-pub test/page_manifest_test.dart'),
    );
    expect(workflow, isNot(contains('grep -c "PageManifestEntry("')));
  });

  test('quality gate verifies root navigation through executable UI tests', () {
    expect(
      workflow,
      contains(
        'flutter test --no-pub test/page_manifest_test.dart '
        'test/live_shell_gate_test.dart',
      ),
    );
    for (final String label in <String>['首页', '发现', '消息', '我的']) {
      expect(
        workflow,
        isNot(contains('grep -F "label: \'$label\'"')),
        reason: '$label must be verified by widget behavior, not source layout',
      );
    }
  });

  test('workflow pins every scoped action to a full commit sha', () {
    expect(
      workflow,
      contains(
        'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
      ),
    );
    expect(
      workflow,
      contains(
        'actions/setup-java@c5195efecf7bdfc987ee8bae7a71cb8b11521c00 # v4.7.1',
      ),
    );
    expect(
      workflow,
      contains(
        'subosito/flutter-action@fd55f4c5af5b953cc57a2be44cb082c8f6635e8e # v2.21.0',
      ),
    );
    expect(
      workflow,
      contains(
        'ReactiveCircus/android-emulator-runner@324029e2f414c084d8b15ba075288885e74aef9c # v2.34.0',
      ),
    );
    expect(
      workflow,
      contains(
        'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2',
      ),
    );
    expect(
      workflow,
      contains(
        'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4.3.0',
      ),
    );
    expect(workflow, isNot(contains('uses: actions/checkout@v4')));
    expect(workflow, isNot(contains('uses: actions/setup-java@v4')));
    expect(workflow, isNot(contains('uses: subosito/flutter-action@v2')));
    expect(
      workflow,
      isNot(contains('uses: ReactiveCircus/android-emulator-runner@v2')),
    );
    expect(workflow, isNot(contains('uses: actions/upload-artifact@v4')));
    expect(workflow, isNot(contains('uses: actions/download-artifact@v4')));
  });

  test('each AVD summary is bound to the workflow commit', () {
    expect(workflow, contains(r'''for summary in "${summaries[@]}"; do'''));
    expect(workflow, contains(r'''sed -n 's/^git_sha=//p' "$summary"'''));
    expect(workflow, contains(r'''= "$expected_sha"'''));
  });

  test('emulator runner invokes one checked-in Bash acceptance script', () {
    expect(androidAcceptanceScriptFile.existsSync(), isTrue);
    expect(
      workflow,
      contains('script: bash tool/qa/run_m33_android_acceptance.sh'),
    );
    expect(
      'script: bash tool/qa/run_m33_android_acceptance.sh'
          .allMatches(workflow)
          .length,
      1,
    );
    expect(workflow, isNot(contains('script: |')));
    for (final String binding in <String>[
      r'EVIDENCE_ROOT: ${{ github.workspace }}/artifacts/m3.3/${{ matrix.id }}',
      r'QA_AVD_ID: ${{ matrix.id }}',
      r'QA_API_LEVEL: ${{ matrix.api }}',
      r'QA_VIEWPORT: ${{ matrix.viewport }}',
      r'QA_WIDTH: ${{ matrix.width }}',
      r'QA_HEIGHT: ${{ matrix.height }}',
      r'QA_PHYSICAL: ${{ matrix.physical }}',
      r'QA_DENSITY: ${{ matrix.density }}',
      r'QA_DPR: ${{ matrix.dpr }}',
    ]) {
      expect(workflow, contains(binding), reason: 'missing $binding');
    }
    expect(workflow, contains("- 'tool/qa/run_m33_android_acceptance.sh'"));
    expect(androidAcceptanceScript, startsWith('#!/usr/bin/env bash\n'));
    expect(androidAcceptanceScript, contains('set -Eeuo pipefail'));
    expect(androidAcceptanceScript, contains('stop_logcat'));
    expect(
      androidAcceptanceScript,
      contains(r'''test -s "$EVIDENCE_ROOT/logcat.txt"'''),
    );
    expect(
      androidAcceptanceScript,
      contains(r'''test -s "$EVIDENCE_ROOT/flutter-drive.log"'''),
    );
    expect(
      androidAcceptanceScript.indexOf(r'''>"$PROGRESS_FILE"'''),
      inInclusiveRange(
        0,
        androidAcceptanceScript.indexOf('adb shell wm size') - 1,
      ),
      reason: 'an early device failure must still leave uploadable evidence',
    );
    for (final String variable in <String>[
      'EVIDENCE_ROOT',
      'QA_AVD_ID',
      'QA_API_LEVEL',
      'QA_VIEWPORT',
      'QA_WIDTH',
      'QA_HEIGHT',
      'QA_PHYSICAL',
      'QA_DENSITY',
      'QA_DPR',
      'GITHUB_SHA',
      'GITHUB_RUN_ID',
      'GITHUB_RUN_ATTEMPT',
    ]) {
      expect(
        androidAcceptanceScript,
        contains(': "\${$variable:?'),
        reason: '$variable must fail closed',
      );
    }
  });

  test('screenshots are emitted directly into the evidence root', () {
    expect(
      androidAcceptanceScript,
      contains(r'''readonly SCREENSHOT_DIR="$EVIDENCE_ROOT/screenshots"'''),
    );
    expect(
      androidAcceptanceScript,
      contains(r'''QA_SCREENSHOT_DIR="$SCREENSHOT_DIR"'''),
    );
    expect(
      androidAcceptanceScript,
      isNot(contains("find . -type f -name 'm33-*.png'")),
    );
    expect(androidAcceptanceScript, contains(r'''find "$SCREENSHOT_DIR"'''));
  });

  test('each AVD records and gates a non-empty interaction video', () {
    expect(androidAcceptanceScript, contains('adb shell screenrecord'));
    expect(
      androidAcceptanceScript,
      contains(r'''/data/local/tmp/m33-${QA_AVD_ID}.mp4'''),
    );
    expect(androidAcceptanceScript, isNot(contains('/sdcard/m33-')));
    expect(androidAcceptanceScript, contains(r'''"$EVIDENCE_ROOT/videos"'''));
    expect(androidAcceptanceScript, contains("-name '*.mp4' -size +0c"));
    expect(androidAcceptanceScript, contains(r'''test "$videos" -ge 1'''));
    expect(androidAcceptanceScript, contains(r'''echo "videos=$videos"'''));
    expect(workflow, contains(r'''sed -n 's/^videos=//p' "$summary"'''));
  });

  test('room tools acceptance uses stable semantics and current labels', () {
    expect(integrationTest, contains("find.byTooltip('更多').hitTestable()"));
    expect(integrationTest, contains("find.text('互动玩法')"));
    expect(integrationTest, isNot(contains("find.text('互动')")));
    expect(integrationTest, isNot(contains('tester.pageBack()')));
    expect(
      'tester.binding.handlePopRoute()'.allMatches(integrationTest).length,
      2,
    );
    expect(
      integrationTest,
      contains("find.text('收起房间').hitTestable().evaluate().isNotEmpty"),
    );
  });

  test('AVD hard-error and forbidden-entry scans fail closed', () {
    expect(
      androidAcceptanceScript,
      contains(
        r'''cat "$EVIDENCE_ROOT/logcat.txt" "$EVIDENCE_ROOT/flutter-drive.log"''',
      ),
    );
    for (final String marker in <String>[
      'Failed assertion',
      '_dependents.isEmpty',
      'EXCEPTION CAUGHT BY',
      'MissingPluginException',
      'RenderFlex overflow',
      'Unhandled Exception',
    ]) {
      expect(
        androidAcceptanceScript,
        contains(marker),
        reason: 'missing $marker scan',
      );
    }
    for (final String forbidden in <String>['会员', 'VIP', '礼物背包', '背包']) {
      expect(workflow, contains(forbidden), reason: 'missing $forbidden gate');
    }
  });

  test(
    'App hard-error gate is UID-scoped and checks exact global App ANRs',
    () {
      expect(
        androidAcceptanceScript,
        contains(r'''readonly APP_PACKAGE="com.kong373.voice_social_app"'''),
      );
      expect(
        androidAcceptanceScript,
        contains(
          r'''readonly APP_LOGCAT_FILE="$EVIDENCE_ROOT/logcat-app.txt"''',
        ),
      );
      expect(androidAcceptanceScript, contains('wait_for_app_uid'));
      expect(androidAcceptanceScript, contains('start_app_logcat'));
      expect(androidAcceptanceScript, contains('wait_for_app_logcat_evidence'));
      expect(androidAcceptanceScript, contains('pm list packages -U'));
      expect(
        androidAcceptanceScript,
        contains(r'''adb logcat --uid="$resolved_uid"'''),
      );
      expect(androidAcceptanceScript, contains('-T 10000'));
      expect(
        androidAcceptanceScript,
        contains(r'''test -s "$APP_LOGCAT_FILE"'''),
      );
      expect(androidAcceptanceScript, contains('am force-stop'));
      expect(
        androidAcceptanceScript,
        contains(r'''ANR in com\.kong373\.voice_social_app([[:space:]:]|$)'''),
      );
      expect(
        androidAcceptanceScript,
        contains(
          r'''cat "$APP_LOGCAT_FILE" "$EVIDENCE_ROOT/flutter-drive.log"''',
        ),
      );
      expect(androidAcceptanceScript, contains('Fatal signal [0-9]+'));
      expect(
        androidAcceptanceScript,
        contains(r'''hard_errors="$((app_hard_errors + global_app_anrs))"'''),
      );
      expect(
        androidAcceptanceScript,
        contains(r'''echo "system_hard_findings=$system_hard_findings"'''),
      );
      expect(
        androidAcceptanceScript,
        contains(r'''test "$global_app_anrs" -eq 0'''),
      );
    },
  );

  test(
    'mobile secret scan cannot be bypassed by a missing platform directory',
    () {
      expect(workflow, contains('test -d ci_app/android'));
      expect(workflow, contains('test -d ci_app/lib'));
      expect(workflow, contains('secret_roots=(ci_app/lib ci_app/android)'));
      expect(
        workflow,
        contains('[[ -d ci_app/ios ]] && secret_roots+=(ci_app/ios)'),
      );
      expect(workflow, contains(r'''"${secret_roots[@]}"'''));
      expect(workflow, isNot(contains('lib android ios')));
    },
  );

  test('provider-call evidence comes from a fail-closed runtime guard', () {
    expect(integrationTest, contains('HttpOverrides'));
    expect(integrationTest, contains('connectionFactory'));
    expect(integrationTest, contains('M33_PROVIDER_CALLS_MADE='));
    expect(integrationTest, contains('M33_PROVIDER_EVIDENCE_SCOPE='));
    expect(
      integrationTest,
      contains('m33_video_runtime_mock_graph_and_http_outbound_guard'),
    );
    expect(integrationTest, contains('AppDependencies.fromEnvironment'));
    expect(integrationTest, isNot(contains("'providerCallsMade': false")));
    expect(integrationTest, isNot(contains('provider_calls_made=false')));
  });
}
