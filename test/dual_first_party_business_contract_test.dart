import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';

import '../integration_test/dual_first_party_business_support.dart';

void main() {
  test(
    'private acceptance has ten ordered send-ready and receive barriers',
    () {
      final privatePhases = dualPhases.where(
        (phase) => phase.startsWith('private-'),
      );
      expect(privatePhases, <String>[
        for (int index = 0; index < 10; index++) ...<String>[
          'private-ready-$index',
          'private-received-$index',
        ],
      ]);
      expect(dualPhases.toSet().length, dualPhases.length);
      expect(dualPhases.last, 'complete');
    },
  );

  test(
    'device-private runtime role accepts only A or B, without a define',
    () async {
      for (final value in ['A', 'B', 'A\n', 'B\r\n']) {
        expect(
          await readDualRuntimeRole(read: () async => value),
          value.trim(),
        );
      }
      for (final value in ['', 'a', 'C', 'AB', ' A', 'B ', 'A\nB', 'A\n\n']) {
        await expectLater(
          readDualRuntimeRole(read: () async => value),
          throwsStateError,
        );
      }
      await expectLater(
        readDualRuntimeRole(
          read: () async {
            throw const FileSystemException('unavailable');
          },
        ),
        throwsStateError,
      );
      final source = File(
        'integration_test/dual_first_party_business_test.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('DUAL_ROLE')));
      expect(source, contains('await readDualRuntimeRole()'));
    },
  );
  final flutterSha = List.filled(40, 'a').join();
  final backendSha = List.filled(40, 'b').join();
  DualConfig parse(Map<String, dynamic> json, String role) => DualConfig(
    json,
    role,
    expectedFlutterSha: flutterSha,
    expectedBackendSha: backendSha,
  );
  Map<String, dynamic> runtimeConfig() {
    final now = DateTime.now();
    final ephemeral = now.microsecondsSinceEpoch.toRadixString(36);
    return {
      'role': 'A',
      'flutterSha': flutterSha,
      'backendSha': backendSha,
      'runId': 'contract-$ephemeral',
      'roomId': ephemeral,
      'peerPostId': ephemeral,
      'peerUserId': 2,
      'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
      'apiBaseUrl': dualBackend,
      'oauthClientId': ephemeral,
      'clientType': Platform.operatingSystem,
      'clientInnerVersion': '1',
      'session': {
        'accessToken': ephemeral,
        'userId': 1,
        'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
      },
    };
  }

  test('runtime config rejects same-user, wrong-role and stale fixtures', () {
    expect(parse(runtimeConfig(), 'A').peerRole, 'B');
    for (final change in <Map<String, dynamic>>[
      {'peerUserId': 1},
      {'role': 'B'},
      {'apiBaseUrl': 'http://10.0.2.2:18080/'},
      {
        'expiresAt': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      },
    ]) {
      expect(
        () => parse(runtimeConfig()..addAll(change), 'A'),
        throwsStateError,
      );
    }
  });

  test('barrier rejects stale run, wrong phase and non-boolean release', () {
    final config = parse(runtimeConfig(), 'A');
    final relay = DualRelay(29001, 'A');
    addTearDown(relay.close);
    final reply = <String, dynamic>{
      'runId': config.runId,
      'phase': 'joined',
      'released': false,
    };
    expect(relay.released(reply, config, 'joined'), isFalse);
    expect(
      relay.released({...reply, 'released': true}, config, 'joined'),
      isTrue,
    );
    for (final change in <Map<String, dynamic>>[
      {'runId': 'stale'},
      {'phase': 'complete'},
      {'released': 'true'},
    ]) {
      expect(
        () => relay.released({...reply, ...change}, config, 'joined'),
        throwsStateError,
      );
    }
  });
  AppEnvironment environment({
    String url = dualBackend,
    String deployment = 'local',
    String mode = 'live',
    bool rtc = false,
    bool im = false,
    bool apple = false,
    bool alipay = false,
  }) => AppEnvironment.fromResolvedValues(
    backendModeValue: mode,
    deploymentValue: deployment,
    timeoutValue: '15',
    apiBaseUrl: url,
    clientType: '',
    clientInnerVersion: '',
    oauthClientId: '',
    realtimeEndpoint: '',
    liveProbePath: '/',
    allowInsecureHttp: true,
    enableAgoraRtc: rtc,
    enableTencentIm: im,
    enableAppleIap: apple,
    enableAlipayAppPay: alipay,
    releaseBuild: false,
  );

  test('only isolated live development with vendors disabled is accepted', () {
    expect(() => validateDualEnvironment(environment()), returnsNormally);
    for (final env in [
      environment(url: 'http://10.0.2.2:18080/'),
      environment(url: '$dualBackend?redirect=1'),
      environment(deployment: 'production'),
      environment(deployment: ''),
      environment(mode: 'mock'),
      environment(rtc: true),
      environment(im: true),
      environment(apple: true),
      environment(alipay: true),
    ]) {
      expect(() => validateDualEnvironment(env), throwsStateError);
    }
    expect(
      () => validateDualEnvironment(environment(), release: true),
      throwsStateError,
    );
  });

  test('invalid configuration never echoes payload or parser details', () {
    final sensitive = List.generate(
      48,
      (i) => String.fromCharCode(65 + i % 26),
    ).join();
    try {
      parse({'session': sensitive, 'role': 'A'}, 'A');
      fail('must reject malformed runtime config');
    } catch (error) {
      expect(error, isStateError);
      expect(error.toString(), isNot(contains(sensitive)));
      expect(error.toString(), contains('Invalid or expired'));
    }
  });

  test(
    'relay rejects business ports and paths before credential I/O',
    () async {
      for (final port in [0, 18080, 28080, 65536]) {
        final relay = DualRelay(port, 'A');
        addTearDown(relay.close);
        await expectLater(relay.request('/dual/config'), throwsStateError);
      }
      final relay = DualRelay(29001, 'A');
      addTearDown(relay.close);
      await expectLater(relay.request('/gift/send'), throwsStateError);
    },
  );

  test(
    'business test contains UI writes, read-only authority and no mock seams',
    () {
      final source = File(
        'integration_test/dual_first_party_business_test.dart',
      ).readAsStringSync();
      for (final forbidden in [
        '.sendGift(',
        '.sendPublicMessage(',
        '.sendPrivateMessage(',
        '.setFollowing(',
        '.toggleLike(',
        '.requestMic(',
        '.leaveMic(',
        '.enterRoom(',
        '.reconnectRoom(',
        '.leaveRoom(',
        '.exitRoom(',
        '.join(',
        'pumpQaPage(',
        'createQaDependencies(',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      for (final required in [
        'VideoRuntimeRoomPage(',
        'PublicProfilePage(',
        'DynamicDetailPage(',
        'tester.enterText(',
        'tester.tap(',
        'fetchGiftReceipt(',
        'fetchWalletSummary(',
        'fetchPublicMessages(',
        'fetchPrivateMessages(',
        'manual_room_reentry',
        '确认离开',
        'controller.dispose()',
        'automatic_http_sync_no_navigation',
        'DISABLED_NOT_TESTED',
      ]) {
        expect(source, contains(required), reason: required);
      }
      expect(dualPhases.toSet().length, dualPhases.length);
      expect(dualPhases.last, 'complete');
    },
  );

  test('candidate identity rejects missing or wrong SHA on either side', () {
    final valid = parse(runtimeConfig(), 'A');
    expect(valid.flutterSha, flutterSha);
    expect(valid.backendSha, backendSha);
    for (final field in ['flutterSha', 'backendSha']) {
      expect(
        () => parse(runtimeConfig()..remove(field), 'A'),
        throwsStateError,
      );
      for (final value in ['', 'short', List.filled(40, 'c').join()]) {
        expect(
          () => parse(runtimeConfig()..[field] = value, 'A'),
          throwsStateError,
        );
      }
    }
    for (final missingFlutter in [true, false]) {
      expect(
        () => DualConfig(
          runtimeConfig(),
          'A',
          expectedFlutterSha: missingFlutter ? '' : flutterSha,
          expectedBackendSha: missingFlutter ? backendSha : '',
        ),
        throwsStateError,
      );
    }
    expect(
      dualPhases,
      containsAllInOrder([
        'public-sent',
        'reentry-off-mic',
        'reentry-left',
        'manual_room_reentry',
        'gift-seated',
        'gift-A',
        'gift-B',
      ]),
    );
    expect(dualPhases, isNot(contains('public-read')));
  });
}
