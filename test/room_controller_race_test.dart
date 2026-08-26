import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  test('a late requestMic cannot restore the session after leave', () async {
    final _RaceRepository repository = _RaceRepository();
    final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
    final RoomController controller = _controller(repository, realtime);
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    await controller.join();
    final Future<bool> request = controller.requestMic(4);
    await repository.requestMicStarted.future;

    final Future<bool> leave = controller.leaveRoom();
    repository.requestMicGate.complete();
    repository.reconnectGate.complete(_snapshot(occupiedOwnSeat: true));

    expect(await request, isFalse);
    expect(await leave, isTrue);
    expect(controller.status, RoomSessionStatus.left);
    expect(
      controller.messages,
      isNot(
        contains(
          predicate<RoomMessage>(
            (RoomMessage message) => message.content == '你已上 4 号麦。',
          ),
        ),
      ),
    );
  });

  test(
    'stale join compensation does not leave a newer session transport',
    () async {
      final _StaleJoinRepository repository = _StaleJoinRepository();
      final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
      final _TrackingRtcAdapter rtc = _TrackingRtcAdapter();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'token',
        repository: repository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      final Future<void> firstJoin = controller.join();
      await repository.firstEnterStarted.future;
      expect(await controller.leaveRoom(), isTrue);
      repository.firstEnterGate.complete(_snapshot(occupiedOwnSeat: false));
      await firstJoin;

      await controller.join();
      expect(controller.status, RoomSessionStatus.joined);
      expect(rtc.leaveCount, 0);
      expect(rtc.joined, isTrue);
    },
  );

  test('late public history cannot write after the room is left', () async {
    final _RaceRepository repository = _RaceRepository()
      ..holdPublicMessages = true;
    final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
    final RoomController controller = _controller(repository, realtime);
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    final Future<void> join = controller.join();
    await repository.publicMessagesStarted.future;
    expect(await controller.leaveRoom(), isTrue);
    repository.publicMessagesGate.complete(<RoomMessage>[
      const RoomMessage(
        messageId: 'late-message',
        sender: '晚星',
        content: '不应写入已离开的房间',
      ),
    ]);
    await join;

    expect(controller.status, RoomSessionStatus.left);
    expect(
      controller.messages,
      isNot(
        contains(
          predicate<RoomMessage>(
            (RoomMessage message) => message.messageId == 'late-message',
          ),
        ),
      ),
    );
  });

  test(
    'late microphone, chat and gift completions do not write after dispose',
    () async {
      final _RaceRepository repository = _RaceRepository();
      final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
      final RoomController controller = _controller(
        repository,
        realtime,
        occupiedOwnSeat: true,
      );
      addTearDown(realtime.dispose);

      await controller.join();

      final Future<bool> microphone = controller.toggleMicrophone();
      await repository.muteStarted.future;
      controller.dispose();
      repository.muteGate.complete();
      expect(await microphone, isFalse);
      expect(controller.micMuted, isFalse);

      final _RaceRepository chatRepository = _RaceRepository();
      final _RaceRealtimeGateway chatRealtime = _RaceRealtimeGateway();
      final RoomController chatController = _controller(
        chatRepository,
        chatRealtime,
      );
      addTearDown(() async {
        chatController.dispose();
        await chatRealtime.dispose();
      });
      await chatController.join();
      final Future<bool> chat = chatController.sendPublicMessage('迟到的消息');
      await chatRepository.chatStarted.future;
      chatController.dispose();
      chatRepository.chatGate.complete();
      expect(await chat, isFalse);
      expect(
        chatController.messages,
        isNot(
          contains(
            predicate<RoomMessage>(
              (RoomMessage message) => message.content == '迟到的消息',
            ),
          ),
        ),
      );

      final _RaceRepository giftRepository = _RaceRepository();
      final _RaceRealtimeGateway giftRealtime = _RaceRealtimeGateway();
      final RoomController giftController = _controller(
        giftRepository,
        giftRealtime,
      );
      addTearDown(() async {
        giftController.dispose();
        await giftRealtime.dispose();
      });
      await giftController.join();
      final Future<bool> gift = giftController.sendGift(
        giftId: 'gift-rose-uuid',
        giftName: '玫瑰',
        receiverUserId: 20001,
        targetName: '房主',
        quantity: 1,
      );
      await giftRepository.giftStarted.future;
      giftController.dispose();
      giftRepository.giftGate.complete(
        const GiftReceipt(success: true, remainingBalance: 1190),
      );
      expect(await gift, isFalse);
      expect(giftController.giftBalance, 1200);
    },
  );

  test('a late leaveMic refresh cannot write after leaving the room', () async {
    final _RaceRepository repository = _RaceRepository();
    final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
    final RoomController controller = _controller(
      repository,
      realtime,
      occupiedOwnSeat: true,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    await controller.join();
    final Future<bool> leaveMic = controller.leaveMic();
    await repository.reconnectStarted.future;
    final Future<bool> leaveRoom = controller.leaveRoom();
    repository.reconnectGate.complete(_snapshot(occupiedOwnSeat: false));

    expect(await leaveMic, isFalse);
    expect(await leaveRoom, isTrue);
    expect(controller.status, RoomSessionStatus.left);
    expect(
      controller.messages,
      isNot(
        contains(
          predicate<RoomMessage>(
            (RoomMessage message) => message.content == '你已离开麦位。',
          ),
        ),
      ),
    );
  });

  test(
    'late reconnect and realtime refresh cannot restore terminal status',
    () async {
      final _RaceRepository repository = _RaceRepository();
      final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
      final RoomController controller = _controller(repository, realtime);
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      final Future<void> reconnect = controller.reconnect();
      await repository.reconnectStarted.future;
      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.kickedOut,
          payload: <String, Object?>{},
        ),
      );
      repository.reconnectGate.complete(_snapshot(occupiedOwnSeat: false));
      await reconnect;
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, RoomSessionStatus.kicked);
      expect(
        controller.messages,
        isNot(
          contains(
            predicate<RoomMessage>(
              (RoomMessage message) =>
                  message.content == '已恢复连接。断线期间公屏消息可能未显示。',
            ),
          ),
        ),
      );

      final _RaceRepository refreshRepository = _RaceRepository();
      final _RaceRealtimeGateway refreshRealtime = _RaceRealtimeGateway();
      final RoomController refreshController = _controller(
        refreshRepository,
        refreshRealtime,
      );
      addTearDown(() async {
        refreshController.dispose();
        await refreshRealtime.dispose();
      });
      await refreshController.join();
      refreshRealtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.micInfo,
          payload: <String, Object?>{},
        ),
      );
      await refreshRepository.reconnectStarted.future;
      refreshRealtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.roomBanned,
          payload: <String, Object?>{},
        ),
      );
      refreshRepository.reconnectGate.complete(
        _snapshot(occupiedOwnSeat: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(refreshController.status, RoomSessionStatus.closed);
      expect(refreshController.isOnMic, isFalse);
    },
  );

  test('leaveRoom failure restores the prior terminal status', () async {
    final _FailingExitRepository repository = _FailingExitRepository();
    final _RaceRealtimeGateway realtime = _RaceRealtimeGateway();
    final RoomController controller = _controller(repository, realtime);
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    await controller.join();
    realtime.emit(
      const RoomRealtimeEvent(
        code: RoomRealtimeEventCodes.kickedOut,
        payload: <String, Object?>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, RoomSessionStatus.kicked);
    expect(await controller.leaveRoom(), isFalse);
    expect(controller.status, RoomSessionStatus.kicked);
  });

  test(
    'terminal cleanup cannot disconnect a newer session on shared transports',
    () async {
      final _RaceRepository firstRepository = _RaceRepository();
      final _RaceRepository secondRepository = _RaceRepository();
      final _SharedTrackingRealtimeGateway realtime =
          _SharedTrackingRealtimeGateway();
      final _SharedTrackingRtcAdapter rtc = _SharedTrackingRtcAdapter();
      final RoomController firstController = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'token',
        repository: firstRepository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      final RoomController secondController = RoomController(
        roomId: '520906',
        title: '电台夜聊',
        currentUserId: 10002,
        accessToken: 'token-2',
        repository: secondRepository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        secondController.dispose();
        firstController.dispose();
        await realtime.dispose();
      });

      await firstController.join();
      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.kickedOut,
          payload: <String, Object?>{},
        ),
      );
      await secondController.join();
      await Future<void>.delayed(Duration.zero);

      expect(firstController.status, RoomSessionStatus.kicked);
      expect(secondController.status, RoomSessionStatus.joined);
      expect(rtc.joined, isTrue);
      expect(realtime.connected, isTrue);
    },
  );

  test(
    'queued dispose cleanup cannot leave a shared adapter reclaimed by a new controller',
    () async {
      final _RaceRepository firstRepository = _RaceRepository()
        ..seedSnapshot(occupiedOwnSeat: true);
      final _RaceRepository secondRepository = _RaceRepository();
      final _RaceRealtimeGateway firstRealtime = _RaceRealtimeGateway();
      final _RaceRealtimeGateway secondRealtime = _RaceRealtimeGateway();
      final _LeaseHandoffRtcAdapter rtc = _LeaseHandoffRtcAdapter();
      final RoomController firstController = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'token',
        repository: firstRepository,
        rtcAdapter: rtc,
        realtimeGateway: firstRealtime,
      );
      final RoomController secondController = RoomController(
        roomId: '520906',
        title: '电台夜聊',
        currentUserId: 10002,
        accessToken: 'token-2',
        repository: secondRepository,
        rtcAdapter: rtc,
        realtimeGateway: secondRealtime,
      );
      addTearDown(() async {
        secondController.dispose();
        firstController.dispose();
        await Future<void>.delayed(Duration.zero);
        await firstRealtime.dispose();
        await secondRealtime.dispose();
      });

      await firstController.join();
      final Future<bool> firstToggle = firstController.toggleMicrophone();
      await firstRepository.muteStarted.future;
      firstRepository.muteGate.complete();
      await rtc.audioStarted.future;

      // dispose queues leave behind the blocked microphone operation while
      // retaining the old lease. The second join is allowed to claim it.
      firstController.dispose();
      await secondController.join();
      expect(secondController.status, RoomSessionStatus.joined);
      expect(rtc.joinCount, 2);
      expect(rtc.joined, isTrue);
      expect(rtc.joinedChannelId, '880217');

      rtc.audioGate.complete();
      expect(await firstToggle, isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(rtc.leaveCount, 0);
      expect(rtc.joined, isTrue);
      expect(secondController.status, RoomSessionStatus.joined);
    },
  );

  test('join failure after rtc join cleans up the claimed transport', () async {
    final _RaceRepository repository = _RaceRepository();
    final _EventsThrowingRealtimeGateway realtime =
        _EventsThrowingRealtimeGateway();
    final _SharedTrackingRtcAdapter rtc = _SharedTrackingRtcAdapter();
    final RoomController controller = RoomController(
      roomId: '880217',
      title: '深夜温柔陪伴',
      currentUserId: 10001,
      accessToken: 'token',
      repository: repository,
      rtcAdapter: rtc,
      realtimeGateway: realtime,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    await controller.join();

    expect(controller.status, RoomSessionStatus.failed);
    expect(rtc.joined, isFalse);
    expect(realtime.disconnectCount, 1);
  });

  test(
    'failed join cleanup cannot disconnect a newer session that reclaims the transport',
    () async {
      final _StaleFailingJoinRepository firstRepository =
          _StaleFailingJoinRepository();
      final _RaceRepository secondRepository = _RaceRepository();
      final _DelayedThrowingJoinRtcAdapter rtc =
          _DelayedThrowingJoinRtcAdapter();
      final _SharedTrackingRealtimeGateway realtime =
          _SharedTrackingRealtimeGateway();
      final RoomController firstController = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'token',
        repository: firstRepository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      final RoomController secondController = RoomController(
        roomId: '520906',
        title: '电台夜聊',
        currentUserId: 10002,
        accessToken: 'token-2',
        repository: secondRepository,
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        secondController.dispose();
        firstController.dispose();
        await realtime.dispose();
      });

      final Future<void> firstJoin = firstController.join();
      await rtc.firstJoinStarted.future;
      await secondController.join();
      rtc.failFirstJoin();
      await firstJoin;

      expect(firstController.status, RoomSessionStatus.failed);
      expect(secondController.status, RoomSessionStatus.joined);
      expect(rtc.joined, isTrue);
      expect(realtime.connected, isTrue);
    },
  );
}

RoomController _controller(
  _RaceRepository repository,
  _RaceRealtimeGateway realtime, {
  bool occupiedOwnSeat = false,
}) {
  repository.seedSnapshot(occupiedOwnSeat: occupiedOwnSeat);
  return RoomController(
    roomId: '880217',
    title: '深夜温柔陪伴',
    currentUserId: 10001,
    accessToken: 'token',
    repository: repository,
    rtcAdapter: _RaceRtcAdapter(),
    realtimeGateway: realtime,
  );
}

RoomSnapshot _snapshot({required bool occupiedOwnSeat}) {
  return RoomSnapshot(
    roomId: '880217',
    roomCode: '880217',
    title: '深夜温柔陪伴',
    topic: '话题',
    ownerId: 20001,
    role: occupiedOwnSeat ? RoomRole.speaker : RoomRole.listener,
    seats: <MicSeat>[
      const MicSeat(
        number: 1,
        backendIndex: 1,
        state: MicSeatState.occupied,
        userId: 20001,
        userName: '房主',
      ),
      MicSeat(
        number: 4,
        backendIndex: 4,
        state: occupiedOwnSeat ? MicSeatState.occupied : MicSeatState.available,
        userId: occupiedOwnSeat ? 10001 : null,
        userName: occupiedOwnSeat ? '我' : null,
        userRole: occupiedOwnSeat ? RoomRole.speaker : RoomRole.listener,
      ),
    ],
    rtc: const RtcCredentials(
      solution: RtcSolution.agora,
      token: 'rtc-token',
      channelId: '880217',
      userId: 10001,
    ),
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: true,
    giftBalance: 1200,
  );
}

class _RaceRepository implements RoomRepository {
  _RaceRepository() : _entrySnapshot = _snapshot(occupiedOwnSeat: false);

  RoomSnapshot _entrySnapshot;
  final Completer<void> requestMicStarted = Completer<void>();
  final Completer<void> requestMicGate = Completer<void>();
  final Completer<void> muteStarted = Completer<void>();
  final Completer<void> muteGate = Completer<void>();
  final Completer<void> chatStarted = Completer<void>();
  final Completer<void> chatGate = Completer<void>();
  final Completer<void> giftStarted = Completer<void>();
  final Completer<GiftReceipt> giftGate = Completer<GiftReceipt>();
  final Completer<void> publicMessagesStarted = Completer<void>();
  final Completer<List<RoomMessage>> publicMessagesGate =
      Completer<List<RoomMessage>>();
  bool holdPublicMessages = false;
  final Completer<void> reconnectStarted = Completer<void>();
  final Completer<RoomSnapshot> reconnectGate = Completer<RoomSnapshot>();

  void seedSnapshot({required bool occupiedOwnSeat}) {
    _entrySnapshot = _snapshot(occupiedOwnSeat: occupiedOwnSeat);
  }

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => _entrySnapshot;

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) {
    if (!reconnectStarted.isCompleted) {
      reconnectStarted.complete();
      return reconnectGate.future;
    }
    return Future<RoomSnapshot>.value(_entrySnapshot);
  }

  @override
  Future<void> exitRoom(String roomId) async {}

  @override
  Future<void> requestMic(int backendMicIndex) async {
    if (!requestMicStarted.isCompleted) {
      requestMicStarted.complete();
      await requestMicGate.future;
    }
  }

  @override
  Future<void> leaveMic() async {}

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    if (!muteStarted.isCompleted) {
      muteStarted.complete();
      await muteGate.future;
    }
  }

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    if (!chatStarted.isCompleted) {
      chatStarted.complete();
      await chatGate.future;
    }
    return RoomMessage(
      roomId: '880217',
      messageId: 'race-chat-1',
      senderId: 10001,
      sender: '我',
      content: '迟到的消息',
      createdAt: DateTime.utc(2026, 8, 22),
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) {
    if (!holdPublicMessages) {
      return Future<List<RoomMessage>>.value(const <RoomMessage>[]);
    }
    if (!publicMessagesStarted.isCompleted) {
      publicMessagesStarted.complete();
    }
    return publicMessagesGate.future;
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) {
    if (!giftStarted.isCompleted) {
      giftStarted.complete();
      return giftGate.future;
    }
    return Future<GiftReceipt>.value(
      const GiftReceipt(success: true, remainingBalance: 1200),
    );
  }
}

class _RaceRealtimeGateway implements RoomRealtimeGateway {
  final StreamController<RoomRealtimeEvent> _events =
      StreamController<RoomRealtimeEvent>.broadcast(sync: true);

  bool _connected = false;

  @override
  Stream<RoomRealtimeEvent> get events => _events.stream;

  @override
  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  }) async {
    _connected = true;
  }

  @override
  Future<void> reconnect() async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  void emit(RoomRealtimeEvent event) {
    if (_connected && !_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> dispose() => _events.close();
}

class _RaceRtcAdapter implements RtcAdapter {
  bool _joined = false;

  @override
  Future<void> join(RtcCredentials credentials) async {
    _joined = true;
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) async {
    _joined = true;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (enabled && !_joined) {
      return;
    }
  }

  @override
  Future<void> leave() async {
    _joined = false;
  }
}

class _StaleJoinRepository implements RoomRepository {
  final Completer<void> firstEnterStarted = Completer<void>();
  final Completer<RoomSnapshot> firstEnterGate = Completer<RoomSnapshot>();
  int _enterCount = 0;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) {
    _enterCount += 1;
    if (_enterCount == 1) {
      firstEnterStarted.complete();
      return firstEnterGate.future;
    }
    return Future<RoomSnapshot>.value(_snapshot(occupiedOwnSeat: false));
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async => _snapshot(occupiedOwnSeat: false);

  @override
  Future<void> exitRoom(String roomId) async {}

  @override
  Future<void> requestMic(int backendMicIndex) async {}

  @override
  Future<void> leaveMic() async {}

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {}

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async => RoomMessage(
    roomId: '880217',
    messageId: 'stale-chat-1',
    senderId: 10001,
    sender: '我',
    content: 'stale',
    createdAt: DateTime.utc(2026, 8, 22),
    deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
    realtimeStatus: 'VENDOR_BLOCKED',
  );

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async =>
      const <RoomMessage>[];

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async => const GiftReceipt(success: true, remainingBalance: 1200);
}

class _FailingExitRepository extends _RaceRepository {
  @override
  Future<void> exitRoom(String roomId) async {
    throw StateError('exit failed');
  }
}

class _StaleFailingJoinRepository extends _RaceRepository {}

class _TrackingRtcAdapter implements RtcAdapter {
  bool joined = false;
  int leaveCount = 0;

  @override
  Future<void> join(RtcCredentials credentials) async {
    joined = true;
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) async {
    joined = true;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {
    leaveCount += 1;
    joined = false;
  }
}

class _SharedTrackingRtcAdapter implements RtcAdapter {
  bool joined = false;

  @override
  Future<void> join(RtcCredentials credentials) async {
    joined = true;
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) async {
    joined = true;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {
    joined = false;
  }
}

class _LeaseHandoffRtcAdapter implements RtcAdapter {
  final Completer<void> audioStarted = Completer<void>();
  final Completer<void> audioGate = Completer<void>();
  final List<bool> audioStates = <bool>[];
  bool joined = false;
  int joinCount = 0;
  int leaveCount = 0;
  String? joinedChannelId;
  bool _blockFirstAudioOperation = true;

  @override
  Future<void> join(RtcCredentials credentials) async {
    joinCount += 1;
    joined = true;
    joinedChannelId = credentials.channelId;
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) async {
    joined = true;
    joinedChannelId = credentials.channelId;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    audioStates.add(enabled);
    if (!audioStarted.isCompleted) {
      audioStarted.complete();
    }
    if (_blockFirstAudioOperation) {
      _blockFirstAudioOperation = false;
      await audioGate.future;
    }
  }

  @override
  Future<void> leave() async {
    leaveCount += 1;
    joined = false;
    joinedChannelId = null;
  }
}

class _DelayedThrowingJoinRtcAdapter implements RtcAdapter {
  final Completer<void> firstJoinStarted = Completer<void>();
  final Completer<void> _firstJoinGate = Completer<void>();
  bool joined = false;
  int _joinCount = 0;

  void failFirstJoin() {
    if (!_firstJoinGate.isCompleted) {
      _firstJoinGate.complete();
    }
  }

  @override
  Future<void> join(RtcCredentials credentials) async {
    _joinCount += 1;
    if (_joinCount == 1) {
      joined = true;
      if (!firstJoinStarted.isCompleted) {
        firstJoinStarted.complete();
      }
      await _firstJoinGate.future;
      throw StateError('join failed after claim');
    }
    joined = true;
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) async {
    joined = true;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> leave() async {
    joined = false;
  }
}

class _SharedTrackingRealtimeGateway implements RoomRealtimeGateway {
  final StreamController<RoomRealtimeEvent> _events =
      StreamController<RoomRealtimeEvent>.broadcast(sync: true);

  bool connected = false;
  int disconnectCount = 0;

  @override
  Stream<RoomRealtimeEvent> get events => _events.stream;

  @override
  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  }) async {
    connected = true;
  }

  @override
  Future<void> reconnect() async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    connected = false;
  }

  void emit(RoomRealtimeEvent event) {
    if (connected && !_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> dispose() => _events.close();
}

class _EventsThrowingRealtimeGateway extends _SharedTrackingRealtimeGateway {
  @override
  Stream<RoomRealtimeEvent> get events =>
      throw StateError('events unavailable');
}
