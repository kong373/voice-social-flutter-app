import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';

const roomId = '11111111-1111-1111-1111-111111111111';
Map<String, Object?> row() => {
  'roomId': roomId,
  'roomCode': '123456',
  'roomName': 'private room',
  'ownerUserId': 42,
  'status': 'CLOSED',
  'version': 7,
  'accessMode': 'PASSWORD',
};
Map<String, Object?> page() => {
  'list': [row()],
  'records': [row()],
  'current': 1,
  'pageSize': 20,
  'total': 1,
  'pages': 1,
  'hasMore': false,
};
void main() {
  late HttpServer server;
  late ValueNotifier<(int, int)> identity;
  late BackendPlatformRoomRepository repository;
  late Future<void> Function(HttpRequest) handle;
  late List<({String path, String body, String? key, String? auth})> calls;
  setUp(() async {
    identity = ValueNotifier((1, 1));
    calls = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handle = (request) async {
      Object data;
      if (request.uri.path.endsWith('/authority')) {
        data = {'platformStaff': true};
      } else if (request.uri.path.endsWith('/list')) {
        data = page();
      } else {
        data = {
          'roomId': roomId,
          'status': 'OPEN',
          'reopened': true,
          'version': 8,
          'providerInvocation': false,
        };
      }
      request.response.write(jsonEncode({'code': 200, 'data': data}));
      await request.response.close();
    };
    server.listen((request) async {
      calls.add((
        path: request.uri.path,
        body: await utf8.decoder.bind(request).join(),
        key: request.headers.value('X-Request-Id'),
        auth: request.headers.value('Authorization'),
      ));
      await handle(request);
    });
    repository = BackendPlatformRoomRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer user-${identity.value.$1}',
      ),
      identity: () => identity.value,
      identityChanges: identity,
    );
  });
  tearDown(() async {
    identity.dispose();
    await server.close(force: true);
  });
  test(
    'legacy empty roomCode preserves the record and whole directory page',
    () async {
      final legacy = row()..['roomCode'] = '';
      final ordinary = row()
        ..['roomId'] = '22222222-2222-4222-8222-222222222222';
      final data = page()
        ..addAll({
          'list': [legacy, ordinary],
          'records': [legacy, ordinary],
          'total': 2,
        });
      handle = (request) async {
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': request.uri.path.endsWith('/authority')
                ? {'platformStaff': true}
                : data,
          }),
        );
        await request.response.close();
      };
      final result = await repository.list();
      expect(result.rooms, hasLength(2));
      expect(result.rooms.first.roomCode, '');
      expect(result.rooms.first.roomId, roomId);
      expect(result.rooms.last.roomCode, '123456');
    },
  );
  test(
    'strict authority, paged directory and exact lifecycle contract',
    () async {
      expect(await repository.authority(), isTrue);
      final result = await repository.list();
      expect(result.rooms.single.accessMode, 'PASSWORD');
      expect(result.rooms.single.ownerUserId, 42);
      await repository.control(roomId: roomId, version: 7, reopen: true);
      expect(calls.last.path, '/app-mini-api/mini/v1/rooms/reopen');
      expect(jsonDecode(calls.last.body), {
        'roomId': roomId,
        'expectedVersion': 7,
      });
      expect(calls.last.key, isNotEmpty);
      expect(repository.pending, isNull);
      expect(
        calls.any((c) => c.path.contains('getRoomSelectByUserId')),
        isFalse,
      );
    },
  );
  test(
    'close posts exact selected room and accepts authoritative terminal receipt',
    () async {
      handle = (request) async {
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': {
              'roomId': roomId,
              'status': 'CLOSED',
              'closed': true,
              'version': 8,
            },
          }),
        );
        await request.response.close();
      };
      await repository.control(roomId: roomId, version: 7, reopen: false);
      expect(calls.single.path, '/app-mini-api/mini/v1/rooms/close');
      expect(jsonDecode(calls.single.body), {
        'roomId': roomId,
        'expectedVersion': 7,
      });
      expect(repository.pending, isNull);
    },
  );
  test(
    'unknown followed by conflict keeps original command, not new version',
    () async {
      var attempts = 0;
      handle = (request) async {
        request.response.statusCode = ++attempts == 1 ? 503 : 409;
        request.response.write(
          jsonEncode({
            'code': request.response.statusCode,
            'message': 'unknown/conflict',
          }),
        );
        await request.response.close();
      };
      await expectLater(
        repository.control(roomId: roomId, version: 7, reopen: false),
        throwsA(isA<ApiException>()),
      );
      final pending = repository.pending;
      await expectLater(
        repository.control(roomId: roomId, version: 7, reopen: false),
        throwsA(isA<ApiException>()),
      );
      expect(repository.pending, same(pending));
      expect(calls[0].body, calls[1].body);
      expect(calls[0].key, calls[1].key);
    },
  );
  for (final invalid in [
    'authority',
    'version',
    'owner',
    'status',
    'records',
    'pages',
  ]) {
    test('reject malformed $invalid', () async {
      handle = (request) async {
        final data = page();
        final first = (data['list'] as List).first as Map<String, Object?>;
        if (invalid == 'version') first['version'] = 1.5;
        if (invalid == 'owner') first['ownerUserId'] = 0;
        if (invalid == 'status') first['status'] = 'HIDDEN';
        if (invalid == 'pages') data['pages'] = 2;
        if (invalid == 'records') data['records'] = [];
        if (invalid != 'records') data['records'] = data['list'];
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': request.uri.path.endsWith('/authority')
                ? {'platformStaff': invalid == 'authority' ? 'true' : true}
                : data,
          }),
        );
        await request.response.close();
      };
      await expectLater(repository.list(), throwsA(isA<ApiException>()));
    });
  }
  test('nonstaff cannot fetch list or infer authority from roles', () async {
    handle = (request) async {
      request.response.write(
        jsonEncode({
          'code': 200,
          'data': {'platformStaff': false, 'role': 'ADMIN'},
        }),
      );
      await request.response.close();
    };
    await expectLater(repository.list(), throwsA(isA<ApiException>()));
    expect(calls.map((c) => c.path), ['/app-api/rooms/platform/authority']);
  });
  for (final code in [403, 404, 409]) {
    test(
      'initial $code rejects; requires explicit fresh confirmation, no automatic write',
      () async {
        handle = (request) async {
          request.response.statusCode = code;
          request.response.write(
            jsonEncode({'code': code, 'message': 'rejected'}),
          );
          await request.response.close();
        };
        await expectLater(
          repository.control(roomId: roomId, version: 7, reopen: true),
          throwsA(isA<ApiException>()),
        );
        expect(calls.length, 1);
        expect(repository.pending, isNull);
      },
    );
  }
  test(
    'unknown keeps exact key/body through A-B-A; cannot replace target/version',
    () async {
      var attempt = 0;
      handle = (request) async {
        if (++attempt == 1) {
          request.response.statusCode = 503;
          request.response.write('{"code":503}');
        } else {
          request.response.write(
            jsonEncode({
              'code': 200,
              'data': {
                'roomId': roomId,
                'status': 'OPEN',
                'reopened': true,
                'version': 8,
                'providerInvocation': false,
              },
            }),
          );
        }
        await request.response.close();
      };
      await expectLater(
        repository.control(roomId: roomId, version: 7, reopen: true),
        throwsA(isA<ApiException>()),
      );
      final original = repository.pending;
      expect(original, isNotNull);
      identity.value = (2, 2);
      expect(repository.pending, isNull);
      identity.value = (1, 3);
      expect(repository.pending, same(original));
      await expectLater(
        Future.sync(
          () => repository.control(roomId: 'other', version: 7, reopen: true),
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        Future.sync(
          () => repository.control(roomId: roomId, version: 8, reopen: true),
        ),
        throwsA(isA<ApiException>()),
      );
      await repository.control(roomId: roomId, version: 7, reopen: true);
      expect(calls.length, 2);
      expect(calls[0].body, calls[1].body);
      expect(calls[0].key, calls[1].key);
      expect(repository.pending, isNull);
    },
  );
  test(
    'A late success cannot complete B or erase original unknown command',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      handle = (request) async {
        entered.complete();
        await release.future;
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': {
              'roomId': roomId,
              'status': 'OPEN',
              'reopened': true,
              'version': 8,
              'providerInvocation': false,
            },
          }),
        );
        await request.response.close();
      };
      final future = repository
          .control(roomId: roomId, version: 7, reopen: true)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await entered.future;
      final original = repository.pending;
      identity.value = (2, 2);
      expect(repository.pending, isNull);
      release.complete();
      expect(await future, isA<ApiException>());
      identity.value = (1, 3);
      expect(repository.pending, same(original));
    },
  );
  for (final scenario in ['open', '401-switch', 'refresh-same']) {
    test('lifecycle binds real Authorization across $scenario', () async {
      final entered = Completer<void>(), release = Completer<void>();
      final transport = _DelayedClient(entered, release, scenario == 'open');
      addTearDown(() => transport.close(force: true));
      var refreshed = false, recovery = 0;
      var requests = 0;
      handle = (request) async {
        requests++;
        if (requests == 1 && scenario != 'open') {
          if (scenario == '401-switch') identity.value = (2, 2);
          request.response.statusCode = 401;
          request.response.write('{"code":401}');
        } else {
          request.response.write(
            jsonEncode({
              'code': 200,
              'data': {
                'roomId': roomId,
                'status': 'OPEN',
                'reopened': true,
                'version': 8,
                'providerInvocation': false,
              },
            }),
          );
        }
        await request.response.close();
      };
      repository = BackendPlatformRoomRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          httpClient: transport,
          authorizationProvider: () =>
              'Bearer ${identity.value.$1}-${refreshed ? 'new' : 'old'}',
          unauthorizedRecovery: () async {
            recovery++;
            refreshed = true;
            return true;
          },
        ),
        identity: () => identity.value,
        identityChanges: identity,
      );
      final work = repository
          .control(roomId: roomId, version: 7, reopen: true)
          .then<Object?>((_) => null, onError: (Object e) => e);
      if (scenario == 'open') {
        await entered.future;
        identity.value = (2, 2);
        release.complete();
      }
      if (scenario == 'refresh-same') {
        expect(await work, isNull);
        expect(calls.map((c) => c.auth), ['Bearer 1-old', 'Bearer 1-new']);
        expect(calls[0].body, calls[1].body);
        expect(calls[0].key, calls[1].key);
        expect(recovery, 1);
      } else {
        expect(await work, isA<ApiException>());
        expect(calls.length, scenario == 'open' ? 0 : 1);
        expect(recovery, 0);
      }
    });
  }
}

class _DelayedClient implements HttpClient {
  _DelayedClient(this.entered, this.release, this.delay);
  final Completer<void> entered, release;
  final bool delay;
  final HttpClient _client = HttpClient();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (delay && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return _client.openUrl(method, url);
  }

  @override
  void close({bool force = false}) => _client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
