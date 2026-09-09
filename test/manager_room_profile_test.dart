import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'room_lease_contract_fixture.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

const profileRoomId = '11111111-2222-4333-8444-555555555555';
Map<String, Object?> profileWire({bool owner = true}) => {
  'roomId': profileRoomId,
  'roomCode': '12345',
  'roomName': '资料房间',
  'topic': '公告',
  'topicTitle': '',
  'welcomeText': '',
  'accessMode': 'PUBLIC',
  'autoLockMic': false,
  'hallVisible': true,
  'status': 'OPEN',
  'version': 2,
  'passwordConfigured': false,
  'canControlLifecycle': owner,
};

class ProfileApi extends ApiClient {
  ProfileApi()
    : super(
        baseUri: Uri.parse('http://invalid.test/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer fixture',
      );
  Map<String, Object?> wire = profileWire();
  final paths = <String>[];
  String expectedRoomId = profileRoomId;
  Completer<void>? getGate;
  Completer<void>? saveGate;
  ApiException? saveError;
  final writes = <Map<String, Object?>>[];
  final requestIds = <String>[];

  @override
  Future<ApiResponse> patchBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    requireIdentity();
    expect(path, '/app-api/rooms/updateRoomInformation');
    writes.add(Map<String, Object?>.from(body!));
    requestIds.add(headers!['X-Request-Id']!);
    await saveGate?.future;
    requireIdentity();
    if (saveError != null) throw saveError!;
    wire = {...wire, ...body, 'version': (body['expectedVersion']! as int) + 1};
    wire.remove('password');
    return ApiResponse(
      code: 200,
      message: 'OK',
      data: {
        ...wire,
        'rtcStatus': 'DISABLED',
        'imStatus': 'DISABLED',
        'providerInvocation': false,
      },
    );
  }

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    paths.add(path);
    if (path == '/app-api/rooms/getRoomSelectByUserId') {
      return ApiResponse(
        code: 200,
        message: 'OK',
        data: {
          'list': [wire],
          'records': [wire],
          'current': 1,
          'size': 50,
          'pageSize': 50,
          'pages': 1,
          'total': 1,
        },
      );
    }
    if (path == '/app-api/rooms/getRoomTopics') {
      return ApiResponse(
        code: 200,
        message: 'OK',
        data: {...wire, 'canEdit': true},
      );
    }
    expect(path, '/app-api/rooms/editable-profile');
    expect(query, {'roomId': expectedRoomId});
    final captured = Map<String, Object?>.from(wire);
    await getGate?.future;
    return ApiResponse(code: 200, message: 'OK', data: captured);
  }
}

void main() {
  test('manager clear password is PUBLIC without password material', () async {
    final api = ProfileApi()
      ..wire = {
        ...profileWire(owner: false),
        'accessMode': 'PASSWORD',
        'passwordConfigured': true,
      };
    final repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: admittedRoomFixture(roomId: profileRoomId),
    );
    final room = await repo.fetchRoom(profileRoomId);
    await repo.saveRoom(room.copyWith(accessMode: RoomAccessMode.publicRoom));
    expect(api.writes.single['accessMode'], 'PUBLIC');
    expect(api.writes.single.containsKey('password'), isFalse);
  });

  test('manager keeps configured password when edit is blank', () async {
    final api = ProfileApi()
      ..wire = {
        ...profileWire(owner: false),
        'accessMode': 'PASSWORD',
        'passwordConfigured': true,
      };
    final repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: admittedRoomFixture(roomId: profileRoomId),
    );
    final room = await repo.fetchRoom(profileRoomId);
    await repo.saveRoom(room.copyWith(title: '只改房名'));
    expect(api.writes.single.containsKey('password'), isFalse);
    expect(api.writes.single['accessMode'], 'PASSWORD');
  });

  test('manager projection cannot create a lease or edit CLOSED', () async {
    for (final closed in [false, true]) {
      final api = ProfileApi()
        ..wire = {...profileWire(owner: false), if (closed) 'status': 'CLOSED'};
      final repo = BackendRoomLifecycleRepository(apiClient: api);
      await expectLater(
        repo.fetchRoom(profileRoomId),
        throwsA(isA<ApiException>()),
      );
      expect(repo.leaseBinding.current, isNull);
      expect(api.writes, isEmpty);
    }
  });

  test(
    'projection rejects malformed typed authority without coercion',
    () async {
      for (final invalid in <Map<String, Object?>>[
        {'canControlLifecycle': 'true'},
        {'passwordConfigured': 1},
        {'version': -1},
        {'version': '2'},
        {'status': 'RETIRED'},
        {'accessMode': 'APPROVAL'},
        {'roomId': 'another'},
        {'hallVisible': 1},
        {'autoLockMic': 'false'},
        {'topic': null},
      ]) {
        final api = ProfileApi()..wire = {...profileWire(), ...invalid};
        await expectLater(
          BackendRoomLifecycleRepository(
            apiClient: api,
          ).fetchRoom(profileRoomId),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
  test('manager save binds exact lease and omits owner controls', () async {
    final api = ProfileApi()..wire = profileWire(owner: false);
    final binding = admittedRoomFixture(roomId: profileRoomId);
    final repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: binding,
    );
    final room = await repo.fetchRoom(profileRoomId);
    expect(room.canControlLifecycle, isFalse);
    await repo.saveRoom(
      room.copyWith(
        title: '修改房名',
        password: '1234',
        accessMode: RoomAccessMode.password,
      ),
    );
    expect(api.writes.single['sessionId'], roomLeaseSessionId);
    expect(api.writes.single['expectedVersion'], 2);
    expect(api.writes.single.containsKey('hallVisible'), isFalse);
    expect(api.writes.single.containsKey('autoLockMic'), isFalse);
    expect(api.writes.single['password'], '1234');
  });

  test('closed owner may save without lease', () async {
    final api = ProfileApi()..wire['status'] = 'CLOSED';
    final repo = BackendRoomLifecycleRepository(apiClient: api);
    final room = await repo.fetchRoom(profileRoomId);
    await repo.saveRoom(room.copyWith(title: '关闭配置'));
    expect(api.writes.single.containsKey('sessionId'), isFalse);
    expect(api.writes.single['hallVisible'], true);
  });

  test('unknown manager save reuses original body and request id', () async {
    final api = ProfileApi()
      ..wire = profileWire(owner: false)
      ..saveError = const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'timeout',
      );
    final repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: admittedRoomFixture(roomId: profileRoomId),
    );
    final room = await repo.fetchRoom(profileRoomId);
    await expectLater(repo.saveRoom(room), throwsA(isA<ApiException>()));
    api.saveError = null;
    await repo.saveRoom(room);
    expect(api.requestIds[0], api.requestIds[1]);
    expect(api.writes[0], api.writes[1]);
  });

  for (final change in ['lease', 'identityABA']) {
    test(
      'stale $change cannot retry previous edit under new authority',
      () async {
        var auth = 0;
        final binding = RoomLeaseBinding(authenticationGeneration: () => auth);
        binding.bind(
          binding.beginEntry('one'),
          profileRoomId,
          1,
          parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
        );
        final api = ProfileApi()..wire = profileWire(owner: false);
        final repo = BackendRoomLifecycleRepository(
          apiClient: api,
          leaseBinding: binding,
        );
        final room = await repo.fetchRoom(profileRoomId);
        if (change == 'lease') {
          binding.beginEntry('two');
        } else {
          auth += 2;
        }
        await expectLater(repo.saveRoom(room), throwsA(isA<ApiException>()));
        expect(api.writes, isEmpty);
      },
    );
  }

  test('late projection is rejected after lease generation changes', () async {
    final binding = RoomLeaseBinding();
    final api = ProfileApi()..getGate = Completer<void>();
    final repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: binding,
    );
    final pending = repo.fetchRoom(profileRoomId);
    binding.beginEntry('another room');
    api.getGate!.complete();
    await expectLater(pending, throwsA(isA<ApiException>()));
  });
  test('editable profile is a single authority read, not owned list', () async {
    final api = ProfileApi();
    final room = await BackendRoomLifecycleRepository(
      apiClient: api,
    ).fetchRoom(profileRoomId);
    expect(room.title, '资料房间');
    expect(room.password, isEmpty);
    expect(api.paths, ['/app-api/rooms/editable-profile']);
  });
  for (final field in [
    'canControlLifecycle',
    'passwordConfigured',
    'version',
    'status',
    'roomId',
  ]) {
    test('editable profile fails closed without $field', () async {
      final api = ProfileApi()..wire.remove(field);
      await expectLater(
        BackendRoomLifecycleRepository(apiClient: api).fetchRoom(profileRoomId),
        throwsA(isA<ApiException>()),
      );
    });
  }
}
