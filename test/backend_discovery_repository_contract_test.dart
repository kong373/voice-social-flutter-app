import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/data/backend_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';

void main() {
  test('home and global search send exact pagination contracts', () async {
    final List<_RequestRecord> requests = <_RequestRecord>[];
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      requests.add(_RequestRecord(request, body));
      switch (request.uri.path) {
        case '/app-api/rooms/v1/getRecommendRooms':
          expect(request.method, 'POST');
          expect(body, <String, Object?>{
            'pageNum': 2,
            'pageSize': 1,
            'platform': 1,
            'rtcSolutionType': 0,
          });
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'roomIdStr': 'room-2',
                  'roomCode': '880217',
                  'roomName': '夜航电台',
                  'description': '晚间聊天',
                  'liveCount': 18,
                  'heatValue': 1,
                  'micUserHeadImgs': <Object?>[
                    '1',
                    '2',
                    '3',
                    '4',
                    '5',
                    '6',
                    '7',
                    '8',
                    '9',
                  ],
                  'isLockRoom': 1,
                },
              ],
            },
          );
        case '/app-api/es/getSearchESResult':
          expect(request.method, 'POST');
          expect(body, <String, Object?>{
            'keyword': '晚星',
            'type': 3,
            'pageNo': 2,
            'pageSize': 10,
          });
          return _reply(
            request,
            data: <String, Object?>{
              'roomsList': <Object?>[
                <String, Object?>{
                  'roomId': 'room-3',
                  'name': '星河房间',
                  'code': '123456',
                  'onlineNum': 4,
                  'collectionFlag': 1,
                },
              ],
              'usersList': <Object?>[
                <String, Object?>{
                  'userId': 10001,
                  'nickName': '晚星',
                  'loginName': '13800138000',
                  'isStayRoom': 'room-3',
                },
              ],
              'pageNo': 2,
              'pageSize': 10,
              'total': 30,
            },
          );
        default:
          return _reply(request, status: 404, code: 404, message: 'not found');
      }
    });
    addTearDown(() => server.close(force: true));
    final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
      apiClient: _client(server),
      clientType: 'Android',
    );

    final List<DiscoveryRoom> home = await repository.fetchHomeRooms(
      page: 2,
      pageSize: 1,
    );
    expect(home, hasLength(1));
    expect(home.single.id, 'room-2');
    expect(home.single.occupiedSeats, 8);
    expect(home.single.isSpeaking, isTrue);
    expect(home.single.isLocked, isTrue);

    final DiscoverySearchResult result = await repository.search(
      keyword: '  晚星 ',
      type: SearchEntityType.all,
      page: 2,
      pageSize: 10,
    );
    expect(result.rooms.single.title, '星河房间');
    expect(result.rooms.single.isFavorite, isTrue);
    expect(result.users.single.name, '晚星');
    expect(result.users.single.currentRoomId, 'room-3');
    expect(result.hasMore, isTrue);
    expect(requests, hasLength(2));
  });

  test(
    'room collections and favorite mutation preserve empty and non-empty states',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/user/favorite/getFvoriteRooms':
            expect(body, <String, Object?>{'pageNum': 3, 'pageSize': 2});
            return _reply(
              request,
              data: <String, Object?>{'records': <Object?>[], 'total': 0},
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            expect(request.method, 'GET');
            return _reply(
              request,
              data: <Object?>[
                <String, Object?>{
                  'id': 'owned-1',
                  'name': '我的房间',
                  'code': '999999',
                },
              ],
            );
          case '/app-api/user/favorite/starRoom':
            expect(request.method, 'PATCH');
            expect(request.uri.queryParameters, <String, String>{
              'roomId': 'owned-1',
              'roomIdStr': 'owned-1',
              'starType': '1',
            });
            return _reply(request, data: null);
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'iOS',
      );

      final RoomCollectionSnapshot snapshot = await repository
          .fetchRoomCollections(page: 3, pageSize: 2);
      expect(snapshot.favorites, isEmpty);
      expect(snapshot.ownedRooms.single.id, 'owned-1');
      expect(
        await repository.setFavorite(roomId: 'owned-1', favorite: true),
        isTrue,
      );
      expect(requests, hasLength(3));
    },
  );

  test(
    'search rejects blank input and propagates an authentication envelope',
    () async {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          status: 401,
          code: 40100,
          message: '登录已过期',
          data: null,
        ),
      );
      addTearDown(() => server.close(force: true));
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );

      await expectLater(
        repository.search(keyword: ' ', type: SearchEntityType.rooms),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.search(keyword: '880217', type: SearchEntityType.rooms),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.unauthorized,
          ),
        ),
      );
    },
  );
}

class _RequestRecord {
  _RequestRecord(HttpRequest request, this.body)
    : method = request.method,
      path = request.uri.path,
      authorization = captureContractAuthorization(request);

  final String method;
  final String path;
  final String authorization;
  final Object? body;
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request, Object? body) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? body = raw.trim().isEmpty ? null : jsonDecode(raw);
    await handler(request, body);
  });
  return server;
}

Future<void> _reply(
  HttpRequest request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{
        'code': code,
        'message': message,
        'data': data,
      }),
    );
  await request.response.close();
}

ApiClient _client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);
