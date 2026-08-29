import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/m5_vendor_live_integration_test.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  final File runner = File('tool/qa/run_m5_vendor_live_avd.sh').absolute;
  final File aggregate = File(
    'tool/qa/aggregate_m5_vendor_live_avd.sh',
  ).absolute;
  final File integration = File(
    'integration_test/m5_vendor_live_integration_test.dart',
  ).absolute;
  final File alipayBridge = File(
    'lib/features/commerce/infrastructure/alipay_app_pay_adapter.dart',
  ).absolute;
  final File alipayAndroidBridge = File(
    'packages/alipay_app_pay/android/src/main/kotlin/com/kong373/alipay_app_pay/AlipayAppPayPlugin.kt',
  ).absolute;
  final String runnerSource = runner.readAsStringSync();
  final String aggregateSource = aggregate.readAsStringSync();
  final String integrationSource = integration.readAsStringSync();
  final String alipayBridgeSource = alipayBridge.readAsStringSync();
  final String alipayAndroidBridgeSource = alipayAndroidBridge
      .readAsStringSync();

  Directory createM5TempRoot(String prefix) {
    // The runner intentionally rejects symlinked artifact ancestors. Resolve
    // macOS's `/var -> /private/var` before creating the child directory so
    // the test remains portable while satisfying that safety contract.
    final Directory parent = Directory(
      Directory.systemTemp.resolveSymbolicLinksSync(),
    );
    parent.createSync(recursive: true);
    final Directory root = parent.createTempSync(prefix);
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    return root;
  }

  test('M5 shell harnesses are syntactically valid', () {
    for (final File file in <File>[runner, aggregate]) {
      final ProcessResult result = Process.runSync('/bin/bash', <String>[
        '-n',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${file.path}: ${result.stderr}');
    }
  });

  test('M5 cold-start uses installed AVD names and serial overrides bypass it', () {
    expect(runnerSource, contains('-gpu swiftshader'));
    expect(runnerSource, isNot(contains('-gpu swiftshader_indirect')));
    expect(
      runnerSource,
      contains(r'select_device "$avd" "$api" "$override" "$avd_name" "$dir"'),
    );
    expect(
      runnerSource,
      contains(
        r'run_one AVD-A "$A_API" "$A_PROFILE" "$A_PHYSICAL" "$A_DENSITY" "$A_WIDTH" "$A_HEIGHT" "$A_DPR" "$AVD_A_SERIAL" "$AVD_A_NAME" &',
      ),
    );
    expect(
      runnerSource,
      contains(
        r'run_one AVD-B "$B_API" "$B_PROFILE" "$B_PHYSICAL" "$B_DENSITY" "$B_WIDTH" "$B_HEIGHT" "$B_DPR" "$AVD_B_SERIAL" "$AVD_B_NAME" &',
      ),
    );

    final String shellScript = r'''
set -euo pipefail
eval "$(sed -n '/^select_device() {/,/^}/p' "$M5_RUNNER")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
record="$root/started-name"

device_for_api() { return 1; }
wait_boot() { return 0; }
start_emulator() {
  printf '%s\n' "$2" >"$record"
  printf '%s\n' 'emulator-cold-start'
}

cold_serial="$(select_device AVD-B 35 '' voice_social_m4_avd_b_api35 "$root")"
[[ "$cold_serial" == 'emulator-cold-start' ]]
recorded_name="$(<"$record")"
[[ "$recorded_name" == 'voice_social_m4_avd_b_api35' ]]

start_emulator() { return 99; }
adb() {
  [[ "$1" == '-s' && "$2" == 'emulator-5554' ]]
  printf '%s\n' '36'
}
override_serial="$(select_device AVD-A 36 emulator-5554 ignored "$root")"
[[ "$override_serial" == 'emulator-5554' ]]
''';
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>['-c', shellScript],
      environment: <String, String>{
        ...Platform.environment,
        'M5_RUNNER': runner.path,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('M5 uses an independent positive provider-call namespace', () {
    expect(runnerSource, contains('M5_PROVIDER_CALLS::'));
    expect(aggregateSource, contains('M5_PROVIDER_CALLS::'));
    expect(integrationSource, contains('M5_PROVIDER_CALLS::'));
    expect(
      runnerSource,
      contains("LAST_RESULT_REASON='no_payment_provider_core_pass'"),
    );
    expect(
      runnerSource,
      contains("LAST_RESULT_REASON='no_payment_provider_core_incomplete'"),
    );
    expect(runnerSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(aggregateSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(integrationSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(aggregateSource, contains('[1-9][0-9]*::[1-9][0-9]*'));
    expect(integrationSource, contains('_tencentProviderCalls <= 0'));
    expect(integrationSource, contains('providerCallback'));
    expect(integrationSource, isNot(contains('providerCall(')));
    expect(integrationSource, contains('c2cHintMessageIdsSnapshot'));
    expect(integrationSource, contains("config.role == 'receiver'"));
    expect(integrationSource, contains('_viewportForRole'));
    expect(integrationSource, contains('/m5/c2c/identity'));
    expect(integrationSource, contains('/m5/c2c/peer'));
    expect(integrationSource, contains('firstPartyUserId'));
    expect(integrationSource, contains('_registerRelayFirstPartyUserId'));
    expect(integrationSource, contains('_pollRelayPeerUserId'));
    expect(
      integrationSource,
      contains('request.contentLength = encodedPayload.length'),
    );
    expect(integrationSource, contains('request.add(encodedPayload)'));
    expect(
      integrationSource,
      contains('tencent_c2c_draft_conversation_from_relay_peer_user_id'),
    );
    expect(integrationSource, contains('ConversationSummary.draft('));
    expect(integrationSource, contains('candidate.targetUserId == peerUserId'));
    expect(integrationSource, contains('/m5/c2c/receiver-ready'));
    expect(integrationSource, contains('hintVerifier.accepts'));
    expect(integrationSource, contains('roomLifecycleRepository'));
    expect(integrationSource, contains('saveRoom'));
    expect(integrationSource, contains('RoomAccessMode.publicRoom'));
    expect(integrationSource, contains('routes.createRoom'));
    expect(
      integrationSource,
      contains('candidate.title.trim() == fixtureTitle'),
    );
    expect(
      integrationSource,
      contains("state: saved.created ? 'created' : 'idempotent_reused'"),
    );
    expect(integrationSource, contains('saved.roomId.trim().isEmpty'));
    expect(integrationSource, contains('sendPublicMessage'));
    expect(integrationSource, contains('/m5/avchatroom/ready'));
    expect(integrationSource, contains('/m5/avchatroom/receiver-joined'));
    expect(integrationSource, contains('/m5/avchatroom/message-sent'));
    expect(integrationSource, contains('/m5/avchatroom/pass'));
    expect(integrationSource, contains('/m5/avchatroom/receiver-left'));
    expect(integrationSource, contains('ownerFixtureCleanupEligible'));
    expect(integrationSource, contains('current_fixture_closed'));
    expect(integrationSource, contains('fetchRoom(roomId)'));
    expect(integrationSource, contains('expectedVersion: owned.version'));
    expect(
      integrationSource,
      contains(
        "if (config.role == 'sender' &&\n        ownerFixtureCleanupEligible",
      ),
    );
    expect(
      integrationSource,
      contains('ownerFixtureCleanupEligible = createdFixture.room.id'),
    );
    expect(
      integrationSource,
      contains('tencent_avchatroom_receiver_left_confirmed'),
    );
    expect(integrationSource, contains('receiverSdkLeaveConfirmed'));
    expect(integrationSource, contains('receiverHttpExitConfirmed'));
    expect(integrationSource, contains('receiver_left_not_confirmed'));
    expect(
      integrationSource,
      contains('owned.accessMode == RoomAccessMode.publicRoom'),
    );
    expect(
      integrationSource,
      isNot(contains("title.startsWith('M5 live m5-')")),
    );
    final int cleanupFinally = integrationSource.indexOf(
      '  } finally {\n    final String? roomId = selectedRoomId;',
    );
    final int nextFunction = integrationSource.indexOf(
      '\nFuture<void> _runAlipaySandbox',
      cleanupFinally,
    );
    expect(cleanupFinally, greaterThanOrEqualTo(0));
    expect(nextFunction, greaterThan(cleanupFinally));
    expect(
      integrationSource.substring(cleanupFinally, nextFunction),
      isNot(contains('return;')),
    );
    expect(runnerSource, contains('receiverLeftRoomId'));
    expect(
      runnerSource,
      contains('self.path == "/m5/avchatroom/receiver-left"'),
    );
    expect(runnerSource, contains('details["role"] == "sender"'));
    expect(runnerSource, contains('details["role"] == "receiver"'));
    expect(runnerSource, contains('expected_room_id = coordination["roomId"]'));
    expect(runnerSource, contains('room_id != expected_room_id'));
    expect(
      runnerSource,
      contains('coordination["receiverLeftRoomId"] = room_id'),
    );
    expect(runnerSource, contains('room_id_mismatch'));
    expect(integrationSource, contains('hasRoomHintForMessage'));
    expect(integrationSource, contains('roomEvents'));
    expect(integrationSource, contains('roomHintFromSdk'));
    expect(
      integrationSource,
      contains('tencent_avchatroom_http_send_message_id'),
    );
    expect(
      integrationSource,
      contains('tencent_avchatroom_sdk_hint_http_refresh'),
    );
    expect(integrationSource, contains('_pollAvChatRoomReadiness'));
    expect(integrationSource, contains('maxAttempts = 75'));
    expect(integrationSource, contains('_workerCycleWaitAttempts = 1200'));
    expect(integrationSource, isNot(contains('readyBeforeEnter')));
    expect(
      integrationSource.indexOf(
        'final RoomSnapshot snapshot = await repository.enterRoom',
      ),
      lessThan(
        integrationSource.indexOf(
          'final TencentImAvChatRoomSession? readySession = roomSession',
        ),
      ),
    );
    expect(runnerSource, contains('receiverReady'));
    expect(runnerSource, contains('wait_for_sender_login_marker'));
    expect(
      runnerSource.indexOf(r'if wait_for_sender_login_marker "$pid_a"'),
      lessThan(
        runnerSource.indexOf(
          r'run_one AVD-B "$B_API" "$B_PROFILE" "$B_PHYSICAL"',
        ),
      ),
    );
    expect(runnerSource, contains('roomMessageId'));
    expect(runnerSource, contains('senderUserId'));
    expect(runnerSource, contains('receiverUserId'));
    expect(runnerSource, contains('/m5/c2c/identity'));
    expect(runnerSource, contains('/m5/c2c/peer'));
    expect(runnerSource, contains('invalid_first_party_user_id'));
    expect(runnerSource, contains('first_party_user_id_conflict'));
    expect(runnerSource, contains('self.headers.get_all("Content-Length")'));
    expect(runnerSource, contains('self.headers.get_all("Transfer-Encoding")'));
    expect(runnerSource, contains('targetUserId'));
    expect(runnerSource, contains('/m5/avchatroom/ready'));
    expect(runnerSource, contains('receiverJoinedRoomId'));
    expect(runnerSource, contains('run_or_role_mismatch'));
    expect(runnerSource, contains('/m5/avchatroom/message-sent'));
    expect(runnerSource, contains('/m5/avchatroom/pass'));
    expect(
      integrationSource,
      contains('tencent_c2c_receiver_sdk_hint_http_refresh'),
    );
    expect(integrationSource, contains('M5_ACCEPTANCE::\$verdict'));
    expect(integrationSource, contains('M5_RESILIENCE::'));
    expect(aggregateSource, contains('M5_SECRETS_IN_CLIENT::0'));
    expect(aggregateSource, contains('resilience_verdict'));
    expect(aggregateSource, contains('ANDROID_EMULATOR_NO_PAY'));
    expect(aggregateSource, contains('ANDROID_EMULATOR_PARTIAL'));
    expect(aggregateSource, contains("payment_mode='success'"));
    expect(runnerSource, contains('--use-application-binary='));
    expect(runnerSource, contains('install_attested_apk'));
    expect(runnerSource, contains('same immutable binary'));
    expect(
      runnerSource,
      contains('build/app/outputs/flutter-apk/app-debug.apk'),
    );
    expect(runnerSource, contains('QA_BACKEND_CONTAINER'));
    expect(runnerSource, contains('inspect --format'));
    expect(runnerSource, contains('/app/backend-source.sha256'));
    expect(runnerSource, contains('HostPort'));
    expect(runnerSource, contains('18080/tcp'));
    expect(runnerSource, contains('container is not healthy'));
    expect(runnerSource, contains('prepare_android_audio_manifest.py'));
    expect(runnerSource, contains('ls-files --error-unmatch'));
    expect(runnerSource, contains('voice-social-m5-android-host.XXXXXX'));
    expect(runnerSource, contains('--no-pub "\$generated_project"'));
    expect(runnerSource, isNot(contains('--no-pub "\$PROJECT_ROOT"')));
    expect(
      runnerSource,
      contains('mv "\$generated_project/android" "\$PROJECT_ROOT/android"'),
    );
    for (final String bindingField in <String>[
      'runId',
      'fixtureId',
      'avd',
      'startNonceSha256',
      'backendSha',
      'flutterSha',
      'apkSha',
      'backendSourceDigest',
    ]) {
      expect(runnerSource, contains(bindingField));
      expect(aggregateSource, contains(bindingField));
    }
    expect(runnerSource, isNot(contains("printf 'db_start_nonce=%s")));
    expect(runnerSource, contains('db_start_nonce_sha256'));
    expect(runnerSource, contains('b\'"startNonce":\''));
    expect(aggregateSource, isNot(contains('binding.get("startNonce")')));
  });

  test('C2C request id is run-scoped and retry-stable', () {
    expect(integrationSource, contains('String _m5C2cRequestId(String avd)'));
    expect(integrationSource, contains('_runId.isEmpty'));
    expect(integrationSource, contains('_fixturePattern.hasMatch(_fixtureId)'));
    expect(
      integrationSource,
      contains(r"'m5-c2c|run=$_runId|fixture=$_fixtureId|avd=$normalizedAvd'"),
    );
    expect(
      integrationSource,
      contains('sha256.convert(utf8.encode(identity)).toString()'),
    );
    expect(
      integrationSource,
      contains(r"final String requestId = 'm5-c2c-$digest';"),
    );
    expect(integrationSource, contains(r"RegExp(r'^[A-Za-z0-9._-]{1,80}$')"));
    expect(integrationSource, contains('requestId: _m5C2cRequestId(avd)'));
    expect(
      integrationSource,
      isNot(contains(r"'m5-${avd.toLowerCase()}-c2c'")),
    );
    expect(
      integrationSource,
      contains('const Duration _c2cHintWindow = Duration(seconds: 75);'),
    );
    expect(
      integrationSource,
      contains(
        'const Duration _c2cHistoryRefreshInterval = Duration(seconds: 1);',
      ),
    );
    expect(integrationSource, contains('M5C2cHintVerifier'));
    expect(integrationSource, contains('c2cHintMessageIdsSnapshot'));
    expect(
      integrationSource,
      contains('while (DateTime.now().isBefore(hintWindowDeadline))'),
    );
    expect(
      integrationSource,
      contains('hintVerifier.accepts(authoritativeHistory)'),
    );
    expect(
      integrationSource,
      contains('authoritativeHistory.length < history.length'),
    );
  });

  test(
    'C2C hint window ignores stale hint until the exact message arrives',
    () {
      final M5C2cHintVerifier verifier = M5C2cHintVerifier(
        senderUserId: 10002,
        expectedContent: 'M5 run current content',
      );
      final ChatMessage currentMessage = _m5Message(
        id: 'message-current',
        senderUserId: 10002,
        content: 'M5 run current content',
      );

      verifier.observeTrustedHint('message-stale');
      expect(verifier.accepts(<ChatMessage>[]), isFalse);
      expect(
        verifier.accepts(<ChatMessage>[currentMessage]),
        isFalse,
        reason: 'history alone must not pass without the exact trusted hint',
      );

      verifier.observeTrustedHint(currentMessage.id);
      expect(verifier.accepts(<ChatMessage>[currentMessage]), isTrue);
    },
  );

  test('C2C hint window remains blocked when only stale hints arrive', () {
    final M5C2cHintVerifier verifier = M5C2cHintVerifier(
      senderUserId: 10002,
      expectedContent: 'M5 run current content',
    );
    verifier.observeTrustedHint('message-stale');

    expect(
      verifier.accepts(<ChatMessage>[
        _m5Message(
          id: 'message-current',
          senderUserId: 10002,
          content: 'M5 run current content',
        ),
      ]),
      isFalse,
    );
    expect(verifier.hasObservedTrustedHints, isTrue);
  });

  test('default Alipay path has no financial side effect', () {
    expect(runnerSource, contains('M5_ALLOW_EXTERNAL_PAYMENT'));
    expect(
      runnerSource,
      contains('M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT'),
    );
    expect(integrationSource, contains('I_UNDERSTAND_SANDBOX_PAYMENT'));
    expect(
      runnerSource,
      contains(
        'ACTION_GATE_STATE_PARENT="\$(cd "\$requested_gate_parent" && pwd -P)"',
      ),
    );
    expect(runnerSource, contains('M5_SCAN_ACTION_OPERATOR'));
    expect(integrationSource, contains("defaultValue: 'none'"));
    expect(integrationSource, contains("'none',"));
    expect(integrationSource, contains("'cancel',"));
    expect(integrationSource, contains("'success',"));
    expect(integrationSource, contains('M5_SUCCESS_CONFIRMATION'));
    expect(integrationSource, contains('I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT'));
    final int optInGate = integrationSource.indexOf('if (!optedIn)');
    final int orderCreation = integrationSource.indexOf('createRechargeOrder(');
    final int nativeInvocation = integrationSource.indexOf(
      'invokePayment(order)',
    );
    expect(optInGate, greaterThanOrEqualTo(0));
    expect(orderCreation, greaterThan(optInGate));
    expect(nativeInvocation, greaterThan(orderCreation));
    expect(
      integrationSource,
      contains('item.enabled && (item.amountMinor ?? 0) > 0'),
    );
    expect(
      integrationSource,
      contains('(candidate.amountMinor ?? 0) < (current.amountMinor ?? 0)'),
    );
    expect(
      integrationSource.indexOf('alipay_positive_product_missing'),
      greaterThan(optInGate),
    );
    expect(
      integrationSource.indexOf('alipay_positive_product_missing'),
      lessThan(orderCreation),
    );
    expect(integrationSource, contains("'alipay.order', 'NOT_OPTED_IN'"));
    expect(
      integrationSource,
      contains("'alipay.native.launch-cancel', 'NOT_OPTED_IN'"),
    );
    expect(integrationSource, contains("'alipay.query-reconcile', 'NOT_RUN'"));
    expect(integrationSource, contains('routes.cancelAlipayRechargeOrder'));
    expect(
      integrationSource,
      contains('result.hasTrustedNativeCancellationEvidence'),
    );
    expect(integrationSource, contains("'vendor_blocked'"));
    expect(integrationSource, contains("'cancel_only'"));
    expect(integrationSource, contains("fullyPass ? 'PARTIAL'"));
    expect(
      RegExp(
        r"evidence\.lane\('alipay\.reconcile-idempotency', 'BLOCKED'\)",
      ).allMatches(integrationSource).length,
      1,
    );
    expect(aggregateSource, contains('payment_lane_not_explicitly_withheld'));
    expect(aggregateSource, contains('PAYMENT_CANCEL_ONLY'));
    expect(aggregateSource, contains('PAYMENT_SUCCESS'));
    expect(aggregateSource, contains('payment_success_proven'));
    expect(aggregateSource, contains('reconcile_repeat'));
    expect(aggregateSource, contains('ledgerEntryCount'));
    expect(aggregateSource, contains('ledgerEntryCount": 2'));
    expect(aggregateSource, contains('payment_lane_must_be_not_run'));
    expect(aggregateSource, contains('AVD-B is receiver-only'));
    expect(aggregateSource, contains('ANDROID_EMULATOR_PARTIAL'));
    expect(aggregateSource, contains('eventCount"] != 0'));
    for (final String paymentCounter in <String>[
      'payment_provider_events',
      'wallet_transactions',
      'ledger_journals',
      'ledger_entries',
    ]) {
      expect(runnerSource, contains(paymentCounter));
      expect(aggregateSource, contains(paymentCounter));
    }
    expect(runnerSource, contains('result_before_acceptance'));
    expect(runnerSource, contains('clear_test_app_data'));
    expect(
      runnerSource,
      contains('adb -s "\$serial" shell pm clear "\$APP_PACKAGE"'),
    );
    expect(
      runnerSource,
      contains('adb -s "\$serial" shell pm list packages "\$APP_PACKAGE"'),
    );
    expect(runnerSource, contains('grep -Fxq "package:\$APP_PACKAGE"'));
    expect(runnerSource, contains('[[ -z "\$package_query" ]]'));
    expect(runnerSource, contains('[[ "\$clear_output" == \'Success\' ]]'));
    expect(runnerSource, contains('app_data_clear_failed'));
    expect(runnerSource, isNot(contains('pm clear com.alipay')));
    final int selectedSerial = runnerSource.indexOf('serial="\$(select_device');
    final int clearedSerial = runnerSource.indexOf(
      'clear_test_app_data "\$serial"',
      selectedSerial,
    );
    final int packageQuery = runnerSource.indexOf(
      'pm list packages "\$APP_PACKAGE"',
    );
    final int exactPackageMatch = runnerSource.indexOf(
      'grep -Fxq "package:\$APP_PACKAGE"',
      packageQuery,
    );
    final int packageClear = runnerSource.indexOf(
      'pm clear "\$APP_PACKAGE"',
      exactPackageMatch,
    );
    final int driveStart = runnerSource.indexOf(
      'run_flutter_test "\$serial"',
      packageClear,
    );
    expect(selectedSerial, greaterThanOrEqualTo(0));
    expect(clearedSerial, greaterThan(selectedSerial));
    expect(packageQuery, greaterThanOrEqualTo(0));
    expect(exactPackageMatch, greaterThan(packageQuery));
    expect(packageClear, greaterThan(exactPackageMatch));
    expect(packageClear, lessThan(clearedSerial));
    expect(driveStart, greaterThan(packageClear));
    expect(runnerSource, contains('start_db_evidence_helper'));
    expect(
      runnerSource,
      contains(r'nonce="$(db_evidence_start "$dir" "$avd")"'),
    );
    expect(runnerSource, isNot(contains('DB_START_NONCE_A')));
    expect(runnerSource, isNot(contains('DB_START_NONCE_B')));
    expect(runnerSource, contains('must be supplied together'));
    expect(runnerSource, contains('M5_DB_EVIDENCE_LISTENING'));
    expect(
      runnerSource,
      isNot(contains("grep -Ec '^M5_ROUTE_STATUS::'.*|| printf 0")),
    );
    expect(
      runnerSource,
      contains(r'[[ "$route_count" =~ ^[0-9]+$ ]] || route_count=0'),
    );
    expect(runnerSource, isNot(contains('NF >= 7')));
    expect(runnerSource, contains('field_count == 6'));
    expect(
      runnerSource,
      contains('sub(/^.*M5_ROUTE_STATUS::/, "M5_ROUTE_STATUS::", line)'),
    );
    expect(runnerSource, contains('sub("^.*" marker, marker, line)'));
    expect(
      RegExp('PYTHONDONTWRITEBYTECODE=1').allMatches(runnerSource).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      RegExp(r'python3 -B(?: -u)?').allMatches(runnerSource).length,
      greaterThanOrEqualTo(4),
    );
    expect(runnerSource, contains('X-M5-Payment-Scenario'));
    expect(runnerSource, contains('paymentSettlementPoll'));
    expect(runnerSource, contains('internal-bounded-90s'));
    expect(runnerSource, contains('opener.open(request, timeout=180)'));
    expect(runnerSource, contains('opener.open(request, timeout=900)'));
    expect(runnerSource, isNot(contains('opener.open(request, timeout=20)')));
    expect(runnerSource, contains('class NoRedirect'));
    expect(runnerSource, contains('redirect_request'));
    expect(runnerSource, contains('response.geturl()'));
    expect(runnerSource, contains('QA_DB_EVIDENCE_URL must use HTTPS'));
    expect(runnerSource, isNot(contains('^https?://')));
    expect(runnerSource, isNot(contains('sleep 90')));
    expect(runnerSource, contains('rm -rf -- "\$DB_HELPER_STATE_DIR"'));
    expect(runnerSource, contains('DB_HELPER_LOG'));
    expect(
      runnerSource,
      contains(
        '[[ "\${#helper_token}" -eq 64 && "\$helper_token" =~ ^[A-Za-z0-9_-]+\$ ]]',
      ),
    );
    expect(
      runnerSource,
      contains('if [[ \${DB_EVIDENCE_RAW_FILES[@]+_} ]]; then'),
    );
    expect(runnerSource, contains('[[ "\$result" != \'FAIL\' ]]'));
    expect(
      runnerSource,
      contains('[[ "\$result" == PASS || "\$result" == NO_PAY ]]'),
    );
  });

  test(
    'Alipay bridge keeps native timeout provenance bounded and redacted',
    () {
      for (final String marker in <String>[
        'pay_task_returned',
        'native_watchdog_timeout',
        'native_not_invoked',
        'native_exception',
        'native_unavailable',
        'dart_watchdog_timeout',
      ]) {
        expect(alipayBridgeSource, contains(marker));
      }
      for (final String marker in <String>[
        'pay_task_returned',
        'native_watchdog_timeout',
        'native_not_invoked',
        'native_exception',
        'native_unavailable',
      ]) {
        expect(alipayAndroidBridgeSource, contains(marker));
      }
      expect(alipayAndroidBridgeSource, contains('"bridgeOutcome"'));
      expect(alipayAndroidBridgeSource, contains('nativeWatchdogTimeout()'));
      expect(alipayAndroidBridgeSource, contains('payTaskReturned(raw'));
      expect(alipayBridgeSource, contains("'bridgeOutcome'"));
      expect(integrationSource, contains('M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::'));
      expect(
        integrationSource,
        contains("'bridgeOutcome': _alipayBridgeOutcome"),
      );
      expect(
        integrationSource,
        contains(
          'const Duration _m5AlipayNativeTimeout = Duration(seconds: 150);',
        ),
      );
      expect(
        integrationSource,
        contains('alipayNativeTimeout: _m5AlipayNativeTimeout'),
      );
      expect(alipayAndroidBridgeSource, isNot(contains('Log.d')));
    },
  );

  test('cancel-only partials coordinate but remain a nonzero runner result', () {
    expect(runnerSource, contains('cancel_partial_coordination_success'));
    expect(
      runnerSource,
      contains(
        '"\${PAYMENT_SCENARIO:-none}" == \'cancel\' &&\n'
        '        "\$result_before_acceptance" == \'PASS\'',
      ),
    );
    expect(runnerSource, contains("reason='payment_cancel_only_partial'"));
    expect(
      runnerSource,
      contains("LAST_RESULT_REASON='payment_cancel_only_partial'"),
    );
    expect(
      runnerSource,
      contains("LAST_RESULT_REASON='cancel_only_avd_result_not_partial'"),
    );
    expect(runnerSource, contains("OVERALL_RESULT='PARTIAL'"));
    expect(runnerSource, contains("PRESERVE_PARTIAL_RESULT='true'"));
    expect(
      runnerSource,
      contains(
        'if [[ "\$result_a" == \'PARTIAL\' && "\$result_b" == \'PARTIAL\' ]];',
      ),
    );
    expect(
      runnerSource,
      contains(
        'if [[ "\$incoming_status" -ne 0 && "\$PRESERVE_PARTIAL_RESULT" != \'true\' ]];',
      ),
    );
    final int resultMapping = runnerSource.indexOf(
      "reason='payment_cancel_only_partial'",
    );
    final int coordinationReturn = runnerSource.indexOf(
      '[[ "\$cancel_partial_coordination_success" == \'true\' ]]',
    );
    final int overallBranch = runnerSource.indexOf(
      '"\${PAYMENT_SCENARIO:-none}" == \'cancel\' ]];',
      resultMapping,
    );
    final int finalExit = runnerSource.indexOf(
      'exit "\$([[ "\$OVERALL_RESULT" == PASS || "\$OVERALL_RESULT" == NO_PAY ]]',
    );
    expect(coordinationReturn, greaterThan(resultMapping));
    expect(overallBranch, greaterThan(coordinationReturn));
    expect(finalExit, greaterThan(overallBranch));
  });

  test('runtime relay and logs redact credentials', () {
    expect(runnerSource, contains('env -u QA_LIVE_PHONE'));
    expect(runnerSource, contains('-u QA_DB_EVIDENCE_TOKEN'));
    expect(runnerSource, contains('must be a distinct second account'));
    expect(runnerSource, contains('sanitize_stream'));
    expect(runnerSource, contains('secret_scan'));
    expect(runnerSource, contains('apk_secret_scan'));
    expect(runnerSource, contains('scan_stream'));
    expect(runnerSource, contains('1024 * 1024'));
    expect(runnerSource, contains('zipfile.ZipFile'));
    expect(runnerSource, contains('libagora_face_capture_extension.so'));
    expect(runnerSource, contains('libagora_lip_sync_extension.so'));
    expect(runnerSource, contains('begin openssh private key'));
    expect(runnerSource, contains('M5_SECRET_RECEIVER_PHONE'));
    expect(runnerSource, contains('>/dev/null 2>&1 <<\'PY\' &'));
    expect(runnerSource, contains('RUN_PID_A='));
    expect(runnerSource, contains('RUN_PID_B='));
    expect(runnerSource, contains("-name '*.raw.log' -print0"));
    expect(runnerSource, contains('[REDACTED_ALIPAY_PAYMENT_PAYLOAD]'));
    expect(runnerSource, contains('orderStr|orderInfo|orderString'));
    expect(integrationSource, contains('M5_RUNTIME_CONFIG_PORT'));
    expect(integrationSource, contains('M5_RUNTIME_CONFIG_PORT'));
    expect(integrationSource, isNot(contains('debugPrint(config.phone')));
  });

  test('Flutter-drive and logcat sanitizers redact Alipay SDK fields', () {
    final String shellScript = r'''
set -euo pipefail
LIVE_PHONE='fixture-phone-a'
RECEIVER_PHONE='fixture-phone-b'
OAUTH_CLIENT_ID='fixture-client-id'
DB_TOKEN='fixture-db-token'
RELAY_TOKEN_A='fixture-relay-token-a'
RELAY_TOKEN_B='fixture-relay-token-b'
eval "$(sed -n '/^sanitize_stream() {/,/^}/p' "$M5_RUNNER")"
printf '%s\n' \
  'flutter prefix {"APDIDTOKEN":"synthetic-apdid-token","DynamicKey":"synthetic-dynamic-key","aPdId":"synthetic-apdid","COLOR":"synthetic-color-value","WeBrTcUrL":"https://fixture.invalid/webrtc"}' \
  'logcat prefix apdidToken=synthetic-apdid-token dynamicKey:synthetic-dynamic-key apdid=synthetic-apdid color=synthetic-color-value webrtcUrl=https://fixture.invalid/webrtc' \
  'orderStr=app_id=fixture&sign=synthetic-signed-order' \
  'ORDERINFO:method=alipay.trade.app.pay&biz_content=synthetic-order' \
  'orderString=synthetic-payment-blob' \
  '{"orderInfo":"synthetic-quoted-payment-blob"}' \
  'alipay_sdk=fixture-sdk&sign_type=RSA2' \
  'method=alipay.trade.app.pay&app_id=fixture' \
  'M5_ROUTE_STATUS::alipay::POST::/m5/alipay::200::success' \
  'M5_PROVIDER_CALLS::1::0' \
  'M5_ACCEPTANCE::NO_PAY' | sanitize_stream
''';
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>['-c', shellScript],
      environment: <String, String>{
        ...Platform.environment,
        'M5_RUNNER': runner.path,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final String sanitized = result.stdout as String;
    for (final String fixtureValue in <String>[
      'synthetic-apdid-token',
      'synthetic-dynamic-key',
      'synthetic-apdid',
      'synthetic-color-value',
      'https://fixture.invalid/webrtc',
      'synthetic-signed-order',
      'synthetic-order',
      'synthetic-payment-blob',
      'synthetic-quoted-payment-blob',
      'fixture-sdk',
    ]) {
      expect(sanitized, isNot(contains(fixtureValue)));
    }
    expect(sanitized, contains('[REDACTED_ALIPAY_SDK_FIELD]'));
    expect(
      RegExp(
        '^\\[REDACTED_ALIPAY_PAYMENT_PAYLOAD\\]\$',
        multiLine: true,
      ).allMatches(sanitized).length,
      6,
    );
    expect(sanitized.toLowerCase(), isNot(contains('orderstr=')));
    expect(sanitized.toLowerCase(), isNot(contains('orderinfo:')));
    expect(sanitized.toLowerCase(), isNot(contains('orderstring=')));
    expect(
      sanitized,
      contains('M5_ROUTE_STATUS::alipay::POST::/m5/alipay::200::success'),
    );
    expect(sanitized, contains('M5_PROVIDER_CALLS::1::0'));
    expect(sanitized, contains('M5_ACCEPTANCE::NO_PAY'));
    expect(
      sanitized
          .split('\n')
          .where((String line) => line.startsWith('M5_ROUTE_STATUS::'))
          .length,
      1,
    );
    expect(
      sanitized
          .split('\n')
          .where(
            (String line) =>
                RegExp(r'^M5_PROVIDER_CALLS::[0-9]+::[0-9]+$').hasMatch(line),
          )
          .length,
      1,
    );
    expect(runnerSource, contains('sanitize_stream <"\$raw" >"\$safe"'));
    expect(
      runnerSource,
      contains('2>"\$dir/logs/logcat.stderr" | sanitize_stream'),
    );
    expect(runnerSource, contains('scan_alipay_sdk_fields'));
    expect(runnerSource, contains('sdk_field_placeholder'));
  });

  test('secret scan rejects unsanitized Alipay SDK fields', () {
    final String shellScript = r'''
set -euo pipefail
LIVE_PHONE='fixture-phone-a'
RECEIVER_PHONE='fixture-phone-b'
OAUTH_CLIENT_ID='fixture-client-id'
DB_TOKEN='fixture-db-token'
RELAY_TOKEN_A='fixture-relay-token-a'
RELAY_TOKEN_B='fixture-relay-token-b'
eval "$(sed -n '/^secret_scan() {/,/^}/p' "$M5_RUNNER")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/logs"
printf '%s\n' \
  '{"APDIDTOKEN":"[REDACTED_ALIPAY_SDK_FIELD]","DynamicKey":"[REDACTED_ALIPAY_SDK_FIELD]","aPdId":"[REDACTED_ALIPAY_SDK_FIELD]","COLOR":"[REDACTED_ALIPAY_SDK_FIELD]","WeBrTcUrL":"[REDACTED_ALIPAY_SDK_FIELD]"}' \
  'M5_PROVIDER_CALLS::1::0' >"$root/logs/sanitized.log"
secret_scan "$root"
printf '%s\n' \
  '{"apdidToken":"synthetic-apdid-token","dynamicKey":"synthetic-dynamic-key","apdid":"synthetic-apdid","color":"synthetic-color-value","webrtcUrl":"https://fixture.invalid/webrtc"}' \
  'M5_PROVIDER_CALLS::1::0' >"$root/logs/unsanitized.log"
if secret_scan "$root"; then
  printf '%s\n' 'secret_scan unexpectedly accepted unsanitized SDK fields' >&2
  exit 1
fi
rm -f -- "$root/logs/unsanitized.log"
printf '%s\n' \
  '{"orderString":"app_id=fixture&method=alipay.trade.app.pay&sign=synthetic"}' \
  'M5_PROVIDER_CALLS::1::0' >"$root/logs/unsanitized-payment.log"
if secret_scan "$root"; then
  printf '%s\n' 'secret_scan unexpectedly accepted Alipay payment payload' >&2
  exit 1
fi
''';
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>['-c', shellScript],
      environment: <String, String>{
        ...Platform.environment,
        'M5_RUNNER': runner.path,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'dry-run is allowed without vendor credentials and never reports pass',
    () {
      final Directory root = createM5TempRoot('m5-vendor-live-contract-');
      final Directory artifact = Directory('${root.path}/artifacts');
      final ProcessResult result = Process.runSync(
        '/bin/bash',
        <String>[runner.path],
        environment: <String, String>{
          ...Platform.environment,
          'QA_ARTIFACT_ROOT': artifact.path,
          'QA_M5_DRY_RUN': 'true',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final String summary = File(
        '${artifact.path}/summary.txt',
      ).readAsStringSync();
      expect(summary, contains('conclusion=DRY_RUN'));
      expect(summary, isNot(contains('M5_ACCEPTANCE::PASS')));
    },
  );

  test('aggregate fails closed when no two AVD evidences exist', () {
    final Directory root = createM5TempRoot(
      'm5-vendor-live-aggregate-contract-',
    );
    final ProcessResult result = Process.runSync(
      '/bin/bash',
      <String>[aggregate.path],
      environment: <String, String>{
        ...Platform.environment,
        'QA_ARTIFACT_ROOT': root.path,
        'QA_FLUTTER_SHA': 'a' * 40,
        'QA_BACKEND_SHA': 'b' * 40,
        'QA_BACKEND_DIGEST': 'c' * 64,
        'QA_M5_RUN_ID': 'm5-contract-run',
        'QA_M5_FIXTURE_ID': 'm5-fresh-contract-fixture',
      },
    );
    expect(result.exitCode, isNonZero);
    expect(File('${root.path}/aggregate-verdict.json').existsSync(), isTrue);
    final String verdict = File(
      '${root.path}/aggregate-verdict.txt',
    ).readAsStringSync();
    expect(verdict, contains('conclusion=ANDROID_EMULATOR_FAIL'));
  });

  test(
    'aggregate accepts exact Flutter envelopes with padded Android PIDs',
    () {
      final Directory root = createM5TempRoot('m5-vendor-live-padded-pid-');
      const String runId = 'm5-padded-pid-contract';
      const String fixtureId = 'm5-fresh-padded-pid-fixture';
      final String flutterSha = 'a' * 40;
      final String backendSha = 'b' * 40;
      final String backendDigest = 'c' * 64;
      final String hostSha = 'd' * 64;
      final String apkSha = 'e' * 64;
      final String nonceSha256 = 'f' * 64;

      void write(String relativePath, String contents) {
        final File file = File('${root.path}/$relativePath');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(contents);
      }

      final String dbEvidence =
          '''
{
  "status":"OK",
  "evidenceBinding":{"runId":"$runId","avd":"AVD-A","fixtureId":"$fixtureId","startNonceSha256":"$nonceSha256","backendSha":"$backendSha","flutterSha":"$flutterSha","apkSha":"$apkSha","backendSourceDigest":"$backendDigest"},
  "writeCounters":{"auth_sessions":1,"im_credentials":1,"c2c_messages":1,"avchatroom_sessions":1,"alipay_orders":0,"payment_provider_events":0,"wallet_transactions":0,"ledger_journals":0,"ledger_entries":0},
  "vendorOutbox":{"tencentIm":{"state":"SENT","attempts":1},"alipay":{"state":"MISSING","attempts":0}},
  "callbackEvents":{"tencentIm":{"verified":true,"eventCount":1},"alipay":{"verified":false,"eventCount":0}},
  "outboxAttempts":{"tencentIm":1,"alipay":0},
  "paymentSettlement":{"providerEventVerified":false,"providerEventProcessedCount":0,"succeededOrderCount":0,"walletTransactionCount":0,"walletCreditCount":0,"ledgerJournalCount":0,"ledgerEntryCount":0,"balancedJournalCount":0,"ledgerImbalanceCount":0},
  "secrets":false,
  "backendSourceDigest":"$backendDigest"
}
''';

      final String noPayLog = '''
M5_ACCEPTANCE::NO_PAY
M5_PROVIDER_CALLS::1::0
M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback
M5_SECRETS_IN_CLIENT::0
M5_ROUTE_STATUS::auth::GET::/m5::200::success
M5_LANE::tencent.credential::PASS
M5_LANE::tencent.login::PASS
M5_LANE::tencent.c2c.http-authority::PASS
M5_LANE::tencent.avchatroom.hint::PASS
M5_LANE::tencent.avchatroom.leave::PASS
M5_LANE::alipay.catalog::PASS
M5_RESILIENCE::NOT_RUN
M5_LANE::alipay.order::NOT_OPTED_IN
M5_LANE::alipay.native.launch-cancel::NOT_OPTED_IN
M5_LANE::alipay.native.launch-success::NOT_OPTED_IN
M5_LANE::alipay.query-reconcile::NOT_RUN
M5_LANE::alipay.settlement::NOT_RUN
M5_LANE::alipay.reconcile-idempotency::NOT_RUN
''';
      final String result =
          '''
result=NO_PAY
acceptance_status=NO_PAY
run_id=$runId
fixture_id=$fixtureId
db_start_nonce_sha256=$nonceSha256
tested_git_sha=$flutterSha
backend_sha=$backendSha
backend_source_digest=$backendDigest
flutter_version=3.44.7
dart_version=3.12.2
flutter_revision=84fc5cbb223bc12f83d65b647ff8a56caf779ffd
android_host_source_sha256=$hostSha
apk_sha256=$apkSha
apk_attestation_sha256=$apkSha
resilience_verdict=NOT_RUN
db_evidence=COLLECTED
outbox_evidence=COLLECTED
callback_evidence=COLLECTED
secret_scan=PASS
apk_secret_scan=PASS
crash_anr_count=0
screenshot_count=1
http_route_marker_count=1
tencent_provider_calls=1
alipay_provider_calls=0
''';

      String flutterEnvelope(String log, {required String pid}) => log
          .split('\n')
          .map((String line) => line.isEmpty ? line : 'I/flutter ($pid): $line')
          .join('\n');

      for (final String avd in <String>['AVD-A', 'AVD-B']) {
        write(
          '$avd/logs/flutter-drive.log',
          avd == 'AVD-A'
              ? flutterEnvelope(noPayLog, pid: ' 1364')
              : flutterEnvelope(noPayLog, pid: '12345'),
        );
        write(
          '$avd/vendor-events.txt',
          'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n',
        );
        write('$avd/http-route-coverage.csv', 'marker,capability\n');
        write('$avd/db-write-counters.txt', 'status=OK\n');
        write('$avd/outbox-evidence.txt', 'tencentIm.state=SENT\n');
        write('$avd/callback-evidence.txt', 'tencentIm.verified=true\n');
        write(
          '$avd/payment-settlement.txt',
          'providerEventVerified=false\nproviderEventProcessedCount=0\n',
        );
        write('$avd/screenshots/m5.png', 'png');
        write('$avd/result.txt', result);
        write(
          '$avd/db-evidence.json',
          dbEvidence.replaceAll('"AVD-A"', '"$avd"'),
        );
      }

      final ProcessResult process = Process.runSync(
        '/bin/bash',
        <String>[aggregate.path],
        environment: <String, String>{
          ...Platform.environment,
          'QA_ARTIFACT_ROOT': root.path,
          'QA_FLUTTER_SHA': flutterSha,
          'QA_BACKEND_SHA': backendSha,
          'QA_BACKEND_DIGEST': backendDigest,
          'QA_M5_RUN_ID': runId,
          'QA_M5_FIXTURE_ID': fixtureId,
        },
      );

      expect(process.exitCode, 0, reason: process.stderr.toString());
      expect(
        File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
        contains('conclusion=ANDROID_EMULATOR_NO_PAY'),
      );
    },
  );

  test(
    'aggregate still rejects prefixed marker lookalikes inside envelopes',
    () {
      final Directory root = createM5TempRoot(
        'm5-vendor-live-prefixed-marker-',
      );
      const String runId = 'm5-prefixed-marker-contract';
      const String fixtureId = 'm5-fresh-prefixed-marker-fixture';
      final String flutterSha = 'a' * 40;
      final String backendSha = 'b' * 40;
      final String backendDigest = 'c' * 64;
      final String hostSha = 'd' * 64;
      final String apkSha = 'e' * 64;
      final String nonceSha256 = 'f' * 64;

      void write(String relativePath, String contents) {
        final File file = File('${root.path}/$relativePath');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(contents);
      }

      final String dbEvidence =
          '''
{
  "status":"OK",
  "evidenceBinding":{"runId":"$runId","avd":"AVD-A","fixtureId":"$fixtureId","startNonceSha256":"$nonceSha256","backendSha":"$backendSha","flutterSha":"$flutterSha","apkSha":"$apkSha","backendSourceDigest":"$backendDigest"},
  "writeCounters":{"auth_sessions":1,"im_credentials":1,"c2c_messages":1,"avchatroom_sessions":1,"alipay_orders":0,"payment_provider_events":0,"wallet_transactions":0,"ledger_journals":0,"ledger_entries":0},
  "vendorOutbox":{"tencentIm":{"state":"SENT","attempts":1},"alipay":{"state":"MISSING","attempts":0}},
  "callbackEvents":{"tencentIm":{"verified":true,"eventCount":1},"alipay":{"verified":false,"eventCount":0}},
  "outboxAttempts":{"tencentIm":1,"alipay":0},
  "paymentSettlement":{"providerEventVerified":false,"providerEventProcessedCount":0,"succeededOrderCount":0,"walletTransactionCount":0,"walletCreditCount":0,"ledgerJournalCount":0,"ledgerEntryCount":0,"balancedJournalCount":0,"ledgerImbalanceCount":0},
  "secrets":false,
  "backendSourceDigest":"$backendDigest"
}
''';
      final String validNoPayLog = '''
M5_ACCEPTANCE::NO_PAY
M5_PROVIDER_CALLS::1::0
M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback
M5_SECRETS_IN_CLIENT::0
M5_ROUTE_STATUS::auth::GET::/m5::200::success
M5_LANE::tencent.credential::PASS
M5_LANE::tencent.login::PASS
M5_LANE::tencent.c2c.http-authority::PASS
M5_LANE::tencent.avchatroom.hint::PASS
M5_LANE::tencent.avchatroom.leave::PASS
M5_LANE::alipay.catalog::PASS
M5_RESILIENCE::NOT_RUN
M5_LANE::alipay.order::NOT_OPTED_IN
M5_LANE::alipay.native.launch-cancel::NOT_OPTED_IN
M5_LANE::alipay.native.launch-success::NOT_OPTED_IN
M5_LANE::alipay.query-reconcile::NOT_RUN
M5_LANE::alipay.settlement::NOT_RUN
M5_LANE::alipay.reconcile-idempotency::NOT_RUN
''';
      final String prefixedLookalikeLog = '''
I/flutter ( 1364): untrusted M5_ACCEPTANCE::NO_PAY
I/flutter ( 1364): M5_PROVIDER_CALLS::1::0
I/flutter ( 1364): M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback
I/flutter ( 1364): M5_SECRETS_IN_CLIENT::0
I/flutter ( 1364): M5_ROUTE_STATUS::auth::GET::/m5::200::success
I/flutter ( 1364): M5_LANE::tencent.credential::PASS
I/flutter ( 1364): M5_LANE::tencent.login::PASS
I/flutter ( 1364): M5_LANE::tencent.c2c.http-authority::PASS
I/flutter ( 1364): M5_LANE::tencent.avchatroom.hint::PASS
I/flutter ( 1364): M5_LANE::tencent.avchatroom.leave::PASS
I/flutter ( 1364): M5_LANE::alipay.catalog::PASS
I/flutter ( 1364): M5_RESILIENCE::NOT_RUN
I/flutter ( 1364): M5_LANE::alipay.order::NOT_OPTED_IN
I/flutter ( 1364): M5_LANE::alipay.native.launch-cancel::NOT_OPTED_IN
I/flutter ( 1364): M5_LANE::alipay.native.launch-success::NOT_OPTED_IN
I/flutter ( 1364): M5_LANE::alipay.query-reconcile::NOT_RUN
I/flutter ( 1364): M5_LANE::alipay.settlement::NOT_RUN
I/flutter ( 1364): M5_LANE::alipay.reconcile-idempotency::NOT_RUN
''';
      final String result =
          '''
result=NO_PAY
acceptance_status=NO_PAY
run_id=$runId
fixture_id=$fixtureId
db_start_nonce_sha256=$nonceSha256
tested_git_sha=$flutterSha
backend_sha=$backendSha
backend_source_digest=$backendDigest
flutter_version=3.44.7
dart_version=3.12.2
flutter_revision=84fc5cbb223bc12f83d65b647ff8a56caf779ffd
android_host_source_sha256=$hostSha
apk_sha256=$apkSha
apk_attestation_sha256=$apkSha
resilience_verdict=NOT_RUN
db_evidence=COLLECTED
outbox_evidence=COLLECTED
callback_evidence=COLLECTED
secret_scan=PASS
apk_secret_scan=PASS
crash_anr_count=0
screenshot_count=1
http_route_marker_count=1
tencent_provider_calls=1
alipay_provider_calls=0
''';

      for (final String avd in <String>['AVD-A', 'AVD-B']) {
        write(
          '$avd/logs/flutter-drive.log',
          avd == 'AVD-A' ? prefixedLookalikeLog : validNoPayLog,
        );
        write(
          '$avd/vendor-events.txt',
          'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n',
        );
        write('$avd/http-route-coverage.csv', 'marker,capability\n');
        write('$avd/db-write-counters.txt', 'status=OK\n');
        write('$avd/outbox-evidence.txt', 'tencentIm.state=SENT\n');
        write('$avd/callback-evidence.txt', 'tencentIm.verified=true\n');
        write(
          '$avd/payment-settlement.txt',
          'providerEventVerified=false\nproviderEventProcessedCount=0\n',
        );
        write('$avd/screenshots/m5.png', 'png');
        write('$avd/result.txt', result);
        write(
          '$avd/db-evidence.json',
          dbEvidence.replaceAll('"AVD-A"', '"$avd"'),
        );
      }

      final ProcessResult process = Process.runSync(
        '/bin/bash',
        <String>[aggregate.path],
        environment: <String, String>{
          ...Platform.environment,
          'QA_ARTIFACT_ROOT': root.path,
          'QA_FLUTTER_SHA': flutterSha,
          'QA_BACKEND_SHA': backendSha,
          'QA_BACKEND_DIGEST': backendDigest,
          'QA_M5_RUN_ID': runId,
          'QA_M5_FIXTURE_ID': fixtureId,
        },
      );

      expect(process.exitCode, isNonZero);
      expect(
        File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
        contains('conclusion=ANDROID_EMULATOR_FAIL'),
      );
    },
  );

  test('aggregate validates resilience markers strictly before fallback', () {
    final Directory root = createM5TempRoot('m5-vendor-live-no-pay-');
    const String runId = 'm5-no-pay-contract';
    const String fixtureId = 'm5-fresh-no-pay-fixture';
    final String flutterSha = 'a' * 40;
    final String backendSha = 'b' * 40;
    final String backendDigest = 'c' * 64;
    final String hostSha = 'd' * 64;
    final String apkSha = 'e' * 64;
    final String nonceSha256 = 'f' * 64;

    void write(String relativePath, String contents) {
      final File file = File('${root.path}/$relativePath');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    final String dbEvidence =
        '''
{
  "status":"OK",
  "evidenceBinding":{"runId":"$runId","avd":"AVD-A","fixtureId":"$fixtureId","startNonceSha256":"$nonceSha256","backendSha":"$backendSha","flutterSha":"$flutterSha","apkSha":"$apkSha","backendSourceDigest":"$backendDigest"},
  "writeCounters":{"auth_sessions":1,"im_credentials":1,"c2c_messages":1,"avchatroom_sessions":1,"alipay_orders":0,"payment_provider_events":0,"wallet_transactions":0,"ledger_journals":0,"ledger_entries":0},
  "vendorOutbox":{"tencentIm":{"state":"SENT","attempts":1},"alipay":{"state":"MISSING","attempts":0}},
  "callbackEvents":{"tencentIm":{"verified":true,"eventCount":1},"alipay":{"verified":false,"eventCount":0}},
  "outboxAttempts":{"tencentIm":1,"alipay":0},
  "paymentSettlement":{"providerEventVerified":false,"providerEventProcessedCount":0,"succeededOrderCount":0,"walletTransactionCount":0,"walletCreditCount":0,"ledgerJournalCount":0,"ledgerEntryCount":0,"balancedJournalCount":0,"ledgerImbalanceCount":0},
  "secrets":false,
  "backendSourceDigest":"$backendDigest"
}
''';
    String logWithResilienceMarker(String resilienceMarker) =>
        '''
untrusted M5_ACCEPTANCE::FAIL
I/flutter (not-a-pid): M5_ACCEPTANCE::FAIL
I/flutter (12345): untrusted M5_ACCEPTANCE::FAIL
M5_ACCEPTANCE::NO_PAY
M5_PROVIDER_CALLS::1::0
M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback
M5_SECRETS_IN_CLIENT::0
M5_ROUTE_STATUS::auth::GET::/m5::200::success
M5_LANE::tencent.credential::PASS
M5_LANE::tencent.login::PASS
M5_LANE::tencent.c2c.http-authority::PASS
M5_LANE::tencent.avchatroom.hint::PASS
M5_LANE::tencent.avchatroom.leave::PASS
M5_LANE::alipay.catalog::PASS
$resilienceMarker
M5_LANE::alipay.order::NOT_OPTED_IN
M5_LANE::alipay.native.launch-cancel::NOT_OPTED_IN
M5_LANE::alipay.native.launch-success::NOT_OPTED_IN
M5_LANE::alipay.query-reconcile::NOT_RUN
M5_LANE::alipay.settlement::NOT_RUN
M5_LANE::alipay.reconcile-idempotency::NOT_RUN
''';

    String flutterEnvelope(String log) => log
        .split('\n')
        .map((String line) => line.isEmpty ? line : 'I/flutter (12345): $line')
        .join('\n');

    final String result =
        '''
result=NO_PAY
acceptance_status=NO_PAY
run_id=$runId
fixture_id=$fixtureId
db_start_nonce_sha256=$nonceSha256
tested_git_sha=$flutterSha
backend_sha=$backendSha
backend_source_digest=$backendDigest
flutter_version=3.44.7
dart_version=3.12.2
flutter_revision=84fc5cbb223bc12f83d65b647ff8a56caf779ffd
android_host_source_sha256=$hostSha
apk_sha256=$apkSha
apk_attestation_sha256=$apkSha
resilience_verdict=NOT_RUN
db_evidence=COLLECTED
outbox_evidence=COLLECTED
callback_evidence=COLLECTED
secret_scan=PASS
apk_secret_scan=PASS
crash_anr_count=0
screenshot_count=1
http_route_marker_count=1
tencent_provider_calls=1
alipay_provider_calls=0
''';

    void writeLogs({required String avdALog, required String avdBLog}) {
      for (final String avd in <String>['AVD-A', 'AVD-B']) {
        // Real Android Flutter output has an `I/flutter (pid): ` envelope;
        // retain one raw fixture as a backwards-compatibility contract too.
        write(
          '$avd/logs/flutter-drive.log',
          avd == 'AVD-A' ? avdALog : avdBLog,
        );
        write(
          '$avd/vendor-events.txt',
          'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n',
        );
        write('$avd/http-route-coverage.csv', 'marker,capability\n');
        write('$avd/db-write-counters.txt', 'status=OK\n');
        write('$avd/outbox-evidence.txt', 'tencentIm.state=SENT\n');
        write('$avd/callback-evidence.txt', 'tencentIm.verified=true\n');
        write(
          '$avd/payment-settlement.txt',
          'providerEventVerified=false\nproviderEventProcessedCount=0\n',
        );
        write('$avd/screenshots/m5.png', 'png');
        write('$avd/result.txt', result);
        write(
          '$avd/db-evidence.json',
          dbEvidence.replaceAll('"AVD-A"', '"$avd"'),
        );
      }
    }

    ProcessResult runAggregate() => Process.runSync(
      '/bin/bash',
      <String>[aggregate.path],
      environment: <String, String>{
        ...Platform.environment,
        'QA_ARTIFACT_ROOT': root.path,
        'QA_FLUTTER_SHA': flutterSha,
        'QA_BACKEND_SHA': backendSha,
        'QA_BACKEND_DIGEST': backendDigest,
        'QA_M5_RUN_ID': runId,
        'QA_M5_FIXTURE_ID': fixtureId,
      },
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
    );
    final ProcessResult process = runAggregate();
    expect(process.exitCode, 0, reason: process.stderr.toString());
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_NO_PAY'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker('M5_LANE::tencent.outage.fallback::NOT_RUN'),
      ),
      avdBLog: logWithResilienceMarker(
        'M5_LANE::tencent.outage.fallback::NOT_RUN',
      ),
    );
    final ProcessResult legacyFallback = runAggregate();
    expect(
      legacyFallback.exitCode,
      0,
      reason: legacyFallback.stderr.toString(),
    );
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_NO_PAY'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker('M5_RESILIENCE::NOT_RUN::unexpected'),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN::unexpected'),
    );
    final ProcessResult extraFieldDedicated = runAggregate();
    expect(extraFieldDedicated.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker(
          'M5_RESILIENCE::NOT_RUN\nM5_RESILIENCE::NOT_RUN',
        ),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
    );
    final ProcessResult duplicateDedicated = runAggregate();
    expect(duplicateDedicated.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker('M5_RESILIENCE::NOT_RUN\nM5_RESILIENCE::PASS'),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
    );
    final ProcessResult conflictingDedicated = runAggregate();
    expect(conflictingDedicated.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker(
          'M5_RESILIENCE::NOT_RUN::unexpected\n'
          'M5_LANE::tencent.outage.fallback::NOT_RUN',
        ),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
    );
    final ProcessResult malformedDedicatedBlocksFallback = runAggregate();
    expect(malformedDedicatedBlocksFallback.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker(
          'M5_LANE::tencent.outage.fallback::NOT_RUN\n'
          'M5_LANE::tencent.outage.fallback::NOT_RUN',
        ),
      ),
      avdBLog: logWithResilienceMarker(
        'M5_LANE::tencent.outage.fallback::NOT_RUN',
      ),
    );
    final ProcessResult duplicateLegacy = runAggregate();
    expect(duplicateLegacy.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    writeLogs(
      avdALog: flutterEnvelope(
        logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
      ),
      avdBLog: logWithResilienceMarker('M5_RESILIENCE::NOT_RUN'),
    );

    final File resultA = File('${root.path}/AVD-A/result.txt');
    resultA.writeAsStringSync(
      resultA.readAsStringSync().replaceFirst(
        'secret_scan=PASS',
        'secret_scan=FAIL',
      ),
    );
    final ProcessResult unsafe = runAggregate();
    expect(unsafe.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );

    resultA.writeAsStringSync(
      resultA
          .readAsStringSync()
          .replaceFirst('secret_scan=FAIL', 'secret_scan=PASS')
          .replaceFirst('result=NO_PAY', 'result=PARTIAL'),
    );
    final ProcessResult partial = runAggregate();
    expect(partial.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_PARTIAL'),
    );
  });

  test('success aggregate requires settlement on AVD-A and withholds AVD-B', () {
    final Directory root = createM5TempRoot('m5-vendor-live-success-');
    const String runId = 'm5-success-contract';
    const String fixtureId = 'm5-fresh-success-fixture';
    final String nonceSha256 = 'f' * 64;
    final String flutterSha = 'a' * 40;
    final String backendSha = 'b' * 40;
    final String backendDigest = 'c' * 64;
    final String hostSha = 'd' * 64;
    final String apkSha = 'e' * 64;

    void write(String relativePath, String contents) {
      final File file = File('${root.path}/$relativePath');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    Map<String, Object?> dbEvidence({required bool owner}) => <String, Object?>{
      'status': 'OK',
      'evidenceBinding': <String, Object?>{
        'runId': runId,
        'avd': owner ? 'AVD-A' : 'AVD-B',
        'fixtureId': fixtureId,
        'startNonceSha256': nonceSha256,
        'backendSha': backendSha,
        'flutterSha': flutterSha,
        'apkSha': apkSha,
        'backendSourceDigest': backendDigest,
      },
      'writeCounters': <String, int>{
        'auth_sessions': 1,
        'im_credentials': 1,
        'c2c_messages': 1,
        'avchatroom_sessions': 1,
        'alipay_orders': owner ? 1 : 0,
        'payment_provider_events': owner ? 1 : 0,
        'wallet_transactions': owner ? 1 : 0,
        'ledger_journals': owner ? 1 : 0,
        'ledger_entries': owner ? 2 : 0,
      },
      'vendorOutbox': <String, Object?>{
        'tencentIm': <String, Object?>{'state': 'SENT', 'attempts': 1},
        'alipay': <String, Object?>{
          'state': owner ? 'SENT' : 'MISSING',
          'attempts': owner ? 1 : 0,
        },
      },
      'callbackEvents': <String, Object?>{
        'tencentIm': <String, Object?>{'verified': true, 'eventCount': 1},
        'alipay': <String, Object?>{
          'verified': owner,
          'eventCount': owner ? 1 : 0,
        },
      },
      'outboxAttempts': <String, int>{'tencentIm': 1, 'alipay': owner ? 1 : 0},
      'paymentSettlement': <String, Object?>{
        'providerEventVerified': owner,
        'providerEventProcessedCount': owner ? 1 : 0,
        'succeededOrderCount': owner ? 1 : 0,
        'walletTransactionCount': owner ? 1 : 0,
        'walletCreditCount': owner ? 1 : 0,
        'ledgerJournalCount': owner ? 1 : 0,
        'ledgerEntryCount': owner ? 2 : 0,
        'balancedJournalCount': owner ? 1 : 0,
        'ledgerImbalanceCount': 0,
      },
      'secrets': false,
      'backendSourceDigest': backendDigest,
    };

    String log({required bool owner}) {
      final List<String> lines = <String>[
        'M5_ACCEPTANCE::PASS',
        'M5_PROVIDER_CALLS::1::${owner ? 1 : 0}',
        'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback',
        if (owner) 'M5_VENDOR_EVENT::alipay::launch_success::sdk_callback',
        if (owner) 'M5_PAYMENT_SUCCESS_FLOW_VERIFIED::1',
        'M5_SECRETS_IN_CLIENT::0',
        'M5_ROUTE_STATUS::auth::GET::/m5::200::success',
        'M5_LANE::tencent.credential::PASS',
        'M5_LANE::tencent.login::PASS',
        'M5_LANE::tencent.c2c.http-authority::PASS',
        'M5_LANE::tencent.avchatroom.hint::PASS',
        'M5_LANE::tencent.avchatroom.leave::PASS',
        'M5_LANE::alipay.catalog::PASS',
        if (owner) ...<String>[
          'M5_LANE::alipay.order::PASS',
          'M5_LANE::alipay.native.launch-success::PASS',
          'M5_LANE::alipay.query-reconcile::PASS',
          'M5_LANE::alipay.settlement::PASS',
          'M5_LANE::alipay.reconcile-idempotency::PASS',
        ] else ...<String>[
          'M5_LANE::alipay.order::NOT_RUN',
          'M5_LANE::alipay.native.launch-cancel::NOT_RUN',
          'M5_LANE::alipay.native.launch-success::NOT_RUN',
          'M5_LANE::alipay.query-reconcile::NOT_RUN',
          'M5_LANE::alipay.settlement::NOT_RUN',
          'M5_LANE::alipay.reconcile-idempotency::NOT_RUN',
        ],
        'M5_LANE::tencent.outage.fallback::NOT_RUN',
      ];
      return '${lines.join('\n')}\n';
    }

    String result({required bool owner}) =>
        '''
result=PASS
acceptance_status=PASS
run_id=$runId
fixture_id=$fixtureId
db_start_nonce_sha256=$nonceSha256
tested_git_sha=$flutterSha
flutter_sha=$flutterSha
backend_sha=$backendSha
backend_source_digest=$backendDigest
flutter_version=3.44.7
dart_version=3.12.2
flutter_revision=84fc5cbb223bc12f83d65b647ff8a56caf779ffd
android_host_source_sha256=$hostSha
apk_sha256=$apkSha
apk_attestation_sha256=$apkSha
resilience_verdict=NOT_RUN
db_evidence=COLLECTED
outbox_evidence=COLLECTED
callback_evidence=COLLECTED
secret_scan=PASS
apk_secret_scan=PASS
crash_anr_count=0
screenshot_count=1
http_route_marker_count=1
vendor_event_count=${owner ? 2 : 1}
tencent_provider_calls=1
alipay_provider_calls=${owner ? 1 : 0}
payment_scenario=success
payment_success_proven=${owner ? 'true' : 'false'}
reconcile_repeat=${owner ? 'PASS' : 'NOT_RUN'}
payment_opt_in=true
payment_invoked=${owner ? 'true' : 'false'}
''';

    for (final bool owner in <bool>[true, false]) {
      final String avd = owner ? 'AVD-A' : 'AVD-B';
      write('$avd/logs/flutter-drive.log', log(owner: owner));
      write(
        '$avd/vendor-events.txt',
        'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n',
      );
      if (owner) {
        write(
          '$avd/vendor-events.txt',
          'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n'
              'M5_VENDOR_EVENT::alipay::launch_success::sdk_callback\n',
        );
      }
      write('$avd/http-route-coverage.csv', 'marker,capability\nroute,auth\n');
      write('$avd/db-write-counters.txt', 'status=OK\n');
      write(
        '$avd/outbox-evidence.txt',
        'tencentIm.state=SENT\nalipay.state=${owner ? 'SENT' : 'MISSING'}\n',
      );
      write(
        '$avd/callback-evidence.txt',
        'tencentIm.verified=true\nalipay.verified=${owner ? 'true' : 'false'}\n',
      );
      write(
        '$avd/payment-settlement.txt',
        'providerEventVerified=${owner ? 'true' : 'false'}\n'
            'ledgerEntryCount=${owner ? 2 : 0}\n',
      );
      write('$avd/screenshots/m5.png', 'png');
      write('$avd/result.txt', result(owner: owner));
      write('$avd/db-evidence.json', jsonEncode(dbEvidence(owner: owner)));
    }

    ProcessResult runAggregate() => Process.runSync(
      '/bin/bash',
      <String>[aggregate.path],
      environment: <String, String>{
        ...Platform.environment,
        'QA_ARTIFACT_ROOT': root.path,
        'QA_FLUTTER_SHA': flutterSha,
        'QA_BACKEND_SHA': backendSha,
        'QA_BACKEND_DIGEST': backendDigest,
        'QA_M5_RUN_ID': runId,
        'QA_M5_FIXTURE_ID': fixtureId,
        'QA_M5_ALLOW_EXTERNAL_PAYMENT': 'true',
        'QA_M5_PAYMENT_CONFIRMATION': 'I_UNDERSTAND_SANDBOX_PAYMENT',
        'QA_M5_SUCCESS_CONFIRMATION': 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT',
        'QA_M5_ALIPAY_SCENARIO': 'success',
      },
    );

    final ProcessResult passed = runAggregate();
    expect(passed.exitCode, 0, reason: passed.stderr.toString());
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_PASS'),
    );
    final File aEvidence = File('${root.path}/AVD-A/db-evidence.json');
    aEvidence.writeAsStringSync(
      aEvidence.readAsStringSync().replaceFirst(
        '"ledgerEntryCount":2',
        '"ledgerEntryCount":1',
      ),
    );
    final ProcessResult unsafe = runAggregate();
    expect(unsafe.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_FAIL'),
    );
  });
}

ChatMessage _m5Message({
  required String id,
  required int senderUserId,
  required String content,
}) => ChatMessage(
  id: id,
  conversationId: 'conversation-m5',
  senderUserId: senderUserId,
  senderName: 'M5 sender',
  content: content,
  createdAt: DateTime.utc(2026, 8, 29),
  isMine: false,
  status: ChatMessageStatus.received,
);
