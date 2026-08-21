import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String workflow = File(
    '.github/workflows/m33-video-runtime-final.yml',
  ).readAsStringSync();
  final String integrationTest = File(
    'integration_test/m3_3_video_runtime_ui_test.dart',
  ).readAsStringSync();

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

  test('quality gate uses the executable 69-page manifest contract', () {
    expect(
      workflow,
      contains('flutter test --no-pub test/page_manifest_test.dart'),
    );
    expect(workflow, isNot(contains('grep -c "PageManifestEntry("')));
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

  test('screenshots are emitted directly into the evidence root', () {
    expect(
      workflow,
      contains(r'''QA_SCREENSHOT_DIR="$EVIDENCE_ROOT/screenshots"'''),
    );
    expect(workflow, isNot(contains("find . -type f -name 'm33-*.png'")));
    expect(workflow, contains(r'''find "$EVIDENCE_ROOT/screenshots"'''));
  });

  test('AVD hard-error and forbidden-entry scans fail closed', () {
    expect(
      workflow,
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
      expect(workflow, contains(marker), reason: 'missing $marker scan');
    }
    for (final String forbidden in <String>['会员', 'VIP', '礼物背包', '背包']) {
      expect(workflow, contains(forbidden), reason: 'missing $forbidden gate');
    }
  });

  test(
    'mobile secret scan cannot be bypassed by a missing platform directory',
    () {
      expect(workflow, contains('secret_roots=(lib android)'));
      expect(workflow, contains('[[ -d ios ]] && secret_roots+=(ios)'));
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
