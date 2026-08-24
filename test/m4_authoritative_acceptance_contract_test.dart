import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File aggregateScript = File(
    'tool/qa/aggregate_m4_authoritative_live_avd.sh',
  ).absolute;
  final String integrationSource = File(
    'integration_test/m4_first_party_live_integration_test.dart',
  ).readAsStringSync();
  const String flutterSha = '1111111111111111111111111111111111111111';
  const String backendSha = '2222222222222222222222222222222222222222';

  Directory makeEvidence({
    String? avdBFlutterSha,
    bool dbEvidence = true,
    bool providerCall = false,
    bool avdBPass = true,
    bool invalidAvdBRouteStatus = false,
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
      final bool pass = avd != 'AVD-B' || avdBPass;
      final String routeStatus = avd == 'AVD-B' && invalidAvdBRouteStatus
          ? '500'
          : '200';
      File('${dir.path}/result.txt').writeAsStringSync(
        [
          'result=${pass ? 'PASS' : 'FAIL'}',
          'acceptance_status=${pass ? 'PASS' : 'FAIL'}',
          'run_id=m4-test-run',
          'tested_git_sha=$testedSha',
          'flutter_sha=$testedSha',
          'backend_sha=$backendSha',
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
            'writeCounters': <String, Object?>{'auth_session': 1},
            'authorityInvariants': <String, Object?>{
              'session_owner_matches_account': true,
            },
            'providerCalls': 0,
            'secrets': false,
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
    },
  );

  test('live integration cannot emit an unconditional PASS', () {
    expect(integrationSource, contains('M4_EXPECTED_FLUTTER_SHA'));
    expect(integrationSource, contains('M4_EXPECTED_BACKEND_SHA'));
    expect(integrationSource, contains("'acceptance': pass ? 'PASS' : 'FAIL'"));
    expect(integrationSource, contains('if (!pass)'));
    expect(integrationSource, contains("state: 'composite_success'"));
    expect(integrationSource, isNot(contains("'result': 'PASS',")));
  });

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
}
