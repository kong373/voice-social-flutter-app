import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'room_lease_contract_fixture.dart';

const _roomId = '22222222-2222-4222-8222-222222222222';
// Frozen first-visit staff CLOSED wire shape: there is deliberately no
// room_member row, so memberRole is NONE, not a fabricated MEMBER.
const _closedNoneJson = '''{
  "roomId":"22222222-2222-4222-8222-222222222222",
  "roomIdStr":"22222222-2222-4222-8222-222222222222",
  "roomCode":"123456", "roomName":"Closed staff inspection",
  "ownerUserId":20002, "viewerUserId":10001, "memberRole":"NONE",
  "ownerClosedAccess":false, "platformStaff":true,
  "closedRoomAccess":true, "canControlRoomLifecycle":true,
  "state":"CLOSED", "status":"CLOSED", "joined":true,
  "memberActive":false, "activeSession":false,
  "realtimeMode":"HTTP_STATE_ONLY", "publicScreenEnabled":false,
  "giftCatalogAvailable":false, "rtcStatus":"VENDOR_BLOCKED",
  "imStatus":"VENDOR_BLOCKED", "providerInvocation":false,
  "roomMuted":false, "version":1, "accessMode":"PASSWORD", "seats":[]
}''';

void main() {
  late HttpServer server;
  late BackendRoomRepository repository;
  late Map<String, Object?> wire;
  late List<({String method, String path, String body})> calls;
  Future<void> Function()? delay;

  setUp(() async {
    wire = jsonDecode(_closedNoneJson) as Map<String, Object?>;
    calls = [];
    delay = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add((
        method: request.method,
        path: request.uri.path,
        body: await utf8.decoder.bind(request).join(),
      ));
      await delay?.call();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'code': 200, 'data': wire}));
      await request.response.close();
    });
    repository = BackendRoomRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer contract-staff',
      ),
    );
  });
  tearDown(() => server.close(force: true));

  Future<RoomSnapshot> enter() => repository.enterRoom(
    roomId: _roomId,
    password: null,
    source: RoomEntrySource.home,
    currentUserId: 10001,
  );
  Future<void> expectReadRejected() async {
    await expectLater(enter(), throwsA(isA<ApiException>()));
    await expectLater(
      repository.fetchRoomAuthority(roomId: _roomId, currentUserId: 10001),
      throwsA(isA<ApiException>()),
    );
    expect(repository.leaseBinding.current, isNull);
  }

  test(
    'NONE closed staff enters and refreshes without membership or governance',
    () async {
      final rtc = MockRtcAdapter();
      final realtime = _TrackingRealtime();
      final controller = RoomController(
        roomId: _roomId,
        title: 'closed',
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
      expect(controller.status, RoomSessionStatus.joined);
      expect(controller.snapshot?.closedRoomAccess, isTrue);
      expect(controller.snapshot?.ownerClosedAccess, isFalse);
      expect(controller.snapshot?.role, RoomRole.listener);
      expect(controller.snapshot?.roomLease, isNull);
      expect(controller.snapshot?.sessionId, isNull);
      expect(repository.leaseBinding.current, isNull);
      wire['version'] = 2;
      await controller.refreshRoomAuthority();
      expect(controller.snapshot?.version, 2);
      expect(controller.status, RoomSessionStatus.joined);
      for (final capability in RoomCapability.values) {
        expect(
          controller.allows(capability),
          capability == RoomCapability.closeRoom,
          reason: capability.name,
        );
      }
      expect(await controller.requestMic(2), isFalse);
      expect(await controller.leaveRoom(), isTrue);
      expect(rtc.joined, isFalse);
      expect(realtime.connects, 0);
      expect(calls.where((c) => c.method == 'POST').map((c) => c.path), [
        '/app-room-api/room/com/v1/enterRoom',
      ]);
      expect(jsonDecode(calls.first.body), {
        'roomId': _roomId,
        'source': RoomEntrySource.home.backendCode,
      });
      expect(
        calls
            .where((c) => c.method == 'GET')
            .every((c) => c.path.endsWith('/queryRoomOtherInfo')),
        isTrue,
      );
    },
  );

  test(
    'NONE closed response after disposal never compensates with exit',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      delay = () async {
        if (!started.isCompleted) started.complete();
        await release.future;
      };
      final rtc = MockRtcAdapter();
      final realtime = _TrackingRealtime();
      final controller = RoomController(
        roomId: _roomId,
        title: 'closed',
        currentUserId: 10001,
        accessToken: 'test',
        repository: repository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      final work = controller.join();
      await started.future;
      controller.dispose();
      release.complete();
      await work;
      await realtime.dispose();
      expect(calls.map((c) => c.path), ['/app-room-api/room/com/v1/enterRoom']);
      expect(repository.leaseBinding.current, isNull);
      expect(rtc.joined, isFalse);
      expect(realtime.connects, 0);
    },
  );

  for (final mutation in <String, Object?>{
    'platformStaff': false,
    'closedRoomAccess': false,
    'canControlRoomLifecycle': false,
    'ownerClosedAccess': true,
    'ownerUserId': 10001,
    'viewerUserId': 20002,
    'state': 'OPEN',
    'status': 'OPEN',
    'joined': false,
    'memberActive': true,
    'activeSession': true,
    'sessionId': roomLeaseSessionId,
    'roomLease': roomLeaseWireFixture(),
    'realtimeMode': 'TENCENT_IM',
    'rtcStatus': 'READY',
    'imStatus': 'READY',
    'providerInvocation': true,
    'publicScreenEnabled': true,
    'giftCatalogAvailable': true,
  }.entries) {
    test(
      'NONE cannot bypass ${mutation.key} validation on enter or context',
      () async {
        wire[mutation.key] = mutation.value;
        await expectReadRejected();
      },
    );
  }

  for (final role in ['NONE', 'MEMBER']) {
    test(
      'OPEN joined staff with valid lease requires actual member role: $role',
      () async {
        wire.addAll({
          'state': 'OPEN',
          'status': 'JOINED',
          'closedRoomAccess': false,
          'memberActive': true,
          'activeSession': true,
          'memberRole': role,
          'sessionId': roomLeaseSessionId,
          'roomLease': roomLeaseWireFixture(),
        });
        if (role == 'NONE') {
          await expectReadRejected();
        } else {
          final snapshot = await enter();
          expect(snapshot.closedRoomAccess, isFalse);
          expect(snapshot.roomLease, isNotNull);
          expect(snapshot.role, RoomRole.listener);
          final context = await repository.fetchRoomAuthority(
            roomId: _roomId,
            currentUserId: 10001,
          );
          expect(context.memberActive, isTrue);
        }
      },
    );
  }
}

class _TrackingRealtime extends MockRoomRealtimeGateway {
  int connects = 0;
  @override
  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  }) {
    connects++;
    return super.connect(
      roomId: roomId,
      userId: userId,
      accessToken: accessToken,
    );
  }
}
