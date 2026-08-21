import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'room operations use the documented HTTP shape and parse responses',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/getRoomOnlinePersonnel':
            expect(request.method, 'POST');
            expect(request.query, isEmpty);
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'pageNum': 2,
              'pageSize': 10,
              'isSearchCount': true,
            });
            return _Reply(
              data: <String, Object?>{
                'list': <Map<String, Object?>>[
                  <String, Object?>{
                    'userId': '10001',
                    'nickName': '晚星',
                    'headImgUrl': 'https://cdn.example/late.png',
                    'userRoomRole': 1,
                    'wealthLevel': '9',
                    'charmLevel': 7,
                  },
                ],
                'current': '2',
                'total': '21',
                'pages': '3',
              },
            );
          case '/app-api/rooms/getRoomMicDownOnlinePersonnel':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'roomId': 9527});
            return _Reply(
              data: <String, Object?>{
                'users': <Map<String, Object?>>[
                  <String, Object?>{
                    'userId': 10002,
                    'nickName': '南风',
                    'headImgUrl': 'https://cdn.example/nan.png',
                  },
                ],
              },
            );
          case '/app-api/roomUsers/getRoomManagers':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <Map<String, Object?>>[
                <String, Object?>{
                  'id': '10003',
                  'nickName': '青禾',
                  'userRoomRole': 5,
                },
              ],
            );
          case '/app-api/roomUsers/getRoomMuteds':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <Map<String, Object?>>[
                <String, Object?>{
                  'id': '10004',
                  'niceName': '白露',
                  'headImgUrl': 'https://cdn.example/bai.png',
                },
              ],
            );
          case '/app-api/rooms/getRoomTopics':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <String, Object?>{
                'topicTitle': '今晚话题',
                'topicContent': '聊聊最近看的电影',
              },
            );
          case '/app-api/rooms/setRoomTopics':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'topicTitle': '新标题',
              'topicContent': '新内容',
            });
            return const _Reply(data: null);
          case '/app-api/roomUsers/setMuted':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'userId': 10002,
              'isMuted': 1,
            });
            return const _Reply(data: null);
          case '/app-api/roomUsers/setRole':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomId': 9527,
              'userId': 10002,
              'userRoomRole': 0,
            });
            return const _Reply(data: null);
          case '/app-api/room/com/kickout':
            expect(request.method, 'POST');
            expect(request.query, <String, String>{
              'roomId': '9527',
              'beUserId': '10002',
            });
            return const _Reply(data: null);
          case '/app-api/micUserBase/hugUserDownMic':
            expect(request.method, 'PUT');
            expect(request.query, <String, String>{
              'micIndex': '3',
              'beUserId': '10002',
            });
            return const _Reply(data: null);
          case '/app-api/micBase/lockMike':
            expect(request.method, 'PUT');
            expect(request.query, <String, String>{'micIndex': '4'});
            return const _Reply(data: null);
          case '/app-api/micBase/unlockMike':
            expect(request.method, 'PUT');
            expect(request.query, <String, String>{'micIndex': '4'});
            return const _Reply(data: null);
          case '/app-api/micBase/openMike':
            expect(request.method, 'PUT');
            expect(request.query, <String, String>{'micIndex': '4'});
            return const _Reply(data: null);
          case '/app-api/micBase/closedMike':
            expect(request.method, 'PUT');
            expect(request.query, <String, String>{'micIndex': '5'});
            return const _Reply(data: null);
          default:
            fail('unexpected room operation route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final RoomMemberPage online = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 2,
        pageSize: 10,
      );
      expect(online.page, 2);
      expect(online.total, 21);
      expect(online.pages, 3);
      expect(online.hasMore, isTrue);
      expect(online.items.single.userId, 10001);
      expect(online.items.single.name, '晚星');
      expect(online.items.single.role, RoomRole.moderator);
      expect(online.items.single.wealthLevel, 9);
      expect(online.items.single.charmLevel, 7);

      final List<RoomMember> listeners = await repository.fetchOffMicListeners(
        '9527',
      );
      expect(listeners.single.name, '南风');
      expect(listeners.single.presence, RoomMemberPresence.listener);

      final List<RoomMember> managers = await repository.fetchManagers('9527');
      expect(managers.single.userId, 10003);
      expect(managers.single.role, RoomRole.moderator);

      final List<RoomMember> muted = await repository.fetchMutedUsers('9527');
      expect(muted.single.name, '白露');
      expect(muted.single.isMuted, isTrue);

      final RoomTopic topic = await repository.fetchTopic('9527');
      expect(topic.title, '今晚话题');
      expect(topic.content, '聊聊最近看的电影');
      await repository.updateTopic(
        roomId: '9527',
        topic: const RoomTopic(title: '新标题', content: '新内容'),
      );
      await repository.setUserMuted(roomId: '9527', userId: 10002, muted: true);
      await repository.setUserRole(
        roomId: '9527',
        userId: 10002,
        manager: false,
      );
      await repository.kickUser(roomId: '9527', userId: 10002);
      await repository.takeUserOffMic(backendMicIndex: 3, userId: 10002);
      await repository.setSeatLocked(backendMicIndex: 4, locked: true);
      await repository.setSeatLocked(backendMicIndex: 4, locked: false);
      await repository.setSeatMuted(backendMicIndex: 5, muted: true);

      expect(server.requests, hasLength(13));
      expect(repository.micCoordinationMode, MicCoordinationMode.direct);
    },
  );

  test(
    'direct-mic backend keeps unsupported approval operations fail-closed',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) =>
            fail('unexpected request: ${request.path}'),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      Future<void> expectConfiguration(Future<void> operation) async {
        await expectLater(
          operation,
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.configuration,
            ),
          ),
        );
      }

      expect(await repository.fetchMicRequests('9527'), isEmpty);
      await expectConfiguration(
        repository.submitMicRequest(
          roomId: '9527',
          userId: 10001,
          seatNumber: 3,
        ),
      );
      await expectConfiguration(
        repository.cancelMicRequest(requestId: 'request-1'),
      );
      await expectConfiguration(
        repository.resolveMicRequest(requestId: 'request-1', accepted: true),
      );
      await expectConfiguration(
        repository.inviteUserToMic(
          roomId: '9527',
          userId: 10002,
          seatNumber: 3,
        ),
      );
      expect(server.requests, isEmpty);
    },
  );

  test(
    'operation error envelopes preserve server failure classification',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          code: 42201,
          message: '话题内容不合法',
          data: null,
          httpStatus: 422,
        ),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      await expectLater(
        repository.fetchTopic('9527'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.validation,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                '话题内容不合法',
              ),
        ),
      );
    },
  );

  test(
    'empty member payloads resolve to empty pages without fake members',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(
          data: <String, Object?>{
            'list': <Object?>[],
            'current': 1,
            'total': 0,
            'pages': 1,
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);

      final RoomMemberPage page = await repository.fetchOnlineMembers(
        roomId: '9527',
        page: 1,
      );
      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
    },
  );
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String authorization;
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
        authorization: captureContractAuthorization(request),
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
