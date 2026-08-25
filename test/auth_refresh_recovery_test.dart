import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_refresh_recovery.dart';

void main() {
  test(
    'pending refresh metadata is secure, bounded, and secret-free',
    () async {
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      final AuthSessionManager manager = AuthSessionManager(store);
      final AuthSession session = _expiredSession();
      final DateTime now = DateTime.utc(2026, 8, 25, 12);

      final PendingAuthRefresh pending = await manager.prepareRefreshRequest(
        session: session,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-fixed-001',
        now: now,
      );

      expect(pending.requestId, 'flutter-auth-refresh-fixed-001');
      expect(pending.createdAt, now);
      expect(
        pending.expiresAt,
        now.add(AuthSessionManager.refreshRecoveryWindow),
      );

      final String? encoded = await store.read(
        AuthSessionManager.pendingRefreshStorageKey,
      );
      expect(encoded, isNotNull);
      expect(encoded, isNot(contains(session.refreshToken)));
      final Map<String, Object?> persisted = Map<String, Object?>.from(
        jsonDecode(encoded!) as Map,
      );
      expect(
        persisted.keys,
        containsAll(<String>[
          'schema',
          'requestId',
          'sessionFingerprint',
          'createdAt',
          'expiresAt',
        ]),
      );
      expect(
        persisted['sessionFingerprint'],
        '1e12a389926f68ba828f4e5dec93f6974737789b0edd82be46857146375b34ff',
      );
    },
  );

  test('a fresh process reuses a valid pending request id', () async {
    final MemoryKeyValueStore store = MemoryKeyValueStore();
    final AuthSession session = _expiredSession();
    final DateTime now = DateTime.utc(2026, 8, 25, 12);
    final AuthSessionManager firstProcess = AuthSessionManager(store);
    await firstProcess.prepareRefreshRequest(
      session: session,
      clientId: 'voice-social-mobile-public',
      requestIdFactory: () => 'flutter-auth-refresh-process-001',
      now: now,
    );

    final AuthSessionManager restartedProcess = AuthSessionManager(store);
    final PendingAuthRefresh recovered = await restartedProcess
        .prepareRefreshRequest(
          session: session,
          clientId: 'voice-social-mobile-public',
          requestIdFactory: () => 'must-not-be-used',
          now: now.add(const Duration(seconds: 5)),
        );

    expect(recovered.requestId, 'flutter-auth-refresh-process-001');
  });

  test(
    'expired or changed-session pending state is cleared before network use',
    () async {
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      final AuthSessionManager manager = AuthSessionManager(store);
      final DateTime now = DateTime.utc(2026, 8, 25, 12);
      final AuthSession session = _expiredSession();
      await manager.prepareRefreshRequest(
        session: session,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-invalid-001',
        now: now,
      );

      await expectLater(
        manager.prepareRefreshRequest(
          session: session,
          clientId: 'voice-social-mobile-public',
          requestIdFactory: () => 'must-not-be-used',
          now: now.add(AuthSessionManager.refreshRecoveryWindow),
        ),
        throwsA(isA<AuthRefreshRecoveryException>()),
      );
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );

      await manager.prepareRefreshRequest(
        session: session,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-changed-001',
        now: now,
      );
      final AuthSession changedSession = AuthSession(
        accessToken: session.accessToken,
        tokenType: session.tokenType,
        expiresAt: session.expiresAt,
        refreshToken: 'changed-refresh-token',
        refreshExpiresAt: session.refreshExpiresAt,
        deviceId: session.deviceId,
        clientId: session.clientId,
        userId: session.userId,
        mobile: session.mobile,
        roles: session.roles,
      );
      await expectLater(
        manager.prepareRefreshRequest(
          session: changedSession,
          clientId: 'voice-social-mobile-public',
          requestIdFactory: () => 'must-not-be-used',
          now: now,
        ),
        throwsA(isA<AuthRefreshRecoveryException>()),
      );
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );
    },
  );

  test(
    'malformed pending state is tombstoned without generating a new id',
    () async {
      final MemoryKeyValueStore store = MemoryKeyValueStore(<String, String>{
        AuthSessionManager.pendingRefreshStorageKey: '{not-json',
      });
      final AuthSessionManager manager = AuthSessionManager(store);

      await expectLater(
        manager.prepareRefreshRequest(
          session: _expiredSession(),
          clientId: 'voice-social-mobile-public',
          requestIdFactory: () => 'must-not-be-used',
        ),
        throwsA(isA<AuthRefreshRecoveryException>()),
      );
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );
    },
  );

  test(
    'manager session changes fail closed even when no pending record remains',
    () async {
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      final AuthSessionManager manager = AuthSessionManager(store);
      final AuthSession original = _expiredSession();
      final AuthSession changed = AuthSession(
        accessToken: original.accessToken,
        tokenType: original.tokenType,
        expiresAt: original.expiresAt,
        refreshToken: 'changed-refresh-token',
        refreshExpiresAt: original.refreshExpiresAt,
        deviceId: original.deviceId,
        clientId: original.clientId,
        userId: original.userId,
        mobile: original.mobile,
        roles: original.roles,
      );
      await manager.save(original);
      await manager.prepareRefreshRequest(
        session: original,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-session-001',
      );
      await manager.save(changed);

      await expectLater(
        manager.prepareRefreshRequest(
          session: original,
          clientId: 'voice-social-mobile-public',
          requestIdFactory: () => 'must-not-be-used',
        ),
        throwsA(isA<AuthRefreshRecoveryException>()),
      );
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );
    },
  );

  test(
    'logout cleanup erases the pending refresh intent with credentials',
    () async {
      final MemoryKeyValueStore store = MemoryKeyValueStore();
      final AuthSessionManager manager = AuthSessionManager(store);
      final AuthSession session = _expiredSession();
      await manager.save(session);
      await manager.prepareRefreshRequest(
        session: session,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-logout-001',
      );

      await manager.clear();

      expect(manager.session, isNull);
      expect(await manager.restore(), isNull);
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );
    },
  );

  test(
    'startup recovery reuses the pending id and clears it after session save',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String> requestIds = <String>[];
      server.listen((HttpRequest request) async {
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{
                'access_token': 'recovered-access',
                'token_type': 'Bearer',
                'expires_in': 3600,
                'refresh_token': 'recovered-refresh',
                'refresh_expires_in': 2592000,
                'userId': 10001,
                'mobile': '13800138000',
                'roles': 'USER',
              },
            }),
          );
        await request.response.close();
      });

      final MemoryKeyValueStore store = MemoryKeyValueStore();
      final AuthSession oldSession = _expiredSession();
      final AuthSessionManager previousProcess = AuthSessionManager(store);
      await previousProcess.acceptConsent();
      await previousProcess.save(oldSession);
      await previousProcess.prepareRefreshRequest(
        session: oldSession,
        clientId: 'voice-social-mobile-public',
        requestIdFactory: () => 'flutter-auth-refresh-crash-001',
      );

      final AuthSessionManager restartedProcess = AuthSessionManager(store);
      final AppEnvironment environment = AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://${server.address.address}:${server.port}/',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'voice-social-mobile-public',
        realtimeEndpoint: '',
        deploymentEnvironment: DeploymentEnvironment.development,
        allowInsecureHttp: true,
      );
      final ApiClient client = ApiClient(
        baseUri: environment.apiBaseUri!,
        clientType: environment.clientType,
        clientInnerVersion: environment.clientInnerVersion,
        authorizationProvider: () => restartedProcess.authorizationHeader,
      );
      final BackendAuthRepository repository = BackendAuthRepository(
        apiClient: client,
        environment: environment,
        sessionManager: restartedProcess,
      );
      final AuthController controller = AuthController(
        repository: repository,
        sessionManager: restartedProcess,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: environment,
          sessionManager: restartedProcess,
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.stage, AuthFlowStage.signedIn);
      expect(controller.session?.refreshToken, 'recovered-refresh');
      expect(requestIds, <String>['flutter-auth-refresh-crash-001']);
      expect(
        await store.read(AuthSessionManager.pendingRefreshStorageKey),
        anyOf(isNull, isEmpty),
      );
    },
  );
}

AuthSession _expiredSession() => AuthSession(
  accessToken: 'expired-access',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
  refreshToken: 'one-time-refresh-secret',
  refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  deviceId: 'device-1',
  clientId: 'voice-social-mobile-public',
  userId: 10001,
  mobile: '13800138000',
  roles: 'USER',
);
