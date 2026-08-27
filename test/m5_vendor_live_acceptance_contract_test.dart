import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File runner = File('tool/qa/run_m5_vendor_live_avd.sh').absolute;
  final File aggregate = File(
    'tool/qa/aggregate_m5_vendor_live_avd.sh',
  ).absolute;
  final File integration = File(
    'integration_test/m5_vendor_live_integration_test.dart',
  ).absolute;
  final String runnerSource = runner.readAsStringSync();
  final String aggregateSource = aggregate.readAsStringSync();
  final String integrationSource = integration.readAsStringSync();

  test('M5 shell harnesses are syntactically valid', () {
    for (final File file in <File>[runner, aggregate]) {
      final ProcessResult result = Process.runSync('/bin/bash', <String>[
        '-n',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${file.path}: ${result.stderr}');
    }
  });

  test('M5 uses an independent positive provider-call namespace', () {
    expect(runnerSource, contains('M5_PROVIDER_CALLS::'));
    expect(aggregateSource, contains('M5_PROVIDER_CALLS::'));
    expect(integrationSource, contains('M5_PROVIDER_CALLS::'));
    expect(runnerSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(aggregateSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(integrationSource, isNot(contains('M4_PROVIDER_CALLS::')));
    expect(aggregateSource, contains('[1-9][0-9]*::[1-9][0-9]*'));
    expect(integrationSource, contains('_tencentProviderCalls <= 0'));
    expect(integrationSource, contains('providerCallback'));
    expect(integrationSource, isNot(contains('providerCall(')));
    expect(integrationSource, contains('c2cHintObserved'));
    expect(integrationSource, contains("config.role == 'receiver'"));
    expect(integrationSource, contains('_viewportForRole'));
    expect(integrationSource, contains('/m5/c2c/receiver-ready'));
    expect(integrationSource, contains('hasC2cHintForMessage'));
    expect(integrationSource, contains('roomLifecycleRepository'));
    expect(integrationSource, contains('saveRoom'));
    expect(integrationSource, contains('RoomAccessMode.publicRoom'));
    expect(integrationSource, contains('routes.createRoom'));
    expect(
      integrationSource,
      contains('candidate.title.trim() == fixtureTitle'),
    );
    expect(integrationSource, contains('!saved.created'));
    expect(integrationSource, contains('sendPublicMessage'));
    expect(integrationSource, contains('/m5/avchatroom/ready'));
    expect(integrationSource, contains('/m5/avchatroom/message-sent'));
    expect(integrationSource, contains('/m5/avchatroom/pass'));
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
    expect(runnerSource, contains('receiverReady'));
    expect(runnerSource, contains('roomMessageId'));
    expect(runnerSource, contains('/m5/avchatroom/ready'));
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
    for (final String bindingField in <String>[
      'runId',
      'fixtureId',
      'avd',
      'startNonce',
      'backendSha',
      'flutterSha',
      'apkSha',
      'backendSourceDigest',
    ]) {
      expect(runnerSource, contains(bindingField));
      expect(aggregateSource, contains(bindingField));
    }
  });

  test('default Alipay path has no financial side effect', () {
    expect(runnerSource, contains('M5_ALLOW_EXTERNAL_PAYMENT'));
    expect(
      runnerSource,
      contains('M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT'),
    );
    expect(integrationSource, contains('I_UNDERSTAND_SANDBOX_PAYMENT'));
    final int optInGate = integrationSource.indexOf('if (!optedIn)');
    final int orderCreation = integrationSource.indexOf('createRechargeOrder(');
    final int nativeInvocation = integrationSource.indexOf(
      'invokePayment(order)',
    );
    expect(optInGate, greaterThanOrEqualTo(0));
    expect(orderCreation, greaterThan(optInGate));
    expect(nativeInvocation, greaterThan(orderCreation));
    expect(integrationSource, contains("'alipay.order', 'NOT_OPTED_IN'"));
    expect(
      integrationSource,
      contains("'alipay.native.launch-cancel', 'NOT_OPTED_IN'"),
    );
    expect(integrationSource, contains("'alipay.query-reconcile', 'NOT_RUN'"));
    expect(integrationSource, contains("'vendor_blocked'"));
    expect(integrationSource, contains("'cancel_only'"));
    expect(integrationSource, contains("fullyPass ? 'PARTIAL'"));
    expect(aggregateSource, contains('payment_lane_not_explicitly_withheld'));
    expect(aggregateSource, contains('PAYMENT_CANCEL_ONLY'));
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
    expect(runnerSource, contains('[[ "\$result" != \'FAIL\' ]]'));
    expect(
      runnerSource,
      contains('[[ "\$result" == PASS || "\$result" == NO_PAY ]]'),
    );
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
    expect(integrationSource, contains('M5_RUNTIME_CONFIG_PORT'));
    expect(integrationSource, contains('M5_RUNTIME_CONFIG_PORT'));
    expect(integrationSource, isNot(contains('debugPrint(config.phone')));
  });

  test(
    'dry-run is allowed without vendor credentials and never reports pass',
    () {
      final Directory root = Directory(
        '/private/tmp/m5-vendor-live-contract-${DateTime.now().microsecondsSinceEpoch}',
      )..createSync();
      addTearDown(() => root.deleteSync(recursive: true));
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
    final Directory root = Directory(
      '/private/tmp/m5-vendor-live-aggregate-contract-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync();
    addTearDown(() => root.deleteSync(recursive: true));
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

  test('aggregate keeps a complete zero-payment run explicitly NO_PAY', () {
    final Directory root = Directory(
      '/private/tmp/m5-vendor-live-no-pay-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync();
    addTearDown(() => root.deleteSync(recursive: true));
    const String runId = 'm5-no-pay-contract';
    const String fixtureId = 'm5-fresh-no-pay-fixture';
    final String flutterSha = 'a' * 40;
    final String backendSha = 'b' * 40;
    final String backendDigest = 'c' * 64;
    final String hostSha = 'd' * 64;
    final String apkSha = 'e' * 64;
    const String nonce = 'nonce-contract-123456';

    void write(String relativePath, String contents) {
      final File file = File('${root.path}/$relativePath');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    final String dbEvidence =
        '''
{
  "status":"OK",
  "evidenceBinding":{"runId":"$runId","avd":"AVD-A","fixtureId":"$fixtureId","startNonce":"$nonce","backendSha":"$backendSha","flutterSha":"$flutterSha","apkSha":"$apkSha","backendSourceDigest":"$backendDigest"},
  "writeCounters":{"auth_sessions":1,"im_credentials":1,"c2c_messages":1,"avchatroom_sessions":1,"alipay_orders":0,"payment_provider_events":0,"wallet_transactions":0,"ledger_journals":0,"ledger_entries":0},
  "vendorOutbox":{"tencentIm":{"state":"SENT","attempts":1},"alipay":{"state":"MISSING","attempts":0}},
  "callbackEvents":{"tencentIm":{"verified":true,"eventCount":1},"alipay":{"verified":false,"eventCount":0}},
  "providerCalls":{"tencentIm":1,"alipay":0},
  "secrets":false,
  "backendSourceDigest":"$backendDigest"
}
''';
    final String log = '''
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
M5_LANE::tencent.outage.fallback::NOT_RUN
M5_LANE::alipay.order::NOT_OPTED_IN
M5_LANE::alipay.native.launch-cancel::NOT_OPTED_IN
M5_LANE::alipay.query-reconcile::NOT_RUN
''';
    final String result =
        '''
result=NO_PAY
acceptance_status=NO_PAY
run_id=$runId
fixture_id=$fixtureId
db_start_nonce=$nonce
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
      write('$avd/logs/flutter-drive.log', log);
      write(
        '$avd/vendor-events.txt',
        'M5_VENDOR_EVENT::tencent-im::login_ready::sdk_callback\n',
      );
      write('$avd/http-route-coverage.csv', 'marker,capability\n');
      write('$avd/db-write-counters.txt', 'status=OK\n');
      write('$avd/outbox-evidence.txt', 'tencentIm.state=SENT\n');
      write('$avd/callback-evidence.txt', 'tencentIm.verified=true\n');
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

    final File resultA = File('${root.path}/AVD-A/result.txt');
    resultA.writeAsStringSync(
      resultA.readAsStringSync().replaceFirst(
        'secret_scan=PASS',
        'secret_scan=FAIL',
      ),
    );
    final ProcessResult unsafe = Process.runSync(
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
    final ProcessResult partial = Process.runSync(
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
    expect(partial.exitCode, isNonZero);
    expect(
      File('${root.path}/aggregate-verdict.txt').readAsStringSync(),
      contains('conclusion=ANDROID_EMULATOR_PARTIAL'),
    );
  });
}
