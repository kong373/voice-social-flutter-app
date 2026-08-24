import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';

void main() {
  test(
    'deep link detail rejects an empty server roomId without request fallback',
    () async {
      final _RoomDetailServer server = await _RoomDetailServer.start(
        detail: const <String, Object?>{
          'roomId': '',
          'roomCode': 'R9527',
          'roomName': '夜航电台',
          'status': 'OPEN',
        },
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.resolveRoomLink('voice-social://room/9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'deep link detail rejects a server roomId that differs from request',
    () async {
      final _RoomDetailServer server = await _RoomDetailServer.start(
        detail: const <String, Object?>{
          'roomId': '9999',
          'roomCode': 'R9999',
          'roomName': '另一间房',
          'status': 'OPEN',
        },
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.resolveRoomLink('voice-social://room/9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'deep link rejects a topic payload without an authoritative roomId',
    () async {
      final _RoomDetailServer server = await _RoomDetailServer.start(
        detail: const <String, Object?>{
          'roomId': '9527',
          'roomCode': 'R9527',
          'roomName': '夜航电台',
          'status': 'OPEN',
        },
        topic: const <String, Object?>{'topic': '', 'welcomeText': ''},
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.resolveRoomLink('voice-social://room/9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('deep link rejects a topic roomId that differs from detail', () async {
    final _RoomDetailServer server = await _RoomDetailServer.start(
      detail: const <String, Object?>{
        'roomId': '9527',
        'roomCode': 'R9527',
        'roomName': '夜航电台',
        'status': 'OPEN',
      },
      topic: const <String, Object?>{
        'roomId': '9999',
        'topic': '',
        'welcomeText': '',
      },
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.resolveRoomLink('voice-social://room/9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('close rejects a padded server roomId echo', () async {
    final _CloseServer server = await _CloseServer.start(
      responseRoomId: ' 9527 ',
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.closeRoom('9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });
}

class _RoomDetailServer {
  _RoomDetailServer._(this.server);

  final HttpServer server;

  late final ApiClient client = ApiClient(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
    clientType: 'Android',
    clientInnerVersion: '6',
    authorizationProvider: () => 'Bearer room-lifecycle-test',
  );

  static Future<_RoomDetailServer> start({
    required Map<String, Object?> detail,
    Map<String, Object?> topic = const <String, Object?>{
      'roomId': '9527',
      'topic': '',
      'welcomeText': '',
    },
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      final Object? data = switch (request.uri.path) {
        '/app-api/rooms/getRoomById' => detail,
        '/app-api/rooms/getRoomTopics' => topic,
        _ => throw StateError('unexpected route: ${request.uri.path}'),
      };
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': data,
          }),
        );
      await request.response.close();
    });
    return _RoomDetailServer._(server);
  }

  Future<void> close() => server.close(force: true);
}

class _CloseServer {
  _CloseServer._(this.server);

  final HttpServer server;

  late final ApiClient client = ApiClient(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
    clientType: 'Android',
    clientInnerVersion: '6',
    authorizationProvider: () => 'Bearer room-lifecycle-test',
  );

  static Future<_CloseServer> start({required String responseRoomId}) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      if (request.uri.path != '/app-mini-api/mini/v1/rooms/close') {
        throw StateError('unexpected route: ${request.uri.path}');
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': <String, Object?>{
              'roomId': responseRoomId,
              'status': 'CLOSED',
              'closed': true,
            },
          }),
        );
      await request.response.close();
    });
    return _CloseServer._(server);
  }

  Future<void> close() => server.close(force: true);
}
