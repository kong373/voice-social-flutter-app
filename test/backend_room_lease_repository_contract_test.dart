import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';

const sessionId = '11111111-1111-4111-8111-111111111111';
Map<String, Object?> lease() => {
  'sessionId': sessionId,
  'sequence': 0,
  'serverTime': '2026-09-08T00:00:00Z',
  'expiresAt': '2026-09-08T00:01:30Z',
  'heartbeatIntervalSeconds': 20,
  'leaseDurationSeconds': 90,
};

void main() {
  test('offline owner role mutation rejects missing actor lease', () async {
    var requests = 0;
    final harness = await Harness.start((request, body) async {
      requests++;
      return <String, Object?>{};
    });
    addTearDown(harness.close);
    final operations = BackendRoomOperationsRepository(
      apiClient: harness.client,
    );
    await expectLater(
      operations.setUserRole(roomId: '9527', userId: 10002, manager: true),
      throwsA(
        isA<ApiException>().having((error) => error.code, 'stale lease', 40937),
      ),
    );
    expect(requests, 0);
  });

  for (final operation in ['room mute', 'seat lock']) {
    test(
      'offline owner resource $operation keeps existing authorization',
      () async {
        final harness = await Harness.start((request, body) async {
          expect(body.containsKey('sessionId'), isFalse);
          return {
            'roomId': '9527',
            'userId': 10002,
            'role': 'MANAGER',
            'muted': true,
            'seatNumber': 1,
            'locked': true,
          };
        });
        addTearDown(harness.close);
        final operations = BackendRoomOperationsRepository(
          apiClient: harness.client,
        );
        await switch (operation) {
          'room mute' => operations.setUserMuted(
            roomId: '9527',
            userId: 10002,
            muted: true,
          ),
          _ => operations.setSeatLocked(
            roomId: '9527',
            backendMicIndex: 1,
            locked: true,
          ),
        };
      },
    );
  }

  test('reconnect confirmation closes an ambiguous heartbeat retry', () async {
    final harness = await Harness.start((request, body) async {
      if (request.uri.path.endsWith('enterRoom')) return room();
      if (request.uri.path.endsWith('reConnectRoomInfo')) {
        return {
          ...room(),
          'roomLease': {...lease(), 'sequence': 1},
        };
      }
      if (body['sequence'] == 1) return {'errorCode': 50300};
      expect(body['sequence'], 2);
      return {...lease(), 'sequence': 2};
    });
    addTearDown(harness.close);
    await enter(harness.repository);
    await expectLater(renew(harness.repository), throwsA(isA<ApiException>()));
    await harness.repository.reconnectRoom(
      roomId: '9527',
      currentUserId: 10001,
    );
    final result = await harness.repository.renewRoomLease(
      roomId: '9527',
      sessionId: sessionId,
      sequence: 2,
      requestId: 'heartbeat-2',
      currentUserId: 10001,
    );
    expect(result.sequence, 2);
  });
  test('queued member writes cannot adopt a new account binding', () async {
    var authGeneration = 1;
    var entries = 0;
    var writes = 0;
    final started = Completer<void>();
    final release = Completer<void>();
    final binding = RoomLeaseBinding(
      authenticationGeneration: () => authGeneration,
    );
    final harness = await Harness.start((request, body) async {
      if (request.uri.path.endsWith('enterRoom')) {
        final id = ++entries == 1 ? sessionId : secondSessionId;
        return {
          ...room(),
          'sessionId': id,
          'roomLease': {...lease(), 'sessionId': id},
        };
      }
      writes++;
      expect(body['sessionId'], sessionId);
      started.complete();
      await release.future;
      return {'roomId': '9527', 'userId': 10002, 'muted': true};
    }, binding: binding);
    addTearDown(harness.close);
    final operations = BackendRoomOperationsRepository(
      apiClient: harness.client,
      leaseBinding: binding,
    );
    await enter(harness.repository);
    final pending = expectLater(
      operations.submitMicRequest(roomId: '9527', userId: 10002, seatNumber: 2),
      throwsA(isA<ApiException>()),
    );
    await started.future;
    final queued = expectLater(
      operations.kickUser(roomId: '9527', userId: 10002),
      throwsA(isA<ApiException>()),
    );
    authGeneration++;
    await harness.repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10003,
    );
    release.complete();
    await pending;
    await queued;
    expect(writes, 1);
    expect(binding.current!.userId, 10003);
    expect(binding.current!.lease.sessionId, secondSessionId);
  });

  test('late mic queue GET cannot repopulate a new generation cache', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var entries = 0;
    final harness = await Harness.start((request, body) async {
      if (request.uri.path.endsWith('enterRoom')) {
        final id = ++entries == 1 ? sessionId : secondSessionId;
        return {
          ...room(),
          'sessionId': id,
          'roomLease': {...lease(), 'sessionId': id},
        };
      }
      expect(request.method, 'GET');
      started.complete();
      await release.future;
      return {
        'roomId': '9527',
        'list': [],
        'records': [],
        'total': 0,
        'coordinationMode': 'APPROVAL',
        'providerInvocation': false,
      };
    });
    addTearDown(harness.close);
    await enter(harness.repository);
    final operations = BackendRoomOperationsRepository(
      apiClient: harness.client,
      leaseBinding: harness.repository.leaseBinding,
    );
    final pending = expectLater(
      operations.fetchMicRequests('9527'),
      throwsA(isA<ApiException>()),
    );
    await started.future;
    await enter(harness.repository);
    release.complete();
    await pending;
    expect(operations.micCoordinationMode, MicCoordinationMode.unavailable);
  });
  for (final (label, wire, accepted) in <(String, Map<String, Object?>, bool)>[
    ('zero remaining', {...lease(), 'expiresAt': '2026-09-08T00:00:00Z'}, true),
    ('safe integer maximum', {...lease(), 'sequence': 9007199254740991}, true),
    (
      'UTC offset zero',
      {...lease(), 'serverTime': '2026-09-08T00:00:00+00:00'},
      true,
    ),
    (
      'nanosecond UTC',
      {
        ...lease(),
        'serverTime': '2026-09-08T00:00:00.123456789Z',
        'expiresAt': '2026-09-08T00:01:30.123456789Z',
      },
      true,
    ),
    (
      'one nanosecond too long',
      {...lease(), 'expiresAt': '2026-09-08T00:01:30.000000001Z'},
      false,
    ),
  ]) {
    test('entry lease boundary $label', () async {
      final harness = await Harness.start(
        (request, body) async => {...room(), 'roomLease': wire},
      );
      addTearDown(harness.close);
      final result = enter(harness.repository);
      if (accepted) {
        expect((await result).roomLease!.isValid, isTrue);
      } else {
        await expectLater(result, throwsA(isA<ApiException>()));
      }
    });
  }
  for (final bad in <Object?>[
    null,
    {},
    {'sessionId': sessionId},
    {...lease(), 'sequence': '0'},
    {...lease(), 'heartbeatIntervalSeconds': 10},
  ]) {
    test('reconnect rejects invalid lease $bad', () async {
      final harness = await Harness.start(
        (request, body) async => request.uri.path.endsWith('enterRoom')
            ? room()
            : {...room(), 'roomLease': bad},
      );
      addTearDown(harness.close);
      await enter(harness.repository);
      final previous = harness.repository.leaseBinding.current;
      await expectLater(
        harness.repository.reconnectRoom(roomId: '9527', currentUserId: 10001),
        throwsA(isA<ApiException>()),
      );
      expect(harness.repository.leaseBinding.current, same(previous));
    });
  }

  test(
    'heartbeat single flight rejects altered retries before sending',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final harness = await Harness.start((request, body) async {
        if (request.uri.path.endsWith('enterRoom')) return room();
        calls++;
        started.complete();
        await release.future;
        return {...lease(), 'sequence': 1};
      });
      addTearDown(harness.close);
      await enter(harness.repository);
      final first = renew(harness.repository);
      await started.future;
      final duplicate = renew(harness.repository);
      for (final (sequence, requestId) in [
        (1, 'changed'),
        (2, 'heartbeat-1'),
      ]) {
        await expectLater(
          harness.repository.renewRoomLease(
            roomId: '9527',
            sessionId: sessionId,
            sequence: sequence,
            requestId: requestId,
            currentUserId: 10001,
          ),
          throwsA(isA<ApiException>()),
        );
      }
      release.complete();
      expect(await first, same(await duplicate));
      expect(calls, 1);
    },
  );
  for (final code in [40101, 40936, 40937, 40938]) {
    test(
      'heartbeat preserves error $code and binding without GET or re-entry',
      () async {
        var calls = 0;
        final harness = await Harness.start((request, body) async {
          calls++;
          if (calls == 1) return room();
          expect(request.uri.path.endsWith('/heartbeatRoom'), isTrue);
          return {'errorCode': code};
        });
        addTearDown(harness.close);
        await enter(harness.repository);
        final current = harness.repository.leaseBinding.current;
        final previous = current!.lease;
        await expectLater(
          renew(harness.repository),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
        expect(harness.repository.leaseBinding.current, same(current));
        expect(current.lease, same(previous));
        expect(calls, 2);
      },
    );
  }

  for (final badResponse in <String, Map<String, Object?>>{
    'wrapped': {
      'roomLease': {...lease(), 'sequence': 1},
    },
    'wrong sequence': {...lease(), 'sequence': 2},
    'regressed time': {
      ...lease(),
      'sequence': 1,
      'serverTime': '2026-09-07T23:59:59Z',
      'expiresAt': '2026-09-08T00:01:29Z',
    },
    'mismatched session': {
      ...lease(),
      'sequence': 1,
      'sessionId': secondSessionId,
    },
  }.entries) {
    test(
      'heartbeat rejects ${badResponse.key} without changing lease',
      () async {
        final harness = await Harness.start(
          (request, body) async => request.uri.path.endsWith('enterRoom')
              ? room()
              : badResponse.value,
        );
        addTearDown(harness.close);
        await enter(harness.repository);
        final previous = harness.repository.leaseBinding.current!.lease;
        await expectLater(
          renew(harness.repository),
          throwsA(isA<ApiException>()),
        );
        expect(harness.repository.leaseBinding.current!.lease, same(previous));
      },
    );
  }

  for (final operation in ['enter', 'reconnect', 'heartbeat', 'exit']) {
    test('late $operation cannot overwrite a newer same-user entry', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var enterCount = 0;
      final harness = await Harness.start((request, body) async {
        final path = request.uri.path;
        if (path.endsWith('/enterRoom')) {
          enterCount++;
          if (operation == 'enter' && enterCount == 1) {
            started.complete();
            await release.future;
          }
          final id = enterCount > 1 ? secondSessionId : sessionId;
          return {
            ...room(),
            'sessionId': id,
            'roomLease': {...lease(), 'sessionId': id},
          };
        }
        started.complete();
        await release.future;
        if (path.endsWith('/exitRoom'))
          return {'roomId': '9527', 'exited': true, 'status': 'EXITED'};
        if (path.endsWith('/heartbeatRoom')) return {...lease(), 'sequence': 1};
        expect(body['sessionId'], sessionId);
        return room();
      });
      addTearDown(harness.close);
      if (operation != 'enter') await enter(harness.repository);
      final Future<Object?> pending = switch (operation) {
        'enter' => enter(harness.repository),
        'reconnect' => harness.repository.reconnectRoom(
          roomId: '9527',
          currentUserId: 10001,
        ),
        'heartbeat' => renew(harness.repository),
        _ => harness.repository.exitRoom('9527'),
      };
      final checked = operation == 'exit'
          ? pending
          : expectLater(pending, throwsA(isA<ApiException>()));
      await started.future;
      // Different entry intent supersedes an in-flight first enter too.
      final fresh = harness.repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.discoveryPost,
        currentUserId: 10001,
      );
      release.complete();
      await checked;
      final result = await fresh;
      expect(result.sessionId, secondSessionId);
      expect(
        harness.repository.leaseBinding.current!.lease.sessionId,
        secondSessionId,
      );
      expect(harness.repository.leaseBinding.current!.lease.sequence, 0);
    });
  }

  test('reconnect rejects a regressed same-sequence lease', () async {
    final harness = await Harness.start((request, body) async {
      if (request.uri.path.endsWith('/enterRoom')) return room();
      expect(body, {'roomId': '9527', 'sessionId': sessionId});
      return {
        ...room(),
        'roomLease': {...lease(), 'expiresAt': '2026-09-08T00:01:29Z'},
      };
    });
    addTearDown(harness.close);
    await enter(harness.repository);
    final previous = harness.repository.leaseBinding.current!.lease;
    await expectLater(
      harness.repository.reconnectRoom(roomId: '9527', currentUserId: 10001),
      throwsA(isA<ApiException>()),
    );
    expect(harness.repository.leaseBinding.current!.lease, same(previous));
  });

  for (final code in [40936, 40937]) {
    test('reconnect $code never falls back to fresh entry', () async {
      var entries = 0;
      final harness = await Harness.start((request, body) async {
        if (request.uri.path.endsWith('/enterRoom')) {
          entries++;
          return room();
        }
        expect(body, {'roomId': '9527', 'sessionId': sessionId});
        return {'errorCode': code};
      });
      addTearDown(harness.close);
      await enter(harness.repository);
      await expectLater(
        harness.repository.reconnectRoom(roomId: '9527', currentUserId: 10001),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
      );
      expect(entries, 1);
    });
  }

  test('offline owner resource edit works with no membership', () async {
    final harness = await Harness.start((request, body) async {
      expect(body, {'roomId': '9527', 'topic': 'new', 'expectedVersion': 1});
      return {
        'roomId': '9527',
        'topic': 'new',
        'welcomeText': '',
        'version': 2,
      };
    });
    addTearDown(harness.close);
    final operations = BackendRoomOperationsRepository(
      apiClient: harness.client,
    );
    await operations.updateTopic(
      roomId: '9527',
      topic: const RoomTopic(title: '', content: 'new', version: 1),
    );
    await expectLater(
      operations.submitMicRequest(roomId: '9527', userId: 10002, seatNumber: 2),
      throwsA(isA<ApiException>()),
    );
  });
  test('member operation requires current shared sessionId', () async {
    final harness = await Harness.start((request, body) async {
      if (request.uri.path.endsWith('enterRoom')) return room();
      expect(body['sessionId'], sessionId);
      return {'roomId': '9527', 'userId': 10002, 'muted': true};
    });
    addTearDown(harness.close);
    await enter(harness.repository);
    final operations = BackendRoomOperationsRepository(
      apiClient: harness.client,
      leaseBinding: harness.repository.leaseBinding,
    );
    await operations.setUserMuted(roomId: '9527', userId: 10002, muted: true);
  });
  test(
    'heartbeat exact POST direct lease, stable retries and sequence',
    () async {
      final requests = <Map<String, Object?>>[];
      var fail = true;
      final harness = await Harness.start((request, body) async {
        if (request.uri.path.endsWith('enterRoom')) return room();
        expect(request.method, 'POST');
        expect(request.uri.path, '/app-room-api/room/com/v1/heartbeatRoom');
        expect(request.uri.query, isEmpty);
        expect(request.headers.value('X-Request-Id'), 'heartbeat-1');
        expect(body, {'roomId': '9527', 'sessionId': sessionId, 'sequence': 1});
        requests.add(body);
        if (fail) {
          fail = false;
          return {'errorCode': 50300};
        }
        return {...lease(), 'sequence': 1};
      });
      addTearDown(harness.close);
      await enter(harness.repository);
      expect(harness.repository, isA<RoomLeaseRepository>());
      final capability = harness.repository as RoomLeaseRepository;
      Future<RoomSessionLease> renew() => capability.renewRoomLease(
        roomId: '9527',
        sessionId: sessionId,
        sequence: 1,
        requestId: 'heartbeat-1',
        currentUserId: 10001,
      );
      await expectLater(renew(), throwsA(isA<ApiException>()));
      expect((await renew()).sequence, 1);
      expect(requests, hasLength(2));
    },
  );

  test(
    'late enter across auth generation cannot bind or authorize writes',
    () async {
      var authGeneration = 1;
      final received = Completer<void>();
      final release = Completer<void>();
      final binding = RoomLeaseBinding(
        authenticationGeneration: () => authGeneration,
      );
      final harness = await Harness.start((request, body) async {
        received.complete();
        await release.future;
        return room();
      }, binding: binding);
      addTearDown(harness.close);
      final pending = enter(harness.repository);
      final rejected = expectLater(pending, throwsA(isA<ApiException>()));
      await received.future;
      authGeneration++;
      release.complete();
      await rejected;
      expect(binding.current, isNull);
      await expectLater(
        harness.repository.leaveMic(),
        throwsA(isA<ApiException>()),
      );
    },
  );

  for (final entry in <String, Object?>{
    'missing': null,
    'valid': lease(),
    'session mismatch': {
      ...lease(),
      'sessionId': '22222222-2222-4222-8222-222222222222',
    },
    'unsafe sequence': {...lease(), 'sequence': 9007199254740992},
    'negative sequence': {...lease(), 'sequence': -1},
    'string sequence': {...lease(), 'sequence': '0'},
    'boolean sequence': {...lease(), 'sequence': false},
    'numeric interval': {...lease(), 'heartbeatIntervalSeconds': 20.0},
    'string duration': {...lease(), 'leaseDurationSeconds': '90'},
    'offset time': {...lease(), 'serverTime': '2026-09-08T08:00:00+08:00'},
    'invalid calendar date': {...lease(), 'serverTime': '2026-09-00T00:00:00Z'},
    'fractional sequence': {...lease(), 'sequence': 0.5},
    'local time': {...lease(), 'serverTime': '2026-09-08T00:00:00'},
    'wrong interval': {...lease(), 'heartbeatIntervalSeconds': 21},
    'wrong duration': {...lease(), 'leaseDurationSeconds': 91},
    'negative lifetime': {...lease(), 'expiresAt': '2026-09-07T23:59:59Z'},
    'long lifetime': {...lease(), 'expiresAt': '2026-09-08T00:01:31Z'},
  }.entries) {
    test('live enter lease: ${entry.key}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'ANDROID',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer contract-test',
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': {
              'roomId': '9527',
              'sessionId': sessionId,
              if (entry.value != null) 'roomLease': entry.value,
            },
          }),
        );
        await request.response.close();
      });
      final repository = BackendRoomRepository(apiClient: client);
      final result = repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );
      if (entry.key == 'valid') {
        expect((await result).roomLease?.sessionId, sessionId);
      } else {
        await expectLater(
          result,
          throwsA(
            isA<ApiException>().having(
              (error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
    });
  }
}

Map<String, Object?> room() => {
  'roomId': '9527',
  'sessionId': sessionId,
  'roomLease': lease(),
};
const secondSessionId = '22222222-2222-4222-8222-222222222222';
Future<RoomSessionLease> renew(BackendRoomRepository repository) =>
    repository.renewRoomLease(
      roomId: '9527',
      sessionId: sessionId,
      sequence: 1,
      requestId: 'heartbeat-1',
      currentUserId: 10001,
    );
Future<RoomSnapshot> enter(BackendRoomRepository repository) =>
    repository.enterRoom(
      roomId: '9527',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );

class Harness {
  Harness(this.server, this.repository, this.client);
  final HttpServer server;
  final BackendRoomRepository repository;
  final ApiClient client;
  static Future<Harness> start(
    Future<Map<String, Object?>> Function(HttpRequest, Map<String, Object?>)
    reply, {
    RoomLeaseBinding? binding,
    Future<bool> Function()? prepareAccessSession,
    String? Function()? authorizationProvider,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final data = await reply(
        request,
        text.isEmpty ? {} : jsonDecode(text) as Map<String, Object?>,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'code': data['errorCode'] ?? 200, 'data': data}),
      );
      await request.response.close();
    });
    final client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      clientType: 'ANDROID',
      clientInnerVersion: '1',
      authorizationProvider:
          authorizationProvider ?? () => 'Bearer contract-test',
    );
    return Harness(
      server,
      BackendRoomRepository(
        apiClient: client,
        leaseBinding: binding,
        prepareAccessSession: prepareAccessSession,
      ),
      client,
    );
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}
