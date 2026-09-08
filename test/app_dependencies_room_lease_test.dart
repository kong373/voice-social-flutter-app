import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';

import 'room_lease_contract_fixture.dart';

void main() {
  test(
    'live wiring shares one binding, survives token refresh and fences logout/account ABA',
    () async {
      final dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'http://127.0.0.1:1/',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'test-client',
          realtimeEndpoint: '',
          allowInsecureHttp: true,
        ),
      );
      addTearDown(dependencies.dispose);
      final room = dependencies.roomRepository as BackendRoomRepository;
      final operations =
          dependencies.roomOperationsRepository
              as BackendRoomOperationsRepository;
      expect(operations.leaseBinding, same(room.leaseBinding));
      AuthSession session(int userId, String token) => AuthSession(
        accessToken: token,
        tokenType: 'Bearer',
        expiresAt: DateTime.utc(2030),
        userId: userId,
        mobile: '',
        roles: '',
      );
      await dependencies.sessionManager.save(session(1, 'test-first'));
      final binding = room.leaseBinding;
      final generation = binding.beginEntry('fixture');
      binding.bind(
        generation,
        '9527',
        1,
        parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
      );
      final current = binding.current;
      await dependencies.sessionManager.save(session(1, 'test-refreshed'));
      expect(binding.generation, generation);
      expect(binding.current, same(current));
      await dependencies.sessionManager.clear();
      await dependencies.sessionManager.save(session(1, 'test-login-again'));
      expect(binding.generation, isNot(generation));
      expect(binding.current, isNull);
      expect(() => binding.check(generation), throwsA(isA<Exception>()));
      final second = binding.beginEntry('fixture');
      binding.bind(
        second,
        '9527',
        1,
        parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
      );
      await dependencies.sessionManager.save(session(2, 'test-other-account'));
      expect(operations.leaseBinding.current, isNull);
    },
  );
}
