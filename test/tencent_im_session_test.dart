import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/im/application/im_session_coordinator.dart';
import 'package:voice_social_app/features/im/data/backend_im_session_credential_repository.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';
import 'package:voice_social_app/features/im/infrastructure/tencent_im_session_adapter.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  group('IM credential contract', () {
    test('parses the exact allow-listed envelope data', () {
      final ImSessionCredentials credentials = ImSessionCredentials.parse(
        _credentialData(now: now),
        now: now,
      );

      expect(credentials.provider, 'tencent-im');
      expect(credentials.sdkAppId, 1400000000);
      expect(credentials.userId, 'u-123');
      expect(credentials.ttlSeconds, 3600);
      expect(credentials.imStatus, 'READY');
      expect(credentials.systemAccount, 'administrator');
      expect(credentials.isExpired(now), isFalse);
      expect(credentials.toRedactedJson(), isNot(contains('u-123')));
      expect(credentials.toRedactedJson(), isNot(contains('userSig')));
      expect(credentials.toRedactedJson(), isNot(contains(credentialSig)));
      expect(credentials.toRedactedJson(), isNot(contains('1400000000')));
      expect(credentials.toString(), isNot(contains(credentialSig)));
      expect(credentials.toString(), isNot(contains('1400000000')));
    });

    test('rejects fields outside the frozen response allow-list', () {
      expect(
        () => ImSessionCredentials.parse(<String, Object?>{
          ..._credentialData(now: now),
          'uid': 123,
        }, now: now),
        throwsA(
          isA<ImCredentialException>().having(
            (ImCredentialException error) => error.failure,
            'failure',
            ImCredentialFailure.unknownField,
          ),
        ),
      );
      expect(
        () => ImSessionCredentials.parse(<String, Object?>{
          ..._credentialData(now: now),
          // The backend contract has one canonical public sender field.  Do
          // not accept a second alias that could drift from systemAccount.
          'hintSenderUserId': 'administrator',
        }, now: now),
        throwsA(
          isA<ImCredentialException>().having(
            (ImCredentialException error) => error.failure,
            'failure',
            ImCredentialFailure.unknownField,
          ),
        ),
      );
    });

    test('validates the public system sender separately from UserSig', () {
      for (final String account in <String>[
        '',
        'administrator with whitespace',
        'admin\n',
        'u-123',
        'u-0',
        'system-',
        List<String>.filled(33, 'x').join(),
      ]) {
        expect(
          () => ImSessionCredentials.parse(<String, Object?>{
            ..._credentialData(now: now),
            'systemAccount': account,
          }, now: now),
          throwsA(isA<ImCredentialException>()),
          reason: 'invalid system sender must fail closed: $account',
        );
      }
    });

    test('accepts explicit system senders but never a user namespace', () {
      expect(ImSessionCredentials.isValidSystemAccount('system-im'), isTrue);
      expect(
        ImSessionCredentials.isValidSystemAccount('administrator'),
        isTrue,
      );
      expect(ImSessionCredentials.isValidSystemAccount('u-123'), isFalse);
    });

    test('enforces bounded UserSig, ttl and internally consistent expiry', () {
      final Map<String, Object?> valid = _credentialData(now: now);
      for (final String sig in <String>[
        '',
        'short',
        'sig_123456789012\n',
        'sig_123456789012+',
        List<String>.filled(
          ImSessionCredentials.maximumUserSigLength + 1,
          'x',
        ).join(),
      ]) {
        expect(
          () => ImSessionCredentials.parse(<String, Object?>{
            ...valid,
            'userSig': sig,
          }, now: now),
          throwsA(isA<ImCredentialException>()),
          reason: 'invalid UserSig must fail closed: ${sig.length}',
        );
      }
      for (final int ttl in <int>[
        ImSessionCredentials.minimumTtlSeconds - 1,
        ImSessionCredentials.maximumTtlSeconds + 1,
      ]) {
        expect(
          () => ImSessionCredentials.parse(<String, Object?>{
            ...valid,
            'ttlSeconds': ttl,
          }, now: now),
          throwsA(isA<ImCredentialException>()),
        );
      }
      expect(
        () => ImSessionCredentials.parse(<String, Object?>{
          ...valid,
          'expiresAt': now.add(const Duration(hours: 2)).toIso8601String(),
        }, now: now),
        throwsA(isA<ImCredentialException>()),
      );
    });

    test('accepts signed-long event versions and rejects overflow', () {
      final ImRefreshHint? int32Boundary = ImRefreshHint.tryParse(
        <String, Object?>{
          'messageId': 'private-message-1',
          'eventVersion': 0x80000000,
        },
        trustedSource: true,
      );
      expect(int32Boundary?.eventVersion, 0x80000000);

      final ImRefreshHint? signedLongMaximum =
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private-message-2',
            'eventVersion': ImRefreshHint.maximumEventVersion,
          }, trustedSource: true);
      expect(
        signedLongMaximum?.eventVersion,
        ImRefreshHint.maximumEventVersion,
      );
      expect(
        ImRefreshHint.tryParse(<String, Object?>{
          'messageId': 'private-message-3',
          'eventVersion': ImRefreshHint.maximumEventVersion + 1,
        }, trustedSource: true),
        isNull,
      );
      expect(
        ImRefreshHint.tryParse(<String, Object?>{
          'messageId': 'private-message-4',
          'eventVersion': 0,
        }, trustedSource: true),
        isNull,
      );
    });

    test(
      'maps only positive platform ids to the deterministic provider id',
      () {
        expect(ImSessionCredentials.userIdForPlatformUserId(123), 'u-123');
        expect(ImSessionCredentials.isCanonicalUserId('u-123'), isTrue);
        expect(ImSessionCredentials.isCanonicalUserId('u-00123'), isFalse);
        expect(ImSessionCredentials.isCanonicalUserId('u-124'), isTrue);
        expect(
          () => ImSessionCredentials.userIdForPlatformUserId(0),
          throwsArgumentError,
        );
        expect(
          () => ImSessionCredentials.userIdForPlatformUserId(-1),
          throwsArgumentError,
        );
      },
    );
  });

  group('Tencent adapter lifecycle', () {
    test(
      'initializes once, logs in idempotently, renews and tears down',
      () async {
        final _RecordingSdk sdk = _RecordingSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(seconds: 1),
        );
        addTearDown(adapter.dispose);
        final ImSessionCredentials first = _credentials(now: now);
        final ImSessionCredentials renewed = _credentials(
          now: now,
          userSig: 'sig_renewed_123456',
        );

        await adapter.initialize(first);
        await adapter.initialize(first);
        await adapter.login(first);
        await adapter.login(first);
        expect(sdk.initCalls, 1);
        expect(sdk.loginCalls, 1);
        expect(sdk.lastUserId, 'u-123');
        expect(sdk.lastUserSig, credentialSig);
        expect(adapter.isReady, isTrue);

        await adapter.renew(renewed);
        expect(sdk.logoutCalls, 1);
        expect(sdk.initCalls, 1);
        expect(sdk.loginCalls, 2);
        expect(adapter.credentials?.userSig, renewed.userSig);

        await adapter.logout();
        await adapter.uninitialize();
        expect(adapter.credentials, isNull);
        expect(adapter.isReady, isFalse);
        expect(adapter.status, ImSessionStatus.idle);
        expect(sdk.uninitCalls, 1);
      },
    );

    test('rejects a system sender that equals the authenticated user', () {
      final _RecordingSdk sdk = _RecordingSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(seconds: 1),
      );
      addTearDown(adapter.dispose);
      final ImSessionCredentials invalid = ImSessionCredentials(
        provider: ImSessionCredentials.expectedProvider,
        sdkAppId: 1400000000,
        userId: 'u-123',
        userSig: credentialSig,
        expiresAt: now.add(const Duration(hours: 1)),
        ttlSeconds: 3600,
        imStatus: ImSessionCredentials.readyStatus,
        systemAccount: 'u-123',
      );

      expect(
        () => adapter.login(invalid),
        throwsA(
          isA<ImSessionException>().having(
            (ImSessionException error) => error.failure,
            'failure',
            ImSessionFailure.invalidCredentials,
          ),
        ),
      );
    });

    test(
      'rejects a mismatched identity before invoking the provider',
      () async {
        final _RecordingSdk sdk = _RecordingSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(seconds: 1),
        );
        addTearDown(adapter.dispose);
        await adapter.login(_credentials(now: now));

        expect(
          () => adapter.renew(
            _credentials(
              now: now,
              userId: 'u-124',
              userSig: 'sig_other_123456',
            ),
          ),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.identityMismatch,
            ),
          ),
        );
        expect(sdk.loginCalls, 1);
        expect(sdk.logoutCalls, 0);
        expect(adapter.activeUserId, 'u-123');
      },
    );

    test(
      'provider calls are bounded and timeout failures clear memory',
      () async {
        final _HangingSdk sdk = _HangingSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 10),
        );
        addTearDown(adapter.dispose);
        final ImSessionCredentials credentials = _credentials(now: now);

        await expectLater(
          adapter.initialize(credentials),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.initialize,
            ),
          ),
        );
        expect(adapter.credentials, isNull);
        expect(adapter.isReady, isFalse);

        // Seed a logged-in state using a non-hanging provider, then make the
        // logout call hang.  The adapter must still erase the in-memory secret.
        final _RecordingSdk workingSdk = _RecordingSdk();
        final TencentImSessionAdapter workingAdapter = TencentImSessionAdapter(
          sdkClient: workingSdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 10),
        );
        await workingAdapter.login(credentials);
        workingSdk.hangLogout = true;
        await expectLater(
          workingAdapter.logout(),
          throwsA(isA<ImSessionException>()),
        );
        expect(workingAdapter.credentials, isNull);
        expect(workingAdapter.isReady, isFalse);
        await workingAdapter.dispose();
      },
    );

    test(
      'refreshes expiry metadata even when the server repeats UserSig',
      () async {
        final _RecordingSdk sdk = _RecordingSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(seconds: 1),
        );
        addTearDown(adapter.dispose);
        final ImSessionCredentials first = _credentials(now: now);
        final ImSessionCredentials extended = _credentials(
          now: now,
          expiresAt: now.add(const Duration(hours: 2)),
          ttlSeconds: 7200,
        );

        await adapter.login(first);
        await adapter.renew(extended);
        expect(adapter.credentials?.expiresAt, extended.expiresAt);
        expect(adapter.credentials?.ttlSeconds, 7200);
        expect(sdk.loginCalls, 2);
      },
    );

    test(
      'trusts only the credential system sender for C2C refresh hints',
      () async {
        final _EventRecordingSdk sdk = _EventRecordingSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(seconds: 1),
        );
        final List<ImSessionEvent> events = <ImSessionEvent>[];
        final StreamSubscription<ImSessionEvent> subscription = adapter.events
            .listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await adapter.dispose();
          await sdk.dispose();
        });

        await adapter.login(_credentials(now: now));
        expect(
          adapter.isTrustedHintSender(
            senderUserId: 'administrator',
            groupId: null,
            isSelf: false,
          ),
          isTrue,
        );
        expect(
          adapter.isTrustedHintSender(
            senderUserId: 'u-123',
            groupId: null,
            isSelf: false,
          ),
          isFalse,
        );
        expect(
          adapter.isTrustedHintSender(
            senderUserId: 'administrator',
            groupId: null,
            isSelf: true,
          ),
          isFalse,
        );
        expect(
          adapter.isTrustedHintSender(
            senderUserId: 'administrator',
            groupId: 'room-1',
            isSelf: false,
          ),
          isFalse,
        );

        sdk.emit(
          TencentImSdkEvent.customElement(
            data: jsonEncode(<String, Object?>{
              'messageId': 'private-message-1',
              'eventVersion': 0x80000000,
            }),
            trustedFirstParty: true,
            senderUserId: 'administrator',
            isSelf: false,
          ),
        );
        sdk.emit(
          TencentImSdkEvent.customElement(
            data: jsonEncode(<String, Object?>{
              'messageId': 'private-message-2',
              'eventVersion': 2,
            }),
            trustedFirstParty: true,
            senderUserId: 'u-123',
            isSelf: false,
          ),
        );
        sdk.emit(
          TencentImSdkEvent.customElement(
            data: jsonEncode(<String, Object?>{
              'messageId': 'private-message-3',
              'eventVersion': 3,
            }),
            trustedFirstParty: true,
            senderUserId: 'administrator',
            isSelf: true,
          ),
        );
        sdk.emit(
          TencentImSdkEvent.customElement(
            data: jsonEncode(<String, Object?>{
              'messageId': 'private-message-4',
              'eventVersion': 4,
            }),
            trustedFirstParty: true,
            senderUserId: 'administrator',
            groupId: 'room-1',
            isSelf: false,
          ),
        );

        expect(events, hasLength(1));
        expect(events.single.kind, ImSessionEventKind.refreshHint);
        expect(events.single.refreshHint?.messageId, 'private-message-1');
        expect(events.single.refreshHint?.eventVersion, 0x80000000);
      },
    );
  });

  group('coordinator lifecycle and identity contract', () {
    test(
      'session userId=123 accepts u-123 and rejects u-124/malformed values',
      () async {
        final AuthSession session = _session(userId: 123);
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
        );
        final _MutableCredentialRepository repository =
            _MutableCredentialRepository(_credentials(now: now));
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: repository,
          now: () => now,
        );
        addTearDown(coordinator.dispose);

        await coordinator.ensureAuthenticated(session);
        expect(coordinator.realtimeReady, isTrue);
        expect(adapter.activeUserId, 'u-123');

        await coordinator.logout();
        repository.credentials = _credentials(now: now, userId: 'u-124');
        await expectLater(
          coordinator.ensureAuthenticated(session),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.identityMismatch,
            ),
          ),
        );
        expect(coordinator.realtimeReady, isFalse);

        await coordinator.logout();
        repository.credentials = _rawCredentials(now: now, userId: '123');
        await expectLater(
          coordinator.ensureAuthenticated(session),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.invalidCredentials,
            ),
          ),
        );
        expect(coordinator.realtimeReady, isFalse);
      },
    );

    test('same-user credential fetches are single-flight', () async {
      final _DelayedCredentialRepository repository =
          _DelayedCredentialRepository(_credentials(now: now));
      final FakeImSessionAdapter adapter = FakeImSessionAdapter(now: () => now);
      final ImSessionCoordinator coordinator = ImSessionCoordinator(
        adapter: adapter,
        credentialsRepository: repository,
        now: () => now,
      );
      addTearDown(coordinator.dispose);
      final AuthSession session = _session(userId: 123);

      final Future<void> first = coordinator.ensureAuthenticated(session);
      final Future<void> second = coordinator.ensureAuthenticated(session);
      expect(identical(first, second), isTrue);
      expect(repository.fetchCalls, 1);
      repository.release.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(adapter.loginCalls, 1);
    });

    test('logout wins a restore/login race and leaves adapter idle', () async {
      final _DelayedCredentialRepository repository =
          _DelayedCredentialRepository(_credentials(now: now));
      final FakeImSessionAdapter adapter = FakeImSessionAdapter(now: () => now);
      final ImSessionCoordinator coordinator = ImSessionCoordinator(
        adapter: adapter,
        credentialsRepository: repository,
        now: () => now,
      );
      addTearDown(coordinator.dispose);
      final Future<void> restore = coordinator.restore(_session(userId: 123));
      await repository.started.future;
      await coordinator.logout();
      repository.release.complete();
      await restore;

      expect(adapter.credentials, isNull);
      expect(adapter.isReady, isFalse);
      expect(coordinator.realtimeReady, isFalse);
    });

    test('near-expiry sessions are not reported as long-lived ready', () async {
      final ImSessionCredentials expiring = _credentials(
        now: now,
        expiresAt: now.add(const Duration(minutes: 4)),
        ttlSeconds: 240,
      );
      final FakeImSessionAdapter adapter = FakeImSessionAdapter(now: () => now);
      final ImSessionCoordinator coordinator = ImSessionCoordinator(
        adapter: adapter,
        credentialsRepository: _MutableCredentialRepository(expiring),
        now: () => now,
      );
      addTearDown(coordinator.dispose);
      await coordinator.ensureAuthenticated(_session(userId: 123));

      // The gateway must trigger ensureAuthenticated again before opening a
      // long-lived stream; a credential within the renewal window is fail
      // closed until that refresh completes.
      expect(coordinator.realtimeReady, isFalse);
    });
  });

  group('backend credential contract', () {
    test(
      'POSTs no uid/body, carries request id, and aggregates Cache-Control',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        final Completer<void> handled = Completer<void>();
        server.listen((HttpRequest request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, BackendRouteCatalog().imCredential);
          expect(request.uri.query, isEmpty);
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer first-party',
          );
          expect(request.headers.value('X-Request-Id'), isNotEmpty);
          expect(request.headers.value('Cache-Control'), 'no-store');
          expect(await utf8.decoder.bind(request).join(), isEmpty);
          request.response.headers.contentType = ContentType.json;
          request.response.headers.add('Cache-Control', 'max-age=0');
          request.response.headers.add('Cache-Control', 'no-store');
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': _credentialData(now: now),
            }),
          );
          await request.response.close();
          handled.complete();
        });

        final ApiClient client = ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer first-party',
        );
        final BackendImSessionCredentialRepository repository =
            BackendImSessionCredentialRepository(
              apiClient: client,
              now: () => now,
            );
        final ImSessionCredentials credentials = await repository.fetch();
        await handled.future;
        expect(credentials.userId, 'u-123');
        expect(credentials.sdkAppId, 1400000000);
      },
    );

    test(
      'the live response identity is bound to first-party session 123',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        String responseUserId = 'u-123';
        server.listen((HttpRequest request) async {
          request.response
            ..headers.contentType = ContentType.json
            ..headers.set('Cache-Control', 'no-store')
            ..write(
              jsonEncode(<String, Object?>{
                'code': 200,
                'message': 'OK',
                'data': _credentialData(now: now, userId: responseUserId),
              }),
            );
          await request.response.close();
        });

        final ApiClient client = ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer first-party',
        );
        final BackendImSessionCredentialRepository repository =
            BackendImSessionCredentialRepository(
              apiClient: client,
              now: () => now,
            );
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
        );
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: repository,
          now: () => now,
        );
        addTearDown(coordinator.dispose);
        final AuthSession session = _session(userId: 123);

        await coordinator.ensureAuthenticated(session);
        expect(coordinator.realtimeReady, isTrue);
        expect(adapter.activeUserId, 'u-123');

        await coordinator.logout();
        responseUserId = 'u-124';
        await expectLater(
          coordinator.ensureAuthenticated(session),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.identityMismatch,
            ),
          ),
        );

        await coordinator.logout();
        responseUserId = 'malformed-user-id';
        await expectLater(
          coordinator.ensureAuthenticated(session),
          throwsA(
            isA<ImSessionException>().having(
              (ImSessionException error) => error.failure,
              'failure',
              ImSessionFailure.invalidCredentials,
            ),
          ),
        );
        expect(coordinator.realtimeReady, isFalse);
      },
    );
  });

  group('dependency feature gate and auth integration', () {
    test(
      'live defaults to blocked and production requires explicit opt-in',
      () {
        final AppEnvironment environment = _liveEnvironment();
        final AppDependencies blocked = AppDependencies.forTestEnvironment(
          environment: environment,
        );
        expect(blocked.imSessionAdapter, isA<BlockedImSessionAdapter>());
        expect(
          blocked.imSessionCredentialRepository,
          isA<BlockedImSessionCredentialRepository>(),
        );

        final AppDependencies enabled = AppDependencies.forTestEnvironment(
          environment: _liveEnvironment(enableTencentIm: true),
        );
        expect(enabled.imSessionAdapter, isA<TencentImSessionAdapter>());
        expect(
          enabled.imSessionCredentialRepository,
          isA<BackendImSessionCredentialRepository>(),
        );
      },
    );

    test(
      'first-party auth remains signed in while IM failure is fail-closed',
      () async {
        final AuthSessionManager sessionManager = AuthSessionManager(
          MemoryKeyValueStore(),
        );
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
          failLogin: true,
        );
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: _MutableCredentialRepository(
            _credentials(now: now),
          ),
          now: () => now,
        );
        final AuthController controller = AuthController(
          repository: const MockAuthRepository(),
          sessionManager: sessionManager,
          deviceIdentityProvider: DeviceIdentityProvider(
            environment: AppEnvironment.mock(),
            sessionManager: sessionManager,
          ),
          imSessionCoordinator: coordinator,
        );
        addTearDown(controller.dispose);
        addTearDown(coordinator.dispose);

        await controller.initialize();
        expect(controller.stage, AuthFlowStage.consentRequired);
        expect(adapter.initializeCalls, 0);
        expect(adapter.loginCalls, 0);

        await controller.acceptConsent();
        expect(
          await controller.signInWithSms(
            phone: '13800138000',
            smsCode: '123456',
          ),
          isTrue,
        );
        expect(controller.stage, AuthFlowStage.signedIn);
        expect(coordinator.realtimeReady, isFalse);
        await controller.signOut();
        expect(adapter.credentials, isNull);
      },
    );
  });
}

const String credentialSig = 'sig_123456789012';

Map<String, Object?> _credentialData({
  required DateTime now,
  String userId = 'u-123',
  String userSig = credentialSig,
  DateTime? expiresAt,
  int ttlSeconds = 3600,
  String systemAccount = 'administrator',
}) => <String, Object?>{
  'provider': 'tencent-im',
  'sdkAppId': 1400000000,
  'userId': userId,
  'userSig': userSig,
  'expiresAt': (expiresAt ?? now.add(Duration(seconds: ttlSeconds)))
      .toIso8601String(),
  'ttlSeconds': ttlSeconds,
  'imStatus': 'READY',
  'systemAccount': systemAccount,
};

ImSessionCredentials _credentials({
  required DateTime now,
  String userId = 'u-123',
  String userSig = credentialSig,
  DateTime? expiresAt,
  int ttlSeconds = 3600,
  String systemAccount = 'administrator',
}) => ImSessionCredentials.fromBackendData(
  _credentialData(
    now: now,
    userId: userId,
    userSig: userSig,
    expiresAt: expiresAt,
    ttlSeconds: ttlSeconds,
    systemAccount: systemAccount,
  ),
  now: now,
);

ImSessionCredentials _rawCredentials({
  required DateTime now,
  String userId = 'u-123',
}) => ImSessionCredentials(
  provider: 'tencent-im',
  sdkAppId: 1400000000,
  userId: userId,
  userSig: credentialSig,
  expiresAt: now.add(const Duration(hours: 1)),
  ttlSeconds: 3600,
  imStatus: 'READY',
  systemAccount: 'administrator',
);

AuthSession _session({required int userId}) => AuthSession(
  accessToken: 'access-$userId',
  tokenType: 'Bearer',
  expiresAt: DateTime.utc(2030, 1, 1, 13),
  refreshToken: 'refresh-$userId',
  refreshExpiresAt: DateTime.utc(2030, 1, 2),
  deviceId: 'device-$userId',
  userId: userId,
  mobile: '13800138000',
  roles: 'USER',
);

AppEnvironment _liveEnvironment({bool enableTencentIm = false}) =>
    AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'http://127.0.0.1:18080/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
      allowInsecureHttp: true,
      enableTencentIm: enableTencentIm,
    );

class _MutableCredentialRepository extends ImSessionCredentialRepository {
  _MutableCredentialRepository(this.credentials);

  ImSessionCredentials credentials;

  @override
  Future<ImSessionCredentials> fetch() async => credentials;
}

class _DelayedCredentialRepository extends ImSessionCredentialRepository {
  _DelayedCredentialRepository(this.credentials);

  final ImSessionCredentials credentials;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  int fetchCalls = 0;

  @override
  Future<ImSessionCredentials> fetch() async {
    fetchCalls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
    return credentials;
  }
}

class _RecordingSdk implements TencentImSdkClient {
  int initCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;
  int uninitCalls = 0;
  String? lastUserId;
  String? lastUserSig;
  bool hangLogout = false;

  @override
  Future<bool> initSdk({required int sdkAppId}) async {
    initCalls += 1;
    return true;
  }

  @override
  Future<int> login({required String userId, required String userSig}) async {
    loginCalls += 1;
    lastUserId = userId;
    lastUserSig = userSig;
    return 0;
  }

  @override
  Future<int> logout() {
    logoutCalls += 1;
    if (hangLogout) {
      return Completer<int>().future;
    }
    return Future<int>.value(0);
  }

  @override
  Future<int> uninitSdk() async {
    uninitCalls += 1;
    return 0;
  }
}

class _HangingSdk implements TencentImSdkClient {
  @override
  Future<bool> initSdk({required int sdkAppId}) => Completer<bool>().future;

  @override
  Future<int> login({required String userId, required String userSig}) =>
      Completer<int>().future;

  @override
  Future<int> logout() => Completer<int>().future;

  @override
  Future<int> uninitSdk() => Completer<int>().future;
}

class _EventRecordingSdk
    implements TencentImSdkClient, TencentImSdkEventSource {
  final StreamController<TencentImSdkEvent> _events =
      StreamController<TencentImSdkEvent>.broadcast(sync: true);

  @override
  Stream<TencentImSdkEvent> get events => _events.stream;

  @override
  Future<bool> initSdk({required int sdkAppId}) async => true;

  @override
  Future<int> login({required String userId, required String userSig}) async =>
      0;

  @override
  Future<int> logout() async => 0;

  @override
  Future<int> uninitSdk() async => 0;

  void emit(TencentImSdkEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> dispose() => _events.close();
}
