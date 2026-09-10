import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/native_room_background_audio.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'support/room_background_audio_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final background in [false, true]) {
    test(
      'native interruption resumes only prior publication after fresh authority (background=$background)',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.publish();
        final reads = h.repo.reads;
        h.interrupt('began');
        await flushBackgroundWork();
        expect(h.rtc.localAudioEnabled, isFalse);
        if (background) h.controller.setForeground(false);
        await flushBackgroundWork();
        h.interrupt('ended');
        await flushBackgroundWork();
        expect(h.repo.reads, greaterThan(reads));
        expect(h.engine.published.where((v) => v), [true, true]);
        expect(h.engine.muted.where((v) => !v), [false, false]);
        expect(h.rtc.localAudioEnabled, isTrue);
        expect(h.permission.requests, 0);
        h.interrupt(
          'ended',
        ); // Duplicate native end never creates a new intent.
        await flushBackgroundWork();
        expect(h.engine.published.where((v) => v), [true, true]);
      },
    );
  }
  for (final denial in [
    'offSeat',
    'offlineOccupancy',
    'forcedMute',
    'selfMute',
    'newOccupancy',
    'newSession',
    'memberInactive',
    'readFailure',
    'permissionDenied',
    'credentialExpired',
  ]) {
    test(
      'fresh recovery rejects $denial without even a transient SDK unmute',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.publish();
        h.interrupt('began');
        await flushBackgroundWork();
        switch (denial) {
          case 'offSeat':
            h.repo.onMic = false;
          case 'offlineOccupancy':
            h.repo.online = false;
          case 'forcedMute':
            h.repo.forcedMuted = true;
          case 'selfMute':
            h.repo.selfMuted = true;
          case 'newOccupancy':
            h.repo.joinedAt = '2026-09-10T00:01:00Z';
          case 'newSession':
            h.repo.sessionId = '00000000-0000-4000-8000-000000000002';
          case 'memberInactive':
            h.repo.memberActive = false;
          case 'readFailure':
            h.repo.readError = StateError('synthetic offline');
          case 'permissionDenied':
            h.permission.granted = false;
          case 'credentialExpired':
            h.now = DateTime.utc(2041);
        }
        h.interrupt('ended');
        await flushBackgroundWork();
        expect(h.engine.published.where((v) => v), [true]);
        expect(h.engine.muted.where((v) => !v), [false]);
        expect(h.rtc.localAudioEnabled, isFalse);
        expect(h.permission.requests, 0);
      },
    );
  }
  for (final boundary in [
    'authority',
    'permission',
    'nativeStart',
    'sdkOptions',
  ]) {
    for (final transition in [
      'accountABA',
      'leave',
      'expiredLease',
      'forcedMute',
    ]) {
      test(
        '$boundary wait rejects $transition before a later SDK unmute',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          await h.publish();
          h.interrupt('began');
          await flushBackgroundWork();
          final authority = Completer<RoomAuthorityProjection>();
          final permission = Completer<PermissionState>();
          final native = Completer<bool>();
          final options = Completer<void>();
          final started = Completer<void>();
          switch (boundary) {
            case 'authority':
              h.repo.pending = authority;
              h.repo.onRead = started.complete;
            case 'permission':
              h.permission.pending = permission;
              h.permission.onRead = started.complete;
            case 'nativeStart':
              h.nativePending = native;
              h.onNativeStart = started.complete;
            case 'sdkOptions':
              h.engine.pendingPublish = options;
          }
          h.interrupt('ended');
          await flushBackgroundWork();
          if (boundary == 'sdkOptions') {
            expect(h.engine.published.where((v) => v), [true, true]);
            // The already-issued options call was legal; its delayed completion
            // must not be followed by an unmute after authority changes.
          } else {
            await started.future.timeout(const Duration(seconds: 2));
            expect(h.engine.published.where((v) => v), [true]);
          }
          final leaving = h.invalidate(transition);
          h.repo.pending = null;
          h.repo.onRead = null;
          h.permission.pending = null;
          h.permission.onRead = null;
          h.nativePending = null;
          h.onNativeStart = null;
          h.engine.pendingPublish = null;
          authority.complete(h.repo.projection());
          permission.complete(PermissionState.granted);
          native.complete(true);
          options.complete();
          if (leaving != null) await leaving;
          await flushBackgroundWork();
          expect(
            h.engine.published.where((v) => v),
            boundary == 'sdkOptions' ? [true, true] : [true],
          );
          expect(h.engine.muted.where((v) => !v), [false]);
          expect(h.rtc.localAudioEnabled, isFalse);
          expect(h.permission.requests, 0);
        },
      );
    }
  }
  test(
    'explicit close during interruption cancels intent and cannot be revived by end',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.publish();
      h.interrupt('began');
      await flushBackgroundWork();
      final oldId = h.nativeId;
      expect(
        h.controller.micMuted,
        isFalse,
      ); // UI retains deliberate switch intent, not live publication.
      expect(await h.controller.toggleMicrophone(), isTrue);
      expect(h.repo.selfMuted, isTrue);
      h.interrupt('ended', id: oldId);
      await flushBackgroundWork();
      expect(h.engine.published.where((v) => v), [true]);
      expect(h.engine.muted.where((v) => !v), [false]);
      expect(h.controller.micMuted, isTrue);
    },
  );
  test(
    'an already-muted listener cannot gain publication from begin or end',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.interrupt('began');
      await flushBackgroundWork();
      h.interrupt('ended');
      await flushBackgroundWork();
      expect(h.engine.published.where((v) => v), isEmpty);
      expect(h.engine.muted.where((v) => !v), isEmpty);
      expect(h.rtc.hasBackgroundAudioLease, isTrue);
    },
  );
  test(
    'old controller recovery cannot publish or mute a replacement owner of the transport',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.publish();
      h.interrupt('began');
      await flushBackgroundWork();
      final pending = Completer<RoomAuthorityProjection>();
      final readStarted = Completer<void>();
      h.repo.pending = pending;
      h.repo.onRead = readStarted.complete;
      h.interrupt('ended');
      await readStarted.future.timeout(const Duration(seconds: 2));
      h.repo.pending = null;
      h.repo.onRead = null;
      final replacement = RoomController(
        roomId: 'unit-room',
        title: 'replacement',
        currentUserId: 42,
        accessToken: 'synthetic-test',
        repository: h.repo,
        rtcAdapter: h.rtc,
        realtimeGateway: h.gateway,
        authoritySyncInterval: const Duration(days: 1),
      );
      try {
        await replacement.join();
        expect(await replacement.toggleMicrophone(), isTrue);
        final publishes = h.engine.published.toList();
        final mutes = h.engine.muted.toList();
        final leaves = h.engine.leaves;
        pending.complete(h.repo.projection());
        await flushBackgroundWork();
        expect(h.engine.published, publishes);
        expect(h.engine.muted, mutes);
        expect(h.engine.leaves, leaves);
        expect(h.rtc.localAudioEnabled, isTrue);
      } finally {
        if (!pending.isCompleted) pending.complete(h.repo.projection());
        replacement.dispose();
      }
    },
  );
  test(
    'a pending first enable is never mistaken for prior publication',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.engine.pendingUnmute = Completer<void>();
      final pending = h.engine.pendingUnmute!;
      h.repo.onMic = true;
      final granting = h.controller.refreshRoomAuthority();
      await flushBackgroundWork();
      expect(h.rtc.localAudioEnabled, isFalse);
      h.interrupt('began');
      await flushBackgroundWork();
      pending.complete();
      await granting;
      h.engine.pendingUnmute = null;
      final enables = h.engine.published.where((v) => v).length;
      h.interrupt('ended');
      await flushBackgroundWork();
      expect(h.engine.published.where((v) => v).length, enables);
      expect(h.rtc.localAudioEnabled, isFalse);
    },
  );
}

class _Harness {
  _Harness() {
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final id = args['sessionId'] as String;
      switch (call.method) {
        case 'start':
          onNativeStart?.call();
          if (nativePending != null) await nativePending!.future;
          nativeId = id;
          active = true;
          return true;
        case 'stop':
          if (id == nativeId) active = false;
          return null;
        case 'isActive':
        case 'renew':
          return active && id == nativeId;
      }
      throw StateError('Unexpected native method');
    });
    rtc = AgoraRtcAdapter(
      engine: engine,
      microphonePermissionAdapter: permission,
      backgroundAudioPort: native,
      now: () => now,
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
  static const channel = MethodChannel('voice_social_app/room_audio');
  static const events = MethodChannel('voice_social_app/room_audio/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final repo = _Repository();
  final permission = _Permission();
  final engine = BackgroundFakeRtcEngine();
  final native = NativeRoomBackgroundAudio();
  final gateway = MockRoomRealtimeGateway();
  final identity = ValueNotifier<int>(42);
  int generation = 0;
  Duration elapsed = Duration.zero;
  DateTime now = DateTime.utc(2026);
  String? nativeId;
  bool active = false;
  Completer<bool>? nativePending;
  VoidCallback? onNativeStart;
  late final AgoraRtcAdapter rtc;
  late final RoomController controller;

  Future<void> publish() async {
    await controller.join();
    repo.onMic = true;
    await controller.refreshRoomAuthority();
    expect(rtc.localAudioEnabled, isTrue);
    expect(engine.published.where((v) => v), [true]);
  }

  void interrupt(String phase, {String? id}) {
    active = false;
    ServicesBinding.instance.channelBuffers.push(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'sessionId': id ?? nativeId,
        'active': false,
        'interruption': phase,
      }),
      (_) {},
    );
  }

  Future<bool>? invalidate(String transition) {
    switch (transition) {
      case 'accountABA':
        generation++;
        identity.value = 99;
        generation++;
        identity.value = 42;
      case 'leave':
        return controller.leaveRoom();
      case 'expiredLease':
        elapsed = const Duration(seconds: 91);
      case 'forcedMute':
        repo.forcedMuted = true;
        gateway.emit(
          const RoomRealtimeEvent(
            code: RoomRealtimeEventCodes.closeMic,
            payload: {},
          ),
        );
    }
    return null;
  }

  Future<void> dispose() async {
    controller.dispose();
    await flushBackgroundWork();
    await rtc.release();
    await native.dispose();
    await gateway.dispose();
    identity.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  }
}

class _Permission extends BackgroundPermission {
  Completer<PermissionState>? pending;
  VoidCallback? onRead;
  @override
  Future<PermissionState> status(PermissionKind kind) async {
    onRead?.call();
    return pending?.future ?? super.status(kind);
  }
}

class _Repository extends MockRoomRepository
    implements RoomAuthorityRepository {
  static const session = '00000000-0000-4000-8000-000000000001';
  bool onMic = false;
  bool online = true;
  bool forcedMuted = false;
  bool selfMuted = false;
  bool memberActive = true;
  String sessionId = session;
  String joinedAt = '2026-09-10T00:00:00Z';
  int reads = 0;
  Completer<RoomAuthorityProjection>? pending;
  Object? readError;
  VoidCallback? onRead;
  RoomSnapshot snapshot() => RoomSnapshot(
    roomId: 'unit-room',
    sessionId: sessionId,
    roomCode: 'test',
    title: 'Room',
    topic: '',
    ownerId: 9,
    role: RoomRole.listener,
    roomLease: RoomSessionLease(
      sessionId: sessionId,
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
        occupantJoinedAt: onMic ? joinedAt : null,
        isOnline: online,
        audioMute: RoomAudioMuteState(
          selfMuted: selfMuted,
          forcedMuted: forcedMuted,
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
  RoomAuthorityProjection projection() => RoomAuthorityProjection(
    snapshot: snapshot(),
    viewerUserId: 42,
    memberActive: memberActive,
    roomMuted: false,
    version: 1,
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
  }) async => snapshot();
  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    reads++;
    onRead?.call();
    if (readError != null) throw readError!;
    return pending?.future ?? projection();
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    selfMuted = muted;
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];
  @override
  Future<void> exitRoom(String roomId) async {}
}
