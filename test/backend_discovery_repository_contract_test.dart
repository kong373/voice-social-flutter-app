import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/data/backend_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';

void main() {
  test(
    'discovery preserves every supported authoritative online-count alias',
    () async {
      const Map<String, int> values = <String, int>{
        'onlineCount': 0,
        'liveCount': 12,
        'userTotal': 13,
        'onlineNum': 14,
      };

      for (final MapEntry<String, int> entry in values.entries) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'roomId': 'room-${entry.key}',
                  'roomName': '实时房间',
                  entry.key: entry.value,
                },
              ],
              'current': 1,
              'pageSize': 20,
              'total': 1,
            },
          ),
        );
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );

        try {
          final List<DiscoveryRoom> rooms = await repository.fetchHomeRooms();
          expect(rooms.single.onlineCount, entry.value, reason: entry.key);
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  test(
    'discovery keeps online count unknown for missing, invalid, and negative values',
    () async {
      const List<Map<String, Object?>> malformedCounts = <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'onlineCount': null},
        <String, Object?>{'onlineCount': 'not-a-count'},
        <String, Object?>{'onlineCount': -1},
        <String, Object?>{'onlineCount': -1, 'liveCount': 7},
      ];

      for (final Map<String, Object?> countFields in malformedCounts) {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'roomId': 'room-unknown',
                  'roomName': '实时房间',
                  ...countFields,
                },
              ],
              'current': 1,
              'pageSize': 20,
              'total': 1,
            },
          ),
        );
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );

        try {
          final List<DiscoveryRoom> rooms = await repository.fetchHomeRooms();
          expect(rooms.single.onlineCount, isNull, reason: '$countFields');
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  test(
    'home and global search use the first-party pagination contract',
    () async {
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
                    'topic': '晚间聊天',
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
                'current': 2,
                'pageSize': 1,
                'total': 2,
              },
            );
          case '/app-api/es/getSearchESResult':
            expect(request.method, 'POST');
            expect(body, <String, Object?>{
              'keyword': '晚星',
              'type': 0,
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
                    'loginName': 'user-10001',
                    'isStayRoom': 'room-3',
                  },
                ],
                'pageNo': 2,
                'pageSize': 10,
                'total': 30,
              },
            );
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
        clientType: 'Android',
      );

      final List<DiscoveryRoom> home = await repository.fetchHomeRooms(
        page: 2,
        pageSize: 1,
      );
      expect(home, hasLength(1));
      expect(home.single.id, 'room-2');
      expect(home.single.topic, '晚间聊天');
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
    },
  );

  test('search entity codes match the frozen first-party contract', () async {
    final List<int> observedTypes = <int>[];
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      observedTypes.add((body! as Map<String, Object?>)['type']! as int);
      return _reply(
        request,
        data: <String, Object?>{
          'roomsList': <Object?>[],
          'usersList': <Object?>[],
          'pageNo': 1,
          'pageSize': 20,
          'total': 0,
        },
      );
    });
    final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
      apiClient: _client(server),
      clientType: 'Android',
    );

    await repository.search(keyword: '晚星', type: SearchEntityType.all);
    await repository.search(keyword: '晚星', type: SearchEntityType.rooms);
    await repository.search(keyword: '晚星', type: SearchEntityType.users);
    expect(observedTypes, <int>[0, 1, 2]);
    await server.close(force: true);
  });

  test('global search rejects missing or drifting page metadata', () async {
    final List<Map<String, Object?>> malformedResponses =
        <Map<String, Object?>>[
          <String, Object?>{
            'roomsList': <Object?>[],
            'usersList': <Object?>[],
            'pageSize': 10,
            'total': 0,
          },
          <String, Object?>{
            'roomsList': <Object?>[],
            'usersList': <Object?>[],
            'pageNo': 2,
            'total': 0,
          },
          <String, Object?>{
            'roomsList': <Object?>[],
            'usersList': <Object?>[],
            'pageNo': 3,
            'pageSize': 10,
            'total': 0,
          },
          <String, Object?>{
            'roomsList': <Object?>[],
            'usersList': <Object?>[],
            'pageNo': 2,
            'pageSize': 20,
            'total': 0,
          },
          <String, Object?>{
            'roomsList': <Object?>[],
            'usersList': <Object?>[],
            'pageNo': 2,
            'pageSize': 10,
          },
        ];

    for (final Map<String, Object?> data in malformedResponses) {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(request, data: data),
      );
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );
      try {
        await expectLater(
          repository.search(
            keyword: '晚星',
            type: SearchEntityType.all,
            page: 2,
            pageSize: 10,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    }
  });

  test('discovery rejects non-map entries in every room/user list', () async {
    final List<({String path, Map<String, Object?> data})> malformedResponses =
        <({String path, Map<String, Object?> data})>[
          (
            path: '/app-api/rooms/v1/getRecommendRooms',
            data: <String, Object?>{
              'records': <Object?>[1],
            },
          ),
          (
            path: '/app-api/es/getSearchESResult',
            data: <String, Object?>{
              'roomsList': <Object?>[1],
              'pageNo': 1,
              'pageSize': 20,
              'total': 1,
            },
          ),
          (
            path: '/app-api/es/getSearchESResult',
            data: <String, Object?>{
              'usersList': <Object?>[1],
              'pageNo': 1,
              'pageSize': 20,
              'total': 1,
            },
          ),
        ];

    for (final ({String path, Map<String, Object?> data}) malformed
        in malformedResponses) {
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) {
        expect(request.uri.path, malformed.path);
        return _reply(request, data: malformed.data);
      });
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );
      try {
        final Future<Object?> operation = malformed.path.contains('getSearch')
            ? repository.search(keyword: '晚星', type: SearchEntityType.all)
            : repository.fetchHomeRooms();
        await expectLater(
          operation,
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    }
  });

  test(
    'discovery rejects conflicting room and user identity aliases',
    () async {
      final List<({String path, Map<String, Object?> data})> conflicts =
          <({String path, Map<String, Object?> data})>[
            (
              path: '/app-api/rooms/v1/getRecommendRooms',
              data: <String, Object?>{
                'records': <Object?>[
                  <String, Object?>{
                    'roomIdStr': 'room-authoritative',
                    'roomId': 'room-conflict',
                    'id': 'room-authoritative',
                  },
                ],
                'current': 1,
                'pageSize': 20,
                'total': 1,
              },
            ),
            (
              path: '/app-api/es/getSearchESResult',
              data: <String, Object?>{
                'roomsList': <Object?>[],
                'usersList': <Object?>[
                  <String, Object?>{'userId': 10001, 'id': 10002},
                ],
                'pageNo': 1,
                'pageSize': 20,
                'total': 1,
              },
            ),
          ];

      for (final ({String path, Map<String, Object?> data}) conflict
          in conflicts) {
        final HttpServer server = await _startServer((
          HttpRequest request,
          Object? body,
        ) {
          expect(request.uri.path, conflict.path);
          return _reply(request, data: conflict.data);
        });
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );
        try {
          final Future<Object?> operation = conflict.path.contains('getSearch')
              ? repository.search(keyword: '晚星', type: SearchEntityType.all)
              : repository.fetchHomeRooms();
          await expectLater(
            operation,
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  test('discovery accepts identity aliases only when they agree', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) {
      expect(request.uri.path, '/app-api/es/getSearchESResult');
      return _reply(
        request,
        data: <String, Object?>{
          'roomsList': <Object?>[
            <String, Object?>{
              'roomIdStr': 'room-1',
              'roomId': 'room-1',
              'id': 'room-1',
            },
          ],
          'usersList': <Object?>[
            <String, Object?>{'userId': 10001, 'id': 10001},
          ],
          'pageNo': 1,
          'pageSize': 20,
          'total': 2,
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
      apiClient: _client(server),
      clientType: 'Android',
    );

    final DiscoverySearchResult result = await repository.search(
      keyword: '晚星',
      type: SearchEntityType.all,
    );

    expect(result.rooms.single.id, 'room-1');
    expect(result.users.single.userId, 10001);
  });

  test('favorite and owned collections unwrap server page maps', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) async {
      switch (request.uri.path) {
        case '/app-api/user/favorite/getFvoriteRooms':
          expect(request.method, 'POST');
          expect(body, <String, Object?>{'pageNum': 3, 'pageSize': 2});
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'roomId': 'fav-1',
                  'roomCode': '100001',
                  'roomName': '收藏房',
                  'topic': '收藏话题',
                  'favorite': true,
                },
              ],
              'list': <Object?>[
                <String, Object?>{
                  'roomId': 'fav-1',
                  'roomCode': '100001',
                  'roomName': '收藏房',
                  'topic': '收藏话题',
                  'favorite': true,
                },
              ],
              'current': 3,
              'size': 2,
              'pageSize': 2,
              'total': 5,
              'pages': 3,
            },
          );
        case '/app-api/rooms/getRoomSelectByUserId':
          expect(request.method, 'GET');
          expect(request.uri.queryParameters, <String, String>{
            'pageNum': '3',
            'pageSize': '2',
          });
          return _reply(
            request,
            data: <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'roomId': 'owned-1',
                  'roomIdStr': 'owned-1',
                  'roomCode': '999999',
                  'roomName': '我的房间',
                  'topic': '房间公告',
                  'status': 'OPEN',
                },
              ],
              'list': <Object?>[
                <String, Object?>{
                  'roomId': 'owned-1',
                  'roomIdStr': 'owned-1',
                  'roomCode': '999999',
                  'roomName': '我的房间',
                  'topic': '房间公告',
                  'status': 'OPEN',
                },
              ],
              'current': 3,
              'size': 2,
              'pageSize': 2,
              'total': 5,
              'pages': 3,
            },
          );
        case '/app-api/user/favorite/starRoom':
          expect(request.method, 'POST');
          expect(request.uri.queryParameters, isEmpty);
          expect(body, <String, Object?>{
            'roomId': 'owned-1',
            'favorite': true,
            'type': 1,
          });
          return _reply(
            request,
            data: <String, Object?>{
              'roomId': 'owned-1',
              'favorite': true,
              'collectionFlag': 1,
            },
          );
        default:
          return _reply(request, status: 404, code: 404, message: 'not found');
      }
    });
    addTearDown(() => server.close(force: true));
    final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
      apiClient: _client(server),
      clientType: 'iOS',
    );

    final RoomCollectionSnapshot snapshot = await repository
        .fetchRoomCollections(page: 3, pageSize: 2);
    expect(snapshot.favorites.single.id, 'fav-1');
    expect(snapshot.favorites.single.isFavorite, isTrue);
    expect(snapshot.ownedRooms.single.id, 'owned-1');
    expect(snapshot.ownedRooms.single.topic, '房间公告');
    expect(
      await repository.setFavorite(roomId: 'owned-1', favorite: true),
      isTrue,
    );
  });

  test(
    'room collections fetch every authoritative page without gaps',
    () async {
      final List<String> requested = <String>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) {
        final int page = request.uri.path.contains('getFvoriteRooms')
            ? (body! as Map<String, Object?>)['pageNum']! as int
            : int.parse(request.uri.queryParameters['pageNum']!);
        final bool favorite = request.uri.path.contains('getFvoriteRooms');
        final String prefix = favorite ? 'fav' : 'owned';
        requested.add('$prefix-$page');
        final List<Object?> records = <Object?>[
          <String, Object?>{
            'roomId': '$prefix-$page',
            'roomName': '$prefix room $page',
          },
        ];
        return _reply(
          request,
          data: <String, Object?>{
            'records': records,
            'list': records,
            'current': page,
            'size': 1,
            'pageSize': 1,
            'total': 2,
            'pages': 2,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );

      final RoomCollectionSnapshot snapshot = await repository
          .fetchRoomCollections(pageSize: 1);
      expect(snapshot.favorites.map((DiscoveryRoom room) => room.id), <String>[
        'fav-1',
        'fav-2',
      ]);
      expect(snapshot.ownedRooms.map((DiscoveryRoom room) => room.id), <String>[
        'owned-1',
        'owned-2',
      ]);
      expect(
        requested,
        containsAll(<String>['fav-1', 'fav-2', 'owned-1', 'owned-2']),
      );
    },
  );

  test('room collections reject missing or divergent page authority', () async {
    final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
      <String, Object?>{
        'records': <Object?>[],
        'list': <Object?>[],
        'current': 1,
        'size': 20,
        'pageSize': 20,
        'total': 0,
      },
      <String, Object?>{
        'records': <Object?>[
          <String, Object?>{'roomId': 'room-a'},
        ],
        'list': <Object?>[
          <String, Object?>{'roomId': 'room-b'},
        ],
        'current': 1,
        'size': 20,
        'pageSize': 20,
        'total': 1,
        'pages': 1,
      },
      <String, Object?>{
        'records': <Object?>[],
        'list': <Object?>[],
        'current': 2,
        'size': 20,
        'pageSize': 20,
        'total': 0,
        'pages': 0,
      },
    ];

    for (final Map<String, Object?> data in malformed) {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(request, data: data),
      );
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );
      try {
        await expectLater(
          repository.fetchRoomCollections(pageSize: 20),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    }
  });

  test('favorite mutation parses an explicit false status', () async {
    final HttpServer server = await _startServer((
      HttpRequest request,
      Object? body,
    ) {
      expect(request.uri.path, '/app-api/user/favorite/starRoom');
      expect(request.method, 'POST');
      expect(body, <String, Object?>{
        'roomId': 'owned-1',
        'favorite': false,
        'type': 0,
      });
      return _reply(
        request,
        data: <String, Object?>{
          'roomId': 'owned-1',
          'favorite': false,
          'collectionFlag': 0,
        },
      );
    });
    addTearDown(() => server.close(force: true));
    final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
      apiClient: _client(server),
      clientType: 'Android',
    );

    expect(
      await repository.setFavorite(roomId: 'owned-1', favorite: false),
      isFalse,
    );
  });

  test(
    'favorite mutation rejects successful envelopes without status',
    () async {
      final List<Object?> malformedData = <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{'roomId': 'owned-1'},
        <String, Object?>{
          'roomId': 'another-room',
          'favorite': true,
          'collectionFlag': 1,
        },
        <String, Object?>{
          'roomId': 'owned-1',
          'favorite': true,
          'collectionFlag': 0,
        },
        <String, Object?>{
          'roomId': 'owned-1',
          'favorite': false,
          'collectionFlag': 0,
        },
      ];

      for (final Object? data in malformedData) {
        final HttpServer server = await _startServer((
          HttpRequest request,
          Object? body,
        ) {
          expect(request.uri.path, '/app-api/user/favorite/starRoom');
          expect(request.method, 'POST');
          return _reply(request, data: data);
        });
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );

        try {
          await expectLater(
            repository.setFavorite(roomId: 'owned-1', favorite: true),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  test(
    'favorite retains pending idempotency keys and coalesces duplicate intent',
    () async {
      final List<String> requestIds = <String>[];
      final Completer<void> releaseReplay = Completer<void>();
      int calls = 0;
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.uri.path, '/app-api/user/favorite/starRoom');
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        calls += 1;
        if (calls == 1) {
          return _reply(
            request,
            status: 409,
            code: 40902,
            message: 'request still in progress',
          );
        }
        if (calls == 2) {
          await releaseReplay.future;
        }
        return _reply(
          request,
          data: <String, Object?>{
            'roomId': 'owned-1',
            'favorite': true,
            'collectionFlag': 1,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );

      await expectLater(
        repository.setFavorite(roomId: 'owned-1', favorite: true),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40902,
          ),
        ),
      );
      final Future<bool> retry = repository.setFavorite(
        roomId: 'owned-1',
        favorite: true,
      );
      final Future<bool> duplicate = repository.setFavorite(
        roomId: 'owned-1',
        favorite: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 2);
      releaseReplay.complete();

      expect(await Future.wait(<Future<bool>>[retry, duplicate]), <bool>[
        true,
        true,
      ]);
      expect(requestIds, hasLength(2));
      expect(requestIds[0], isNotEmpty);
      expect(requestIds[1], requestIds[0]);
    },
  );

  for (final (int status, ApiFailureKind kind) in <(int, ApiFailureKind)>[
    (401, ApiFailureKind.unauthorized),
    (403, ApiFailureKind.forbidden),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test(
      'favorite write preserves $status failure without fake state',
      () async {
        final HttpServer server = await _startServer(
          (HttpRequest request, Object? body) => _reply(
            request,
            status: status,
            code: status == 500 ? 50001 : status,
            message: 'favorite failure $status',
          ),
        );
        addTearDown(() => server.close(force: true));
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );

        await expectLater(
          repository.setFavorite(roomId: 'owned-1', favorite: true),
          throwsA(
            isA<ApiException>()
                .having((ApiException error) => error.kind, 'kind', kind)
                .having(
                  (ApiException error) => error.message,
                  'message',
                  'favorite failure $status',
                ),
          ),
        );
      },
    );
  }

  for (final (int conflictCode, bool shouldReuseRequestId) in <(int, bool)>[
    (40901, true),
    (40902, true),
    (40903, false),
  ]) {
    test(
      'favorite handles $conflictCode with explicit request-id policy',
      () async {
        final List<String> requestIds = <String>[];
        int calls = 0;
        final HttpServer server = await _startServer((
          HttpRequest request,
          Object? body,
        ) {
          expect(request.uri.path, '/app-api/user/favorite/starRoom');
          requestIds.add(request.headers.value('X-Request-Id') ?? '');
          calls += 1;
          if (calls == 1) {
            return _reply(
              request,
              status: 409,
              code: conflictCode,
              message: 'idempotency conflict',
            );
          }
          return _reply(
            request,
            data: <String, Object?>{
              'roomId': 'owned-1',
              'favorite': true,
              'collectionFlag': 1,
            },
          );
        });
        addTearDown(() => server.close(force: true));
        final BackendDiscoveryRepository repository =
            BackendDiscoveryRepository(
              apiClient: _client(server),
              clientType: 'Android',
            );

        await expectLater(
          repository.setFavorite(roomId: 'owned-1', favorite: true),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.code,
              'code',
              conflictCode,
            ),
          ),
        );
        expect(
          await repository.setFavorite(roomId: 'owned-1', favorite: true),
          isTrue,
        );

        expect(requestIds, hasLength(2));
        expect(requestIds[0], isNotEmpty);
        expect(
          requestIds[1] == requestIds[0],
          shouldReuseRequestId,
          reason: '$conflictCode request-id policy',
        );
      },
    );
  }

  test(
    'blank search is rejected before network and auth envelopes propagate',
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
        repository.fetchHomeRooms(pageSize: 51),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.search(
          keyword: List<String>.filled(65, '长').join(),
          type: SearchEntityType.all,
        ),
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

  test('discovery propagates 400, 403, 409, 422, and 500 envelopes', () async {
    const List<int> statuses = <int>[400, 403, 409, 422, 500];
    for (final int status in statuses) {
      final HttpServer server = await _startServer(
        (HttpRequest request, Object? body) => _reply(
          request,
          status: status,
          code: status == 500 ? 50001 : status * 100,
          message: 'failure',
        ),
      );
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );
      final ApiFailureKind expected = switch (status) {
        403 => ApiFailureKind.forbidden,
        409 => ApiFailureKind.conflict,
        500 => ApiFailureKind.server,
        _ => ApiFailureKind.validation,
      };
      await expectLater(
        repository.fetchHomeRooms(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            expected,
          ),
        ),
      );
      await server.close(force: true);
    }
  });

  test(
    'search suggestions use the reviewed read-only authority contract',
    () async {
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/app-api/es/getSearchSuggestions');
        expect(request.uri.queryParameters, <String, String>{'limit': '5'});
        expect(captureContractAuthorization(request), 'Bearer contract-test');
        expect(body, isNull);
        await _reply(
          request,
          data: <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'keyword': '深夜陪伴',
                'source': 'ROOM_HOT_TITLE',
                'moderationStatus': 'FIRST_PARTY_REVIEWED',
              },
              <String, Object?>{
                'keyword': '音乐点唱',
                'source': 'CURATED_SEED',
                'moderationStatus': 'FIRST_PARTY_REVIEWED',
              },
            ],
            'records': <Object?>[
              <String, Object?>{
                'keyword': '深夜陪伴',
                'source': 'ROOM_HOT_TITLE',
                'moderationStatus': 'FIRST_PARTY_REVIEWED',
              },
              <String, Object?>{
                'keyword': '音乐点唱',
                'source': 'CURATED_SEED',
                'moderationStatus': 'FIRST_PARTY_REVIEWED',
              },
            ],
            'total': 2,
            'providerInvocation': false,
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendDiscoveryRepository repository = BackendDiscoveryRepository(
        apiClient: _client(server),
        clientType: 'Android',
      );

      final List<DiscoverySearchSuggestion> suggestions = await repository
          .fetchSearchSuggestions(limit: 5);

      expect(
        suggestions.map((DiscoverySearchSuggestion item) => item.keyword),
        <String>['深夜陪伴', '音乐点唱'],
      );
      expect(suggestions.first.source, DiscoverySuggestionSource.roomHotTitle);
      expect(suggestions.last.source, DiscoverySuggestionSource.curatedSeed);
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
