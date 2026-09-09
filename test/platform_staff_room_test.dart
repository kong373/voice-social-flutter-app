import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'room_closed_owner_rules_test.dart' show closedOwner;

void main() {
  test(
    'late closed entry after disposal never sends ordinary exit compensation',
    () async {
      final wire = closedOwner()
        ..addAll({
          'ownerUserId': 20002,
          'memberRole': 'MEMBER',
          'ownerClosedAccess': false,
          'platformStaff': true,
          'closedRoomAccess': true,
          'canControlRoomLifecycle': true,
        });
      final entered = Completer<void>(), release = Completer<void>();
      final calls = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        calls.add(request.uri.path);
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        request.response.write(jsonEncode({'code': 200, 'data': wire}));
        await request.response.close();
      });
      final repository = BackendRoomRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer test',
        ),
      );
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: '9527',
        title: 'closed',
        currentUserId: 10001,
        accessToken: 'test',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      final work = controller.join();
      await entered.future;
      controller.dispose();
      release.complete();
      await work;
      await realtime.dispose();
      expect(calls, ['/app-room-api/room/com/v1/enterRoom']);
    },
  );
  for (final role in [RoomRole.listener, RoomRole.owner, RoomRole.moderator]) {
    test('staff adds lifecycle only, preserving real $role permissions', () {
      RoomSnapshot snapshot(bool staff) => RoomSnapshot(
        roomId: '9527',
        roomCode: '9527',
        title: 'room',
        topic: '',
        ownerId: 20002,
        role: role,
        seats: const [],
        rtc: const RtcCredentials(
          solution: RtcSolution.unknown,
          token: '',
          channelId: '9527',
          userId: 10001,
        ),
        publicScreenEnabled: true,
        pictureMessagesAllowed: false,
        autoLockMic: false,
        giftCatalogAvailable: true,
        giftBalance: 0,
        platformStaff: staff,
        canControlRoomLifecycle: staff,
      );
      const policy = RoomPermissionPolicy();
      for (final capability in RoomCapability.values) {
        final original = policy.allows(
          snapshot: snapshot(false),
          capability: capability,
          isOnMic: false,
        );
        expect(
          policy.allows(
            snapshot: snapshot(true),
            capability: capability,
            isOnMic: false,
          ),
          capability == RoomCapability.closeRoom ? true : original,
          reason: capability.name,
        );
      }
    });
  }
  test(
    'staff closed password room accepts independent authority without lease',
    () async {
      final wire = closedOwner()
        ..addAll({
          'ownerUserId': 20002,
          'memberRole': 'MEMBER',
          'ownerClosedAccess': false,
          'platformStaff': true,
          'closedRoomAccess': true,
          'canControlRoomLifecycle': true,
          'accessMode': 'PASSWORD',
        });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodies = <Map<String, dynamic>>[];
      server.listen((request) async {
        bodies.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'code': 200, 'data': wire}));
        await request.response.close();
      });
      final repository = BackendRoomRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer test',
        ),
      );
      final snapshot = await repository.enterRoom(
        roomId: '9527',
        password: null,
        source: RoomEntrySource.home,
        currentUserId: 10001,
      );
      expect(snapshot.ownerClosedAccess, isFalse);
      expect(snapshot.role, RoomRole.listener);
      expect(snapshot.sessionId, isNull);
      expect(snapshot.roomLease, isNull);
      expect(repository.leaseBinding.current, isNull);
      expect(bodies.single.containsKey('password'), isFalse);
      for (final capability in RoomCapability.values) {
        expect(
          const RoomPermissionPolicy().allows(
            snapshot: snapshot,
            capability: capability,
            isOnMic: false,
          ),
          capability == RoomCapability.closeRoom,
        );
      }
    },
  );

  for (final mutation in <String, Object?>{
    'platformStaff': false,
    'canControlRoomLifecycle': false,
    'ownerClosedAccess': true,
    'memberRole': 'OWNER',
    'closedRoomAccess': false,
    'sessionId': 'fake',
    'roomLease': {},
    'memberActive': true,
    'activeSession': true,
    'viewerUserId': 20002,
    'state': 'OPEN',
    'providerInvocation': true,
    'publicScreenEnabled': true,
    'giftCatalogAvailable': true,
    'rtcStatus': 'READY',
    'imStatus': 'READY',
    'version': 1.5,
  }.entries) {
    test('staff closed rejects ${mutation.key}', () async {
      final wire = closedOwner()
        ..addAll({
          'ownerUserId': 20002,
          'memberRole': 'MEMBER',
          'ownerClosedAccess': false,
          'platformStaff': true,
          'closedRoomAccess': true,
          'canControlRoomLifecycle': true,
        })
        ..[mutation.key] = mutation.value;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.write(jsonEncode({'code': 200, 'data': wire}));
        await request.response.close();
      });
      final repository = BackendRoomRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer test',
        ),
      );
      await expectLater(
        repository.enterRoom(
          roomId: '9527',
          password: null,
          source: RoomEntrySource.home,
          currentUserId: 10001,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repository.leaseBinding.current, isNull);
    });
  }

  test(
    'staff controller closed has no transport, mic or session writes; revocation ends view',
    () async {
      final wire = closedOwner()
        ..addAll({
          'ownerUserId': 20002,
          'memberRole': 'MEMBER',
          'ownerClosedAccess': false,
          'platformStaff': true,
          'closedRoomAccess': true,
          'canControlRoomLifecycle': true,
        });
      final calls = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var revoked = false;
      server.listen((request) async {
        await request.drain<void>();
        calls.add('${request.method} ${request.uri.path}');
        request.response.statusCode = revoked ? 404 : 200;
        request.response.write(
          jsonEncode({
            'code': revoked ? 40431 : 200,
            'data': revoked ? null : wire,
          }),
        );
        await request.response.close();
      });
      final repository = BackendRoomRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer test',
        ),
      );
      final rtc = MockRtcAdapter();
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: '9527',
        title: 'staff',
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
      expect(controller.snapshot!.isClosedManagementView, isTrue);
      expect(rtc.joined, isFalse);
      expect(repository.leaseBinding.current, isNull);
      expect(await controller.requestMic(2), isFalse);
      for (final capability in RoomCapability.values) {
        expect(
          controller.allows(capability),
          capability == RoomCapability.closeRoom,
        );
      }
      revoked = true;
      await controller.refreshRoomAuthority();
      expect(controller.status, RoomSessionStatus.left);
      expect(controller.allows(RoomCapability.closeRoom), isFalse);
      expect(calls.where((x) => x.startsWith('POST')).length, 1);
      expect(
        calls.every(
          (x) => x.endsWith('/enterRoom') || x.endsWith('/queryRoomOtherInfo'),
        ),
        isTrue,
      );
    },
  );
}
