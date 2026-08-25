import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File aggregateScript = File(
    'tool/qa/aggregate_m4_authoritative_live_avd.sh',
  ).absolute;
  final File dbEvidenceHelper = File(
    'tool/qa/m4_db_evidence_server.py',
  ).absolute;
  final String runnerSource = File(
    'tool/qa/run_m4_authoritative_live_avd.sh',
  ).readAsStringSync();
  final String acceptanceDocSource = File(
    'docs/qa/m4-authoritative-live-avd-acceptance.md',
  ).readAsStringSync();
  final String integrationSource = File(
    'integration_test/m4_first_party_live_integration_test.dart',
  ).readAsStringSync();
  final String registrationSource = File(
    'lib/features/account/presentation/registration_page.dart',
  ).readAsStringSync();
  const String flutterSha = '1111111111111111111111111111111111111111';
  const String backendSha = '2222222222222222222222222222222222222222';
  const String androidHostSha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  String runnerBlock(String startMarker, String endMarker) {
    final int start = runnerSource.indexOf(startMarker);
    final int end = runnerSource.indexOf(endMarker, start);
    if (start < 0 || end <= start) {
      throw StateError('runner block not found: $startMarker');
    }
    return runnerSource.substring(start, end);
  }

  ProcessResult runCheckoutGate(Directory repository) {
    final String script =
        '''
set -Eeuo pipefail
PROJECT_ROOT="\$M4_TEST_REPOSITORY"
OVERALL_RESULT=PASS
fail() {
  OVERALL_RESULT=FAIL
  return 64
}
${runnerBlock('assert_flutter_checkout_clean() {', '\ncleanup() {')}
assert_flutter_checkout_clean
''';
    return Process.runSync(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        ...Platform.environment,
        'M4_TEST_REPOSITORY': repository.path,
      },
    );
  }

  ProcessResult runArtifactRootGate(String artifactRoot) {
    final String script =
        '''
set -Eeuo pipefail
ARTIFACT_ROOT="\$M4_TEST_ARTIFACT_ROOT"
${runnerBlock('create_safe_artifact_root() {', '\nattest_flutter_sdk() {')}
create_safe_artifact_root
''';
    return Process.runSync(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        ...Platform.environment,
        'M4_TEST_ARTIFACT_ROOT': artifactRoot,
      },
    );
  }

  ProcessResult runAndroidHostGate({
    required Directory repository,
    required Directory fakeBin,
  }) {
    final String script =
        '''
set -Eeuo pipefail
PROJECT_ROOT="\$M4_TEST_REPOSITORY"
ANDROID_HOST_SOURCE_SHA256=''
FLUTTER_BIN="\$(command -v flutter)"
OVERALL_RESULT=PASS
fail() {
  OVERALL_RESULT=FAIL
  return 64
}
${runnerBlock('attest_android_host_source() {', '\ncleanup() {')}
attest_android_host_source
printf 'android_host_source_sha256=%s\n' "\$ANDROID_HOST_SOURCE_SHA256"
''';
    return Process.runSync(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
        'M4_TEST_REPOSITORY': repository.path,
      },
    );
  }

  ProcessResult runFlutterSdkGate({
    required Directory fakeBin,
    required String frameworkVersion,
    required String dartVersion,
    required String frameworkRevision,
  }) {
    final String script =
        '''
set -Eeuo pipefail
EXPECTED_FLUTTER_VERSION='3.44.7'
EXPECTED_DART_VERSION='3.12.2'
EXPECTED_FLUTTER_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
FLUTTER_BIN=''
FLUTTER_FRAMEWORK_VERSION=''
FLUTTER_DART_VERSION=''
FLUTTER_FRAMEWORK_REVISION=''
OVERALL_RESULT=PASS
fail() {
  OVERALL_RESULT=FAIL
  return 64
}
${runnerBlock('attest_flutter_sdk() {', '\nattest_android_host_source() {')}
attest_flutter_sdk
''';
    return Process.runSync(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        ...Platform.environment,
        'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
        'M4_FAKE_FRAMEWORK_VERSION': frameworkVersion,
        'M4_FAKE_DART_VERSION': dartVersion,
        'M4_FAKE_FRAMEWORK_REVISION': frameworkRevision,
      },
    );
  }

  ProcessResult runScanner({
    required String mode,
    required Directory projectRoot,
    required Directory target,
  }) {
    final String script =
        '''
set -Eeuo pipefail
IFS=\$'\\n\\t'
LIVE_PHONE="\$M4_TEST_LIVE_PHONE"
OAUTH_CLIENT_ID="\$M4_TEST_OAUTH_CLIENT_ID"
DB_TOKEN="\$M4_TEST_DB_TOKEN"
RELAY_TOKEN_A="\$M4_TEST_RELAY_TOKEN_A"
RELAY_TOKEN_B="\$M4_TEST_RELAY_TOKEN_B"
PROJECT_ROOT="\$M4_TEST_PROJECT_ROOT"
${runnerBlock('contains_literal_file() {', '\nrun_one() {')}
set +e
if [[ "\$M4_TEST_SCAN_MODE" == secret ]]; then
  secret_scan "\$M4_TEST_TARGET"
else
  apk_scan "\$M4_TEST_TARGET"
fi
status=\$?
printf 'scanner_exit=%s\\n' "\$status"
exit "\$status"
''';
    return Process.runSync(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        ...Platform.environment,
        'M4_TEST_SCAN_MODE': mode,
        'M4_TEST_PROJECT_ROOT': projectRoot.path,
        'M4_TEST_TARGET': target.path,
        'M4_TEST_LIVE_PHONE': '13800138000',
        'M4_TEST_OAUTH_CLIENT_ID': 'oauth-contract-test',
        'M4_TEST_DB_TOKEN': 'db-contract-test',
        'M4_TEST_RELAY_TOKEN_A': 'relay-contract-a',
        'M4_TEST_RELAY_TOKEN_B': 'relay-contract-b',
      },
    );
  }

  Directory makeEvidence({
    String? avdBFlutterSha,
    String? avdBAndroidHostSha,
    bool dbEvidence = true,
    bool providerCall = false,
    bool avdBPass = true,
    bool invalidAvdBRouteStatus = false,
    bool zeroWriteDelta = false,
    bool staleDbBinding = false,
    bool extraMutationKey = false,
    bool missingMutationKey = false,
    String flutterVersion = '3.44.7',
    String fixtureId = 'm4-fresh-test-fixture',
    String fixtureStatus = 'fresh_dedicated',
  }) {
    final Directory root = Directory.systemTemp.createTempSync(
      'm4-aggregate-contract-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    for (final String avd in <String>['AVD-A', 'AVD-B']) {
      final Directory dir = Directory('${root.path}/$avd')..createSync();
      Directory('${dir.path}/logs').createSync();
      File('${dir.path}/http-route-coverage.csv').writeAsStringSync(
        'capability,method,route,status,state\nrequired,GET,/health,200,success\n',
      );
      File('${dir.path}/authority-invariants.txt').writeAsStringSync(
        'session_owner_matches_account\nroom_exit_compensates_enter\n',
      );
      File(
        '${dir.path}/db-write-counters.txt',
      ).writeAsStringSync('source=operator_redacted_db_evidence\n');
      File('${dir.path}/logs/flutter-errors.txt').writeAsStringSync('');
      File('${dir.path}/logs/crash-anr.txt').writeAsStringSync('');
      File('${dir.path}/secret-scan.txt').writeAsStringSync('secret_scan=0\n');
      File(
        '${dir.path}/apk-secret-scan.txt',
      ).writeAsStringSync('apk_secret_scan=0\n');
      final String testedSha = avd == 'AVD-B' && avdBFlutterSha != null
          ? avdBFlutterSha
          : flutterSha;
      final String testedAndroidHostSha =
          avd == 'AVD-B' && avdBAndroidHostSha != null
          ? avdBAndroidHostSha
          : androidHostSha;
      final bool pass = avd != 'AVD-B' || avdBPass;
      final String routeStatus = avd == 'AVD-B' && invalidAvdBRouteStatus
          ? '500'
          : '200';
      final String dbStartNonce = avd == 'AVD-B' && staleDbBinding
          ? 'm4-stale-nonce-000000000000'
          : 'm4-start-nonce-000000000000';
      final String bindingRunId = avd == 'AVD-B' && staleDbBinding
          ? 'm4-old-run'
          : 'm4-test-run';
      final String bindingAvd = avd == 'AVD-B' && staleDbBinding
          ? 'AVD-A'
          : avd;
      final List<String> mutationKeys = <String>[
        'auth_sessions',
        'room_activity',
        'commerce_activity',
        'social_community_messages',
        'social_user_reports',
        'idempotency_audit',
      ];
      if (extraMutationKey) {
        mutationKeys.add('unexpected_mutation');
      }
      if (missingMutationKey) {
        mutationKeys.removeLast();
      }
      final Map<String, Object?> writeCounters = <String, Object?>{
        'auth_sessions': zeroWriteDelta ? 0 : 1,
        'room_activity': 0,
        'commerce_activity': 0,
        'social_community_messages': 0,
        'social_user_reports': zeroWriteDelta ? 0 : 1,
        'idempotency_audit': 0,
      };
      final Map<String, Object?> scopedCounters = <String, Object?>{
        'refresh_session_user': zeroWriteDelta ? 0 : 1,
        'user_report_reporter': zeroWriteDelta ? 0 : 1,
        'operation_idempotency_actor': zeroWriteDelta ? 0 : 1,
      };
      if (extraMutationKey) {
        writeCounters['unexpected_mutation'] = 1;
      }
      if (missingMutationKey) {
        writeCounters.remove('idempotency_audit');
      }
      File('${dir.path}/result.txt').writeAsStringSync(
        [
          'result=${pass ? 'PASS' : 'FAIL'}',
          'acceptance_status=${pass ? 'PASS' : 'FAIL'}',
          'run_id=m4-test-run',
          'fixture_id=$fixtureId',
          'fixture_status=$fixtureStatus',
          'db_start_nonce=$dbStartNonce',
          'tested_git_sha=$testedSha',
          'flutter_sha=$testedSha',
          'backend_sha=$backendSha',
          'android_host_source_sha256=$testedAndroidHostSha',
          'flutter_version=$flutterVersion',
          'dart_version=3.12.2',
          'flutter_revision=84fc5cbb223bc12f83d65b647ff8a56caf779ffd',
          'http_route_marker_count=12',
          'authority_invariant_count=6',
          'screenshot_count=4',
          'hard_finding_count=0',
          'crash_anr_count=0',
          'provider_calls_made=${providerCall ? 'true' : 'false'}',
          'db_evidence=${dbEvidence ? 'COLLECTED' : 'NOT_CONFIGURED'}',
          'secret_scan=PASS',
          'apk_secret_scan=PASS',
          '',
        ].join('\n'),
      );
      File('${dir.path}/logs/flutter-drive.log').writeAsStringSync(
        [
          '${avd == 'AVD-B' ? 'flutter: ' : ''}M4_ROUTE_STATUS::required::GET::/health::$routeStatus::success',
          '${avd == 'AVD-B' ? 'flutter: ' : ''}M4_AUTHORITY_INVARIANT::session_owner_matches_account',
          '${avd == 'AVD-B' ? 'flutter: ' : ''}M4_AUTHORITY_INVARIANT::room_exit_compensates_enter',
          '${avd == 'AVD-B' ? 'flutter: ' : ''}M4_PROVIDER_CALLS::${providerCall ? '1' : '0'}',
          '${avd == 'AVD-B' ? 'flutter: ' : ''}M4_ACCEPTANCE::${pass ? 'PASS' : 'FAIL'}',
          '',
        ].join('\n'),
      );
      if (dbEvidence) {
        File('${dir.path}/db-evidence.json').writeAsStringSync(
          jsonEncode(<String, Object?>{
            'status': 'OK',
            'writeCounters': writeCounters,
            'scopedCounters': scopedCounters,
            'authorityInvariants': <String, Object?>{
              'core_schema_present': true,
              'provider_outbox_allowed_states': true,
              'provider_outbox_attempts_zero': true,
              'private_message_delivery_blocked': true,
              'adapter_status_projection_blocked': true,
              'backend_environment_development': true,
              'backend_profile_development': true,
              'development_outbox_or_blocked_sms': true,
              'formal_vendor_adapters_blocked': true,
              'provider_invocation_rows_zero': true,
              'first_party_writes_observed_since_start': !zeroWriteDelta,
              'expected_backend_sha_matches': true,
            },
            'providerCalls': 0,
            'secrets': false,
            'evidenceBinding': <String, Object?>{
              'runId': bindingRunId,
              'avd': bindingAvd,
              'startNonce': dbStartNonce,
              'fixtureId': fixtureId,
              'fixtureAccountState': avd == 'AVD-A'
                  ? 'created_during_run'
                  : 'preexisting_fixture',
              'mutationKeys': mutationKeys,
            },
          }),
        );
      }
    }
    return root;
  }

  ProcessResult runAggregate(Directory root) => Process.runSync(
    '/bin/bash',
    <String>[aggregateScript.path],
    environment: <String, String>{
      ...Platform.environment,
      'QA_ARTIFACT_ROOT': root.path,
      'QA_FLUTTER_SHA': flutterSha,
      'QA_BACKEND_SHA': backendSha,
      'QA_RUN_ID': 'm4-test-run',
      'QA_M4_FIXTURE_ID': 'm4-fresh-test-fixture',
      'QA_M4_FIXTURE_STATUS': 'fresh_dedicated',
    },
  );

  test('live integration cannot emit an unconditional PASS', () {
    expect(integrationSource, contains('M4_EXPECTED_FLUTTER_SHA'));
    expect(integrationSource, contains('M4_EXPECTED_BACKEND_SHA'));
    expect(integrationSource, contains("'acceptance': pass ? 'PASS' : 'FAIL'"));
    expect(integrationSource, contains('if (!pass)'));
    expect(integrationSource, contains("state: 'composite_success'"));
    expect(integrationSource, isNot(contains("'result': 'PASS',")));
    expect(integrationSource, contains('QA_M4_FIXTURE_ID'));
    expect(integrationSource, contains('sha256.convert'));
    expect(integrationSource, contains('m4-runtime-relay-token'));
    expect(integrationSource, contains('HttpHeaders.authorizationHeader'));
    expect(
      integrationSource,
      contains("', detail=\$preflightDetail'"),
      reason: 'live gate failures must retain their user-visible diagnosis',
    );
  });

  test('cold-start emulator discovery restores adb whitespace parsing', () {
    expect(runnerSource, contains("while IFS=\$' \\t' read -r serial _state"));
    expect(runnerSource, isNot(contains('while read -r serial _state; do')));
  });

  test('runner binds a clean Flutter checkout before generated outputs', () {
    expect(runnerSource, contains('assert_flutter_checkout_clean()'));
    expect(runnerSource, contains('--untracked-files=all'));
    expect(
      runnerSource,
      contains(
        'Generated outputs therefore cannot turn a clean checkout dirty',
      ),
    );

    final Directory repository = Directory.systemTemp.createTempSync(
      'm4-checkout-contract-',
    );
    addTearDown(() => repository.deleteSync(recursive: true));
    File(
      '${repository.path}/.gitignore',
    ).writeAsStringSync('build/\n.dart_tool/\n');
    final File pubspec = File('${repository.path}/pubspec.yaml')
      ..writeAsStringSync('name: checkout_fixture\n');
    void gitOk(List<String> arguments) {
      final ProcessResult result = Process.runSync('git', <String>[
        '-C',
        repository.path,
        ...arguments,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }

    gitOk(<String>['init', '--quiet']);
    gitOk(<String>['config', 'user.email', 'm4-contract@example.invalid']);
    gitOk(<String>['config', 'user.name', 'M4 Contract']);
    gitOk(<String>['add', '.']);
    gitOk(<String>['commit', '--quiet', '-m', 'baseline']);
    expect(runCheckoutGate(repository).exitCode, 0);

    Directory('${repository.path}/build').createSync(recursive: true);
    File('${repository.path}/build/generated.apk').writeAsStringSync('ignored');
    expect(
      runCheckoutGate(repository).exitCode,
      0,
      reason:
          'normal ignored Flutter build output must not invalidate the pre-run binding',
    );

    pubspec.writeAsStringSync('name: checkout_fixture_dirty\n');
    expect(runCheckoutGate(repository).exitCode, isNot(0));
    pubspec.writeAsStringSync('name: checkout_fixture\n');
    File(
      '${repository.path}/untracked_source.dart',
    ).writeAsStringSync('void main() {}\n');
    expect(runCheckoutGate(repository).exitCode, isNot(0));
  });

  test('artifact root is new, absolute, and has no symlinked parent', () {
    expect(runnerSource, contains('create_safe_artifact_root()'));
    expect(runnerSource, contains('os.path.lexists(raw)'));
    expect(runnerSource, contains('stat.S_ISLNK'));
    expect(runnerSource, contains('publish_scan_output()'));
    expect(runnerSource, contains('os.replace(temporary, final)'));
    expect(runnerSource, contains('local incoming_status=\$?'));
    expect(runnerSource, contains('trap - EXIT'));
    expect(runnerSource, contains('exit "\$incoming_status"'));
    expect(
      runnerSource,
      isNot(contains('>"\$MANIFEST_FILE" 2>/dev/null || true')),
    );

    final Directory fixture = Directory.systemTemp.createTempSync(
      'm4-artifact-root-contract-',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final String fixturePath = fixture.resolveSymbolicLinksSync();
    final String safeRoot = '$fixturePath/safe/nested/evidence';
    expect(runArtifactRootGate(safeRoot).exitCode, 0);
    expect(Directory(safeRoot).existsSync(), isTrue);
    expect(runArtifactRootGate(safeRoot).exitCode, isNot(0));

    final Directory outside = Directory('$fixturePath/outside')..createSync();
    final Link linkedParent = Link('$fixturePath/linked-parent')
      ..createSync(outside.path);
    final String escapedRoot = '${linkedParent.path}/evidence';
    expect(runArtifactRootGate(escapedRoot).exitCode, isNot(0));
    expect(Directory('${outside.path}/evidence').existsSync(), isFalse);
  });

  test('ignored Android host inputs are bound to the selected Flutter SDK', () {
    expect(runnerSource, contains('attest_android_host_source()'));
    expect(runnerSource, contains('--platforms=android'));
    expect(runnerSource, contains('Android host does not match'));
    expect(runnerSource, contains('GeneratedPluginRegistrant.java'));
    expect(runnerSource, contains('android_host_source_sha256'));
    expect(runnerSource, contains("EXPECTED_FLUTTER_VERSION='3.44.7'"));
    expect(runnerSource, contains("EXPECTED_DART_VERSION='3.12.2'"));
    expect(runnerSource, contains('--android-language=kotlin'));
    expect(runnerSource, contains('"\$FLUTTER_BIN" clean'));
    expect(runnerSource, contains('pub get --enforce-lockfile'));
    expect(runnerSource, contains('"\$FLUTTER_BIN" drive'));
    expect(runnerSource, isNot(contains('\n      flutter drive')));
    expect(
      runnerSource.lastIndexOf('\nattest_flutter_sdk\n'),
      lessThan(runnerSource.lastIndexOf('\nstart_relay\n')),
    );

    final Directory fixture = Directory.systemTemp.createTempSync(
      'm4-android-host-contract-',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    final Directory repository = Directory('${fixture.path}/repository')
      ..createSync(recursive: true);
    final Directory android = Directory('${repository.path}/android/app')
      ..createSync(recursive: true);
    File('${android.path}/build.gradle.kts').writeAsStringSync('baseline\n');
    File(
      '${repository.path}/android/local.properties',
    ).writeAsStringSync('stale=true\n');
    final Directory registrantDirectory = Directory(
      '${repository.path}/android/app/src/main/java/io/flutter/plugins',
    )..createSync(recursive: true);
    final File registrant = File(
      '${registrantDirectory.path}/GeneratedPluginRegistrant.java',
    )..writeAsStringSync('generated\n');
    Directory(
      '${repository.path}/android/.gradle/cache',
    ).createSync(recursive: true);
    File(
      '${repository.path}/android/.gradle/cache/output.bin',
    ).writeAsStringSync('cache\n');

    final Directory fakeBin = Directory('${fixture.path}/bin')
      ..createSync(recursive: true);
    final File fakeFlutter = File('${fakeBin.path}/flutter')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '--version' ]]; then
  printf '{"frameworkVersion":"%s","dartSdkVersion":"%s","frameworkRevision":"%s"}\n' \
    "${M4_FAKE_FRAMEWORK_VERSION:-3.44.7}" \
    "${M4_FAKE_DART_VERSION:-3.12.2}" \
    "${M4_FAKE_FRAMEWORK_REVISION:-84fc5cbb223bc12f83d65b647ff8a56caf779ffd}"
  exit 0
fi
target="${@: -1}"
mkdir -p "$target/android/app"
printf 'baseline\n' >"$target/android/app/build.gradle.kts"
printf 'sdk.dir=/development/android\nflutter.sdk=/development/flutter\n' >"$target/android/local.properties"
''');
    expect(
      Process.runSync('chmod', <String>['700', fakeFlutter.path]).exitCode,
      0,
    );

    expect(
      runFlutterSdkGate(
        fakeBin: fakeBin,
        frameworkVersion: '3.44.7',
        dartVersion: '3.12.2',
        frameworkRevision: '84fc5cbb223bc12f83d65b647ff8a56caf779ffd',
      ).exitCode,
      0,
    );
    expect(
      runFlutterSdkGate(
        fakeBin: fakeBin,
        frameworkVersion: '3.44.8',
        dartVersion: '3.12.2',
        frameworkRevision: '84fc5cbb223bc12f83d65b647ff8a56caf779ffd',
      ).exitCode,
      isNot(0),
    );
    expect(
      runFlutterSdkGate(
        fakeBin: fakeBin,
        frameworkVersion: '3.44.7',
        dartVersion: '3.12.2',
        frameworkRevision: 'ffffffffffffffffffffffffffffffffffffffff',
      ).exitCode,
      isNot(0),
    );

    final ProcessResult clean = runAndroidHostGate(
      repository: repository,
      fakeBin: fakeBin,
    );
    expect(clean.exitCode, 0, reason: '${clean.stdout}\n${clean.stderr}');
    expect(
      clean.stdout,
      matches(RegExp(r'android_host_source_sha256=[0-9a-f]{64}')),
    );
    expect(registrant.existsSync(), isFalse);
    expect(
      File('${repository.path}/android/local.properties').readAsStringSync(),
      contains('flutter.sdk=/development/flutter'),
    );

    File('${android.path}/build.gradle.kts').writeAsStringSync('tampered\n');
    final ProcessResult tampered = runAndroidHostGate(
      repository: repository,
      fakeBin: fakeBin,
    );
    expect(tampered.exitCode, isNot(0));

    File('${android.path}/build.gradle.kts').writeAsStringSync('baseline\n');
    File('${android.path}/unexpected.gradle.kts').writeAsStringSync('extra\n');
    final ProcessResult extraInput = runAndroidHostGate(
      repository: repository,
      fakeBin: fakeBin,
    );
    expect(extraInput.exitCode, isNot(0));
  });

  test(
    'secret and APK scanners fail closed on unreadable and corrupt inputs',
    () {
      expect(runnerSource, contains('scanner_error=unreadable_artifact'));
      expect(runnerSource, contains('scanner_error=corrupt_or_unreadable_apk'));
      expect(runnerSource, contains('unzip -t'));
      expect(
        runnerSource,
        contains("IFS=' ' read -r unzip_status grep_status"),
      );
      expect(runnerSource, contains('mktemp "\$dir/.m4-secret-scan-files.'));
      expect(runnerSource, contains('mktemp "\$dir/.m4-apk-scan-files.'));
      expect(runnerSource, isNot(contains('\$output.files.\$\$')));
      expect(runnerSource, isNot(contains('done < <(find')));
      expect(
        runnerSource,
        isNot(contains('contains_literal_stream "\$LIVE_PHONE" &&')),
      );

      final Directory fixture = Directory.systemTemp.createTempSync(
        'm4-scanner-contract-',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));
      final Directory evidence = Directory('${fixture.path}/evidence')
        ..createSync(recursive: true);
      final File unreadable = File('${evidence.path}/unreadable.log')
        ..writeAsStringSync('not readable by the scanner\n');
      final ProcessResult chmodResult = Process.runSync('chmod', <String>[
        '000',
        unreadable.path,
      ]);
      expect(chmodResult.exitCode, 0);
      try {
        final ProcessResult result = runScanner(
          mode: 'secret',
          projectRoot: fixture,
          target: evidence,
        );
        expect(
          result.exitCode,
          isNot(0),
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          File('${evidence.path}/secret-scan.txt').readAsStringSync(),
          contains('scanner_error=unreadable_artifact'),
        );
      } finally {
        Process.runSync('chmod', <String>['600', unreadable.path]);
      }

      final Link linkedArtifact = Link('${evidence.path}/linked.log')
        ..createSync(unreadable.path);
      final ProcessResult linkedResult = runScanner(
        mode: 'secret',
        projectRoot: fixture,
        target: evidence,
      );
      expect(linkedResult.exitCode, isNot(0));
      expect(
        File('${evidence.path}/secret-scan.txt').readAsStringSync(),
        contains('scanner_error=non_regular_artifact_node'),
      );
      linkedArtifact.deleteSync();

      final File protectedName = File('${evidence.path}/trace-13800138000.log')
        ..writeAsStringSync('safe content\n');
      final ProcessResult protectedNameResult = runScanner(
        mode: 'secret',
        projectRoot: fixture,
        target: evidence,
      );
      expect(protectedNameResult.exitCode, isNot(0));
      expect(
        File('${evidence.path}/secret-scan.txt').readAsStringSync(),
        contains('forbidden_artifact_path_value=true'),
      );
      protectedName.deleteSync();

      final File secretOutput = File('${evidence.path}/secret-scan.txt');
      if (secretOutput.existsSync()) {
        secretOutput.deleteSync();
      }
      final File outside = File('${fixture.path}/outside-sentinel.txt')
        ..writeAsStringSync('unchanged\n');
      Link(secretOutput.path).createSync(outside.path);
      final ProcessResult outputLinkResult = runScanner(
        mode: 'secret',
        projectRoot: fixture,
        target: evidence,
      );
      expect(outputLinkResult.exitCode, isNot(0));
      expect(outside.readAsStringSync(), 'unchanged\n');
      expect(secretOutput.statSync().type, FileSystemEntityType.file);
      secretOutput.deleteSync();

      final File androidNumericLog =
          File('${evidence.path}/android-numeric.log')..writeAsStringSync(
            'iccId=89860313999999999897 timestamp=313999999999\n',
          );
      final ProcessResult androidNumericResult = runScanner(
        mode: 'secret',
        projectRoot: fixture,
        target: evidence,
      );
      expect(
        androidNumericResult.exitCode,
        0,
        reason:
            '${androidNumericResult.stdout}\n${androidNumericResult.stderr}',
      );
      androidNumericLog.writeAsStringSync('phone=13999999999\n');
      final ProcessResult standalonePhoneResult = runScanner(
        mode: 'secret',
        projectRoot: fixture,
        target: evidence,
      );
      expect(standalonePhoneResult.exitCode, isNot(0));
      expect(
        File('${evidence.path}/secret-scan.txt').readAsStringSync(),
        contains('credential_like_value_found=true'),
      );
      androidNumericLog.deleteSync();

      final Directory apkOutput = Directory(
        '${fixture.path}/build/app/outputs/flutter-apk',
      )..createSync(recursive: true);
      File(
        '${apkOutput.path}/corrupt.apk',
      ).writeAsStringSync('this is not a zip archive\n');
      final ProcessResult apkResult = runScanner(
        mode: 'apk',
        projectRoot: fixture,
        target: evidence,
      );
      expect(
        apkResult.exitCode,
        isNot(0),
        reason: '${apkResult.stdout}\n${apkResult.stderr}',
      );
      expect(
        File('${evidence.path}/apk-secret-scan.txt').readAsStringSync(),
        contains('scanner_error=corrupt_or_unreadable_apk'),
      );
      File('${apkOutput.path}/corrupt.apk').deleteSync();

      final File validApk = File('${apkOutput.path}/valid.apk');
      void writeZip(String content) {
        final ProcessResult result = Process.runSync('python3', <String>[
          '-c',
          'import sys, zipfile; '
              'archive=zipfile.ZipFile(sys.argv[1], "w"); '
              'archive.writestr("assets/payload.txt", sys.argv[2]); '
              'archive.close()',
          validApk.path,
          content,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }

      writeZip('safe APK content');
      final ProcessResult validApkResult = runScanner(
        mode: 'apk',
        projectRoot: fixture,
        target: evidence,
      );
      expect(
        validApkResult.exitCode,
        0,
        reason: '${validApkResult.stdout}\n${validApkResult.stderr}',
      );

      writeZip('embedded 13800138000 protected value');
      final ProcessResult taintedApkResult = runScanner(
        mode: 'apk',
        projectRoot: fixture,
        target: evidence,
      );
      expect(taintedApkResult.exitCode, isNot(0));
      expect(
        File('${evidence.path}/apk-secret-scan.txt').readAsStringSync(),
        contains('apk_secret_value_found=true'),
      );
    },
  );

  test(
    'runner requires a fresh dedicated fixture and bounds same-phone cooldown',
    () {
      expect(runnerSource, contains('QA_M4_FIXTURE_ID'));
      expect(runnerSource, contains('QA_M4_FIXTURE_STATUS'));
      expect(runnerSource, contains('fresh_dedicated'));
      expect(runnerSource, contains('SMS_COOLDOWN_SECONDS'));
      expect(runnerSource, contains('wait_for_sms_cooldown'));
      expect(runnerSource, contains('sleep "\$nap"'));
      expect(runnerSource, isNot(contains('sleep 65')));
      expect(runnerSource, contains('feed_runtime_relay_token'));
      expect(runnerSource, contains('run-as "\$APP_PACKAGE"'));
      expect(
        runnerSource,
        contains('run-as "\$APP_PACKAGE" tee "\$RUNTIME_TOKEN_TMP_FILE"'),
      );
      expect(
        runnerSource,
        contains('run-as "\$APP_PACKAGE" chmod 600 "\$RUNTIME_TOKEN_TMP_FILE"'),
      );
      expect(
        runnerSource,
        contains(
          'run-as "\$APP_PACKAGE" mv "\$RUNTIME_TOKEN_TMP_FILE" "\$RUNTIME_TOKEN_FILE"',
        ),
      );
      expect(
        RegExp(
          r'"\$RUNTIME_TOKEN_FILE" "\$RUNTIME_TOKEN_TMP_FILE"',
        ).allMatches(runnerSource).length,
        greaterThanOrEqualTo(2),
      );
      expect(runnerSource, isNot(contains('run-as "\$APP_PACKAGE" sh -c')));
      expect(runnerSource, contains('RELAY_TOKEN_A'));
      expect(runnerSource, contains('RELAY_TOKEN_B'));
      expect(runnerSource, contains('--dart-define=QA_M4_FIXTURE_ID'));
    },
  );

  test('fixture nickname fits the registration UI limit end to end', () {
    final String helperSource = dbEvidenceHelper.readAsStringSync();
    expect(registrationSource, contains('maxLength: 16'));
    expect(integrationSource, contains("RegExp(r'^m4-[0-9a-f]{13}\$')"));
    expect(integrationSource, contains('digest.substring(0, 13)'));
    expect(
      helperSource,
      contains('FIXTURE_NICKNAME_RE = re.compile(r"^m4-[0-9a-f]{13}\$")'),
    );
    expect(helperSource, contains('digest[:13]'));
    expect(acceptanceDocSource, contains('first-13-lowercase-hex-of-sha256'));
  });

  test(
    'bundled DB evidence helper is self-contained and passes its self-test',
    () {
      expect(dbEvidenceHelper.existsSync(), isTrue);
      final ProcessResult result = Process.runSync('python3', <String>[
        dbEvidenceHelper.path,
        '--self-test',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('self-test=PASS'));
      expect(runnerSource, contains('m4_db_evidence_server.py'));
      expect(runnerSource, contains('--self-test'));
    },
  );

  test('loopback DB evidence requests bypass host proxy configuration', () {
    expect(
      RegExp(
        r'urllib\.request\.ProxyHandler\(\{\}\)',
      ).allMatches(runnerSource).length,
      2,
    );
    expect(
      RegExp(
        r'with opener\.open\(request, timeout=20\) as response:',
      ).allMatches(runnerSource).length,
      2,
    );
    expect(
      runnerSource,
      isNot(contains('urllib.request.urlopen(request, timeout=20)')),
    );
  });

  test('DB evidence is bound to run, AVD, nonce, and fixed mutation keys', () {
    expect(runnerSource, contains('X-M4-Run-ID'));
    expect(runnerSource, contains('X-M4-AVD'));
    expect(runnerSource, contains('X-M4-Start-Nonce'));
    expect(runnerSource, contains('required_counter_keys'));
    expect(runnerSource, contains('social_user_reports'));
    expect(
      runnerSource,
      contains('payload["writeCounters"]["social_user_reports"] <= 0'),
    );
    expect(runnerSource, contains('mutationKeys'));
    expect(runnerSource, contains('evidenceBinding'));
    expect(runnerSource, contains('X-M4-Fixture-ID'));
    expect(runnerSource, contains('scopedCounters'));
    expect(runnerSource, contains('refresh_session_user'));
    expect(runnerSource, contains('expected_backend_sha_matches'));
    expect(
      dbEvidenceHelper.readAsStringSync(),
      contains('M4_FIXTURE_NICKNAME'),
    );
    expect(
      dbEvidenceHelper.readAsStringSync(),
      contains('m4_development_fixture_user'),
    );
    expect(
      dbEvidenceHelper.readAsStringSync(),
      contains('fixture-scoped mutation evidence'),
    );
  });

  test('backend source attestation is checkout and content bound', () {
    final String helperSource = dbEvidenceHelper.readAsStringSync();
    expect(helperSource, contains('QA_BACKEND_SHA'));
    expect(helperSource, contains('QA_BACKEND_REPO'));
    expect(
      helperSource,
      contains('scripts", "compute-backend-source-digest.sh'),
    );
    expect(helperSource, contains('/app/backend-source.sha256'));
    expect(helperSource, contains('git status'));
    expect(helperSource, contains('expected_backend_digest'));
    expect(
      helperSource,
      isNot(contains('for name in BACKEND_SHA QA_BACKEND_SHA BUILD_SHA')),
    );
    expect(helperSource, isNot(contains("printf 'S|%s\\n'")));
    expect(acceptanceDocSource, contains('ps -q backend'));
    expect(acceptanceDocSource, contains('ps -q mysql'));
    expect(
      acceptanceDocSource,
      isNot(contains('voice-social-backend-backend-1')),
    );
    expect(
      acceptanceDocSource,
      isNot(contains('voice-social-backend-mysql-1')),
    );
  });

  test('protected artifact values never become grep subprocess argv', () {
    for (final String protectedName in <String>[
      'LIVE_PHONE',
      'OAUTH_CLIENT_ID',
      'DB_TOKEN',
      'RELAY_TOKEN_A',
      'RELAY_TOKEN_B',
    ]) {
      expect(runnerSource, isNot(contains('grep -aFq "\$$protectedName"')));
    }
    expect(runnerSource, contains('grep -aFq -f <(printf'));
    expect(runnerSource, contains('contains_literal_file'));
    expect(runnerSource, contains('contains_literal_stream'));

    final ProcessResult behavior = Process.runSync('/bin/bash', <String>[
      '-c',
      r'''
set -euo pipefail
contains_literal_file() {
  local value="$1" path="$2"
  [[ -n "$value" ]] || return 1
  grep -aFq -f <(printf '%s' "$value") "$path" 2>/dev/null
}
contains_literal_stream() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  grep -aFq -f <(printf '%s' "$value") 2>/dev/null
}
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' 'safe prefix; $(touch should-not-run)' >"$tmp"
secret='prefix; $(touch should-not-run)'
contains_literal_file "$secret" "$tmp"
printf '%s\n' 'safe prefix; $(touch should-not-run)' | contains_literal_stream "$secret"
''',
    ]);
    expect(
      behavior.exitCode,
      0,
      reason: '${behavior.stdout}\n${behavior.stderr}',
    );
  });

  test('logcat capture is bounded and cannot block after Flutter exits', () {
    expect(runnerSource, contains('logcat -G 16M'));
    expect(runnerSource, contains('logcat -d -v threadtime'));
    expect(runnerSource, contains("reason='logcat_capture_failed'"));
    expect(runnerSource, isNot(contains('logcat -v threadtime | sanitize')));
    expect(runnerSource, isNot(contains('LOGCAT_PID')));
    expect(
      runnerSource,
      contains(
        'cat "\$dir/logs/logcat-full.txt" "\$dir/logs/flutter-drive.log" | grep -Eci',
      ),
    );
    expect(
      runnerSource,
      isNot(
        contains(
          'grep -Eci \'FATAL EXCEPTION|Fatal signal [0-9]+|ANR in com\\.kong373\\.voice_social_app\' "\$dir/logs/logcat-full.txt" "\$dir/logs/flutter-drive.log"',
        ),
      ),
    );
  });

  test(
    'live integration covers first-party mutations without vendor success',
    () {
      for (final String capability in <String>[
        'community.checkin',
        'community.task.claim',
        'room.moderation.mute',
        'room.seat.up',
        'room.pk.invite',
        'commerce.gift.send',
        'commerce.withdraw.apply',
        'commerce.refund.submit',
        'message.private.send',
        'message.notifications.clear',
      ]) {
        expect(integrationSource, contains(capability));
      }
      expect(integrationSource, contains('requireCapability'));
      expect(integrationSource, contains('already_authoritative'));
      expect(
        integrationSource,
        contains('pkRecoveryRoom: ownedModeRooms.approval'),
      );
      expect(
        integrationSource,
        contains('required DiscoveryRoom pkRecoveryRoom'),
      );
      expect(
        integrationSource,
        contains('dependencies.roomPkRepository.searchOpponents'),
      );
      expect(integrationSource, contains("capability: 'room.pk.search'"));
      expect(integrationSource, contains('keyword: pkRecoveryRoom.id'));
      expect(
        integrationSource,
        contains('item.roomId == pkRecoveryRoom.id && !item.isInPk'),
      );
      expect(
        integrationSource,
        contains('pk_recovery_targeted_search_uses_canonical_room_id'),
      );
      expect(integrationSource, contains('providerInvocation != false'));
      expect(integrationSource, contains('M4_PROVIDER_CALLS::0'));
      expect(
        integrationSource,
        isNot(contains('gift_send_and_payment_invocation_not_attempted')),
      );
      expect(
        integrationSource,
        isNot(contains('withdraw_and_refund_mutations_not_attempted')),
      );
    },
  );

  test('aggregate passes only with complete matching A/B evidence', () {
    final Directory root = makeEvidence();
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_PASS'),
    );
    final Map<String, Object?> verdict =
        jsonDecode(
              File('${root.path}/aggregate-verdict.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(verdict['tested_git_sha'], flutterSha);
    expect(verdict['backend_sha'], backendSha);
    expect(verdict['android_host_source_sha256'], androidHostSha);
    expect(verdict['flutter_version'], '3.44.7');
    expect(verdict['dart_version'], '3.12.2');
    expect(verdict['avd'], <String, String>{'AVD-A': 'PASS', 'AVD-B': 'PASS'});
  });

  test('aggregate rejects missing database evidence', () {
    final Directory root = makeEvidence(dbEvidence: false);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );
  });

  test('aggregate rejects a mismatched tested SHA', () {
    final Directory root = makeEvidence(
      avdBFlutterSha: '3333333333333333333333333333333333333333',
    );
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('AVD-B=FAIL'),
    );
  });

  test('aggregate rejects mismatched Android host source attestation', () {
    final Directory root = makeEvidence(
      avdBAndroidHostSha:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('android_host_source_attestation_mismatch'),
    );
  });

  test('aggregate rejects a non-frozen Flutter SDK', () {
    final Directory root = makeEvidence(flutterVersion: '3.44.8');
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('flutter_version_mismatch'),
    );
  });

  test('aggregate rejects nonzero provider calls', () {
    final Directory root = makeEvidence(providerCall: true);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('AVD-A=FAIL'),
    );
  });

  test('aggregate rejects an A/B partial failure', () {
    final Directory root = makeEvidence(avdBPass: false);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('AVD-B=FAIL'),
    );
  });

  test('aggregate rejects a prefixed non-success route status', () {
    final Directory root = makeEvidence(invalidAvdBRouteStatus: true);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('AVD-B=FAIL'),
    );
  });

  test('aggregate rejects database evidence without current-run writes', () {
    final Directory root = makeEvidence(zeroWriteDelta: true);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('ANDROID_EMULATOR_FAIL'),
    );
  });

  test('aggregate rejects stale or unrelated DB evidence binding', () {
    final Directory root = makeEvidence(staleDbBinding: true);
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('AVD-B=FAIL'),
    );
  });

  test('aggregate rejects missing or extra mutation keys', () {
    for (final Map<String, bool> option in <Map<String, bool>>[
      <String, bool>{'missingMutationKey': true},
      <String, bool>{'extraMutationKey': true},
    ]) {
      final Directory root = makeEvidence(
        missingMutationKey: option['missingMutationKey'] ?? false,
        extraMutationKey: option['extraMutationKey'] ?? false,
      );
      final ProcessResult result = runAggregate(root);
      expect(result.exitCode, isNot(0));
      expect(
        File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
        contains('ANDROID_EMULATOR_FAIL'),
      );
    }
  });

  test('aggregate rejects a legacy or non-fresh fixture attestation', () {
    final Directory root = makeEvidence(
      fixtureId: 'm4-fresh-test-fixture',
      fixtureStatus: 'legacy',
    );
    final ProcessResult result = runAggregate(root);
    expect(result.exitCode, isNot(0));
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('fixture_status_mismatch'),
    );
  });
}
