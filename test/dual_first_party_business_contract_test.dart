import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

import '../integration_test/dual_first_party_business_support.dart';
import '../integration_test/dual_first_party_business_test.dart' as business;

void main() {
  test(
    'approval evidence rejects promotion, invite, wrong actor and wrong seat',
    () {
      MicAccessRequest request({
        RoomRole role = RoomRole.listener,
        MicRequestType type = MicRequestType.request,
        MicRequestStatus status = MicRequestStatus.approved,
        int resolver = 1,
        int subject = 2,
        int seat = 2,
        int? assigned = 2,
        String room = 'room',
      }) => MicAccessRequest(
        id: 'request',
        roomId: room,
        member: RoomMember(
          userId: 2,
          name: 'peer',
          role: role,
          presence: RoomMemberPresence.onMic,
        ),
        requestedByUserId: 2,
        subjectUserId: subject,
        type: type,
        status: status,
        seatNumber: seat,
        assignedSeatNumber: assigned,
        resolvedByUserId: resolver,
        createdAt: DateTime.utc(2026),
        resolvedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
      );
      void check(MicAccessRequest value, {int seat = 2}) =>
          business.expectDualApprovedRequest(
            value,
            roomId: 'room',
            applicant: 2,
            owner: 1,
            seat: seat,
          );
      for (final seat in List.generate(8, (i) => i + 2)) {
        check(
          request(seat: seat, assigned: seat),
          seat: seat,
        );
      }
      for (final invalid in [
        request(role: RoomRole.moderator),
        request(role: RoomRole.owner),
        request(type: MicRequestType.invite),
        request(status: MicRequestStatus.pending),
        request(status: MicRequestStatus.accepted),
        request(status: MicRequestStatus.expired),
        request(resolver: 2),
        request(subject: 3),
        request(assigned: null),
        request(assigned: 3),
        request(room: 'other'),
        request(seat: 1),
      ]) {
        expect(() => check(invalid), throwsA(isA<TestFailure>()));
      }
      expect(
        () => check(request(seat: 1, assigned: 1), seat: 1),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test(
    'gift income requires current currency and per-transfer exact amount',
    () {
      GiftReceipt receipt({
        String? currency = 'GIFT_COIN_TENTH',
        int? income = 105,
        int quantity = 3,
      }) => GiftReceipt(
        success: true,
        remainingBalance: null,
        quantity: quantity,
        creatorIncomeMinor: income,
        creatorIncomeCurrency: currency,
      );
      business.expectDualGiftIncome(
        receipt(),
        price: 7,
        quantity: 3,
        cashEligible: false,
      );
      business.expectDualGiftIncome(
        receipt(currency: 'CASH_CNY'),
        price: 7,
        quantity: 3,
        cashEligible: true,
      );
      for (final invalid in [
        receipt(currency: null),
        receipt(currency: 'CASH_CNY'),
        receipt(income: null),
        receipt(income: 104),
        receipt(quantity: 1),
      ]) {
        expect(
          () => business.expectDualGiftIncome(
            invalid,
            price: 7,
            quantity: 3,
            cashEligible: false,
          ),
          throwsA(isA<TestFailure>()),
        );
      }
    },
  );

  test(
    'pair settlement counts both chair commissions and exact ordinary tenths',
    () {
      final beforeA = _wallet('1000', 10, chair: true);
      final beforeB = _wallet('1001', 10);
      // One coin = 10 fen: each gift yields 5 fen to receiver, 1 fen to chair.
      business.expectDualGiftSettlement(
        before: beforeA,
        after: _wallet('990', 10.07, chair: true),
        price: 1,
        chair: true,
      );
      business.expectDualGiftSettlement(
        before: beforeB,
        after: _wallet('996', 10),
        price: 1,
        chair: false,
      );
      for (final invalid in [
        _wallet('990', 10.06, chair: true),
        _wallet('990', 10.08, chair: true),
        _wallet('989', 10.07, chair: true),
      ]) {
        expect(
          () => business.expectDualGiftSettlement(
            before: beforeA,
            after: invalid,
            price: 1,
            chair: true,
          ),
          throwsA(isA<TestFailure>()),
        );
      }
      expect(
        () => business.expectDualGiftSettlement(
          before: beforeB,
          after: _wallet('991', 10.05),
          price: 1,
          chair: false,
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => business.expectDualGiftSettlement(
          before: beforeB,
          after: _wallet('996', 10.001),
          price: 1,
          chair: false,
        ),
        throwsA(isA<TestFailure>()),
      );
      final huge = BigInt.parse('90071992547409931');
      business.expectDualGiftSettlement(
        before: _wallet('$huge', 0),
        after: _wallet('${huge - BigInt.from(5)}', 0),
        price: 1,
        chair: false,
      );
    },
  );
  final android = DualPlatformSupport.forTest(DualPlatform.android);
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
    platformForTest: android,
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
            .add(const Duration(minutes: 20, seconds: 30))
            .toIso8601String(),
        'session': {
          ...(runtimeConfig()['session'] as Map<String, dynamic>),
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 30))
              .toIso8601String(),
        },
      },
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
    expect(
      () => validateDualEnvironment(environment(), platformForTest: android),
      returnsNormally,
    );
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
      expect(
        () => validateDualEnvironment(env, platformForTest: android),
        throwsStateError,
      );
    }
    expect(
      () => validateDualEnvironment(environment(), release: true),
      throwsStateError,
    );
  });

  test('each runtime origin is accepted only on its actual platform', () {
    for (final platform in DualPlatform.values) {
      final support = DualPlatformSupport.forTest(platform);
      final roleB = DualConfig(
        runtimeConfig()..addAll({'role': 'B', 'apiBaseUrl': support.backend}),
        'B',
        expectedFlutterSha: flutterSha,
        expectedBackendSha: backendSha,
        platformForTest: support,
      );
      expect(roleB.peerRole, 'A');
      expect(roleB.flutterSha, flutterSha);
      for (final origin in [
        dualBackend,
        'http://127.0.0.1:28080/',
        'http://127.0.0.1:18080/',
        'http://localhost:28080/',
        'https://example.com/',
        '${support.backend}?x=1',
      ]) {
        final accepted = origin == support.backend;
        expect(
          () => validateDualEnvironment(
            environment(url: origin),
            platformForTest: support,
          ),
          accepted ? returnsNormally : throwsStateError,
        );
        expect(
          () => DualConfig(
            runtimeConfig()..['apiBaseUrl'] = origin,
            'A',
            expectedFlutterSha: flutterSha,
            expectedBackendSha: backendSha,
            platformForTest: support,
          ),
          accepted ? returnsNormally : throwsStateError,
        );
      }
      expect(
        () => DualConfig(
          runtimeConfig()..['apiBaseUrl'] = support.backend,
          'B',
          expectedFlutterSha: flutterSha,
          expectedBackendSha: backendSha,
          platformForTest: support,
        ),
        throwsStateError,
      );
    }
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
        '.resolveMicRequest(',
        '.setManager(',
        '.assignMic(',
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

  test(
    'both seat rounds require ordinary application and owner UI approval',
    () {
      final source = File(
        'integration_test/dual_first_party_business_test.dart',
      ).readAsStringSync();
      expect(
        'await _seatPairThroughApproval('.allMatches(source),
        hasLength(2),
      );
      for (final required in [
        'approval-mic-seat-',
        "find.text('同意')",
        'fetchRoomAuthority(',
        'expectDualApprovedRequest(',
        'expectDualGiftSettlement(',
        'IncomeRole.ordinary',
        'IncomeRole.guildChair',
      ]) {
        expect(source, contains(required), reason: required);
      }
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

WalletSummary _wallet(String tenths, double cash, {bool chair = false}) =>
    WalletSummary(
      giftCoinBalance: null,
      coinPrecision: GiftCoinBalance(
        available: GiftCoinAmount.fromTenths(tenths),
        frozen: const GiftCoinAmount.whole(0),
      ),
      incomeCapability: IncomeCapability(
        chair ? IncomeRole.guildChair : IncomeRole.ordinary,
        chair,
        chair,
      ),
      cashBalance: cash,
      frozenBalance: 0,
      totalEarnings: 0,
      yesterdayEarnings: 0,
      totalWithdrawn: 0,
      realNameVerified: true,
      bankCard: null,
      agentEarnings: null,
      superAgentEarnings: null,
    );
