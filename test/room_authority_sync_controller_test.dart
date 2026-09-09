import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

const _interval = Duration(milliseconds: 30);
final _harnesses = <_Harness>[];

void _roomTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final harness in _harnesses) {
        harness.dispose();
      }
      _harnesses.clear();
      await tester.pump();
    }
  });
}

void main() {
  _roomTest('disposed pending join checks durable identity generation', (
    tester,
  ) async {
    final identity = ValueNotifier<int?>(1);
    var generation = 0;
    final h = _Harness(
      identity: identity,
      identityGeneration: () => generation,
    );
    addTearDown(identity.dispose);
    final pending = Completer<RoomSnapshot>();
    h.repo.nextEnter = pending;
    final joining = h.controller.join();
    h.dispose();
    identity.value = 2;
    generation++;
    identity.value = 1;
    generation++;
    pending.complete(h.repo.state);
    await joining;
    expect(h.repo.writes, 0);
  });
  for (final switchBack in [false, true]) {
    _roomTest(
      'pending join cannot compensate with another identity ABA=$switchBack',
      (tester) async {
        final identity = ValueNotifier<int?>(1);
        final h = _Harness(identity: identity);
        addTearDown(identity.dispose);
        final pending = Completer<RoomSnapshot>();
        h.repo.nextEnter = pending;
        final joining = h.controller.join();
        identity.value = 2;
        if (switchBack) identity.value = 1;
        pending.complete(h.repo.state);
        await joining;
        expect(h.repo.writes, 0);
        expect(h.controller.status, RoomSessionStatus.left);
        expect(h.controller.snapshot, isNull);
      },
    );
  }
  _roomTest(
    'background RTC revocation is not blocked by a pending history read',
    (tester) async {
      final h = _Harness();
      h.repo.state = h.repo.state.copyWith(
        transportMode: RoomTransportMode.interactive,
        role: RoomRole.speaker,
        seats: [_seat(1)],
        rtc: const RtcCredentials(
          solution: RtcSolution.agora,
          token: 'fixture',
          channelId: 'room-1',
          userId: 1,
          role: 'broadcaster',
        ),
      );
      await h.controller.join();
      await h.controller.toggleMicrophone();
      await h.controller.toggleMicrophone();
      expect(h.rtc.audioEnabled, isTrue);
      final slowHistory = Completer<List<RoomMessage>>();
      h.repo.nextHistory = slowHistory;
      final reading = h.controller.refreshRoomAuthority();
      await tester.pump();
      h.controller.setForeground(false);
      h.repo.muted = true;
      try {
        await tester.pump(_interval);
        expect(h.controller.mutedInRoom, isTrue);
        expect(h.rtc.audioEnabled, isFalse);
        final enables = h.rtc.enables;
        h.repo.muted = false;
        await tester.pump(_interval);
        expect(h.controller.mutedInRoom, isFalse);
        expect(h.rtc.enables, enables);
        expect(h.rtc.reconnects, 0);
      } finally {
        slowHistory.complete([]);
        await reading;
      }
    },
  );
  _roomTest(
    'foreground timer updates peer seats, moderation and public history without re-entry',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      h.repo.state = h.repo.state.copyWith(seats: [_seat(2)], onlineCount: 2);
      h.repo.muted = true;
      h.repo.history = [_message('peer-1')];
      await tester.pump(_interval);
      expect(h.controller.seats.single.userId, 2);
      expect(h.controller.snapshot!.onlineCount, 2);
      expect(h.controller.mutedInRoom, isTrue);
      expect(h.controller.canSendPublicMessage, isFalse);
      expect(h.controller.messages.single.messageId, 'peer-1');
      h.repo.muted = false;
      h.repo.state = h.repo.state.copyWith(seats: [_seat(null)]);
      await tester.pump(_interval);
      expect(h.controller.canSendPublicMessage, isTrue);
      expect(h.controller.seats.single.userId, isNull);
      expect(h.repo.enters, 1);
      expect(h.repo.reconnects, 0);
      expect(h.repo.writes, 0);
      expect(h.rtc.reconnects, 0);
    },
  );

  _roomTest('approval queue changes appear without reopening the panel', (
    tester,
  ) async {
    final ops = MockRoomOperationsRepository();
    final h = _Harness(operations: ops);
    h.repo.state = h.repo.state.copyWith(accessMode: 'PUBLIC');
    addTearDown(h.dispose);
    await h.controller.join();
    ops.seedMicRequestForQa(
      MicAccessRequest(
        id: 'request-1',
        roomId: 'room-1',
        member: const RoomMember(
          userId: 2,
          name: 'Peer',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
        seatNumber: 1,
        status: MicRequestStatus.pending,
        createdAt: DateTime.utc(2026),
      ),
    );
    await tester.pump(_interval);
    expect(h.controller.micRequests.single.id, 'request-1');
    expect(h.repo.reconnects, 0);
  });

  _roomTest(
    'mute and seat revocation stop audio; later grant never auto-publishes',
    (tester) async {
      final h = _Harness();
      h.repo.state = h.repo.state.copyWith(
        transportMode: RoomTransportMode.interactive,
        role: RoomRole.speaker,
        seats: [_seat(1)],
        rtc: const RtcCredentials(
          solution: RtcSolution.agora,
          token: 'fixture',
          channelId: 'room-1',
          userId: 1,
          role: 'broadcaster',
        ),
      );
      addTearDown(h.dispose);
      await h.controller.join();
      expect(h.rtc.enables, 0);
      await h.controller.toggleMicrophone(); // Explicit mute.
      await h.controller.toggleMicrophone(); // Explicit unmute.
      expect(h.rtc.audioEnabled, isTrue);
      h.repo.muted = true;
      await tester.pump(_interval);
      expect(h.rtc.audioEnabled, isFalse);
      final enables = h.rtc.enables;
      h.repo.muted = false;
      h.repo.state = h.repo.state.copyWith(
        seats: [_seat(null)],
        role: RoomRole.listener,
      );
      await tester.pump(_interval);
      h.repo.state = h.repo.state.copyWith(
        seats: [_seat(1)],
        role: RoomRole.speaker,
      );
      await tester.pump(_interval);
      expect(h.rtc.enables, enables);
      expect(h.rtc.reconnects, 0);
    },
  );

  _roomTest('busy refresh hints are coalesced instead of lost', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.controller.join();
    final delayed = Completer<RoomAuthorityProjection>();
    h.repo.nextRead = delayed;
    final first = h.controller.refreshRoomAuthority();
    final second = h.controller.refreshRoomAuthority();
    final third = h.controller.refreshRoomAuthority();
    expect(identical(first, second), isTrue);
    final before = h.repo.reads;
    h.repo.state = h.repo.state.copyWith(topic: 'newest');
    delayed.complete(h.repo.projection(topic: 'older'));
    await Future.wait([first, second, third]);
    expect(h.repo.reads, before + 1);
    expect(h.controller.topic, 'newest');
  });

  _roomTest('an earlier GET cannot undo a later local mic write', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.state = h.repo.state.copyWith(role: RoomRole.moderator);
    addTearDown(h.dispose);
    await h.controller.join();
    final old = h.repo.projection();
    final delayed = Completer<RoomAuthorityProjection>();
    h.repo.nextRead = delayed;
    final reading = h.controller.refreshRoomAuthority();
    expect(await h.controller.requestMic(1), isTrue);
    expect(h.controller.isOnMic, isTrue);
    delayed.complete(old);
    await reading;
    expect(h.controller.isOnMic, isTrue);
    expect(h.repo.reconnects, 1); // Only the explicit mic action.
  });

  _roomTest(
    'background invalidates in-flight reads; resume fetches immediately',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      final delayed = Completer<RoomAuthorityProjection>();
      h.repo.nextRead = delayed;
      final reading = h.controller.refreshRoomAuthority();
      h.controller.setForeground(false);
      delayed.complete(h.repo.projection(topic: 'stale-background'));
      await reading;
      final reads = h.repo.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(h.repo.reads, reads);
      expect(h.controller.topic, 'initial');
      h.repo.state = h.repo.state.copyWith(topic: 'foreground');
      h.controller.setForeground(true);
      await tester.pump();
      expect(h.controller.topic, 'foreground');
    },
  );

  _roomTest('A to B to A invalidates the old controller permanently', (
    tester,
  ) async {
    final identity = ValueNotifier<int?>(1);
    final h = _Harness(identity: identity);
    addTearDown(() {
      h.dispose();
      identity.dispose();
    });
    await h.controller.join();
    final delayed = Completer<RoomAuthorityProjection>();
    h.repo.nextRead = delayed;
    final reading = h.controller.refreshRoomAuthority();
    identity.value = 2;
    identity.value = 1;
    delayed.complete(h.repo.projection(topic: 'old-account'));
    await reading;
    expect(h.controller.status, RoomSessionStatus.left);
    expect(h.controller.snapshot, isNull);
    expect(h.controller.messages, isEmpty);
    expect(h.repo.writes, 0);
  });

  for (final reason in ['inactive', 'session-replaced']) {
    _roomTest('$reason ends the local lease without a new server write', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.controller.join();
      if (reason == 'inactive') {
        h.repo.active = false;
      } else {
        h.repo.state = h.repo.state.copyWith(sessionId: 'other-session');
      }
      await tester.pump(_interval);
      expect(h.controller.status, RoomSessionStatus.left);
      expect(h.controller.allows(RoomCapability.requestMic), isFalse);
      expect(h.repo.writes, 0);
      expect(h.repo.reconnects, 0);
    });
  }

  _roomTest('failed reads retain messages and retry automatically', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repo.history = [_message('old')];
    await h.controller.join();
    h.repo.failRead = true;
    h.repo.failHistory = true;
    await tester.pump(_interval);
    expect(h.controller.messages.single.messageId, 'old');
    expect(h.controller.historyErrorKind, isNotNull);
    h.repo.failRead = false;
    h.repo.failHistory = false;
    h.repo.history = [_message('new')];
    await tester.pump(_interval);
    expect(h.controller.messages.single.messageId, 'new');
    expect(h.controller.historyErrorKind, isNull);
    expect(h.controller.realtimeDegraded, isFalse);
  });

  _roomTest('a send completing during a history read is not erased', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.controller.join();
    h.repo.nextHistory = Completer<List<RoomMessage>>();
    final reading = h.controller.refreshRoomAuthority();
    await tester.pump();
    expect(await h.controller.sendPublicMessage('outgoing'), isTrue);
    h.repo.nextHistory!.complete([_message('incoming')]);
    await reading;
    expect(h.controller.messages.map((m) => m.messageId), [
      'incoming',
      'outgoing',
    ]);
    h.repo.nextHistory = null;
  });

  _roomTest('dispose fences in-flight results and cancels the timer', (
    tester,
  ) async {
    final h = _Harness();
    await h.controller.join();
    final delayed = Completer<RoomAuthorityProjection>();
    h.repo.nextRead = delayed;
    final reading = h.controller.refreshRoomAuthority();
    h.dispose();
    final reads = h.repo.reads;
    delayed.complete(h.repo.projection(topic: 'disposed'));
    await reading;
    await tester.pump(const Duration(seconds: 2));
    expect(h.repo.reads, reads);
    expect(h.controller.topic, 'initial');
  });
}

MicSeat _seat(int? userId) => MicSeat(
  number: 1,
  backendIndex: 1,
  state: userId == null ? MicSeatState.available : MicSeatState.occupied,
  userId: userId,
  userName: userId == null ? null : 'User',
);
RoomMessage _message(String id) => RoomMessage(
  roomId: 'room-1',
  messageId: id,
  senderId: 2,
  sender: 'Peer',
  content: id,
);

class _Harness {
  _Harness({
    ValueNotifier<int?>? identity,
    int Function()? identityGeneration,
    MockRoomOperationsRepository? operations,
  }) {
    _harnesses.add(this);
    controller = RoomController(
      roomId: 'room-1',
      title: 'Room',
      currentUserId: 1,
      accessToken: 'fixture',
      repository: repo,
      rtcAdapter: rtc,
      realtimeGateway: realtime,
      roomOperationsRepository: operations,
      allowSyntheticPublicMessages: false,
      authoritySyncInterval: _interval,
      sessionChanges: identity,
      identityGeneration: identityGeneration,
      activeUserId: identity == null ? null : () => identity.value,
    );
  }
  final repo = _Repository();
  final rtc = _Rtc();
  final realtime = MockRoomRealtimeGateway();
  late final RoomController controller;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    unawaited(realtime.dispose());
  }
}

class _Repository extends MockRoomRepository
    implements RoomAuthorityRepository {
  RoomSnapshot state = RoomSnapshot(
    roomId: 'room-1',
    sessionId: 'session-1',
    roomCode: 'room-1',
    title: 'Room',
    topic: 'initial',
    ownerId: 9,
    role: RoomRole.listener,
    seats: [_seat(null)],
    rtc: const RtcCredentials(
      solution: RtcSolution.unknown,
      token: '',
      channelId: 'room-1',
      userId: 1,
    ),
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: true,
    giftBalance: 20,
    accessMode: 'PUBLIC',
    transportMode: RoomTransportMode.snapshotOnly,
  );
  bool active = true, muted = false, failRead = false, failHistory = false;
  int reads = 0, enters = 0, reconnects = 0, writes = 0;
  List<RoomMessage> history = [];
  Completer<RoomAuthorityProjection>? nextRead;
  Completer<RoomSnapshot>? nextEnter;
  Completer<List<RoomMessage>>? nextHistory;
  RoomAuthorityProjection projection({String? topic}) =>
      RoomAuthorityProjection(
        snapshot: state.copyWith(topic: topic),
        viewerUserId: 1,
        memberActive: active,
        roomMuted: muted,
        version: 1,
      );
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    enters++;
    if (nextEnter != null) return nextEnter!.future;
    return state;
  }

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    reads++;
    final pending = nextRead;
    nextRead = null;
    if (pending != null) return pending.future;
    if (failRead)
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'offline',
      );
    return projection();
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async {
    if (nextHistory != null) return nextHistory!.future;
    if (failHistory)
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'offline',
      );
    return history;
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    reconnects++;
    return state;
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    writes++;
    state = state.copyWith(seats: [_seat(1)]);
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    writes++;
    state = state.copyWith(
      seats: [
        state.seats.single.copyWith(
          state: muted ? MicSeatState.occupiedMuted : MicSeatState.occupied,
        ),
      ],
    );
  }

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    writes++;
    return _message('outgoing');
  }

  @override
  Future<void> exitRoom(String roomId) async {
    writes++;
  }
}

class _Rtc extends MockRtcAdapter {
  int enables = 0, reconnects = 0;
  @override
  Future<void> setLocalAudioEnabled(bool enabled) {
    if (enabled) enables++;
    return super.setLocalAudioEnabled(enabled);
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) {
    reconnects++;
    return super.reconnect(credentials);
  }
}
