import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/registration_avatar.dart';
import 'support/media_http_fakes.dart';

const _challenge = '00000000-0000-4000-8000-000000000001';
RegistrationProfile _profile({int sex = 0, bool avatar = true}) =>
    RegistrationProfile(
      nickname: '鲸',
      sex: sex,
      avatar: avatar
          ? RegistrationAvatarChoice.preset('avatar-preset-sea')
          : null,
    );

void main() {
  test(
    'new user cannot reuse a missing or another phone SMS challenge',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      expect(
        await fixture.controller.signInWithSms(
          phone: '13900000000',
          smsCode: '123456',
        ),
        isFalse,
      );
      await fixture.controller.sendSmsCode('13800000000');
      expect(
        await fixture.controller.signInWithSms(
          phone: '13900000000',
          smsCode: '123456',
        ),
        isFalse,
      );
      expect(fixture.repository.proofs, isEmpty);
    },
  );

  test(
    'missing avatar and invalid explicit sex never reach registration',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      await fixture.ready();
      expect(
        await fixture.controller.completeRegistration(_profile(avatar: false)),
        isFalse,
      );
      expect(
        await fixture.controller.completeRegistration(_profile(sex: -1)),
        isFalse,
      );
      expect(
        await fixture.controller.completeRegistration(_profile(sex: 3)),
        isFalse,
      );
      expect(fixture.repository.proofs, isEmpty);
    },
  );

  test(
    'unknown registration preserves the same challenge and request id',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      await fixture.ready();
      fixture.repository.failNext = true;
      expect(
        await fixture.controller.completeRegistration(_profile()),
        isFalse,
      );
      expect(fixture.repository.proofs, hasLength(1));
      expect(fixture.controller.stage, AuthFlowStage.registrationRequired);
      expect(await fixture.controller.completeRegistration(_profile()), isTrue);
      expect(fixture.repository.proofs, hasLength(2));
      expect(
        fixture.repository.proofs.last.requestId,
        fixture.repository.proofs.first.requestId,
      );
      expect(fixture.repository.proofs.last.challengeId, _challenge);
      expect(fixture.repository.proofs.last.avatarCapability, isNull);
      expect(fixture.controller.session, isNotNull);
    },
  );

  test('new SMS request invalidates an old registration proof', () async {
    final fixture = _Fixture();
    addTearDown(fixture.controller.dispose);
    await fixture.ready();
    fixture.repository.failNext = true;
    await fixture.controller.completeRegistration(_profile());
    final old = fixture.repository.proofs.single;
    await fixture.controller.sendSmsCode('13900000000');
    expect(old.requireCurrent, throwsA(isA<ApiException>()));
    expect(await fixture.controller.completeRegistration(_profile()), isFalse);
    expect(fixture.repository.proofs, hasLength(1));
  });

  test('cancelled registration cannot publish a late server session', () async {
    final fixture = _Fixture();
    addTearDown(fixture.controller.dispose);
    await fixture.ready();
    final release = Completer<void>();
    fixture.repository.delay = release;
    final result = fixture.controller.completeRegistration(_profile());
    await fixture.repository.started.future;
    fixture.controller.cancelRegistration();
    release.complete();
    expect(await result, isFalse);
    expect(fixture.controller.session, isNull);
    expect(fixture.controller.stage, AuthFlowStage.signedOut);
  });

  test(
    'anonymous bound request never sends injected bearer or follows redirects',
    () async {
      final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
      final api = ApiClient(
        baseUri: Uri.parse('https://configured.backend.test'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer must-not-send',
        requestHeadersProvider: () => {
          'Authorization': 'Bearer injected',
          'Content-Encoding': 'gzip',
        },
        httpClient: http,
      );
      await api.postAnonymousBound(
        '/app-register-api/test',
        requireCurrent: () {},
        headers: {
          'X-Request-Id': 'original-key',
          'X-Registration-Avatar-Capability': 'header-only',
        },
        body: {'challengeId': _challenge},
      );
      final request = http.requests.single;
      expect(request.headers.value('Authorization'), isNull);
      expect(request.headers.value('Content-Encoding'), isNull);
      expect(request.headers.value('X-Request-Id'), 'original-key');
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 0);
      expect(jsonDecode(utf8.decode(request.body)), {
        'challengeId': _challenge,
      });
    },
  );

  test(
    'anonymous 401 does not invoke authenticated refresh or replay',
    () async {
      var refreshes = 0;
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json(null, status: 401, code: 401),
      );
      final api = http.api(
        actor,
        refresh: () async {
          refreshes++;
          return true;
        },
      );
      await expectLater(
        api.postAnonymousBound('/app-register-api/test', requireCurrent: () {}),
        throwsA(isA<ApiException>()),
      );
      expect(http.requests, hasLength(1));
      expect(refreshes, 0);
    },
  );

  test(
    'registration change while opening connection aborts before body',
    () async {
      final opened = Completer<void>(), release = Completer<void>();
      var valid = true;
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
      http.beforeOpen = (_) async {
        opened.complete();
        await release.future;
      };
      final api = http.api(actor);
      final result = expectLater(
        api.postAnonymousBound(
          '/app-register-api/test',
          requireCurrent: () {
            if (!valid) throw registrationChoiceInvalid;
          },
          body: {'challengeId': _challenge},
        ),
        throwsA(isA<ApiException>()),
      );
      await opened.future;
      valid = false;
      release.complete();
      await result;
      expect(http.requests.single.aborted, isTrue);
      expect(http.requests.single.closes, 0);
      expect(http.requests.single.body, isEmpty);
    },
  );

  test('avatar identifiers and capabilities reject noncanonical spellings', () {
    for (final id in [
      _challenge.toUpperCase().replaceFirst('0000', 'AAAA'),
      '$_challenge\n',
      'https://example.invalid/a',
      '1-1-1-1-1',
    ]) {
      expect(
        () => RegistrationAvatarChoice.uploaded(id, 0),
        throwsA(isA<ApiException>()),
      );
    }
    final uploaded = RegistrationAvatarChoice.uploaded(_challenge, 0);
    for (final capability in ['a' * 42, 'a' * 43, '${'A' * 43}\n']) {
      expect(
        () => RegistrationProof(
          challengeId: _challenge,
          requestId: 'key',
          requireCurrent: () {},
          avatarCapability: capability,
        ).validate(uploaded),
        throwsA(isA<ApiException>()),
      );
    }
    RegistrationProof(
      challengeId: _challenge,
      requestId: 'key',
      requireCurrent: () {},
      avatarCapability: 'A' * 43,
    ).validate(uploaded);
    expect(uploaded.toJson(), {
      'kind': 'UPLOADED',
      'reference': _challenge,
      'expectedVersion': 0,
    });
  });
}

class _Fixture {
  _Fixture() {
    final manager = AuthSessionManager(MemoryKeyValueStore());
    controller = AuthController(
      repository: repository,
      sessionManager: manager,
      deviceIdentityProvider: DeviceIdentityProvider(
        environment: AppEnvironment.mock(),
        sessionManager: manager,
      ),
    );
  }
  final repository = _Repository();
  late final AuthController controller;
  Future<void> ready() async {
    await controller.acceptConsent();
    await controller.sendSmsCode('13900000000');
    expect(
      await controller.signInWithSms(phone: '13900000000', smsCode: '123456'),
      isTrue,
    );
  }
}

class _Repository extends MockAuthRepository {
  final proofs = <RegistrationProof>[];
  final started = Completer<void>();
  Completer<void>? delay;
  bool failNext = false;
  @override
  Future<SmsChallenge> sendSmsCode({
    required String phone,
    required ClientDevice device,
  }) async => SmsChallenge(
    challengeId: _challenge,
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    retryAfter: 60,
  );
  @override
  Future<AuthSession> registerWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
    required RegistrationProfile profile,
    RegistrationProof? proof,
  }) async {
    proofs.add(proof!);
    if (!started.isCompleted) started.complete();
    await delay?.future;
    if (failNext) {
      failNext = false;
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'unknown',
      );
    }
    // Deliberately return even after cancellation to exercise the controller fence.
    return super.registerWithSms(
      phone: phone,
      smsCode: smsCode,
      device: device,
      profile: profile,
    );
  }
}
