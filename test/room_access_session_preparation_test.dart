import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';

import 'backend_room_lease_repository_contract_test.dart' as fixture;

AuthSession session({
  int seconds = 45,
  int user = 10001,
  String token = 'old',
}) => AuthSession(
  accessToken: token,
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(Duration(seconds: seconds)),
  refreshToken: 'refresh-$token',
  deviceId: 'fixture-device',
  clientId: 'fixture-client',
  refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  userId: user,
  mobile: '',
  roles: '',
);

class DelayedAuth extends MockAuthRepository {
  final result = Completer<AuthSession>();
  final started = Completer<void>();
  int calls = 0;

  @override
  Future<AuthSession> refreshSession(AuthSession session) {
    calls++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  test('AppDependencies refreshes before the strict heartbeat', () async {
    final paths = <String>[];
    final harness = await fixture.Harness.start((request, body) async {
      paths.add(request.uri.path.split('/').last);
      if (paths.last == 'refreshSession') {
        return {
          'access_token': 'wired-new',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': 'wired-refresh',
          'refresh_expires_in': 86400,
          'userId': 10001,
          'mobile': '',
          'roles': 'USER',
        };
      }
      expect(request.headers.value('authorization'), 'Bearer wired-new');
      expect(request.headers.value('X-Request-Id'), 'heartbeat-1');
      expect(body['sequence'], 1);
      expect(body['sessionId'], fixture.sessionId);
      return {...fixture.lease(), 'sequence': 1};
    });
    addTearDown(harness.close);
    final dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://127.0.0.1:${harness.server.port}/',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'fixture-client',
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      ),
    );
    addTearDown(dependencies.dispose);
    await dependencies.sessionManager.save(session());
    final repository = dependencies.roomRepository as BackendRoomRepository;
    final binding = repository.leaseBinding;
    final generation = binding.beginEntry('fixture');
    binding.bind(
      generation,
      '9527',
      10001,
      parseRoomLease(fixture.lease(), sessionId: fixture.sessionId),
    );
    expect((await fixture.renew(repository)).sequence, 1);
    expect(paths, ['refreshSession', 'heartbeatRoom']);
    expect(binding.generation, generation);
    expect(dependencies.sessionManager.session!.accessToken, 'wired-new');
  });

  for (final operation in ['enter', 'reconnect', 'member', 'exit']) {
    for (final failure in ['false', 'throw', 'generation']) {
      test('$operation preparation $failure sends no POST', () async {
        final binding = RoomLeaseBinding();
        binding.bind(
          binding.beginEntry('fixture'),
          '9527',
          10001,
          parseRoomLease(fixture.lease(), sessionId: fixture.sessionId),
        );
        final started = Completer<void>();
        final ready = Completer<bool>();
        var posts = 0;
        final harness = await fixture.Harness.start(
          (request, body) async {
            posts++;
            return fixture.room();
          },
          binding: binding,
          prepareAccessSession: () {
            started.complete();
            return ready.future;
          },
        );
        addTearDown(harness.close);
        final Future<Object?> pending = switch (operation) {
          'enter' => fixture.enter(harness.repository),
          'reconnect' => harness.repository.reconnectRoom(
            roomId: '9527',
            currentUserId: 10001,
          ),
          'member' => harness.repository.requestMic(1),
          _ => harness.repository.exitRoom('9527'),
        };
        final checked = expectLater(pending, throwsA(isA<ApiException>()));
        await started.future.timeout(const Duration(seconds: 2));
        expect(posts, 0);
        if (failure == 'generation') binding.beginEntry('another-room');
        if (failure == 'throw') {
          ready.completeError(
            const ApiException(
              kind: ApiFailureKind.configuration,
              message: 'fixture',
            ),
          );
        } else {
          ready.complete(failure == 'generation');
        }
        await checked;
        expect(posts, 0);
      });
    }
  }
  for (final scenario in [
    'near expiry',
    'fresh',
    'existing flight',
    'logout',
    'account',
    'same user relogin',
    'room change',
    'refresh failure',
    'refresh unauthorized',
    'strict 401',
  ]) {
    test('room access preparation: $scenario', () async {
      final manager = AuthSessionManager(MemoryKeyValueStore());
      await manager.save(
        session(
          seconds: scenario == 'fresh' || scenario == 'existing flight'
              ? 3600
              : 45,
        ),
      );
      final auth = DelayedAuth();
      final controller = AuthController(
        repository: auth,
        sessionManager: manager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: manager,
        ),
      );
      addTearDown(controller.dispose);
      final binding = RoomLeaseBinding(
        authenticationGeneration: () => manager.identityGeneration,
      );
      binding.bind(
        binding.beginEntry('fixture'),
        '9527',
        10001,
        parseRoomLease(fixture.lease(), sessionId: fixture.sessionId),
      );
      final original = binding.current!;
      final deadline = original.lease;
      var posts = 0;
      var recoveries = 0;
      final harness = await fixture.Harness.start(
        (request, body) async {
          posts++;
          expect(
            request.headers.value('authorization'),
            'Bearer ${scenario == 'fresh' ? 'old' : 'new'}',
          );
          expect(request.headers.value('X-Request-Id'), 'heartbeat-1');
          expect(body, {
            'roomId': '9527',
            'sessionId': fixture.sessionId,
            'sequence': 1,
          });
          return scenario == 'strict 401'
              ? {'errorCode': 40101}
              : {...fixture.lease(), 'sequence': 1};
        },
        binding: binding,
        prepareAccessSession: controller.ensureFreshAccessSession,
        authorizationProvider: () => manager.authorizationHeader,
      );
      addTearDown(harness.close);
      harness.client.setUnauthorizedRecovery(() async {
        recoveries++;
        return true;
      });
      final existing = scenario == 'existing flight'
          ? controller.refreshSession()
          : null;
      final rejected = [
        'logout',
        'account',
        'same user relogin',
        'room change',
        'refresh failure',
        'refresh unauthorized',
        'strict 401',
      ].contains(scenario);
      final first = fixture.renew(harness.repository);
      final checked = rejected
          ? expectLater(first, throwsA(isA<ApiException>()))
          : first;
      if (scenario != 'fresh') {
        await auth.started.future.timeout(const Duration(seconds: 2));
        expect(posts, 0);
        final parallel = controller.ensureFreshAccessSession();
        final duplicate = rejected ? null : fixture.renew(harness.repository);
        switch (scenario) {
          case 'logout':
            await controller.discardSessionAndSignOut();
          case 'account':
            await manager.save(session(user: 10002));
          case 'same user relogin':
            await controller.discardSessionAndSignOut();
            await manager.save(session());
          case 'room change':
            binding.beginEntry('different-room');
        }
        if (scenario == 'refresh failure' ||
            scenario == 'refresh unauthorized') {
          auth.result.completeError(
            ApiException(
              kind: scenario == 'refresh failure'
                  ? ApiFailureKind.configuration
                  : ApiFailureKind.unauthorized,
              message: 'fixture refresh failure',
            ),
          );
        } else {
          auth.result.complete(session(seconds: 3600, token: 'new'));
        }
        await parallel;
        if (duplicate != null) expect((await duplicate).sequence, 1);
      }
      await checked;
      if (existing != null) expect(await existing, isTrue);
      expect(auth.calls, scenario == 'fresh' ? 0 : 1);
      expect(posts, rejected && scenario != 'strict 401' ? 0 : 1);
      expect(recoveries, 0);
      if (rejected) expect(original.lease, same(deadline));
      if (scenario == 'refresh failure')
        expect(binding.current, same(original));
      if (scenario == 'refresh unauthorized') expect(binding.current, isNull);
    });
  }
}
