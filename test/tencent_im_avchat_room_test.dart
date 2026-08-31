import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/im/application/tencent_im_avchat_room_coordinator.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/tencent_im_room_models.dart';
import 'package:voice_social_app/features/im/infrastructure/tencent_im_session_adapter.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  group('AVChatRoom backend projection', () {
    test('accepts the seven-field READY projection inside a full snapshot', () {
      final TencentImAvChatRoomSession session =
          TencentImAvChatRoomSession.fromBackendData(<String, Object?>{
            'roomId': 'room-1',
            'sessionId': 'session-1',
            'version': 0x80000000,
            'title': 'ordinary room snapshot field',
            'realtimeGroup': <String, Object?>{
              'provider': 'tencent-im',
              'type': 'AVCHATROOM',
              'groupType': 'AVChatRoom',
              'groupId': 'room-group-1',
              'status': 'READY',
              'messageMode': 'METADATA_HINT',
              'contentAuthority': 'HTTP',
            },
          });

      expect(session.roomId, 'room-1');
      expect(session.groupId, 'room-group-1');
      expect(session.version, 0x80000000);
      expect(session.hasActiveLease(now), isTrue);
      expect(session.toString(), isNot(contains('session-1')));
      expect(session.toString(), isNot(contains('room-group-1')));
    });

    test('fails closed for malformed group fields and 64-bit overflow', () {
      final Map<String, Object?> valid = _roomData();
      expect(
        () => TencentImAvChatRoomSession.fromBackendData(<String, Object?>{
          ...valid,
          'version': TencentImAvChatRoomSession.maximumVersion + 1,
        }),
        throwsA(
          isA<TencentImRoomCredentialException>().having(
            (TencentImRoomCredentialException error) => error.failure,
            'failure',
            TencentImRoomCredentialFailure.invalidVersion,
          ),
        ),
      );
      expect(
        TencentImAvChatRoomSession.tryParseFromRoomData(<String, Object?>{
          ...valid,
          'realtimeGroup': <String, Object?>{
            ...(valid['realtimeGroup']! as Map<String, Object?>),
            'unknown': 'must reject',
          },
        }),
        isNull,
      );
      expect(
        TencentImAvChatRoomSession.tryParseFromRoomData(<String, Object?>{
          ...valid,
          'realtimeGroup': <String, Object?>{
            ...(valid['realtimeGroup']! as Map<String, Object?>),
            'status': 'PENDING',
          },
        }),
        isNull,
      );
      expect(
        TencentImAvChatRoomSession.tryParseFromRoomData(<String, Object?>{
          ...valid,
          'realtimeGroup': <String, Object?>{
            ...(valid['realtimeGroup']! as Map<String, Object?>),
            'contentAuthority': 'PROVIDER',
          },
        }),
        isNull,
      );
    });

    test('retains PENDING for readiness polling but never joins it', () {
      final Map<String, Object?> pendingRaw = _roomData(status: 'PENDING');
      expect(
        () => TencentImAvChatRoomSession.fromBackendData(pendingRaw),
        throwsA(
          isA<TencentImRoomCredentialException>().having(
            (TencentImRoomCredentialException error) => error.failure,
            'failure',
            TencentImRoomCredentialFailure.groupNotReady,
          ),
        ),
      );

      final TencentImAvChatRoomSession? pending =
          TencentImAvChatRoomSession.tryParseRoomReadinessFromRoomData(
            pendingRaw,
          );
      expect(pending, isNotNull);
      expect(pending!.isReady, isFalse);
      expect(pending.groupId, 'room-group-1');
    });
  });

  group('AVChatRoom adapter and coordinator', () {
    test(
      'joins once, refreshes only for trusted current-room hints, and quits',
      () async {
        final _GroupSdk sdk = _GroupSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        final List<String> refreshedRooms = <String>[];
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(
              sessionAdapter: adapter,
              refreshRoom: (String roomId) async => refreshedRooms.add(roomId),
              operationTimeout: const Duration(milliseconds: 100),
            );
        addTearDown(() async {
          await coordinator.dispose();
          await adapter.dispose();
          await sdk.dispose();
        });

        await adapter.login(_credentials(now));
        final TencentImAvChatRoomSession session =
            TencentImAvChatRoomSession.fromBackendData(_roomData());
        final TencentImAvChatRoomJoinResult joined = await coordinator.enter(
          session,
        );
        expect(joined.mode, TencentImAvChatRoomJoinMode.joined);
        expect(sdk.joinedGroupIds, <String>['room-group-1']);

        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 1,
          ),
        );
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 1,
          ),
        );
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 2,
          ),
        );
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: true,
            sessionId: 'session-1',
            version: 3,
          ),
        );
        sdk.emit(
          _customEvent(
            groupId: 'other-group',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 4,
          ),
        );
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'not-system-account',
            isSelf: false,
            sessionId: 'session-1',
            version: 5,
          ),
        );
        await _eventTurn();
        expect(refreshedRooms, <String>['room-1', 'room-1']);

        await coordinator.leave();
        expect(sdk.quitGroupIds, <String>['room-group-1']);
        // A late event after leave is fenced even if the native stream emits it.
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 6,
          ),
        );
        await _eventTurn();
        expect(refreshedRooms, hasLength(2));
      },
    );

    test('treats 10010 as join failure and only 0 as quit success', () async {
      final _GroupSdk sdk = _GroupSdk()
        ..joinResultCode = 10010
        ..quitResultCode = 10015;
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(() async {
        await adapter.dispose();
        await sdk.dispose();
      });
      await adapter.login(_credentials(now));
      expect(
        await adapter.joinGroup(
          groupId: 'room-group-1',
          groupType: 'AVChatRoom',
        ),
        isFalse,
      );
      expect(
        adapter.isTrustedRoomHintSender(
          senderUserId: 'administrator',
          groupId: 'room-group-1',
          isSelf: false,
        ),
        isFalse,
      );

      sdk.joinResultCode = 0;
      expect(
        await adapter.joinGroup(
          groupId: 'room-group-1',
          groupType: 'AVChatRoom',
        ),
        isTrue,
      );
      expect(await adapter.quitGroup(groupId: 'room-group-1'), isFalse);
      expect(
        adapter.isTrustedRoomHintSender(
          senderUserId: 'administrator',
          groupId: 'room-group-1',
          isSelf: false,
        ),
        isFalse,
      );
    });

    test(
      'keeps stale room-switch hint proposals inert until the current binding commits them',
      () {
        final Map<String, int> acceptedVersionsByMessage = <String, int>{};
        int? lastAcceptedEventVersion;

        final ImRefreshHintVersionFence staleFence = ImRefreshHintVersionFence(
          'stale-room-message',
          9,
          acceptedVersionsByMessage,
          lastAcceptedEventVersion,
        );
        expect(staleFence.shouldAccept(), isTrue);
        expect(acceptedVersionsByMessage, isEmpty);
        expect(staleFence.nextLastVersion, isNull);

        // A room switch clears the old binding's dedupe state before the stale
        // event is allowed to commit anything into the next room's fence.
        acceptedVersionsByMessage.clear();
        lastAcceptedEventVersion = null;

        final ImRefreshHintVersionFence currentFence =
            ImRefreshHintVersionFence(
              'current-room-message',
              1,
              acceptedVersionsByMessage,
              lastAcceptedEventVersion,
            );
        expect(currentFence.shouldAccept(), isTrue);
        currentFence.apply();
        lastAcceptedEventVersion = currentFence.nextLastVersion;

        expect(acceptedVersionsByMessage, <String, int>{
          'current-room-message': 1,
        });
        expect(lastAcceptedEventVersion, 1);
      },
    );

    test('retries the current READY group after a late IM login', () async {
      final _GroupSdk sdk = _GroupSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
      );
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 100),
          );
      addTearDown(() async {
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      final TencentImAvChatRoomJoinResult initial = await coordinator.enter(
        TencentImAvChatRoomSession.fromBackendData(_roomData()),
      );
      expect(initial.mode, TencentImAvChatRoomJoinMode.httpOnly);
      expect(sdk.joinedGroupIds, isEmpty);

      await adapter.login(_credentials(now));
      await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
      expect(sdk.joinedGroupIds, <String>['room-group-1']);
      expect(coordinator.activeGroupId, 'room-group-1');
    });

    test(
      'uses HTTP-only mode when the group capability is unavailable',
      () async {
        final _BasicSdk sdk = _BasicSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(sessionAdapter: adapter);
        addTearDown(() async {
          await coordinator.dispose();
          await adapter.dispose();
        });
        await adapter.login(_credentials(now));
        final TencentImAvChatRoomJoinResult result = await coordinator.enter(
          TencentImAvChatRoomSession.fromBackendData(_roomData()),
        );
        expect(result.mode, TencentImAvChatRoomJoinMode.httpOnly);
        expect(coordinator.activeGroupId, isNull);
      },
    );

    test(
      'room controller binds enter, refreshes authoritative HTTP, and exits',
      () async {
        final _GroupSdk sdk = _GroupSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        await adapter.login(_credentials(now));
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(
              sessionAdapter: adapter,
              operationTimeout: const Duration(milliseconds: 100),
            );
        final _TencentRoomRepository repository = _TencentRoomRepository();
        final RoomController controller = RoomController(
          roomId: 'room-1',
          title: '房间',
          currentUserId: 123,
          accessToken: 'first-party-token',
          repository: repository,
          rtcAdapter: MockRtcAdapter(),
          realtimeGateway: MockRoomRealtimeGateway(),
          tencentImAvChatRoomCoordinator: coordinator,
        );
        addTearDown(() async {
          controller.dispose();
          await coordinator.dispose();
          await adapter.dispose();
          await sdk.dispose();
        });

        await controller.join();
        expect(controller.status, RoomSessionStatus.joined);
        await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
        expect(sdk.joinedGroupIds, <String>['room-group-1']);
        expect(repository.fetchCalls, 1);

        repository.messages = <RoomMessage>[
          const RoomMessage(
            roomId: 'room-1',
            messageId: 'authoritative-1',
            sender: '系统',
            content: '来自 HTTP 权威历史',
          ),
        ];
        sdk.emit(
          _customEvent(
            groupId: 'room-group-1',
            sender: 'administrator',
            isSelf: false,
            sessionId: 'session-1',
            version: 10,
          ),
        );
        await _eventTurn();
        await _eventTurn();
        expect(repository.fetchCalls, 2);
        expect(controller.messages.single.messageId, 'authoritative-1');

        expect(await controller.leaveRoom(), isTrue);
        expect(repository.exitCalls, 1);
        expect(sdk.quitGroupIds, <String>['room-group-1']);
      },
    );

    test('room leave does not wait for a timed-out provider quit', () async {
      final _GroupSdk sdk = _GroupSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 10),
      );
      await adapter.login(_credentials(now));
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 10),
          );
      final _TencentRoomRepository repository = _TencentRoomRepository();
      final RoomController controller = RoomController(
        roomId: 'room-1',
        title: '房间',
        currentUserId: 123,
        accessToken: 'first-party-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: MockRoomRealtimeGateway(),
        tencentImAvChatRoomCoordinator: coordinator,
      );
      addTearDown(() async {
        controller.dispose();
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      await controller.join();
      await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
      sdk.quitResultCode = 10015;
      sdk.hangQuit = true;
      final Stopwatch stopwatch = Stopwatch()..start();
      expect(await controller.leaveRoom(), isTrue);
      stopwatch.stop();
      expect(repository.exitCalls, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 100)));
      // The local fence is cleared before HTTP exit; a late group hint cannot
      // trigger another fetch while the provider future times out.
      sdk.emit(
        _customEvent(
          groupId: 'room-group-1',
          sender: 'administrator',
          isSelf: false,
          sessionId: 'session-1',
          version: 11,
        ),
      );
      await _eventTurn();
      expect(repository.fetchCalls, 1);
    });

    test('keeps HTTP enter usable while PENDING becomes READY', () async {
      final _GroupSdk sdk = _GroupSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
      );
      await adapter.login(_credentials(now));
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 100),
          );
      final _TencentRoomRepository repository = _TencentRoomRepository()
        ..returnPendingOnEnter = true
        ..readinessSession = TencentImAvChatRoomSession.fromBackendData(
          _roomData(status: 'READY'),
        );
      final RoomController controller = RoomController(
        roomId: 'room-1',
        title: '房间',
        currentUserId: 123,
        accessToken: 'first-party-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: MockRoomRealtimeGateway(),
        tencentImAvChatRoomCoordinator: coordinator,
      );
      addTearDown(() async {
        controller.dispose();
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      final Stopwatch stopwatch = Stopwatch()..start();
      await controller.join();
      stopwatch.stop();
      expect(controller.status, RoomSessionStatus.joined);
      // The first readiness GET is detached from join; no provider wait can
      // turn a successful first-party enter into a failed room navigation.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
      expect(repository.readinessCalls, greaterThanOrEqualTo(1));
      expect(sdk.joinedGroupIds, <String>['room-group-1']);
    });

    test(
      'keeps polling across delayed Tencent worker cycles before joining',
      () async {
        final _GroupSdk sdk = _GroupSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        await adapter.login(_credentials(now));
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(
              sessionAdapter: adapter,
              operationTimeout: const Duration(milliseconds: 100),
            );
        final TencentImAvChatRoomSession ready =
            TencentImAvChatRoomSession.fromBackendData(_roomData());
        final _TencentRoomRepository repository = _TencentRoomRepository()
          ..returnPendingOnEnter = true
          ..readinessSequence = <TencentImAvChatRoomSession?>[
            null,
            null,
            ready,
          ];
        final RoomController controller = _roomController(
          repository,
          coordinator,
          tencentImReadinessPollInterval: const Duration(milliseconds: 5),
          tencentImReadinessPollWindow: const Duration(milliseconds: 100),
        );
        addTearDown(() async {
          controller.dispose();
          await coordinator.dispose();
          await adapter.dispose();
          await sdk.dispose();
        });

        await controller.join();
        await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
        expect(repository.readinessCalls, greaterThanOrEqualTo(3));
        expect(sdk.joinedGroupIds, <String>['room-group-1']);
        expect(controller.status, RoomSessionStatus.joined);
      },
    );

    test(
      'cancels readiness polling immediately when leaving the room',
      () async {
        final _GroupSdk sdk = _GroupSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        await adapter.login(_credentials(now));
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(
              sessionAdapter: adapter,
              operationTimeout: const Duration(milliseconds: 100),
            );
        final _TencentRoomRepository repository = _TencentRoomRepository()
          ..returnPendingOnEnter = true
          ..readinessSession = null;
        final RoomController controller = _roomController(
          repository,
          coordinator,
          tencentImReadinessPollInterval: const Duration(milliseconds: 40),
          tencentImReadinessPollWindow: const Duration(milliseconds: 300),
        );
        addTearDown(() async {
          controller.dispose();
          await coordinator.dispose();
          await adapter.dispose();
          await sdk.dispose();
        });

        await controller.join();
        await _waitUntil(() => repository.readinessCalls >= 1);
        expect(await controller.leaveRoom(), isTrue);
        final int callsAfterLeave = repository.readinessCalls;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(repository.readinessCalls, callsAfterLeave);
        expect(sdk.joinedGroupIds, isEmpty);
        expect(controller.status, RoomSessionStatus.left);
      },
    );

    test('cancels readiness polling immediately when disposed', () async {
      final _GroupSdk sdk = _GroupSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
      );
      await adapter.login(_credentials(now));
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 100),
          );
      final _TencentRoomRepository repository = _TencentRoomRepository()
        ..returnPendingOnEnter = true
        ..readinessSession = null;
      final RoomController controller = _roomController(
        repository,
        coordinator,
        tencentImReadinessPollInterval: const Duration(milliseconds: 40),
        tencentImReadinessPollWindow: const Duration(milliseconds: 300),
      );
      addTearDown(() async {
        controller.dispose();
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      await controller.join();
      await _waitUntil(() => repository.readinessCalls >= 1);
      controller.dispose();
      final int callsAfterDispose = repository.readinessCalls;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(repository.readinessCalls, callsAfterDispose);
      expect(sdk.joinedGroupIds, isEmpty);
    });

    test('drops a stale readiness response after leave and re-entry', () async {
      final _GroupSdk sdk = _GroupSdk();
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
      );
      await adapter.login(_credentials(now));
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 100),
          );
      final TencentImAvChatRoomSession ready =
          TencentImAvChatRoomSession.fromBackendData(_roomData());
      final Completer<TencentImAvChatRoomSession?> staleReadiness =
          Completer<TencentImAvChatRoomSession?>();
      final _TencentRoomRepository repository = _TencentRoomRepository()
        ..returnPendingOnEnter = true
        ..readinessFactory = () => staleReadiness.future;
      final RoomController controller = _roomController(
        repository,
        coordinator,
        tencentImReadinessPollInterval: const Duration(milliseconds: 5),
        tencentImReadinessPollWindow: const Duration(milliseconds: 100),
      );
      addTearDown(() async {
        controller.dispose();
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      await controller.join();
      await _waitUntil(() => repository.readinessCalls >= 1);
      expect(await controller.leaveRoom(), isTrue);
      staleReadiness.complete(ready);
      await _eventTurn();
      expect(sdk.joinedGroupIds, isEmpty);

      repository.readinessFactory = null;
      repository.readinessSession = ready;
      await controller.join();
      await _waitUntil(() => sdk.joinedGroupIds.isNotEmpty);
      expect(sdk.joinedGroupIds, <String>['room-group-1']);
    });

    test(
      'keeps HTTP-only state after the bounded readiness window expires',
      () async {
        final _GroupSdk sdk = _GroupSdk();
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
        );
        await adapter.login(_credentials(now));
        final TencentImAvChatRoomCoordinator coordinator =
            TencentImAvChatRoomCoordinator(
              sessionAdapter: adapter,
              operationTimeout: const Duration(milliseconds: 100),
            );
        final _TencentRoomRepository repository = _TencentRoomRepository()
          ..returnPendingOnEnter = true
          ..readinessSession = null;
        final RoomController controller = _roomController(
          repository,
          coordinator,
          tencentImReadinessPollInterval: const Duration(milliseconds: 5),
          tencentImReadinessPollWindow: const Duration(milliseconds: 30),
        );
        addTearDown(() async {
          controller.dispose();
          await coordinator.dispose();
          await adapter.dispose();
          await sdk.dispose();
        });

        await controller.join();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(repository.readinessCalls, greaterThanOrEqualTo(1));
        expect(sdk.joinedGroupIds, isEmpty);
        expect(controller.status, RoomSessionStatus.joined);
      },
    );

    test('does not block HTTP room entry on a hanging provider join', () async {
      final _GroupSdk sdk = _GroupSdk()..hangJoin = true;
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 10),
      );
      await adapter.login(_credentials(now));
      final TencentImAvChatRoomCoordinator coordinator =
          TencentImAvChatRoomCoordinator(
            sessionAdapter: adapter,
            operationTimeout: const Duration(milliseconds: 10),
          );
      final _TencentRoomRepository repository = _TencentRoomRepository();
      final RoomController controller = RoomController(
        roomId: 'room-1',
        title: '房间',
        currentUserId: 123,
        accessToken: 'first-party-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: MockRoomRealtimeGateway(),
        tencentImAvChatRoomCoordinator: coordinator,
      );
      addTearDown(() async {
        controller.dispose();
        await coordinator.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });

      final Stopwatch stopwatch = Stopwatch()..start();
      await controller.join();
      stopwatch.stop();
      expect(controller.status, RoomSessionStatus.joined);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(repository.fetchCalls, 1);
    });
  });
}

Map<String, Object?> _roomData({String status = 'READY'}) => <String, Object?>{
  'roomId': 'room-1',
  'sessionId': 'session-1',
  'version': 1,
  'realtimeGroup': <String, Object?>{
    'provider': 'tencent-im',
    'type': 'AVCHATROOM',
    'groupType': 'AVChatRoom',
    'groupId': 'room-group-1',
    'status': status,
    'messageMode': 'METADATA_HINT',
    'contentAuthority': 'HTTP',
  },
};

RoomController _roomController(
  _TencentRoomRepository repository,
  TencentImAvChatRoomCoordinator coordinator, {
  required Duration tencentImReadinessPollInterval,
  required Duration tencentImReadinessPollWindow,
}) => RoomController(
  roomId: 'room-1',
  title: '房间',
  currentUserId: 123,
  accessToken: 'first-party-token',
  repository: repository,
  rtcAdapter: MockRtcAdapter(),
  realtimeGateway: MockRoomRealtimeGateway(),
  tencentImAvChatRoomCoordinator: coordinator,
  tencentImReadinessPollInterval: tencentImReadinessPollInterval,
  tencentImReadinessPollWindow: tencentImReadinessPollWindow,
);

ImSessionCredentials _credentials(DateTime now) => ImSessionCredentials(
  provider: ImSessionCredentials.expectedProvider,
  sdkAppId: 1400000000,
  userId: 'u-123',
  userSig: 'sig_123456789012',
  expiresAt: now.add(const Duration(hours: 1)),
  ttlSeconds: 3600,
  imStatus: ImSessionCredentials.readyStatus,
  systemAccount: 'administrator',
);

TencentImSdkEvent _customEvent({
  required String groupId,
  required String sender,
  required bool isSelf,
  required String sessionId,
  required int version,
}) => TencentImSdkEvent.customElement(
  data: jsonEncode(<String, Object?>{
    'messageId': 'room-message-$version',
    'eventVersion': version,
  }),
  trustedFirstParty: true,
  senderUserId: sender,
  groupId: groupId,
  sessionId: sessionId,
  isSelf: isSelf,
);

Future<void> _eventTurn() => Future<void>.delayed(Duration.zero);

Future<void> _waitUntil(bool Function() condition) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition did not become true');
}

class _BasicSdk implements TencentImSdkClient {
  @override
  Future<bool> initSdk({required int sdkAppId}) async => true;

  @override
  Future<int> login({required String userId, required String userSig}) async =>
      0;

  @override
  Future<int> logout() async => 0;

  @override
  Future<int> uninitSdk() async => 0;
}

class _GroupSdk
    implements
        TencentImSdkClient,
        TencentImSdkEventSource,
        TencentImSdkGroupClient {
  final StreamController<TencentImSdkEvent> _eventController =
      StreamController<TencentImSdkEvent>.broadcast(sync: true);
  final List<String> joinedGroupIds = <String>[];
  final List<String> quitGroupIds = <String>[];
  int joinResultCode = 0;
  int quitResultCode = 0;
  bool hangJoin = false;
  bool hangQuit = false;

  @override
  Stream<TencentImSdkEvent> get events => _eventController.stream;

  @override
  Future<bool> initSdk({required int sdkAppId}) async => true;

  @override
  Future<int> login({required String userId, required String userSig}) async =>
      0;

  @override
  Future<int> logout() async => 0;

  @override
  Future<int> uninitSdk() async => 0;

  @override
  Future<int> joinGroup({
    required String groupId,
    required String groupType,
  }) async {
    joinedGroupIds.add(groupId);
    if (hangJoin) {
      return Completer<int>().future;
    }
    return joinResultCode;
  }

  @override
  Future<int> quitGroup({required String groupId}) async {
    quitGroupIds.add(groupId);
    if (hangQuit) {
      return Completer<int>().future;
    }
    return quitResultCode;
  }

  void emit(TencentImSdkEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  Future<void> dispose() => _eventController.close();
}

class _TencentRoomRepository extends MockRoomRepository
    implements TencentImRoomSessionSource, TencentImRoomReadinessSource {
  TencentImAvChatRoomSession? session =
      TencentImAvChatRoomSession.fromBackendData(_roomData());
  TencentImAvChatRoomSession? readinessSession;
  List<TencentImAvChatRoomSession?> readinessSequence =
      <TencentImAvChatRoomSession?>[];
  Future<TencentImAvChatRoomSession?> Function()? readinessFactory;
  bool returnPendingOnEnter = false;
  List<RoomMessage> messages = const <RoomMessage>[];
  int fetchCalls = 0;
  int readinessCalls = 0;
  int exitCalls = 0;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final RoomSnapshot snapshot = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    session = TencentImAvChatRoomSession.fromBackendData(<String, Object?>{
      ..._roomData(status: returnPendingOnEnter ? 'PENDING' : 'READY'),
      'roomId': snapshot.roomId,
    }, allowPending: returnPendingOnEnter);
    return snapshot;
  }

  @override
  Future<TencentImAvChatRoomSession?> fetchTencentImRoomReadiness(
    String roomId,
  ) async {
    readinessCalls += 1;
    final Future<TencentImAvChatRoomSession?> Function()? factory =
        readinessFactory;
    if (factory != null) {
      return factory();
    }
    if (readinessSequence.isNotEmpty) {
      return readinessSequence.removeAt(0);
    }
    return readinessSession;
  }

  @override
  Future<void> exitRoom(String roomId) async {
    exitCalls += 1;
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async {
    fetchCalls += 1;
    return List<RoomMessage>.of(messages);
  }

  @override
  TencentImAvChatRoomSession? get lastTencentImRoomSession => session;

  @override
  TencentImAvChatRoomSession? takeTencentImRoomSession(String roomId) {
    final TencentImAvChatRoomSession? value = session;
    session = null;
    return value?.roomId == roomId ? value : null;
  }
}
