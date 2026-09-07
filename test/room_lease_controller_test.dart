import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

const session = '00000000-0000-4000-8000-000000000001';
RoomSessionLease lease(
  int sequence, {
  int remaining = 90,
  String id = session,
  int serverSeconds = 0,
}) => RoomSessionLease(
  sessionId: id,
  sequence: sequence,
  serverTime: DateTime.utc(2026).add(Duration(seconds: serverSeconds)),
  expiresAt: DateTime.utc(
    2026,
  ).add(Duration(seconds: serverSeconds + remaining)),
  heartbeatIntervalSeconds: 20,
  leaseDurationSeconds: 90,
);

class Repo extends MockRoomRepository implements RoomLeaseRepository {
  bool includeLease = true;
  bool interactive = false;
  int Function() now = () => 0;
  final calls = <({int sequence, String requestId})>[];
  Completer<RoomSessionLease>? pending;
  Object? failure;
  bool failExit = false;
  int exits = 0;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => RoomSnapshot(
    roomId: roomId,
    roomCode: roomId,
    title: '',
    topic: '',
    ownerId: 1,
    role: RoomRole.listener,
    seats: const [],
    rtc: const RtcCredentials(
      solution: RtcSolution.agora,
      token: '',
      channelId: 'r',
      userId: 1,
    ),
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
    transportMode: interactive
        ? RoomTransportMode.interactive
        : RoomTransportMode.snapshotOnly,
    sessionId: session,
    roomLease: includeLease ? lease(0) : null,
  );
  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
  @override
  Future<void> exitRoom(String roomId) async {
    exits++;
    if (failExit) throw Exception('exit response lost');
  }

  @override
  Future<RoomSessionLease> renewRoomLease({
    required String roomId,
    required String sessionId,
    required int sequence,
    required String requestId,
    required int currentUserId,
  }) async {
    calls.add((sequence: sequence, requestId: requestId));
    if (failure != null) throw failure!;
    return pending == null
        ? lease(sequence, serverSeconds: now())
        : pending!.future;
  }
}

class AuthorityRepo extends Repo implements RoomAuthorityRepository {
  int reads = 0;
  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    reads++;
    return RoomAuthorityProjection(
      snapshot: (await enterRoom(
        roomId: roomId,
        password: null,
        source: RoomEntrySource.home,
        currentUserId: currentUserId,
      )).copyWith(roomLease: lease(0, serverSeconds: now())),
      viewerUserId: currentUserId,
      memberActive: true,
      roomMuted: false,
      version: reads,
    );
  }
}

class NoCapabilityRepo extends MockRoomRepository {
  final fixture = Repo()..includeLease = false;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) => fixture.enterRoom(
    roomId: roomId,
    password: password,
    source: source,
    currentUserId: currentUserId,
  );
  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
}

void main() {
  late Repo repo;
  late RoomController controller;
  late ChangeNotifier identity;
  late MockRtcAdapter rtc;
  int? user;
  int generation = 0;
  Duration elapsed = Duration.zero;
  void setup({Repo? repository}) {
    repo = repository ?? Repo();
    rtc = MockRtcAdapter();
    identity = ChangeNotifier();
    user = 1;
    generation = 0;
    elapsed = Duration.zero;
    repo.now = () => elapsed.inSeconds;
    controller = RoomController(
      roomId: 'r',
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: repo,
      rtcAdapter: rtc,
      realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
      sessionChanges: identity,
      activeUserId: () => user,
      identityGeneration: () => generation,
      leaseElapsed: () => elapsed,
    );
    addTearDown(() {
      controller.dispose();
      identity.dispose();
    });
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    elapsed += Duration(seconds: seconds);
    await tester.pump(Duration(seconds: seconds));
  }

  testWidgets('idle 20s POST; failure retries same id/seq; success advances', (
    tester,
  ) async {
    setup();
    await controller.join();
    repo.failure = Exception('offline');
    await tick(tester, 19);
    expect(repo.calls, isEmpty);
    await tick(tester, 1);
    expect(repo.calls.single.sequence, 1);
    await tick(tester, 20);
    expect(repo.calls[1], repo.calls[0]);
    repo.failure = null;
    await tick(tester, 20);
    expect(repo.calls[2], repo.calls[0]);
    await tick(tester, 20);
    expect(repo.calls.last.sequence, 2);
    expect(repo.calls.last.requestId, isNot(repo.calls.first.requestId));
    controller.dispose();
  });
  testWidgets(
    'single flight and late response cannot revive deadline equality',
    (tester) async {
      setup();
      await controller.join();
      repo.pending = Completer();
      await tick(tester, 20);
      await tick(tester, 20);
      expect(repo.calls, hasLength(1));
      await tick(tester, 50);
      expect(controller.status, RoomSessionStatus.left);
      repo.pending!.complete(lease(1));
      await tester.pump();
      expect(controller.status, RoomSessionStatus.left);
      expect(repo.exits, 0);
    },
  );
  testWidgets('hidden pauses POST; resume checks immediately without reenter', (
    tester,
  ) async {
    setup();
    await controller.join();
    controller.setForeground(false);
    await tick(tester, 30);
    expect(repo.calls, isEmpty);
    controller.setForeground(true);
    await tester.pump();
    expect(repo.calls, hasLength(1));
    controller.setForeground(false);
    await tick(tester, 90);
    controller.setForeground(true);
    await tester.pump();
    expect(controller.status, RoomSessionStatus.left);
    expect(repo.calls, hasLength(1));
  });
  for (final action in ['logout', 'switch', 'generation', 'dispose', 'leave']) {
    testWidgets('$action stops timers and fences pending old response', (
      tester,
    ) async {
      setup();
      await controller.join();
      repo.pending = Completer();
      await tick(tester, 20);
      switch (action) {
        case 'logout':
          user = null;
          identity.notifyListeners();
        case 'switch':
          user = 2;
          identity.notifyListeners();
        case 'generation':
          generation++;
          identity.notifyListeners();
        case 'dispose':
          controller.dispose();
        case 'leave':
          await controller.leaveRoom();
      }
      repo.pending!.complete(lease(1));
      await tester.pump();
      await tick(tester, 100);
      expect(repo.calls, hasLength(1));
      if (action != 'dispose')
        expect(controller.status, RoomSessionStatus.left);
      expect(repo.exits, action == 'leave' ? 1 : 0);
    });
  }
  for (final code in [40936, 40937, 40101]) {
    testWidgets('$code revokes local session without exit write', (
      tester,
    ) async {
      setup();
      await controller.join();
      repo.failure = ApiException(
        kind: ApiFailureKind.business,
        code: code,
        message: 'expired',
      );
      await tick(tester, 20);
      expect(controller.status, RoomSessionStatus.left);
      expect(controller.canSendPublicMessage, isFalse);
      expect(repo.exits, 0);
    });
  }

  testWidgets('successful idle renewal stays alive beyond original 90s', (
    tester,
  ) async {
    setup();
    await controller.join();
    for (var i = 0; i < 8; i++) {
      await tick(tester, 20);
    }
    expect(repo.calls, hasLength(8));
    expect(controller.snapshot!.roomLease!.sequence, 8);
    expect(controller.status, RoomSessionStatus.joined);
    controller.dispose();
  });

  for (final response in [
    lease(0),
    lease(2),
    lease(1, id: '00000000-0000-4000-8000-000000000002'),
  ]) {
    testWidgets(
      'reject response identity/sequence ${response.sessionId}/${response.sequence}',
      (tester) async {
        setup();
        await controller.join();
        repo.pending = Completer();
        await tick(tester, 20);
        repo.pending!.complete(response);
        await tester.pump();
        expect(controller.snapshot!.roomLease!.sequence, 0);
        repo.pending = null;
        await tick(tester, 20);
        expect(repo.calls[1], repo.calls[0]);
        controller.dispose();
      },
    );
  }

  testWidgets(
    'deadline equality rejects response before expiry timer dispatch',
    (tester) async {
      setup();
      await controller.join();
      repo.pending = Completer();
      await tick(tester, 20);
      elapsed = const Duration(seconds: 90);
      repo.pending!.complete(lease(1, serverSeconds: 20));
      await tester.pump();
      expect(controller.snapshot!.roomLease!.sequence, 0);
      expect(controller.canSendPublicMessage, isFalse);
      controller.setForeground(false);
      controller.setForeground(true);
      expect(controller.status, RoomSessionStatus.left);
    },
  );

  testWidgets('retry replay of old server timestamps does not gain lifetime', (
    tester,
  ) async {
    setup();
    await controller.join();
    repo.failure = Exception('lost response');
    await tick(tester, 20);
    await tick(tester, 20);
    repo.failure = null;
    repo.pending = Completer();
    await tick(tester, 20);
    repo.pending!.complete(lease(1, serverSeconds: 20));
    await tester.pump();
    controller.setForeground(false);
    await tick(tester, 49);
    expect(controller.status, RoomSessionStatus.joined);
    await tick(tester, 1);
    expect(controller.status, RoomSessionStatus.left);
  });

  testWidgets('old room flight cannot modify explicitly rejoined controller', (
    tester,
  ) async {
    setup();
    await controller.join();
    repo.pending = Completer();
    final old = repo.pending!;
    await tick(tester, 20);
    await controller.leaveRoom();
    repo.pending = null;
    await controller.join();
    old.complete(lease(1, serverSeconds: 20));
    await tester.pump();
    expect(controller.snapshot!.roomLease!.sequence, 0);
    await tick(tester, 20);
    expect(controller.snapshot!.roomLease!.sequence, 1);
    controller.dispose();
  });

  test('wire validation rejects unsafe sequence and non UTC times', () {
    expect(lease(0).isValid, isTrue);
    expect(lease(9007199254740992).isValid, isFalse);
    expect(lease(-1).isValid, isFalse);
    expect(lease(0, remaining: 91).isValid, isFalse);
    expect(lease(0, remaining: -1).isValid, isFalse);
    expect(lease(0, remaining: 0).isValid, isTrue);
    expect(lease(0, id: 'not-a-session').isValid, isFalse);
    final nonUtc = RoomSessionLease(
      sessionId: session,
      sequence: 0,
      serverTime: DateTime(2026),
      expiresAt: DateTime(2026),
      heartbeatIntervalSeconds: 20,
      leaseDurationSeconds: 90,
    );
    expect(nonUtc.isValid, isFalse);
  });

  testWidgets(
    'GET projections cannot extend deadline or replace confirmed lease',
    (tester) async {
      final authority = AuthorityRepo();
      setup(repository: authority);
      repo.failure = Exception('POST offline');
      await controller.join();
      final confirmed = controller.snapshot!.roomLease;
      for (var i = 0; i < 3; i++) {
        await tick(tester, 20);
      }
      expect(authority.reads, greaterThan(1));
      expect(controller.snapshot!.roomLease, same(confirmed));
      await tick(tester, 30);
      expect(controller.status, RoomSessionStatus.left);
    },
  );

  for (final code in [40936, 40937, 40101]) {
    testWidgets('RTC publication is torn down on lease error $code', (
      tester,
    ) async {
      setup(repository: Repo()..interactive = true);
      await controller.join();
      await rtc.setLocalAudioEnabled(true);
      expect(rtc.audioEnabled, isTrue);
      repo.failure = ApiException(
        kind: ApiFailureKind.business,
        code: code,
        message: 'expired',
      );
      await tick(tester, 20);
      expect(rtc.audioEnabled, isFalse);
      expect(rtc.joined, isFalse);
      expect(controller.canSendPublicMessage, isFalse);
      expect(repo.exits, 0);
    });
  }

  testWidgets('Mock without capability or lease keeps original behavior', (
    tester,
  ) async {
    final mock = NoCapabilityRepo();
    final c = RoomController(
      roomId: 'r',
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: mock,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
    );
    await c.join();
    await tester.pump(const Duration(seconds: 180));
    expect(c.snapshot!.roomLease, isNull);
    expect(c.status, RoomSessionStatus.joined);
    c.dispose();
  });

  testWidgets('capability alone does not fabricate a lease', (tester) async {
    setup(repository: Repo()..includeLease = false);
    await controller.join();
    await tick(tester, 180);
    expect(repo.calls, isEmpty);
    expect(controller.status, RoomSessionStatus.joined);
    expect(controller.snapshot!.roomLease, isNull);
    controller.dispose();
  });

  testWidgets('failed leave still terminates local lease and RTC', (
    tester,
  ) async {
    setup(repository: Repo()..interactive = true);
    await controller.join();
    await rtc.setLocalAudioEnabled(true);
    repo.failExit = true;
    expect(await controller.leaveRoom(), isFalse);
    await tester.pump();
    expect(controller.status, RoomSessionStatus.left);
    expect(rtc.audioEnabled, isFalse);
    await tick(tester, 100);
    expect(repo.calls, isEmpty);
  });

  testWidgets('a received lease expires even without renewal capability', (
    tester,
  ) async {
    final mock = NoCapabilityRepo();
    mock.fixture.includeLease = true;
    final c = RoomController(
      roomId: 'r',
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: mock,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
    );
    await c.join();
    await tester.pump(const Duration(seconds: 90));
    expect(c.status, RoomSessionStatus.left);
    expect(c.canSendPublicMessage, isFalse);
    c.dispose();
  });

  testWidgets('response transit time is subtracted from remaining lifetime', (
    tester,
  ) async {
    setup();
    await controller.join();
    repo.pending = Completer();
    await tick(tester, 20);
    await tick(tester, 10);
    repo.pending!.complete(lease(1, serverSeconds: 20));
    await tester.pump();
    controller.setForeground(false);
    await tick(tester, 80);
    expect(controller.status, RoomSessionStatus.left);
  });
}
