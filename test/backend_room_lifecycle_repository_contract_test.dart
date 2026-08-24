import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_intent_digest.dart';

void main() {
  test('fetchRoom joins room information and topic contracts', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      switch (request.path) {
        case '/app-api/rooms/getRoomSelectByUserId':
          expect(request.method, 'GET');
          expect(request.query, <String, String>{
            'pageNum': '1',
            'pageSize': '50',
          });
          return _Reply(
            data: <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'roomId': '9527',
                  'roomIdStr': '9527',
                  'roomCode': 'R9527',
                  'roomName': '夜航电台',
                  'topic': '列表中的旧话题，不作为编辑 authority',
                  'accessMode': 'APPROVAL',
                  'hallVisible': false,
                  'status': 'OPEN',
                  'topicTitle': '电影夜',
                  'autoLockMic': true,
                  'coverImgUrl': 'https://cdn.example/room.png',
                },
              ],
              'records': <Object?>[
                <String, Object?>{
                  'roomId': '9527',
                  'roomIdStr': '9527',
                  'roomCode': 'R9527',
                  'roomName': '夜航电台',
                  'topic': '列表中的旧话题，不作为编辑 authority',
                  'accessMode': 'APPROVAL',
                  'hallVisible': false,
                  'status': 'OPEN',
                  'topicTitle': '电影夜',
                  'autoLockMic': true,
                  'coverImgUrl': 'https://cdn.example/room.png',
                },
              ],
              'current': 1,
              'pageSize': 50,
              'size': 50,
              'total': 1,
              'pages': 1,
            },
          );
        case '/app-api/rooms/getRoomTopics':
          expect(request.method, 'GET');
          expect(request.query, <String, String>{'roomId': '9527'});
          return _Reply(
            data: <String, Object?>{
              'topic': '聊聊最近的电影',
              'topicTitle': '电影夜',
              'welcomeText': '欢迎来到夜航电台',
              'autoLockMic': true,
              'roomId': '9527',
              'canEdit': true,
              'version': 4,
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
    expect(room.topicTitle, '电影夜');
    expect(room.topicContent, '聊聊最近的电影');
    expect(room.welcomeMessage, '欢迎来到夜航电台');
    expect(room.accessMode, RoomAccessMode.approval);
    expect(room.password, isEmpty);
    expect(room.showInHall, isFalse);
    expect(room.autoLockMic, isTrue);
    expect(room.availability, RoomAvailability.open);
    expect(room.coverUrl, 'https://cdn.example/room.png');
    expect(room.version, 4);
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
        expect(request.query, <String, String>{
          'pageNum': '1',
          'pageSize': '50',
        });
        return const _Reply(
          data: <String, Object?>{
            'list': <Object?>[],
            'records': <Object?>[],
            'current': 1,
            'pageSize': 50,
            'size': 50,
            'pages': 0,
            'total': 0,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      expect(await repository.fetchOwnedRoom(), isNull);
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'closed owner room is read-only and preserves lifecycle controls',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        if (request.path == '/app-api/rooms/getRoomSelectByUserId') {
          return _Reply(
            data: _ownerPage(
              row: const <String, Object?>{
                'roomId': '9527',
                'roomCode': 'R9527',
                'roomName': '已关闭房间',
                'accessMode': 'PUBLIC',
                'hallVisible': false,
                'status': 'CLOSED',
                'topicTitle': '保留标题',
                'autoLockMic': true,
              },
            ),
          );
        }
        return const _Reply(
          data: <String, Object?>{
            'roomId': '9527',
            'topicTitle': '保留标题',
            'topic': '保留内容',
            'welcomeText': '',
            'autoLockMic': true,
            'canEdit': false,
            'version': 9,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      final RoomConfiguration room = await repository.fetchRoom('9527');

      expect(room.availability, RoomAvailability.closed);
      expect(room.topicTitle, '保留标题');
      expect(room.autoLockMic, isTrue);
    },
  );

  test(
    'create rejects a created snapshot that does not echo the submitted configuration',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _createSnapshot(
            roomName: '服务端另一间房',
            topic: '服务端话题',
            welcomeText: '服务端欢迎语',
            accessMode: 'PUBLIC',
            hallVisible: false,
            created: true,
            reused: false,
          ),
        ),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.saveRoom(
          const RoomConfiguration(
            title: '提交房间',
            topicTitle: '',
            topicContent: '提交话题',
            welcomeMessage: '提交欢迎语',
            accessMode: RoomAccessMode.publicRoom,
            password: '',
            showInHall: true,
            autoLockMic: false,
            availability: RoomAvailability.open,
          ),
        ),
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
    'create requires explicit mutually-exclusive flags and vendor boundary fields',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: <String, Object?>{
            'roomId': 'room-created',
            'roomCode': '9527',
            'roomName': '新房间',
            'topic': '',
            'welcomeText': '',
            'status': 'OPEN',
            'accessMode': 'PUBLIC',
            'hallVisible': true,
            'created': false,
            'reused': false,
            'rtcStatus': 'VENDOR_BLOCKED',
            'imStatus': 'VENDOR_BLOCKED',
            // providerInvocation is intentionally omitted.
          },
        ),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.saveRoom(
          const RoomConfiguration(
            title: '新房间',
            topicTitle: '',
            topicContent: '',
            welcomeMessage: '',
            accessMode: RoomAccessMode.publicRoom,
            password: '',
            showInHall: true,
            autoLockMic: false,
            availability: RoomAvailability.open,
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('create rejects a non-boolean hallVisible', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: _createSnapshot(
          hallVisible: 'true',
          created: true,
          reused: false,
        ),
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.saveRoom(_newPublicRoom()),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('create never fills missing snapshot fields from the request', () async {
    final Map<String, Object?> snapshot = _createSnapshot(
      created: true,
      reused: false,
    )..remove('topic');
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(data: snapshot),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.saveRoom(_newPublicRoom()),
      throwsA(isA<ApiException>()),
    );
  });

  test('create rejects non-frozen vendor metadata', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: _createSnapshot(
          created: true,
          reused: false,
          providerInvocation: 'false',
        ),
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.saveRoom(_newPublicRoom()),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'reused create result is explicit and may return existing configuration',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => _Reply(
          data: _createSnapshot(
            roomName: '已有房间',
            topic: '已有话题',
            welcomeText: '已有欢迎语',
            accessMode: 'APPROVAL',
            hallVisible: false,
            created: false,
            reused: true,
          ),
        ),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      final RoomLifecycleSaveResult result = await repository.saveRoom(
        _newPublicRoom(),
      );
      expect(result.created, isFalse);
      expect(result.roomId, 'room-created');
      expect(result.roomCode, '9527');
    },
  );

  test('owner room status rejects values outside OPEN and CLOSED', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: _ownerPage(
          row: <String, Object?>{
            'roomId': '9527',
            'roomCode': 'R9527',
            'roomName': '未知状态房',
            'accessMode': 'PUBLIC',
            'hallVisible': true,
            'status': 'PAUSED',
          },
        ),
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.fetchRoom('9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('owner pagination refuses more than 100 pages', () async {
    final List<Object?> rows = List<Object?>.generate(
      50,
      (int index) => <String, Object?>{
        'roomId': 'room-$index',
        'roomCode': 'R$index',
        'roomName': '房间 $index',
        'accessMode': 'PUBLIC',
        'hallVisible': true,
        'status': 'OPEN',
      },
    );
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: <String, Object?>{
          'list': rows,
          'records': rows,
          'current': 1,
          'pageSize': 50,
          'size': 50,
          'total': 5050,
          'pages': 101,
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.fetchOwnedRoom(),
      throwsA(isA<ApiException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test(
    'owner room topic requires exact identity, canEdit true, and version',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        if (request.path == '/app-api/rooms/getRoomSelectByUserId') {
          return _Reply(
            data: _ownerPage(
              row: <String, Object?>{
                'roomId': '9527',
                'roomCode': 'R9527',
                'roomName': '话题房',
                'accessMode': 'PUBLIC',
                'hallVisible': true,
                'status': 'OPEN',
              },
            ),
          );
        }
        return const _Reply(
          data: <String, Object?>{
            'roomId': '9527',
            'topic': '公告',
            'welcomeText': '欢迎',
            'canEdit': false,
            'version': -1,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.fetchRoom('9527'),
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

  test('owner hallVisible must be an explicit bool', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => _Reply(
        data: _ownerPage(
          row: <String, Object?>{
            'roomId': '9527',
            'roomCode': 'R9527',
            'roomName': '布尔房',
            'accessMode': 'PUBLIC',
            'hallVisible': 'true',
            'status': 'OPEN',
          },
        ),
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.fetchRoom('9527'),
      throwsA(isA<ApiException>()),
    );
  });

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
    'empty room detail is rejected instead of becoming a fake room',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) => const _Reply(data: <String, Object?>{}),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.fetchRoom('9527'),
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

  test('owner configuration fails closed when accessMode is absent', () async {
    final _RunningServer server = await _RunningServer.start(
      (_CapturedRequest request) => const _Reply(
        data: <String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'roomId': '9527',
              'roomCode': 'R9527',
              'roomName': '锁定但未声明模式',
              'hallVisible': true,
              'status': 'OPEN',
              'locked': true,
            },
          ],
          'records': <Object?>[
            <String, Object?>{
              'roomId': '9527',
              'roomCode': 'R9527',
              'roomName': '锁定但未声明模式',
              'hallVisible': true,
              'status': 'OPEN',
              'locked': true,
            },
          ],
          'current': 1,
          'pageSize': 50,
          'size': 50,
          'total': 1,
          'pages': 1,
        },
      ),
    );
    addTearDown(server.close);
    final BackendRoomLifecycleRepository repository =
        BackendRoomLifecycleRepository(apiClient: server.client);

    await expectLater(
      repository.fetchRoom('9527'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
    expect(server.requests, hasLength(1));
  });

  test(
    'saveRoom sends one authoritative information write, then re-reads authority',
    () async {
      final List<_CapturedRequest> seen = <_CapturedRequest>[];
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        seen.add(request);
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'roomName': '新房间',
              'topicTitle': '新话题',
              'topic': '新的内容',
              'welcomeText': '欢迎新朋友',
              'accessMode': 'PASSWORD',
              'hallVisible': true,
              'autoLockMic': false,
              'password': '1357',
              'expectedVersion': 3,
            });
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新话题',
                'autoLockMic': false,
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 4,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'pageNum': '1',
              'pageSize': '50',
            });
            return _Reply(
              data: <String, Object?>{
                'list': <Object?>[
                  <String, Object?>{
                    'roomId': '9527',
                    'roomCode': 'R9527',
                    'roomName': '新房间',
                    'accessMode': 'PASSWORD',
                    'hallVisible': true,
                    'status': 'OPEN',
                    'topicTitle': '新话题',
                    'autoLockMic': false,
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'roomId': '9527',
                    'roomCode': 'R9527',
                    'roomName': '新房间',
                    'accessMode': 'PASSWORD',
                    'hallVisible': true,
                    'status': 'OPEN',
                    'topicTitle': '新话题',
                    'autoLockMic': false,
                  },
                ],
                'current': 1,
                'pageSize': 50,
                'size': 50,
                'total': 1,
                'pages': 1,
              },
            );
          case '/app-api/rooms/getRoomTopics':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{'roomId': '9527'});
            return _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新话题',
                'topic': '新的内容',
                'welcomeText': '欢迎新朋友',
                'autoLockMic': false,
                'canEdit': true,
                'version': 4,
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
          version: 3,
        ),
      );

      expect(result.roomId, '9527');
      expect(result.roomCode, 'R9527');
      expect(result.created, isFalse);
      expect(
        seen.map((_CapturedRequest request) => request.path),
        containsAllInOrder(<String>[
          '/app-api/rooms/updateRoomInformation',
          // The two authority reads may complete in either order.
        ]),
      );
      expect(seen, hasLength(3));
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
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'roomCode': 'R9527',
                'roomName': '服务端已改名',
                'topicTitle': '新话题',
                'autoLockMic': false,
                'hallVisible': true,
                'accessMode': 'PUBLIC',
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 1,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            expect(request.query, <String, String>{
              'pageNum': '1',
              'pageSize': '50',
            });
            return const _Reply(
              data: <String, Object?>{
                'list': <Object?>[
                  <String, Object?>{
                    'roomId': '9527',
                    'roomCode': 'R9527',
                    'roomName': '服务端已改名',
                    'accessMode': 'PUBLIC',
                    'hallVisible': true,
                    'status': 'OPEN',
                    'topicTitle': '新话题',
                    'autoLockMic': false,
                  },
                ],
                'records': <Object?>[
                  <String, Object?>{
                    'roomId': '9527',
                    'roomCode': 'R9527',
                    'roomName': '服务端已改名',
                    'accessMode': 'PUBLIC',
                    'hallVisible': true,
                    'status': 'OPEN',
                    'topicTitle': '新话题',
                    'autoLockMic': false,
                  },
                ],
                'current': 1,
                'pageSize': 50,
                'size': 50,
                'total': 1,
                'pages': 1,
              },
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新话题',
                'topic': '新的内容',
                'welcomeText': '欢迎',
                'autoLockMic': false,
                'canEdit': true,
                'version': 1,
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
        version: 0,
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

  test(
    'saveRoom detects authoritative accessMode drift after update',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '',
                'autoLockMic': false,
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 1,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            return _Reply(
              data: _ownerPage(
                row: <String, Object?>{
                  'roomId': '9527',
                  'roomCode': 'R9527',
                  'roomName': '新房间',
                  'accessMode': 'PUBLIC',
                  'hallVisible': true,
                  'status': 'OPEN',
                  'topicTitle': '',
                  'autoLockMic': false,
                },
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '',
                'topic': '',
                'welcomeText': '',
                'autoLockMic': false,
                'canEdit': true,
                'version': 1,
              },
            );
          default:
            fail('unexpected accessMode drift route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.saveRoom(
          const RoomConfiguration(
            roomId: '9527',
            roomCode: 'R9527',
            title: '新房间',
            topicTitle: '',
            topicContent: '',
            welcomeMessage: '',
            accessMode: RoomAccessMode.password,
            password: '1357',
            showInHall: true,
            autoLockMic: false,
            availability: RoomAvailability.open,
            version: 0,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.business,
          ),
        ),
      );
    },
  );

  test(
    'saveRoom detects authoritative hallVisible drift after update',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '',
                'autoLockMic': false,
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 1,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            return _Reply(
              data: _ownerPage(
                row: <String, Object?>{
                  'roomId': '9527',
                  'roomCode': 'R9527',
                  'roomName': '新房间',
                  'accessMode': 'PUBLIC',
                  'hallVisible': false,
                  'status': 'OPEN',
                  'topicTitle': '',
                  'autoLockMic': false,
                },
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '',
                'topic': '',
                'welcomeText': '',
                'autoLockMic': false,
                'canEdit': true,
                'version': 1,
              },
            );
          default:
            fail('unexpected hallVisible drift route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.saveRoom(
          const RoomConfiguration(
            roomId: '9527',
            roomCode: 'R9527',
            title: '新房间',
            topicTitle: '',
            topicContent: '',
            welcomeMessage: '',
            accessMode: RoomAccessMode.publicRoom,
            password: '',
            showInHall: true,
            autoLockMic: false,
            availability: RoomAvailability.open,
            version: 0,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.business,
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
        final String roomId = request.query['roomId']!;
        return _Reply(
          data: <String, Object?>{
            'roomId': roomId,
            'roomCode': 'R$roomId',
            'roomName': roomId == '9999' ? '已关闭房间' : '公开房间',
            'status': roomId == '9999' ? 'CLOSED' : 'OPEN',
          },
        );
      }
      if (request.path == '/app-api/rooms/getRoomTopics') {
        return _Reply(
          data: <String, Object?>{
            'roomId': request.query['roomId']!,
            'topicTitle': '',
            'topic': '',
            'welcomeText': '',
            'autoLockMic': false,
            'version': 0,
          },
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

    final RoomLinkResolution uuid = await repository.resolveRoomLink(
      'voice-social://room/550e8400-e29b-41d4-a716-446655440000',
    );
    expect(uuid.status, RoomLinkStatus.valid);
    expect(uuid.room?.roomId, '550e8400-e29b-41d4-a716-446655440000');
  });

  test(
    'create, update, and close preserve 403/409/422/500 envelopes with request ids',
    () async {
      final List<
        ({
          String name,
          String path,
          Future<void> Function(BackendRoomLifecycleRepository repository)
          invoke,
        })
      >
      writes =
          <
            ({
              String name,
              String path,
              Future<void> Function(BackendRoomLifecycleRepository repository)
              invoke,
            })
          >[
            (
              name: 'create',
              path: '/app-mini-api/mini/v1/rooms',
              invoke: (BackendRoomLifecycleRepository repository) async {
                await repository.saveRoom(_newPublicRoom());
              },
            ),
            (
              name: 'update',
              path: '/app-api/rooms/updateRoomInformation',
              invoke: (BackendRoomLifecycleRepository repository) async {
                await repository.saveRoom(_existingPublicRoom());
              },
            ),
            (
              name: 'close',
              path: '/app-mini-api/mini/v1/rooms/close',
              invoke: (BackendRoomLifecycleRepository repository) async {
                await repository.closeRoom('9527', expectedVersion: 0);
              },
            ),
          ];
      final List<({int status, int code, ApiFailureKind kind})> failures =
          <({int status, int code, ApiFailureKind kind})>[
            (status: 403, code: 40335, kind: ApiFailureKind.forbidden),
            (status: 409, code: 40943, kind: ApiFailureKind.conflict),
            (status: 422, code: 42201, kind: ApiFailureKind.validation),
            (status: 500, code: 50001, kind: ApiFailureKind.server),
          ];

      for (final write in writes) {
        for (final failure in failures) {
          final _RunningServer server = await _RunningServer.start((
            _CapturedRequest request,
          ) {
            expect(request.path, write.path, reason: write.name);
            expect(request.requestId, isNotEmpty, reason: write.name);
            expect(
              request.requestId,
              matches(RegExp(r'^room-lifecycle-[0-9a-f]{32}$')),
              reason: write.name,
            );
            return _Reply(
              code: failure.code,
              message: '${write.name}-${failure.status}',
              data: null,
              httpStatus: failure.status,
            );
          });
          final BackendRoomLifecycleRepository repository =
              BackendRoomLifecycleRepository(apiClient: server.client);

          await expectLater(
            write.invoke(repository),
            throwsA(
              isA<ApiException>()
                  .having(
                    (ApiException error) => error.kind,
                    'kind',
                    failure.kind,
                  )
                  .having(
                    (ApiException error) => error.code,
                    'code',
                    failure.code,
                  )
                  .having(
                    (ApiException error) => error.httpStatus,
                    'httpStatus',
                    failure.status,
                  )
                  .having(
                    (ApiException error) => error.message,
                    'message',
                    '${write.name}-${failure.status}',
                  ),
            ),
            reason: '${write.name} HTTP ${failure.status}',
          );
          expect(server.requests, hasLength(1));
          await server.close();
        }
      }
    },
  );

  test('room lifecycle intent digest is opaque and stable for PIN configs', () {
    const List<String> fields = <String>[
      'new',
      'PIN 房间',
      '',
      '',
      '',
      'password',
      '1357',
      'false',
      'true',
      'false',
      'open',
    ];
    final String first = roomIntentDigest(
      scope: 'room-lifecycle-save',
      fields: fields,
    );
    final String sameConfiguration = roomIntentDigest(
      scope: 'room-lifecycle-save',
      fields: fields,
    );
    final String differentPin = roomIntentDigest(
      scope: 'room-lifecycle-save',
      fields: <String>[...fields.sublist(0, 6), '2468', ...fields.sublist(7)],
    );

    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(first, isNot(contains('1357')));
    expect(first, sameConfiguration);
    expect(first, isNot(differentPin));
  });

  test(
    'close requires matching roomId, CLOSED, and closed=true authority',
    () async {
      final List<Map<String, Object?>> nonAuthoritative =
          <Map<String, Object?>>[
            <String, Object?>{
              'roomId': '9527',
              'status': 'OPEN',
              'closed': true,
            },
            <String, Object?>{
              'roomId': '9527',
              'status': 'CLOSED',
              'closed': false,
            },
            <String, Object?>{
              'roomId': 'other-room',
              'status': 'CLOSED',
              'closed': true,
            },
            <String, Object?>{'roomId': '9527', 'closed': true},
            <String, Object?>{'roomId': '9527', 'status': 'CLOSED'},
          ];

      for (final Map<String, Object?> payload in nonAuthoritative) {
        final _RunningServer server = await _RunningServer.start((
          _CapturedRequest request,
        ) {
          expect(request.path, '/app-mini-api/mini/v1/rooms/close');
          expect(request.requestId, isNotEmpty);
          return _Reply(data: payload);
        });
        final BackendRoomLifecycleRepository repository =
            BackendRoomLifecycleRepository(apiClient: server.client);

        await expectLater(
          repository.closeRoom('9527', expectedVersion: 0),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
          reason: '$payload',
        );
        expect(server.requests, hasLength(1));
        await server.close();
      }
    },
  );

  test('create and close use first-party lifecycle endpoints', () async {
    final _RunningServer server = await _RunningServer.start((
      _CapturedRequest request,
    ) {
      switch (request.path) {
        case '/app-mini-api/mini/v1/rooms':
          expect(request.method, 'POST');
          expect(request.body, <String, Object?>{
            'roomName': '新房间',
            'topicTitle': '',
            'topic': '',
            'welcomeText': '',
            'accessMode': 'PUBLIC',
            'hallVisible': true,
            'autoLockMic': false,
          });
          return const _Reply(
            data: <String, Object?>{
              'roomId': 'room-created',
              'roomCode': '9527',
              'roomName': '新房间',
              'topicTitle': '',
              'topic': '',
              'welcomeText': '',
              'accessMode': 'PUBLIC',
              'hallVisible': true,
              'autoLockMic': false,
              'status': 'OPEN',
              'created': true,
              'reused': false,
              'rtcStatus': 'VENDOR_BLOCKED',
              'imStatus': 'VENDOR_BLOCKED',
              'providerInvocation': false,
              'version': 0,
            },
          );
        case '/app-mini-api/mini/v1/rooms/close':
          expect(request.method, 'POST');
          expect(request.body, <String, Object?>{
            'roomId': 'room-created',
            'expectedVersion': 0,
          });
          return const _Reply(
            data: <String, Object?>{
              'roomId': 'room-created',
              'closed': true,
              'status': 'CLOSED',
              'version': 1,
            },
          );
        default:
          fail('unexpected lifecycle write: ${request.path}');
      }
    });
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

    final RoomLifecycleSaveResult result = await repository.saveRoom(newRoom);
    expect(result.roomId, 'room-created');
    expect(result.roomCode, '9527');
    expect(result.created, isTrue);
    await repository.closeRoom('room-created', expectedVersion: 0);
    expect(server.requests, hasLength(2));
  });

  test(
    'replayed create response is parsed as reused without a fake duplicate',
    () async {
      int createCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-mini-api/mini/v1/rooms');
        expect(request.method, 'POST');
        expect(request.body, <String, Object?>{
          'roomName': '幂等房间',
          'topicTitle': '',
          'topic': '',
          'welcomeText': '',
          'accessMode': 'PUBLIC',
          'hallVisible': true,
          'autoLockMic': false,
        });
        createCalls += 1;
        return _Reply(
          data: <String, Object?>{
            'roomId': 'room-replayed',
            'roomCode': '9528',
            'roomName': '幂等房间',
            'topicTitle': '',
            'topic': '',
            'welcomeText': '',
            'accessMode': 'PUBLIC',
            'hallVisible': true,
            'autoLockMic': false,
            'status': 'OPEN',
            'created': createCalls == 1,
            'reused': createCalls > 1,
            'rtcStatus': 'VENDOR_BLOCKED',
            'imStatus': 'VENDOR_BLOCKED',
            'providerInvocation': false,
            'version': 0,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      const RoomConfiguration room = RoomConfiguration(
        title: '幂等房间',
        topicTitle: '',
        topicContent: '',
        welcomeMessage: '',
        accessMode: RoomAccessMode.publicRoom,
        password: '',
        showInHall: true,
        autoLockMic: false,
        availability: RoomAvailability.open,
      );

      final RoomLifecycleSaveResult first = await repository.saveRoom(room);
      final RoomLifecycleSaveResult replay = await repository.saveRoom(room);

      expect(first.roomId, replay.roomId);
      expect(first.created, isTrue);
      expect(replay.created, isFalse);
      expect(createCalls, 2);
    },
  );

  test(
    'approval room creation uses APPROVAL and does not require a password',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-mini-api/mini/v1/rooms');
        expect(request.method, 'POST');
        expect(request.body, <String, Object?>{
          'roomName': '审批房',
          'topicTitle': '入房规则',
          'topic': '先申请再进入',
          'welcomeText': '请等待房主批准',
          'accessMode': 'APPROVAL',
          'hallVisible': true,
          'autoLockMic': true,
        });
        return const _Reply(
          data: <String, Object?>{
            'roomId': 'approval-room',
            'roomCode': '9529',
            'roomName': '审批房',
            'topicTitle': '入房规则',
            'topic': '先申请再进入',
            'welcomeText': '请等待房主批准',
            'accessMode': 'APPROVAL',
            'hallVisible': true,
            'autoLockMic': true,
            'status': 'OPEN',
            'created': true,
            'reused': false,
            'rtcStatus': 'VENDOR_BLOCKED',
            'imStatus': 'VENDOR_BLOCKED',
            'providerInvocation': false,
            'version': 0,
          },
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      final RoomLifecycleSaveResult result = await repository.saveRoom(
        const RoomConfiguration(
          title: '审批房',
          topicTitle: '入房规则',
          topicContent: '先申请再进入',
          welcomeMessage: '请等待房主批准',
          accessMode: RoomAccessMode.approval,
          password: '',
          showInHall: true,
          autoLockMic: true,
          availability: RoomAvailability.open,
        ),
      );

      expect(result.roomId, 'approval-room');
      expect(repository.capabilities.supportsApprovalAccessMode, isTrue);
      expect(repository.capabilities.supportsTopicTitle, isTrue);
      expect(repository.capabilities.supportsAutoLockMic, isTrue);
      expect(repository.capabilities.supportsReopen, isTrue);
    },
  );

  test(
    'closed live room reopens then persists the requested configuration',
    () async {
      String? reopenRequestId;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-mini-api/mini/v1/rooms/reopen':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': '9527',
              'expectedVersion': 4,
            });
            reopenRequestId = request.requestId;
            expect(reopenRequestId, isNotEmpty);
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'status': 'OPEN',
                'reopened': true,
                'providerInvocation': false,
                'version': 5,
              },
            );
          case '/app-api/rooms/updateRoomInformation':
            expect(request.method, 'PATCH');
            expect(request.body, <String, Object?>{
              'roomName': '重新开放房间',
              'topicTitle': '新标题',
              'topic': '新内容',
              'welcomeText': '新欢迎语',
              'accessMode': 'APPROVAL',
              'hallVisible': true,
              'autoLockMic': true,
              'roomId': '9527',
              'expectedVersion': 5,
            });
            expect(request.requestId, reopenRequestId);
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新标题',
                'autoLockMic': true,
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 6,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            return _Reply(
              data: _ownerPage(
                row: const <String, Object?>{
                  'roomId': '9527',
                  'roomCode': 'R9527',
                  'roomName': '重新开放房间',
                  'topic': '新内容',
                  'topicTitle': '新标题',
                  'autoLockMic': true,
                  'accessMode': 'APPROVAL',
                  'hallVisible': true,
                  'status': 'OPEN',
                },
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新标题',
                'topic': '新内容',
                'welcomeText': '新欢迎语',
                'autoLockMic': true,
                'canEdit': true,
                'version': 6,
              },
            );
          default:
            fail('unexpected lifecycle route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      final RoomLifecycleSaveResult result = await repository.saveRoom(
        const RoomConfiguration(
          roomId: '9527',
          roomCode: 'R9527',
          title: '重新开放房间',
          topicTitle: '新标题',
          topicContent: '新内容',
          welcomeMessage: '新欢迎语',
          accessMode: RoomAccessMode.approval,
          password: '',
          showInHall: true,
          autoLockMic: true,
          availability: RoomAvailability.closed,
          version: 4,
        ),
      );
      expect(result.roomId, '9527');
      expect(result.created, isFalse);
      expect(
        server.requests.map((_CapturedRequest item) => item.path),
        <String>[
          '/app-mini-api/mini/v1/rooms/reopen',
          '/app-api/rooms/updateRoomInformation',
          '/app-api/rooms/getRoomSelectByUserId',
          '/app-api/rooms/getRoomTopics',
        ],
      );
    },
  );

  test(
    'closed live room does not overwrite after reopen committed before update failed',
    () async {
      int reopenCalls = 0;
      int updateCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-mini-api/mini/v1/rooms/reopen':
            reopenCalls += 1;
            if (reopenCalls == 1) {
              return const _Reply(
                data: <String, Object?>{
                  'roomId': '9527',
                  'status': 'OPEN',
                  'reopened': true,
                  'providerInvocation': false,
                  'version': 5,
                },
              );
            }
            return const _Reply(
              code: 40945,
              message: 'ROOM_VERSION_CONFLICT',
              data: <String, Object?>{'currentVersion': 5},
              httpStatus: 409,
            );
          case '/app-api/rooms/updateRoomInformation':
            updateCalls += 1;
            expect(request.body, containsPair('expectedVersion', 5));
            if (updateCalls == 1) {
              return const _Reply(
                code: 42201,
                message: '模拟一次可修正的资料更新失败',
                httpStatus: 422,
              );
            }
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新标题',
                'autoLockMic': true,
                'status': 'OPEN',
                'rtcStatus': 'VENDOR_BLOCKED',
                'imStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
                'version': 6,
              },
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            return _Reply(
              data: _ownerPage(
                row: const <String, Object?>{
                  'roomId': '9527',
                  'roomCode': 'R9527',
                  'roomName': '重新开放房间',
                  'topic': '新内容',
                  'topicTitle': '新标题',
                  'autoLockMic': true,
                  'accessMode': 'APPROVAL',
                  'hallVisible': true,
                  'status': 'OPEN',
                },
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '新标题',
                'topic': '新内容',
                'welcomeText': '新欢迎语',
                'autoLockMic': true,
                'canEdit': true,
                'version': 6,
              },
            );
          default:
            fail('unexpected lifecycle route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      const RoomConfiguration configuration = RoomConfiguration(
        roomId: '9527',
        roomCode: 'R9527',
        title: '重新开放房间',
        topicTitle: '新标题',
        topicContent: '新内容',
        welcomeMessage: '新欢迎语',
        accessMode: RoomAccessMode.approval,
        password: '',
        showInHall: true,
        autoLockMic: true,
        availability: RoomAvailability.closed,
        version: 4,
      );

      await expectLater(
        repository.saveRoom(configuration),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            42201,
          ),
        ),
      );

      await expectLater(
        repository.saveRoom(configuration),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.code, 'code', 40945)
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              ),
        ),
      );
      expect(reopenCalls, 2);
      expect(updateCalls, 1);
    },
  );

  test(
    'room version conflict is surfaced without an authority overwrite',
    () async {
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        expect(request.path, '/app-api/rooms/updateRoomInformation');
        expect(request.method, 'PATCH');
        expect(request.body, containsPair('expectedVersion', 3));
        return const _Reply(
          code: 40945,
          message: 'ROOM_VERSION_CONFLICT',
          data: <String, Object?>{'currentVersion': 4},
          httpStatus: 409,
        );
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);

      await expectLater(
        repository.saveRoom(
          _existingPublicRoom().copyWith(title: '不会覆盖服务端内容', version: 3),
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.code, 'code', 40945)
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              ),
        ),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'live lifecycle writes reject missing or invalid versions before network',
    () async {
      final _RunningServer server = await _RunningServer.start(
        (_CapturedRequest request) =>
            fail('unexpected unversioned lifecycle request: ${request.path}'),
      );
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      const RoomConfiguration missingVersion = RoomConfiguration(
        roomId: '9527',
        roomCode: 'R9527',
        title: '现有房间',
        topicTitle: '',
        topicContent: '',
        welcomeMessage: '',
        accessMode: RoomAccessMode.publicRoom,
        password: '',
        showInHall: true,
        autoLockMic: false,
        availability: RoomAvailability.open,
      );

      for (final RoomConfiguration configuration in <RoomConfiguration>[
        missingVersion,
        missingVersion.copyWith(version: -1),
      ]) {
        await expectLater(
          repository.saveRoom(configuration),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.validation,
            ),
          ),
        );
      }
      for (final int? version in <int?>[null, -1]) {
        await expectLater(
          repository.closeRoom('9527', expectedVersion: version),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.validation,
            ),
          ),
        );
      }
      expect(server.requests, isEmpty);
    },
  );

  test(
    'concurrent saves with one snapshot version reject the stale loser',
    () async {
      int updateCalls = 0;
      final _RunningServer server = await _RunningServer.start((
        _CapturedRequest request,
      ) {
        switch (request.path) {
          case '/app-api/rooms/updateRoomInformation':
            updateCalls += 1;
            expect(request.body, containsPair('expectedVersion', 0));
            if (updateCalls == 1) {
              return const _Reply(
                data: <String, Object?>{
                  'roomId': '9527',
                  'topicTitle': '',
                  'autoLockMic': false,
                  'status': 'OPEN',
                  'rtcStatus': 'VENDOR_BLOCKED',
                  'imStatus': 'VENDOR_BLOCKED',
                  'providerInvocation': false,
                  'version': 1,
                },
              );
            }
            return const _Reply(
              code: 40945,
              message: 'ROOM_VERSION_CONFLICT',
              data: <String, Object?>{'currentVersion': 1},
              httpStatus: 409,
            );
          case '/app-api/rooms/getRoomSelectByUserId':
            return _Reply(
              data: _ownerPage(
                row: const <String, Object?>{
                  'roomId': '9527',
                  'roomCode': 'R9527',
                  'roomName': '第一个写入',
                  'accessMode': 'PUBLIC',
                  'hallVisible': true,
                  'status': 'OPEN',
                  'topicTitle': '',
                  'autoLockMic': false,
                },
              ),
            );
          case '/app-api/rooms/getRoomTopics':
            return const _Reply(
              data: <String, Object?>{
                'roomId': '9527',
                'topicTitle': '',
                'topic': '',
                'welcomeText': '',
                'autoLockMic': false,
                'canEdit': true,
                'version': 1,
              },
            );
          default:
            fail('unexpected concurrent lifecycle route: ${request.path}');
        }
      });
      addTearDown(server.close);
      final BackendRoomLifecycleRepository repository =
          BackendRoomLifecycleRepository(apiClient: server.client);
      final RoomConfiguration first = _existingPublicRoom().copyWith(
        title: '第一个写入',
        version: 0,
      );
      final RoomConfiguration second = _existingPublicRoom().copyWith(
        title: '第二个写入',
        version: 0,
      );

      final Future<RoomLifecycleSaveResult> firstWrite = repository.saveRoom(
        first,
      );
      final Future<RoomLifecycleSaveResult> secondWrite = repository.saveRoom(
        second,
      );

      await firstWrite;
      await expectLater(
        secondWrite,
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.code, 'code', 40945)
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.conflict,
              ),
        ),
      );
      expect(updateCalls, 2);
      expect(
        server.requests.where(
          (_CapturedRequest request) =>
              request.path == '/app-api/rooms/getRoomSelectByUserId',
        ),
        hasLength(1),
      );
    },
  );
}

RoomConfiguration _newPublicRoom() => const RoomConfiguration(
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

RoomConfiguration _existingPublicRoom() => const RoomConfiguration(
  roomId: '9527',
  roomCode: 'R9527',
  title: '现有房间',
  topicTitle: '',
  topicContent: '',
  welcomeMessage: '',
  accessMode: RoomAccessMode.publicRoom,
  password: '',
  showInHall: true,
  autoLockMic: false,
  availability: RoomAvailability.open,
  version: 0,
);

Map<String, Object?> _createSnapshot({
  String roomId = 'room-created',
  String roomCode = '9527',
  String roomName = '新房间',
  String topicTitle = '',
  String topic = '',
  String welcomeText = '',
  String status = 'OPEN',
  String accessMode = 'PUBLIC',
  Object? hallVisible = true,
  Object? autoLockMic = false,
  required bool created,
  required bool reused,
  Object? rtcStatus = 'VENDOR_BLOCKED',
  Object? imStatus = 'VENDOR_BLOCKED',
  Object? providerInvocation = false,
  int version = 0,
}) => <String, Object?>{
  'roomId': roomId,
  'roomCode': roomCode,
  'roomName': roomName,
  'topicTitle': topicTitle,
  'topic': topic,
  'welcomeText': welcomeText,
  'status': status,
  'accessMode': accessMode,
  'hallVisible': hallVisible,
  'autoLockMic': autoLockMic,
  'created': created,
  'reused': reused,
  'rtcStatus': rtcStatus,
  'imStatus': imStatus,
  'providerInvocation': providerInvocation,
  'version': version,
};

Map<String, Object?> _ownerPage({
  required Map<String, Object?> row,
  int current = 1,
  int pageSize = 50,
  int? total,
  int? pages,
}) {
  final int resolvedTotal = total ?? 1;
  final int resolvedPages = pages ?? 1;
  final int expectedCount = resolvedPages == 0
      ? 0
      : current < resolvedPages
      ? pageSize
      : resolvedTotal - ((resolvedPages - 1) * pageSize);
  final List<Object?> rows = List<Object?>.generate(expectedCount, (_) => row);
  return <String, Object?>{
    'list': rows,
    'records': rows,
    'current': current,
    'pageSize': pageSize,
    'size': pageSize,
    'total': resolvedTotal,
    'pages': resolvedPages,
  };
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String authorization;
  final String requestId;
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
        requestId: request.headers.value('X-Request-Id') ?? '',
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
