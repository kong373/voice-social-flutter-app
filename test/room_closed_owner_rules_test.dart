import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';

Map<String, Object?> closedOwner() => {
  'roomId': '9527',
  'roomName': '关闭房间',
  'ownerUserId': 10001,
  'viewerUserId': 10001,
  'memberRole': 'OWNER',
  'ownerClosedAccess': true,
  'state': 'CLOSED',
  'status': 'CLOSED',
  'joined': true,
  'memberActive': false,
  'activeSession': false,
  'realtimeMode': 'HTTP_STATE_ONLY',
  'publicScreenEnabled': false,
  'giftCatalogAvailable': false,
  'rtcStatus': 'VENDOR_BLOCKED',
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
  'roomMuted': false,
  'version': 1,
  'accessMode': 'PUBLIC',
  'seats': [],
};

void main() {
  late HttpServer server;
  late BackendRoomRepository repository;
  late Map<String, Object?> wire;
  late List<String> calls;
  setUp(() async {
    calls = [];
    wire = closedOwner();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      calls.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'code': 200, 'data': wire}));
      await request.response.close();
    });
    repository = BackendRoomRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer contract-test',
      ),
    );
  });
  tearDown(() => server.close(force: true));

  Future<RoomSnapshot> enter() => repository.enterRoom(
    roomId: '9527',
    password: null,
    source: RoomEntrySource.home,
    currentUserId: 10001,
  );

  test(
    'closed owner is management only and never acquires membership',
    () async {
      final snapshot = await enter();
      expect(snapshot.ownerClosedAccess, isTrue);
      expect(snapshot.sessionId, isNull);
      expect(snapshot.roomLease, isNull);
      expect(repository.leaseBinding.current, isNull);
      for (final capability in RoomCapability.values) {
        expect(
          const RoomPermissionPolicy().allows(
            snapshot: snapshot,
            capability: capability,
            isOnMic: false,
          ),
          capability == RoomCapability.editRoom,
          reason: capability.name,
        );
      }
      final context = await repository.fetchRoomAuthority(
        roomId: '9527',
        currentUserId: 10001,
      );
      expect(context.memberActive, isFalse);
      expect(context.snapshot.ownerClosedAccess, isTrue);
      await expectLater(repository.requestMic(1), throwsA(isA<ApiException>()));
      expect(calls.length, 2);
    },
  );

  for (final mutation in <String, Object?>{
    'ownerUserId': 20002,
    'viewerUserId': 20002,
    'memberRole': 'MANAGER',
    'memberActive': true,
    'activeSession': true,
    'state': 'OPEN',
    'status': 'OPEN',
    'sessionId': 'fake',
    'roomLease': <String, Object?>{},
    'providerInvocation': true,
    'publicScreenEnabled': true,
    'giftCatalogAvailable': true,
    'realtimeMode': 'INTERACTIVE',
  }.entries) {
    test('closed management rejects inconsistent ${mutation.key}', () async {
      wire[mutation.key] = mutation.value;
      await expectLater(enter(), throwsA(isA<ApiException>()));
      expect(repository.leaseBinding.current, isNull);
    });
  }

  test('OPEN and unmarked CLOSED still require an exact lease', () async {
    wire.remove('ownerClosedAccess');
    await expectLater(enter(), throwsA(isA<ApiException>()));
    wire['status'] = 'OPEN';
    wire['state'] = 'OPEN';
    await expectLater(enter(), throwsA(isA<ApiException>()));
  });

  test('controller exits closed management without any session POST', () async {
    final rtc = MockRtcAdapter();
    final realtime = MockRoomRealtimeGateway();
    final controller = RoomController(
      roomId: '9527',
      title: '关闭房间',
      currentUserId: 10001,
      accessToken: 'test',
      repository: repository,
      rtcAdapter: rtc,
      realtimeGateway: realtime,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });
    await controller.join();
    expect(controller.snapshot?.ownerClosedAccess, isTrue);
    expect(rtc.joined, isFalse);
    expect(await controller.requestMic(1), isFalse);
    expect(await controller.leaveRoom(), isTrue);
    expect(calls.where((call) => call.startsWith('POST')).length, 1);
    expect(
      calls.every(
        (call) =>
            call.endsWith('/enterRoom') || call.endsWith('/queryRoomOtherInfo'),
      ),
      isTrue,
    );
  });

  for (final change in ['owner', 'reopen']) {
    test(
      'closed context $change ends view without granting a session',
      () async {
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: '9527',
          title: '关闭房间',
          currentUserId: 10001,
          accessToken: 'test',
          repository: repository,
          rtcAdapter: const SnapshotOnlyRtcAdapter(),
          realtimeGateway: realtime,
        );
        addTearDown(() async {
          controller.dispose();
          await realtime.dispose();
        });
        await controller.join();
        if (change == 'owner') {
          wire['ownerUserId'] = 20002;
        } else {
          wire.remove('ownerClosedAccess');
          wire['state'] = 'OPEN';
          wire['status'] = 'OPEN';
        }
        await controller.refreshRoomAuthority();
        expect(controller.status, RoomSessionStatus.left);
        expect(controller.allows(RoomCapability.editRoom), isFalse);
        expect(controller.allows(RoomCapability.requestMic), isFalse);
        expect(repository.leaseBinding.current, isNull);
        expect(calls.where((call) => call.startsWith('POST')).length, 1);
      },
    );
  }
}
