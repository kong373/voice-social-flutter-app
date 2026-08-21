import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

void main() {
  test('fetchRoom joins room information and topic contracts', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      switch (request.path) {
        case '/app-api/rooms/getRoomById':
          expect(request.method, 'GET');
          expect(request.query, <String, String>{'id': '9527'});
          return _Reply(
            data: <String, Object?>{
              'idStr': '9527',
              'code': 'R9527',
              'name': '夜航电台',
              'welcomeWord': '欢迎来到夜航电台',
              'isLock': '1',
              'password': '2468',
              'isShow': 1,
              'isAutoLockMic': '1',
              'status': 1,
              'sysStatus': 0,
              'coverImgUrl': 'https://cdn.example/room.png',
            },
          );
        case '/app-api/rooms/getRoomTopics':
          expect(request.method, 'GET');
          expect(request.query, <String, String>{'roomId': '9527'});
          return _Reply(
            data: <String, Object?>{
              'topicTitle': '今晚话题',
              'topicContent': '聊聊最近的电影',
            },
          );
        default:
          fail('unexpected lifecycle route: ${request.path}');
      }
    });
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    final RoomConfiguration room = await repository.fetchRoom('9527');
    expect(room.roomId, '9527');
    expect(room.roomCode, 'R9527');
    expect(room.title, '夜航电台');
    expect(room.topicTitle, '今晚话题');
    expect(room.topicContent, '聊聊最近的电影');
    expect(room.welcomeMessage, '欢迎来到夜航电台');
    expect(room.accessMode, RoomAccessMode.password);
    expect(room.password, '2468');
    expect(room.showInHall, isTrue);
    expect(room.autoLockMic, isTrue);
    expect(room.availability, RoomAvailability.open);
    expect(room.coverUrl, 'https://cdn.example/room.png');
    expect(server.requests, hasLength(2));
  });

  test(
    'owned room list is empty without manufacturing a configuration',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'GET');
        expect(request.path, '/app-api/rooms/getRoomSelectByUserId');
        expect(request.query, isEmpty);
        return const _Reply(data: <Object?>[]);
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      expect(await repository.fetchOwnedRoom(), isNull);
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'lifecycle error envelopes preserve HTTP and business failure details',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 40401,
          message: '房间不存在',
          data: null,
          httpStatus: 404,
        ),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.fetchRoom('9527'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.validation,
              )
              .having(
                (ApiException error) => error.httpStatus,
                'httpStatus',
                404,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                '房间不存在',
              ),
        ),
      );
    },
  );

  test(
    'saveRoom sends information and topic writes, then re-reads authority',
    () async {
      final List<_CapturedRequest> seen = <_CapturedRequest>[];
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        seen.add(request);
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
            expect(request.method, 'PUT');
            expect(request.body, <String, Object?>{
              'id': 9527,
              'name': '新房间',
              'isShow': 1,
              'isLock': 1,
              'password': '1357',
              'welcomeWord': '欢迎新朋友',
            });
            return const _Reply(data: null);
          case '/app-api/rooms/setRoomTopics':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'topicTitle': '新话题',
              'topicContent': '新的内容',
            });
            return const _Reply(data: null);
          case '/app-api/rooms/getRoomById':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'id': '9527'});
            return _Reply(
              data: <String, Object?>{
                'id': '9527',
                'code': 'R9527',
                'name': '新房间',
                'isLock': 1,
                'isShow': 1,
                'status': 1,
                'sysStatus': 0,
              },
            );
          case '/app-api/rooms/getRoomTopics':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <String, Object?>{
                'topicTitle': '新话题',
                'topicContent': '新的内容',
              },
            );
          default:
            fail('unexpected save route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      final RoomLifecycleSaveResult result = await repository.saveRoom(
        const RoomConfiguration(
          roomId: '9527',
          roomCode: 'R9527',
          title: '新房间',
          topicTitle: '新话题',
          topicContent: '新的内容',
          welcomeMessage: '欢迎新朋友',
          accessMode: RoomAccessMode.password,
          password: '1357',
          showInHall: true,
          autoLockMic: false,
          availability: RoomAvailability.open,
        ),
      );

      expect(result.roomId, '9527');
      expect(result.roomCode, 'R9527');
      expect(result.created, isFalse);
      expect(
        seen.map((_CapturedRequest request) => request.path),
        containsAllInOrder(<String>[
          '/app-api/rooms/updateRoomInformation',
          '/app-api/rooms/setRoomTopics',
          // The two authority reads may complete in either order.
        ]),
      );
      expect(server.requests, hasLength(4));
    },
  );

  test(
    'saveRoom rejects validation locally and detects authoritative conflict',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
          case '/app-api/rooms/setRoomTopics':
            return const _Reply(data: null);
          case '/app-api/rooms/getRoomById':
            return const _Reply(
              data: <String, Object?>{
                'id': '9527',
                'code': 'R9527',
                'name': '服务端已改名',
                'isShow': 1,
                'status': 1,
                'sysStatus': 0,
              },
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'topicTitle': '新话题',
                'topicContent': '新的内容',
              },
            );
          default:
            fail('unexpected conflict route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      const RoomConfiguration valid = RoomConfiguration(
        roomId: '9527',
        roomCode: 'R9527',
        title: '新房间',
        topicTitle: '新话题',
        topicContent: '新的内容',
        welcomeMessage: '欢迎',
        accessMode: RoomAccessMode.publicRoom,
        password: '',
        showInHall: true,
        autoLockMic: false,
        availability: RoomAvailability.open,
      );

      await expectLater(
        repository.saveRoom(valid.copyWith(title: '')),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      expect(server.requests, isEmpty);

      await expectLater(
        repository.saveRoom(valid),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.business,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('其他操作更新'),
              ),
        ),
      );
    },
  );

  test('room links distinguish invalid, closed, and valid snapshots', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      if (request.path == '/app-api/rooms/getRoomById') {
        final String roomId = request.query['id']!;
        return _Reply(
          data: <String, Object?>{
            'id': roomId,
            'code': 'R$roomId',
            'name': roomId == '9999' ? '已关闭房间' : '公开房间',
            'sysStatus': roomId == '9999' ? 1 : 0,
            'status': 1,
          },
        );
      }
      if (request.path == '/app-api/rooms/getRoomTopics') {
        return const _Reply(
          data: <String, Object?>{'topicTitle': '', 'topicContent': ''},
        );
      }
      fail('unexpected link route: ${request.path}');
    });
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    final RoomLinkResolution invalid = await repository.resolveRoomLink(
      'not-a-room',
    );
    expect(invalid.status, RoomLinkStatus.invalid);
    expect(server.requests, isEmpty);

    final RoomLinkResolution closed = await repository.resolveRoomLink(
      'voice-social://room/9999',
    );
    expect(closed.status, RoomLinkStatus.closed);
    expect(closed.canEnter, isFalse);

    final RoomLinkResolution valid = await repository.resolveRoomLink(
      'https://room/room/9527',
    );
    expect(valid.status, RoomLinkStatus.valid);
    expect(valid.canEnter, isTrue);
    expect(valid.room?.roomId, '9527');
  });

  test('unsupported create and close operations fail closed', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => fail('unexpected lifecycle write'),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);
    const RoomConfiguration newRoom = RoomConfiguration(
      title: '新房间',
      topicTitle: '',
      topicContent: '',
      welcomeMessage: '',
      accessMode: RoomAccessMode.publicRoom,
      password: '',
      showInHall: true,
      autoLockMic: false,
      availability: RoomAvailability.open,
    );

    await expectLater(
      repository.saveRoom(newRoom),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
    await expectLater(
      repository.closeRoom('9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
    expect(server.requests, isEmpty);
  });
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
}

class _Reply {
  const _Reply({
    this.code = 200,
    this.message = 'OK',
    this.data,
    this.httpStatus = 200,
  });

  final int code;
  final String message;
  final Object? data;
  final int httpStatus;
}

typedef _Responder = _Reply Function(_CapturedRequest request);

class _RunningServer {
  _RunningServer._(this.server, this.requests);

  final HttpServer server;
  final List<_CapturedRequest> requests;

  late final ApiClient client = ApiClient(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
    clientType: 'Android',
    clientInnerVersion: '6',
    authorizationProvider: () => 'Bearer contract-test',
  );

  static Future<_RunningServer> start(_Responder responder) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<_CapturedRequest> requests = <_CapturedRequest>[];
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? body = rawBody.trim().isEmpty ? null : jsonDecode(rawBody);
      final _CapturedRequest captured = _CapturedRequest(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: body,
      );
      requests.add(captured);
      final _Reply reply = responder(captured);
      request.response
        ..statusCode = reply.httpStatus
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': reply.code,
            'message': reply.message,
            'data': reply.data,
          }),
        );
      await request.response.close();
    });
    return _RunningServer._(server, requests);
  }

  Future<void> close() => server.close(force: true);
}
