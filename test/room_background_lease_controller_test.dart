import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'room_lease_controller_test.dart' as fixtures;
import 'support/room_background_audio_fakes.dart';

class BackgroundRepo extends fixtures.Repo {
  BackendRoomRepository? heartbeatBackend;
  Object? heartbeatError;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final snapshot = (await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    )).copyWith(rtc: backgroundCredentials());
    final binding = heartbeatBackend?.leaseBinding;
    binding?.bind(
      binding.generation,
      roomId,
      currentUserId,
      snapshot.roomLease!,
    );
    return snapshot;
  }

  @override
  Future<RoomSessionLease> renewRoomLease({
    required String roomId,
    required String sessionId,
    required int sequence,
    required String requestId,
    required int currentUserId,
  }) async {
    try {
      return await (heartbeatBackend?.renewRoomLease(
            roomId: roomId,
            sessionId: sessionId,
            sequence: sequence,
            requestId: requestId,
            currentUserId: currentUserId,
          ) ??
          super.renewRoomLease(
            roomId: roomId,
            sessionId: sessionId,
            sequence: sequence,
            requestId: requestId,
            currentUserId: currentUserId,
          ));
    } catch (error) {
      heartbeatError = error;
      rethrow;
    }
  }
}

// Wire-level assertions at the HTTP boundary, with no network/provider call.
class HeartbeatHttpBoundary extends Fake implements ApiClient {
  HeartbeatHttpBoundary(this.elapsed);
  final Duration Function() elapsed;
  final requests = <({int sequence, String requestId})>[];
  @override
  Future<ApiResponse> postWithoutUnauthorizedRecovery(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    expectSync(path, '/app-room-api/room/com/v1/heartbeatRoom');
    expectSync(authenticated, isTrue);
    expectSync(
      body!.keys,
      unorderedEquals(['roomId', 'sessionId', 'sequence']),
    );
    expectSync(body['sessionId'], fixtures.session);
    final sequence = body['sequence']! as int;
    requests.add((sequence: sequence, requestId: headers!['X-Request-Id']!));
    final now = DateTime.utc(2026).add(elapsed());
    return ApiResponse(
      code: 200,
      message: '',
      data: {
        'sessionId': fixtures.session,
        'sequence': sequence,
        'serverTime': now.toIso8601String(),
        'expiresAt': now.add(const Duration(seconds: 90)).toIso8601String(),
        'heartbeatIntervalSeconds': 20,
        'leaseDurationSeconds': 90,
      },
    );
  }
}

// This suite exercises HTTP/RTC ownership, not realtime delivery. An explicit
// cancellation future keeps the unused event transport within the test zone.
class BackgroundGateway extends MockRoomRealtimeGateway {
  @override
  Stream<RoomRealtimeEvent> get events => _QuietStream();
}

class _QuietStream extends Stream<RoomRealtimeEvent> {
  @override
  StreamSubscription<RoomRealtimeEvent> listen(
    void Function(RoomRealtimeEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _QuietSubscription();
}

class _QuietSubscription implements StreamSubscription<RoomRealtimeEvent> {
  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late BackgroundRepo repo;
  late FakeRoomAudioPort native;
  late BackgroundFakeRtcEngine engine;
  late AgoraRtcAdapter rtc;
  late RoomController controller;
  late ChangeNotifier identity;
  late MockRoomRealtimeGateway gateway;
  Duration elapsed = Duration.zero;
  int? user = 1;
  void setup({bool snapshotOnly = false, bool withNative = true}) {
    elapsed = Duration.zero;
    user = 1;
    identity = ChangeNotifier();
    repo = BackgroundRepo()..interactive = !snapshotOnly;
    repo.now = () => elapsed.inSeconds;
    native = FakeRoomAudioPort();
    gateway = BackgroundGateway();
    engine = BackgroundFakeRtcEngine();
    rtc = AgoraRtcAdapter(
      engine: engine,
      backgroundAudioPort: withNative ? native : null,
      microphonePermissionAdapter: BackgroundPermission(),
    );
    controller = RoomController(
      roomId: 'r',
      title: '',
      currentUserId: 1,
      accessToken: '',
      repository: repo,
      rtcAdapter: rtc,
      realtimeGateway: snapshotOnly
          ? SnapshotOnlyRoomRealtimeGateway()
          : gateway,
      sessionChanges: identity,
      activeUserId: () => user,
      leaseElapsed: () => elapsed,
    );
    addTearDown(() async {
      controller.dispose();
      await flushBackgroundWork();
      await rtc.release();
      await native.changes.close();
      await gateway.dispose();
      identity.dispose();
    });
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    elapsed += Duration(seconds: seconds);
    await tester.pump(Duration(seconds: seconds));
  }

  testWidgets('owned RTC + fresh native query sends new heartbeats for 3x90s', (
    tester,
  ) async {
    setup();
    await controller.join();
    controller.setForeground(false);
    for (var i = 0; i < 15; i++) {
      await tick(tester, 20);
    }
    expect(repo.calls, hasLength(15));
    expect(repo.calls.map((v) => v.sequence), List.generate(15, (i) => i + 1));
    expect(repo.calls.map((v) => v.requestId).toSet(), hasLength(15));
    expect(native.queries.length, greaterThanOrEqualTo(15));
    expect(controller.status, RoomSessionStatus.joined);
    expect(controller.snapshot!.roomLease!.sequence, 15);
    controller.dispose();
    await tester.pump();
  });

  testWidgets(
    '3x90s reaches authenticated POST boundary through live repository',
    (tester) async {
      setup();
      final http = HeartbeatHttpBoundary(() => elapsed);
      repo.heartbeatBackend = BackendRoomRepository(apiClient: http);
      await controller.join();
      controller.setForeground(false);
      expect(repo.heartbeatBackend!.leaseBinding.current, isNotNull);
      expect(rtc.hasBackgroundAudioLease, isTrue);
      for (var i = 0; i < 15; i++) await tick(tester, 20);
      expect(repo.heartbeatError, isNull);
      expect(
        http.requests.map((r) => r.sequence),
        List.generate(15, (i) => i + 1),
      );
      expect(http.requests.map((r) => r.requestId).toSet(), hasLength(15));
      expect(controller.snapshot!.roomLease!.sequence, 15);
      controller.dispose();
      await tester.pump();
    },
  );

  for (final snapshot in [true, false]) {
    testWidgets(
      '${snapshot ? 'snapshot-only' : 'null native'} never continues background lease',
      (tester) async {
        setup(snapshotOnly: snapshot, withNative: snapshot);
        await controller.join();
        controller.setForeground(false);
        await tick(tester, 90);
        expect(repo.calls, isEmpty);
        expect(native.starts, isEmpty);
        expect(controller.status, RoomSessionStatus.left);
        controller.setForeground(true);
        await tester.pump();
        expect(repo.calls, isEmpty);
      },
    );
  }

  for (final failure in [
    'event',
    'query false',
    'query exception',
    'query timeout',
  ]) {
    testWidgets(
      'native $failure stops background renewal without extending deadline',
      (tester) async {
        setup();
        await controller.join();
        controller.setForeground(false);
        await tick(tester, 20);
        expect(repo.calls, hasLength(1));
        final id = native.starts.single.sessionId;
        Completer<bool>? pending;
        switch (failure) {
          case 'event':
            native.emit(id, false);
          case 'query false':
            native.active[id] = false;
          case 'query exception':
            native.queryFails = true;
          case 'query timeout':
            pending = Completer<bool>();
            native.pendingQuery = pending;
        }
        await tick(tester, 20);
        await tick(tester, 3);
        pending?.complete(true);
        await tester.pump();
        await tick(tester, 67);
        expect(repo.calls, hasLength(1));
        expect(controller.status, RoomSessionStatus.left);
        expect(rtc.joined, isFalse);
      },
    );
  }

  for (final action in ['logout', 'dispose', 'leave', 'deadline']) {
    testWidgets('$action during native await fences reply before HTTP send', (
      tester,
    ) async {
      setup();
      await controller.join();
      controller.setForeground(false);
      final pending = Completer<bool>();
      native.pendingQuery = pending;
      await tick(tester, 20);
      expect(native.queries, isNotEmpty);
      Future<bool>? leaving;
      switch (action) {
        case 'logout':
          user = null;
          identity.notifyListeners();
        case 'dispose':
          controller.dispose();
        case 'leave':
          leaving = controller.leaveRoom();
        case 'deadline':
          elapsed = const Duration(seconds: 90);
      }
      pending.complete(true);
      await tester.pump();
      if (leaving != null) {
        expect(repo.exits, 1);
        await leaving;
        expect(engine.leaves, 1);
      }
      expect(repo.calls, isEmpty);
      if (action == 'deadline') {
        controller.setForeground(true);
        await tester.pump();
      }
      if (action != 'dispose')
        expect(controller.status, RoomSessionStatus.left);
    });
  }

  testWidgets('old query and activity cannot renew new controller epoch', (
    tester,
  ) async {
    setup();
    await controller.join();
    final oldId = native.starts.single.sessionId;
    controller.setForeground(false);
    final pending = Completer<bool>();
    native.pendingQuery = pending;
    await tick(tester, 20);
    final leaving = controller.leaveRoom();
    pending.complete(true);
    await tester.pump();
    await leaving;
    await controller.join();
    controller.setForeground(true);
    await tester.pump();
    final before = repo.calls.length;
    native.emit(oldId, true);
    native.emit(oldId, false);
    controller.setForeground(false);
    await tick(tester, 20);
    expect(repo.calls, hasLength(before + 1));
    expect(native.starts.last.sessionId, isNot(oldId));
    controller.dispose();
    await tester.pump();
  });

  testWidgets(
    'ownership transfer fences old native query and old controller disposal',
    (tester) async {
      setup();
      await controller.join();
      controller.setForeground(false);
      final pending = Completer<bool>();
      native.pendingQuery = pending;
      await tick(tester, 20);
      final nextRepo = BackgroundRepo()..interactive = true;
      nextRepo.now = () => elapsed.inSeconds;
      final nextGateway = BackgroundGateway();
      final next = RoomController(
        roomId: 'r',
        title: '',
        currentUserId: 1,
        accessToken: '',
        repository: nextRepo,
        rtcAdapter: rtc,
        realtimeGateway: nextGateway,
        leaseElapsed: () => elapsed,
      );
      addTearDown(() async {
        next.dispose();
        await nextGateway.dispose();
      });
      await next.join();
      next.setForeground(false);
      pending.complete(true);
      await tester.pump();
      expect(repo.calls, isEmpty);
      controller.dispose();
      await tester.pump();
      expect(rtc.joined, isTrue);
      await tick(tester, 20);
      expect(nextRepo.calls, hasLength(1));
      expect(repo.calls, isEmpty);
      next.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'background failed heartbeat retries original request then expires',
    (tester) async {
      setup();
      await controller.join();
      controller.setForeground(false);
      repo.failure = StateError('HTTP response lost');
      for (var i = 0; i < 4; i++) {
        await tick(tester, 20);
      }
      expect(repo.calls, hasLength(4));
      expect(repo.calls.toSet(), hasLength(1));
      expect(controller.snapshot!.roomLease!.sequence, 0);
      await tick(tester, 10);
      expect(controller.status, RoomSessionStatus.left);
      controller.setForeground(true);
      await tester.pump();
      expect(repo.calls, hasLength(4));
    },
  );
}
