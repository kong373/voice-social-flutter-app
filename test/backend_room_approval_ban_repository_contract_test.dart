import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'approval and ban capabilities preserve first-party HTTP contracts',
    () async {
      final _ContractServer server = await _ContractServer.start((request) {
        switch (request.uri.path) {
          case '/app-mini-api/mini/v1/rooms/join-requests':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'roomId': 'room-9527',
              'pageNum': '1',
              'pageSize': '20',
            });
            return _Response(
              data: <String, Object?>{
                'list': <Object?>[
                  <String, Object?>{
                    'joinRequestId': 'join-request-1',
                    'status': 'PENDING',
                    'message': '想和大家一起聊天',
                    'userId': 10002,
                    'nickName': '晚星',
                    'headImgUrl': 'https://cdn.example/late.png',
                    'createdAt': '2026-08-25T08:00:00Z',
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'joinRequestId': 'join-request-1',
                    'status': 'PENDING',
                    'message': '想和大家一起聊天',
                    'userId': 10002,
                    'nickName': '晚星',
                    'headImgUrl': 'https://cdn.example/late.png',
                    'createdAt': '2026-08-25T08:00:00Z',
                  },
                ],
                'current': 1,
                'pageSize': 20,
                'size': 20,
                'total': 1,
                'pages': 1,
              },
            );
          case '/app-mini-api/mini/v1/rooms/banned-users':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'roomId': 'room-9527',
              'pageNum': '1',
              'pageSize': '20',
            });
            return _Response(
              data: <String, Object?>{
                'list': <Object?>[
                  <String, Object?>{
                    'userId': 10003,
                    'nickName': '清禾',
                    'reason': '重复刷屏',
                    'bannedAt': '2026-08-25T08:01:00Z',
                    'expiresAt': null,
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'userId': 10003,
                    'nickName': '清禾',
                    'reason': '重复刷屏',
                    'bannedAt': '2026-08-25T08:01:00Z',
                    'expiresAt': null,
                  },
                ],
                'current': 1,
                'pageSize': 20,
                'size': 20,
                'total': 1,
                'pages': 1,
              },
            );
          case '/app-mini-api/mini/v1/rooms/join-requests/resolve':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'joinRequestId': 'join-request-1',
              'approved': true,
            });
            expect(request.headers.value('X-Request-Id'), isNotEmpty);
            return const _Response(
              data: <String, Object?>{
                'joinRequestId': 'join-request-1',
                'status': 'APPROVED',
              },
            );
          case '/app-mini-api/mini/v1/rooms/unban':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': 'room-9527',
              'userId': 10003,
            });
            expect(request.headers.value('X-Request-Id'), isNotEmpty);
            return const _Response(
              data: <String, Object?>{
                'roomId': 'room-9527',
                'userId': 10003,
                'banned': false,
              },
            );
          default:
            fail('unexpected room capability route: ${request.uri.path}');
        }
      });
      addTearDown(server.close);

      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);
      final RoomJoinRequestPage requests = await repository.fetchJoinRequests(
        roomId: 'room-9527',
      );
      expect(requests.items.single.id, 'join-request-1');
      expect(requests.items.single.status, RoomJoinRequestStatus.pending);
      expect(requests.items.single.member.userId, 10002);
      expect(requests.items.single.message, '想和大家一起聊天');
      await repository.resolveJoinRequest(
        joinRequestId: 'join-request-1',
        approved: true,
      );

      final RoomBannedUserPage banned = await repository.fetchBannedUsers(
        roomId: 'room-9527',
      );
      expect(banned.items.single.member.userId, 10003);
      expect(banned.items.single.reason, '重复刷屏');
      expect(banned.items.single.expiresAt, isNull);
      await repository.unbanUser(roomId: 'room-9527', userId: 10003);
      expect(server.requests, hasLength(4));
    },
  );
}

class _ContractServer {
  _ContractServer._(this.server, this.handler)
    : client = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'contract-test',
        clientInnerVersion: 'contract-test',
        authorizationProvider: () => 'Bearer contract-test',
      );

  final HttpServer server;
  final FutureOr<_Response> Function(_CapturedRequest request) handler;
  final ApiClient client;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  static Future<_ContractServer> start(
    FutureOr<_Response> Function(_CapturedRequest request) handler,
  ) async {
    final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
    final _ContractServer value = _ContractServer._(server, handler);
    server.listen(value._serve);
    return value;
  }

  Future<void> _serve(HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
    final _CapturedRequest captured = _CapturedRequest(
      method: request.method,
      uri: request.uri,
      body: decoded is Map
          ? <String, Object?>{
              for (final MapEntry<Object?, Object?> entry in decoded.entries)
                entry.key.toString(): entry.value,
            }
          : null,
      headers: request.headers,
    );
    requests.add(captured);
    final _Response response = await handler(captured);
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'OK',
          'data': response.data,
        }),
      );
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.uri,
    required this.body,
    required this.headers,
  });

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
  final HttpHeaders headers;
}

class _Response {
  const _Response({required this.data});

  final Map<String, Object?> data;
}
