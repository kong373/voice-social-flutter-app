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

void main() {
  for (final problem in ['expiredLease', 'differentLease', 'SDKUnconfirmed']) {
    test('$problem cannot complete a fresh grant publication', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repo.withLease = true;
      await h.controller.join();
      h.repo.onMic = true;
      final pending = Completer<RoomSnapshot>();
      h.repo.pendingToken = pending;
      final reading = h.controller.refreshRoomAuthority();
      await Future<void>.delayed(Duration.zero);
      if (problem == 'expiredLease') h.elapsed = const Duration(seconds: 91);
      if (problem == 'SDKUnconfirmed') h.rtc.ignoreEnable = true;
      pending.complete(
        h.repo.snapshot().copyWith(
          sessionId: problem == 'differentLease'
              ? '00000000-0000-4000-8000-000000000002'
              : null,
        ),
      );
      await reading;
      expect(h.rtc.audioEnabled, isFalse);
      expect(h.controller.micMuted, isTrue);
    });
  }
  test(
    'unknown direct placement retries original seat and never guesses a second write',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repo.role = RoomRole.owner;
      await h.controller.join();
      h.repo.failWriteOnce = true;
      expect(await h.controller.requestMic(4), isFalse);
      expect(h.controller.pendingMicPlacementSeat, 4);
      expect(await h.controller.requestMic(5), isFalse);
      expect(h.repo.placementWrites, [4]);
      await h.controller.refreshRoomAuthority();
      expect(h.rtc.enableAttempts, 0);
      expect(await h.controller.requestMic(4), isTrue);
      expect(h.repo.placementWrites, [4, 4]);
      expect(h.controller.pendingMicPlacementSeat, isNull);
      expect(
        h.rtc.audioEnabled,
        isFalse,
      ); // Unknown result consumed the automatic attempt.
    },
  );
  test(
    'unknown personal mute retries original boolean after server state changes',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.repo.onMic = true;
      await h.controller.refreshRoomAuthority();
      h.repo.failWriteOnce = true;
      expect(await h.controller.toggleMicrophone(), isFalse);
      await h.controller.refreshRoomAuthority();
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.repo.muteWrites, [true, true]);
      expect(h.rtc.audioEnabled, isFalse);
    },
  );
  test('reconnect SDK failure cannot retain a publication intent', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.controller.join();
    h.repo.onMic = true;
    await h.controller.refreshRoomAuthority();
    h.rtc.failEnable = true;
    await h.controller.reconnect();
    expect(h.rtc.audioEnabled, isFalse);
    h.rtc.failEnable = false;
    final enables = h.rtc.enableAttempts;
    await h.controller.reconnect();
    expect(h.rtc.enableAttempts, enables);
    expect(h.rtc.audioEnabled, isFalse);
  });
  test(
    'fresh ordinary grant publishes once; self mute survives reads and reconnect',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      expect(h.rtc.audioEnabled, isFalse);
      h.repo.onMic = true;
      await h.controller.refreshRoomAuthority();
      expect(h.repo.tokenReads, 1);
      expect(h.rtc.audioEnabled, isTrue);
      expect(h.controller.micMuted, isFalse);
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.rtc.audioEnabled, isFalse);
      expect(h.repo.selfMuted, isTrue);
      await h.controller.refreshRoomAuthority();
      await h.controller.reconnect();
      expect(h.rtc.audioEnabled, isFalse);
      final tokens = h.repo.tokenReads;
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.repo.tokenReads, tokens + 1);
      expect(h.rtc.audioEnabled, isTrue);
    },
  );

  test(
    'public text mute neither revokes audio nor blocks personal audio control',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.repo.onMic = true;
      await h.controller.refreshRoomAuthority();
      h.repo.textMuted = true;
      await h.controller.refreshRoomAuthority();
      expect(h.controller.canSendPublicMessage, isFalse);
      expect(h.rtc.audioEnabled, isTrue);
      h.realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.mutedInRoom,
          payload: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.rtc.audioEnabled, isTrue);
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.rtc.audioEnabled, isTrue);
    },
  );

  for (final reason in ['forced', 'legacy', 'unknown']) {
    test(
      '$reason grant stays unpublished and refresh cannot silently unmute',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.controller.join();
        h.repo.onMic = true;
        h.repo.reason = reason;
        await h.controller.refreshRoomAuthority();
        expect(h.rtc.audioEnabled, isFalse);
        expect(await h.controller.toggleMicrophone(), isFalse);
        h.repo.reason = null;
        await h.controller.refreshRoomAuthority();
        await h.controller.reconnect();
        expect(h.rtc.audioEnabled, isFalse);
        expect(await h.controller.toggleMicrophone(), isTrue);
        expect(h.rtc.audioEnabled, isTrue);
      },
    );
  }

  test(
    'SDK failure consumes automatic grant and leaves only explicit retry',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.repo.onMic = true;
      h.rtc.failEnable = true;
      await h.controller.refreshRoomAuthority();
      expect(h.rtc.enableAttempts, 1);
      expect(h.rtc.audioEnabled, isFalse);
      expect(h.controller.isOnMic, isTrue);
      expect(h.controller.micMuted, isTrue);
      h.rtc.failEnable = false;
      await h.controller.refreshRoomAuthority();
      await h.controller.reconnect();
      expect(h.rtc.enableAttempts, 1);
      expect(h.rtc.audioEnabled, isFalse);
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.rtc.audioEnabled, isTrue);
    },
  );

  for (final transition in ['leave', 'accountABA', 'forced', 'background']) {
    test(
      'late publisher token cannot restore audio after $transition',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.controller.join();
        h.repo.onMic = true;
        final pending = Completer<RoomSnapshot>();
        h.repo.pendingToken = pending;
        final old = h.repo.snapshot();
        final refreshing = h.controller.refreshRoomAuthority();
        await Future<void>.delayed(Duration.zero);
        expect(h.repo.tokenReads, 1);
        if (transition == 'leave') {
          await h.controller.leaveRoom();
        } else if (transition == 'accountABA') {
          h.generation++;
          h.identity.value = 2;
          h.generation++;
          h.identity.value = 1;
        } else if (transition == 'background') {
          h.controller.setForeground(false);
        } else {
          h.repo.reason = 'forced';
          h.realtime.emit(
            const RoomRealtimeEvent(
              code: RoomRealtimeEventCodes.closeMic,
              payload: {},
            ),
          );
        }
        pending.complete(old);
        await refreshing;
        await Future<void>.delayed(Duration.zero);
        expect(h.rtc.audioEnabled, isFalse);
        expect(h.rtc.enableAttempts, 0);
      },
    );
  }
}

class _Harness {
  _Harness() {
    controller = RoomController(
      roomId: 'room',
      title: 'Room',
      currentUserId: 1,
      accessToken: 'test',
      repository: repo,
      rtcAdapter: rtc,
      realtimeGateway: realtime,
      authoritySyncInterval: const Duration(days: 1),
      sessionChanges: identity,
      identityGeneration: () => generation,
      activeUserId: () => identity.value,
      leaseElapsed: () => elapsed,
    );
  }
  final repo = _Repository();
  final rtc = _Rtc();
  final realtime = MockRoomRealtimeGateway();
  final identity = ValueNotifier<int>(1);
  int generation = 0;
  Duration elapsed = Duration.zero;
  late final RoomController controller;
  Future<void> dispose() async {
    controller.dispose();
    identity.dispose();
    await realtime.dispose();
  }
}

class _Repository extends MockRoomRepository
    implements RoomAuthorityRepository {
  bool onMic = false, selfMuted = false, textMuted = false;
  bool withLease = false, failWriteOnce = false;
  RoomRole role = RoomRole.listener;
  final List<int> placementWrites = [];
  final List<bool> muteWrites = [];
  String? reason;
  int tokenReads = 0;
  Completer<RoomSnapshot>? pendingToken;
  RoomSnapshot snapshot() => RoomSnapshot(
    roomId: 'room',
    sessionId: '00000000-0000-4000-8000-000000000001',
    roomCode: 'room',
    title: 'Room',
    topic: '',
    ownerId: role == RoomRole.owner ? 1 : 99,
    roomLease: withLease
        ? RoomSessionLease(
            sessionId: '00000000-0000-4000-8000-000000000001',
            sequence: 0,
            serverTime: DateTime.utc(2026),
            expiresAt: DateTime.utc(2026).add(const Duration(seconds: 90)),
            heartbeatIntervalSeconds: 20,
            leaseDurationSeconds: 90,
          )
        : null,
    role: role,
    seats: [
      MicSeat(
        number: 4,
        backendIndex: 4,
        state: !onMic
            ? MicSeatState.available
            : selfMuted || reason == 'forced' || reason == 'legacy'
            ? MicSeatState.occupiedMuted
            : MicSeatState.occupied,
        userId: onMic ? 1 : null,
        occupantJoinedAt: onMic ? '2026-09-10T00:00:00Z' : null,
        audioMute: reason == 'unknown'
            ? null
            : RoomAudioMuteState(
                selfMuted: selfMuted,
                forcedMuted: reason == 'forced',
                legacyMuted: reason == 'legacy',
              ),
      ),
    ],
    rtc: RtcCredentials(
      solution: RtcSolution.agora,
      provider: 'agora',
      appId: 'test-public-app',
      token: 'fresh-$tokenReads',
      channelId: 'room',
      uid: 1,
      role: onMic && !selfMuted && reason == null ? 'broadcaster' : 'audience',
      expiresAt: DateTime.utc(2035),
    ),
    transportMode: RoomTransportMode.interactive,
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
    onlineCount: 1,
  );
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => snapshot();
  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async => RoomAuthorityProjection(
    snapshot: snapshot(),
    viewerUserId: 1,
    memberActive: true,
    roomMuted: textMuted,
    version: 1,
  );
  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    tokenReads++;
    final pending = pendingToken;
    pendingToken = null;
    return pending == null ? snapshot() : pending.future;
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    muteWrites.add(muted);
    selfMuted = muted;
    _failOnce();
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    placementWrites.add(backendMicIndex);
    onMic = true;
    _failOnce();
  }

  void _failOnce() {
    if (failWriteOnce) {
      failWriteOnce = false;
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'response lost',
      );
    }
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
  @override
  Future<void> exitRoom(String roomId) async {}
}

class _Rtc extends MockRtcAdapter {
  bool failEnable = false, ignoreEnable = false;
  int enableAttempts = 0;
  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (enabled) {
      enableAttempts++;
      if (failEnable)
        throw const RtcAdapterException(
          failure: RtcAdapterFailure.permission,
          message: '麦克风权限未授予',
        );
    }
    if (enabled && ignoreEnable) return;
    await super.setLocalAudioEnabled(enabled);
  }
}
