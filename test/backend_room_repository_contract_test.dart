import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  test(
    'room snapshot contract preserves request shape and authoritative data',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.method, 'GET');
        expect(request.path, '/app-api/rooms/getRoomById');
        expect(request.query, <String, String>{'roomId': '9527'});
        return _Reply(
          data: <String, Object?>{
            'roomIdStr': '9527',
            'roomCode': 'R9527',
            'roomName': '夜航电台',
            'topicContent': '今晚聊电影',
            'ownerId': '10001',
            'onlineNum': '18',
            'coverImgUrl': 'https://cdn.example/room.png',
            'seats': <Map<String, Object?>>[
              <String, Object?>{
                'index': 0,
                'status': 1,
                'userId': 10001,
                'userName': '晚星',
                'avatarUrl': 'https://cdn.example/u.png',
              },
              <String, Object?>{'index': 1, 'status': 0},
            ],
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      final RoomSnapshot snapshot = await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.discoveryPost,
        currentUserId: 10001,
      );

      expect(snapshot.roomId, '9527');
      expect(snapshot.roomCode, 'R9527');
      expect(snapshot.title, '夜航电台');
      expect(snapshot.topic, '今晚聊电影');
      expect(snapshot.ownerId, 10001);
      expect(snapshot.role, RoomRole.owner);
      expect(snapshot.onlineCount, 18);
      expect(snapshot.coverUrl, 'https://cdn.example/room.png');
      expect(snapshot.transportMode, RoomTransportMode.snapshotOnly);
      expect(snapshot.rtc.solution, RtcSolution.unknown);
      expect(snapshot.rtc.token, isEmpty);
      expect(snapshot.isSnapshotOnly, isTrue);
      expect(snapshot.seats, hasLength(8));
      expect(snapshot.seats[0].state, MicSeatState.occupied);
      expect(snapshot.seats[0].userId, 10001);
      expect(snapshot.seats[0].userRole, RoomRole.owner);
      expect(snapshot.seats[1].state, MicSeatState.available);
      expect(snapshot.seats[7].backendIndex, 8);
    },
  );

  test('reconnect uses the same read-only snapshot contract', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: <String, Object?>{
          'id': 'room-abc',
          'name': '回声房',
          'description': '重连快照',
          'userId': 20002,
          'liveCount': 2,
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    final RoomSnapshot snapshot = await repository.reconnectRoom(
      roomId: 'room-abc',
      currentUserId: 10001,
    );

    expect(snapshot.roomId, 'room-abc');
    expect(snapshot.title, '回声房');
    expect(snapshot.topic, '重连快照');
    expect(snapshot.role, RoomRole.listener);
    expect(snapshot.onlineCount, 2);
    expect(server.requests, hasLength(1));
    expect(server.requests.single.query, <String, String>{
      'roomId': 'room-abc',
    });
  });

  test('empty snapshot envelope is rejected as a protocol error', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(data: <String, Object?>{}),
    );
    addTearDown(server.close);
    final BackendRoomRepository repository = BackendRoomRepository(
      apiClient: server.client,
    );

    await expectLater(
      repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'error envelope is surfaced without manufacturing a room snapshot',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 40901,
          message: '房间状态已变化',
          data: null,
          httpStatus: 409,
        ),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      await expectLater(
        repository.enterRoom(
          roomId: '9527',
          password: null,
          source: RoomEntrySource.search,
          currentUserId: 10001,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                '房间状态已变化',
              ),
        ),
      );
    },
  );

  test(
    'snapshot room never bypasses the vendor-blocked write boundary',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(data: <String, Object?>{}),
      );
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );

      Future<void> expectVendorBlocked(Future<void> operation) async {
        await expectLater(
          operation,
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException error) => error.kind,
                  'kind',
                  ApiFailureKind.configuration,
                )
                .having(
                  (ApiException error) => error.message,
                  'message',
                  contains('VENDOR_BLOCKED'),
                ),
          ),
        );
      }

      await expectVendorBlocked(repository.requestMic(0));
      await expectVendorBlocked(repository.leaveMic());
      await expectVendorBlocked(
        repository.setSelfMicrophoneMuted(backendMicIndex: 0, muted: true),
      );
      await expectVendorBlocked(
        repository.sendPublicMessage(roomId: '9527', content: 'hello'),
      );
      await expectLater(
        repository.sendGift(
          roomId: '9527',
          giftId: 1,
          receiverUserIds: <int>[10001],
          quantity: 1,
          giftFrom: 10001,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.configuration,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('VENDOR_BLOCKED'),
              ),
        ),
      );
      await repository.exitRoom('9527');
      expect(server.requests, isEmpty);
    },
  );
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
