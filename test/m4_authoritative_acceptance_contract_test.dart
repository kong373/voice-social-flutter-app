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
  const String flutterSha = '1111111111111111111111111111111111111111';
  const String backendSha = '2222222222222222222222222222222222222222';

  Directory makeEvidence({
    String? avdBFlutterSha,
    bool dbEvidence = true,
    bool providerCall = false,
    bool avdBPass = true,
    bool invalidAvdBRouteStatus = false,
    bool zeroWriteDelta = false,
    bool staleDbBinding = false,
    bool extraMutationKey = false,
    bool missingMutationKey = false,
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
  });

  test('cold-start emulator discovery restores adb whitespace parsing', () {
    expect(runnerSource, contains("while IFS=\$' \\t' read -r serial _state"));
    expect(runnerSource, isNot(contains('while read -r serial _state; do')));
  });

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
      expect(runnerSource, contains('RELAY_TOKEN_A'));
      expect(runnerSource, contains('RELAY_TOKEN_B'));
      expect(runnerSource, contains('--dart-define=QA_M4_FIXTURE_ID'));
    },
  );

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
