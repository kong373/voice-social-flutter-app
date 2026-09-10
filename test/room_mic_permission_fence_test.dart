import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'support/room_background_audio_fakes.dart';

void main() {
  for (final boundary in ['permissionStatus', 'backgroundStart']) {
    for (final transition in ['accountABA', 'leave', 'expiredLease']) {
      test(
        'real Agora $boundary rechecks $transition before any SDK enable',
        () async {
          final h = _Harness(withNative: boundary == 'backgroundStart');
          addTearDown(h.dispose);
          final backgroundStarted = Completer<void>();
          final backgroundResult = Completer<bool>();
          if (boundary == 'permissionStatus') {
            h.permission.pauseStatus = true;
          } else {
            h.permission.result.complete(PermissionState.granted);
            h.native.onStart = (microphone) {
              if (microphone) {
                h.native.pendingStart = backgroundResult;
                if (!backgroundStarted.isCompleted)
                  backgroundStarted.complete();
              }
            };
          }
          await h.controller.join();
          h.repo.onMic = true;
          final granting = h.controller.refreshRoomAuthority();
          await (boundary == 'permissionStatus'
                  ? h.permission.started.future
                  : backgroundStarted.future)
              .timeout(const Duration(seconds: 2));
          final leaving = h.invalidate(transition);
          if (boundary == 'permissionStatus') {
            h.permission.result.complete(PermissionState.denied);
          } else {
            backgroundResult.complete(true);
          }
          await granting;
          if (leaving != null) await leaving;
          await flushBackgroundWork();
          expect(h.engine.published.where((v) => v), isEmpty);
          expect(h.engine.muted.where((v) => !v), isEmpty);
          if (boundary == 'permissionStatus') expect(h.permission.requests, 0);
        },
      );
    }
  }

  test(
    'synchronous adapter cancellation invalidates permission wait without queuing disable',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.rtc.join(backgroundCredentials());
      final enabling = h.rtc.setLocalAudioEnabled(true);
      await h.permission.started.future.timeout(const Duration(seconds: 2));
      h.rtc.cancelPendingPublication();
      h.permission.result.complete(PermissionState.granted);
      await enabling;
      expect(h.engine.published, isEmpty);
      expect(h.engine.muted, isEmpty);
    },
  );

  test(
    'real Agora checks authority again between SDK options and stream unmute',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final pendingOptions = Completer<void>();
      h.engine.pendingPublish = pendingOptions;
      addTearDown(() {
        if (!pendingOptions.isCompleted) pendingOptions.complete();
      });
      await h.controller.join();
      h.repo.onMic = true;
      final granting = h.controller.refreshRoomAuthority();
      await h.permission.started.future.timeout(const Duration(seconds: 2));
      h.permission.result.complete(PermissionState.granted);
      await flushBackgroundWork();
      expect(
        h.engine.published.where((v) => v),
        [true],
      ); // Requested while authority was valid; initial audience disable is allowed.
      h.invalidate('accountABA');
      pendingOptions.complete();
      await granting;
      await flushBackgroundWork();
      expect(h.engine.muted.where((v) => !v), isEmpty);
      expect(h.engine.published.where((v) => v), [true]);
      expect(h.rtc.localAudioEnabled, isFalse);
    },
  );

  test(
    'old pending permission cannot enable or close a replacement controller transport',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.repo.onMic = true;
      final granting = h.controller.refreshRoomAuthority();
      await h.permission.started.future.timeout(const Duration(seconds: 2));
      final replacement = RoomController(
        roomId: 'unit-room',
        title: 'replacement',
        currentUserId: 42,
        accessToken: 'synthetic',
        repository: h.repo,
        rtcAdapter: h.rtc,
        realtimeGateway: h.gateway,
        authoritySyncInterval: const Duration(days: 1),
      );
      try {
        await replacement.join();
        final leaves = h.engine.leaves;
        h.permission.result.complete(PermissionState.granted);
        await granting;
        await flushBackgroundWork();
        expect(h.engine.published.where((v) => v), isEmpty);
        expect(h.engine.muted.where((v) => !v), isEmpty);
        expect(h.engine.leaves, leaves);
        expect(h.rtc.joined, isTrue);
      } finally {
        replacement.dispose();
      }
    },
  );
  for (final transition in [
    'accountABA',
    'leave',
    'expiredLease',
    'forcedMute',
    'dispose',
  ]) {
    test(
      'real Agora fresh grant cannot enable after $transition during permission await',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.controller.join();
        h.repo.onMic = true;
        final granting = h.controller.refreshRoomAuthority();
        await h.permission.started.future.timeout(const Duration(seconds: 2));
        expect(h.repo.tokenReads, 1);
        expect(h.rtc.credentials!.role, 'broadcaster');
        expect(h.engine.published.where((enabled) => enabled), isEmpty);
        final leaving = h.invalidate(transition);
        h.permission.result.complete(PermissionState.granted);
        await granting;
        if (leaving != null) await leaving;
        await flushBackgroundWork();
        // Recording every SDK call catches even a transient enable followed by
        // a later controller disable; final localAudioEnabled alone is unsafe.
        expect(h.engine.published.where((enabled) => enabled), isEmpty);
        expect(h.engine.muted.where((muted) => !muted), isEmpty);
        expect(h.rtc.localAudioEnabled, isFalse);
      },
    );
  }

  for (final withNative in [false, true]) {
    test(
      'real Agora valid fresh grant enables only after permission completes (native=$withNative)',
      () async {
        final h = _Harness(withNative: withNative);
        addTearDown(h.dispose);
        await h.controller.join();
        h.repo.onMic = true;
        final granting = h.controller.refreshRoomAuthority();
        await h.permission.started.future.timeout(const Duration(seconds: 2));
        expect(h.engine.published.where((enabled) => enabled), isEmpty);
        h.permission.result.complete(PermissionState.granted);
        await granting;
        expect(h.engine.published.where((enabled) => enabled), [true]);
        expect(h.engine.muted.where((muted) => !muted), [false]);
        expect(h.rtc.localAudioEnabled, isTrue);
      },
    );
  }
}

class _Harness {
  _Harness({bool withNative = false}) {
    rtc = AgoraRtcAdapter(
      engine: engine,
      microphonePermissionAdapter: permission,
      backgroundAudioPort: withNative ? native : null,
    );
    controller = RoomController(
      roomId: 'unit-room',
      title: 'Room',
      currentUserId: 42,
      accessToken: 'synthetic-test',
      repository: repo,
      rtcAdapter: rtc,
      realtimeGateway: gateway,
      authoritySyncInterval: const Duration(days: 1),
      sessionChanges: identity,
      activeUserId: () => identity.value,
      identityGeneration: () => generation,
      leaseElapsed: () => elapsed,
    );
  }
  final repo = _Repository();
  final permission = _PendingPermission();
  final engine = BackgroundFakeRtcEngine();
  final native = FakeRoomAudioPort();
  final gateway = MockRoomRealtimeGateway();
  final identity = ValueNotifier<int>(42);
  int generation = 0;
  Duration elapsed = Duration.zero;
  late final AgoraRtcAdapter rtc;
  late final RoomController controller;
  Future<bool>? invalidate(String transition) {
    switch (transition) {
      case 'accountABA':
        generation++;
        identity.value = 99;
        generation++;
        identity.value = 42;
      case 'leave':
        // Do not wait for cleanup: it is behind the publication mutex.
        return controller.leaveRoom();
      case 'expiredLease':
        elapsed = const Duration(seconds: 91);
      case 'forcedMute':
        gateway.emit(
          const RoomRealtimeEvent(
            code: RoomRealtimeEventCodes.closeMic,
            payload: {},
          ),
        );
      case 'dispose':
        controller.dispose();
    }
    return null;
  }

  Future<void> dispose() async {
    if (!permission.result.isCompleted)
      permission.result.complete(PermissionState.denied);
    controller.dispose();
    await flushBackgroundWork();
    await rtc.release();
    await native.changes.close();
    await gateway.dispose();
    identity.dispose();
  }
}

class _PendingPermission extends BackgroundPermission {
  final started = Completer<void>();
  final result = Completer<PermissionState>();
  bool pauseStatus = false;
  @override
  Future<PermissionState> status(PermissionKind kind) async {
    if (!pauseStatus) return PermissionState.denied;
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<PermissionState> request(PermissionKind kind) {
    requests++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _Repository extends MockRoomRepository
    implements RoomAuthorityRepository {
  static const session = '00000000-0000-4000-8000-000000000001';
  bool onMic = false;
  int tokenReads = 0;
  RoomSnapshot snapshot() => RoomSnapshot(
    roomId: 'unit-room',
    sessionId: session,
    roomCode: 'test',
    title: 'Room',
    topic: '',
    ownerId: 9,
    role: RoomRole.listener,
    roomLease: RoomSessionLease(
      sessionId: session,
      sequence: 0,
      serverTime: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026).add(const Duration(seconds: 90)),
      heartbeatIntervalSeconds: 20,
      leaseDurationSeconds: 90,
    ),
    seats: [
      MicSeat(
        number: 4,
        backendIndex: 4,
        userId: onMic ? 42 : null,
        state: onMic ? MicSeatState.occupied : MicSeatState.available,
        occupantJoinedAt: onMic ? '2026-09-10T00:00:00Z' : null,
        audioMute: const RoomAudioMuteState(
          selfMuted: false,
          forcedMuted: false,
          legacyMuted: false,
        ),
      ),
    ],
    rtc: backgroundCredentials(role: onMic ? 'broadcaster' : 'audience'),
    transportMode: RoomTransportMode.interactive,
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
  );
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => snapshot();
  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    tokenReads++;
    return snapshot();
  }

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async => RoomAuthorityProjection(
    snapshot: snapshot(),
    viewerUserId: 42,
    memberActive: true,
    roomMuted: false,
    version: 1,
  );
  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
  @override
  Future<void> exitRoom(String roomId) async {}
}
