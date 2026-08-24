import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  test(
    'room controller keeps eight seats and supports the core flow',
    () async {
      final MockRtcAdapter rtc = MockRtcAdapter();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: MockRoomRepository(),
        rtcAdapter: rtc,
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      expect(controller.seats, hasLength(8));
      expect(controller.status, RoomSessionStatus.idle);

      await controller.join();
      expect(controller.status, RoomSessionStatus.joined);
      expect(controller.seats, hasLength(8));
      expect(controller.role, RoomRole.listener);
      expect(rtc.joined, isTrue);

      final bool joinedMic = await controller.requestMic(4);
      expect(joinedMic, isTrue);
      expect(controller.role, RoomRole.speaker);
      expect(
        controller.seats
            .singleWhere((MicSeat seat) => seat.number == 4)
            .userName,
        '我',
      );

      final bool muted = await controller.toggleMicrophone();
      expect(muted, isTrue);
      expect(controller.micMuted, isTrue);

      final int balanceBefore = controller.giftBalance!;
      final bool sent = await controller.sendGift(
        giftId: '101',
        giftName: '玫瑰',
        receiverUserId: 20001,
        targetName: '房主 · 鹿屿',
        quantity: 1,
      );
      expect(sent, isTrue);
      expect(controller.giftBalance, balanceBefore - 10);

      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.publicChat,
          payload: <String, Object?>{
            'userId': 20003,
            'nickname': '晚星',
            'message': '欢迎来到房间',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.messages.last.content, '欢迎来到房间');

      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.mutedInRoom,
          payload: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.mutedInRoom, isTrue);
      expect(controller.canSendPublicMessage, isFalse);
      expect(await controller.sendPublicMessage('这条不应发送'), isFalse);

      realtime.emit(
        const RoomRealtimeEvent(
          code: RoomRealtimeEventCodes.unmutedInRoom,
          payload: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.canSendPublicMessage, isTrue);

      final int messageCount = controller.messages.length;
      realtime.emit(
        const RoomRealtimeEvent(code: 999999, payload: <String, Object?>{}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.messages, hasLength(messageCount));

      await controller.reconnect();
      expect(controller.status, RoomSessionStatus.joined);
      expect(controller.messages.last.content, '已恢复连接。断线期间公屏消息可能未显示。');

      final bool left = await controller.leaveRoom();
      expect(left, isTrue);
      expect(controller.status, RoomSessionStatus.left);
      expect(rtc.joined, isFalse);
    },
  );

  test(
    'room join hydrates persisted public history in chronological order',
    () async {
      final _HistoryRoomRepository repository = _HistoryRoomRepository(
        history: <RoomMessage>[
          const RoomMessage(
            messageId: 'message-1',
            senderId: 10001,
            sender: '晚星',
            type: 'TEXT',
            content: '先发的消息',
          ),
          const RoomMessage(
            messageId: 'message-2',
            senderId: 10002,
            sender: '南风',
            type: 'TEXT',
            content: '后发的消息',
          ),
        ],
      );
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();

      expect(controller.status, RoomSessionStatus.joined);
      expect(
        controller.messages.map((RoomMessage message) => message.messageId),
        <String?>['message-1', 'message-2'],
      );
    },
  );

  test(
    'gift receipt recovery uses the retained request id without a second send',
    () async {
      final _ReceiptRecoveryRoomRepository repository =
          _ReceiptRecoveryRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
        requestIdGenerator: (String prefix) => '$prefix-recovery-1',
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(
        await controller.sendGift(
          giftId: '101',
          giftName: '玫瑰',
          receiverUserId: 20001,
          targetName: '房主 · 鹿屿',
          quantity: 1,
        ),
        isFalse,
      );

      final GiftReceipt? recovered = await controller.fetchGiftReceipt();
      expect(recovered?.success, isTrue);
      expect(repository.sendCalls, 1);
      expect(repository.receiptRequestIds, <String?>['room-gift-recovery-1']);
      expect(repository.receiptParticipants, <int?>[10001]);
      expect(controller.giftBalance, 1189);
    },
  );

  test(
    'public history failure keeps the room joined with a classified degraded error',
    () async {
      final _HistoryRoomRepository repository = _HistoryRoomRepository(
        failure: StateError('history unavailable'),
      );
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();

      expect(controller.status, RoomSessionStatus.joined);
      expect(controller.historyErrorKind, ApiFailureKind.protocol);
      expect(controller.historyErrorMessage, '公屏历史暂时不可用');
      expect(
        controller.messages,
        isNot(
          contains(
            predicate<RoomMessage>(
              (RoomMessage message) =>
                  message.content == '公屏历史暂时不可用，当前仅显示本地提示；实时同步尚未配置。',
            ),
          ),
        ),
      );
    },
  );

  test(
    'controller only appends authoritative chat/gift history and reuses retry ids',
    () async {
      final _AuthorityRoomRepository repository = _AuthorityRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      final int beforeChat = controller.messages.length;
      expect(await controller.sendPublicMessage('服务端聊天'), isTrue);
      expect(controller.messages.length, beforeChat + 1);
      expect(controller.messages.last.messageId, 'server-chat-1');
      expect(controller.messages.last.createdAt, isNotNull);
      expect(repository.chatRequestIds, hasLength(1));

      final bool sentGift = await controller.sendGift(
        giftId: '101',
        giftName: '玫瑰',
        receiverUserId: 20001,
        targetName: '房主',
        quantity: 1,
      );
      expect(sentGift, isTrue);
      expect(
        controller.messages.where(
          (RoomMessage message) => message.content.contains('我送给'),
        ),
        isEmpty,
      );
      expect(repository.giftRequestIds, hasLength(1));
    },
  );

  test('timeout retries reuse the same request id for chat and gift', () async {
    final _RetryAuthorityRoomRepository repository =
        _RetryAuthorityRoomRepository();
    final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
    final RoomController controller = RoomController(
      roomId: '880217',
      title: '深夜温柔陪伴',
      currentUserId: 10001,
      accessToken: 'mock-access-token',
      repository: repository,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: realtime,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    await controller.join();
    expect(await controller.sendPublicMessage('重试聊天'), isFalse);
    expect(await controller.sendPublicMessage('重试聊天'), isTrue);
    expect(repository.chatRequestIds, hasLength(2));
    expect(repository.chatRequestIds[0], repository.chatRequestIds[1]);

    expect(
      await controller.sendGift(
        giftId: '101',
        giftName: '玫瑰',
        receiverUserId: 20001,
        targetName: '房主',
        quantity: 1,
      ),
      isFalse,
    );
    expect(
      await controller.sendGift(
        giftId: '101',
        giftName: '玫瑰',
        receiverUserId: 20001,
        targetName: '房主',
        quantity: 1,
      ),
      isTrue,
    );
    expect(repository.giftRequestIds, hasLength(2));
    expect(repository.giftRequestIds[0], repository.giftRequestIds[1]);
  });

  test(
    'ambiguous protocol/server failures reuse ids while definitive failures rotate ids',
    () async {
      final _RetryClassificationRoomRepository repository =
          _RetryClassificationRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      int idSequence = 0;
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
        requestIdGenerator: (String prefix) {
          idSequence += 1;
          return '$prefix-test-$idSequence';
        },
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(await controller.sendPublicMessage('协议重试'), isFalse);
      expect(await controller.sendPublicMessage('协议重试'), isTrue);
      expect(repository.chatRequestIds[0], repository.chatRequestIds[1]);

      expect(
        await controller.sendGift(
          giftId: '101',
          giftName: '玫瑰',
          receiverUserId: 20001,
          targetName: '房主',
          quantity: 1,
        ),
        isFalse,
      );
      expect(
        await controller.sendGift(
          giftId: '101',
          giftName: '玫瑰',
          receiverUserId: 20001,
          targetName: '房主',
          quantity: 1,
        ),
        isTrue,
      );
      expect(repository.giftRequestIds[0], repository.giftRequestIds[1]);

      expect(await controller.sendPublicMessage('明确失败后新操作'), isFalse);
      expect(await controller.sendPublicMessage('明确失败后新操作'), isTrue);
      expect(repository.chatRequestIds[2], isNot(repository.chatRequestIds[1]));
    },
  );

  test(
    'idempotency pending conflicts reuse chat and gift request ids',
    () async {
      final _IdempotencyPendingRoomRepository repository =
          _IdempotencyPendingRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      expect(await controller.sendPublicMessage('处理中消息'), isFalse);
      expect(await controller.sendPublicMessage('处理中消息'), isTrue);
      expect(repository.chatRequestIds, hasLength(2));
      expect(repository.chatRequestIds[0], repository.chatRequestIds[1]);

      expect(
        await controller.sendGift(
          giftId: '101',
          giftName: '玫瑰',
          receiverUserId: 20001,
          targetName: '房主',
          quantity: 1,
        ),
        isFalse,
      );
      expect(
        await controller.sendGift(
          giftId: '101',
          giftName: '玫瑰',
          receiverUserId: 20001,
          targetName: '房主',
          quantity: 1,
        ),
        isTrue,
      );
      expect(repository.giftRequestIds, hasLength(2));
      expect(repository.giftRequestIds[0], repository.giftRequestIds[1]);
    },
  );

  test(
    'public messages coalesce identical intent and serialize different content',
    () async {
      final _ConcurrentChatRoomRepository repository =
          _ConcurrentChatRoomRepository();
      final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
      final RoomController controller = RoomController(
        roomId: '880217',
        title: '深夜温柔陪伴',
        currentUserId: 10001,
        accessToken: 'mock-access-token',
        repository: repository,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: realtime,
      );
      addTearDown(() async {
        controller.dispose();
        await realtime.dispose();
      });

      await controller.join();
      final Future<bool> first = controller.sendPublicMessage('第一条');
      await repository.firstStarted.future;
      final Future<bool> duplicate = controller.sendPublicMessage('第一条');
      final Future<bool> second = controller.sendPublicMessage('第二条');

      await Future<void>.delayed(Duration.zero);
      expect(repository.contents, <String>['第一条']);

      repository.firstGate.complete();
      expect(
        await Future.wait(<Future<bool>>[first, duplicate, second]),
        <bool>[true, true, true],
      );
      expect(repository.contents, <String>['第一条', '第二条']);
      expect(repository.maximumConcurrentCalls, 1);
      expect(repository.requestIds, hasLength(2));
      expect(repository.requestIds[0], isNot(repository.requestIds[1]));
    },
  );
}

class _HistoryRoomRepository extends MockRoomRepository {
  _HistoryRoomRepository({this.history = const <RoomMessage>[], this.failure});

  final List<RoomMessage> history;
  final Object? failure;

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async {
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    return history;
  }
}

class _AuthorityRoomRepository extends MockRoomRepository {
  final List<String?> chatRequestIds = <String?>[];
  final List<String?> giftRequestIds = <String?>[];

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    chatRequestIds.add(requestId);
    return RoomMessage(
      messageId: 'server-chat-1',
      roomId: '880217',
      senderId: 10001,
      sender: '我',
      content: '服务端聊天',
      createdAt: DateTime(2026, 8, 22, 12),
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    giftRequestIds.add(requestId);
    return const GiftReceipt(
      success: true,
      remainingBalance: 1190,
      transferId: 'transfer-1',
      roomId: '880217',
      senderUserId: 10001,
      receiverUserId: 20001,
      giftId: '101',
      giftName: '玫瑰',
      quantity: 1,
      source: 'WALLET',
      deliveryMode: 'FIRST_PARTY_LEDGER_COMMITTED',
      providerInvocation: false,
      status: 'SUCCEEDED',
    );
  }
}

class _RetryAuthorityRoomRepository extends MockRoomRepository {
  final List<String?> chatRequestIds = <String?>[];
  final List<String?> giftRequestIds = <String?>[];
  int _chatAttempts = 0;
  int _giftAttempts = 0;

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    chatRequestIds.add(requestId);
    _chatAttempts += 1;
    if (_chatAttempts == 1) {
      throw const ApiException(kind: ApiFailureKind.timeout, message: '请求超时');
    }
    return RoomMessage(
      roomId: roomId,
      messageId: 'retry-chat-1',
      senderId: 10001,
      sender: '我',
      content: content,
      createdAt: DateTime.utc(2026, 8, 22),
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    giftRequestIds.add(requestId);
    _giftAttempts += 1;
    if (_giftAttempts == 1) {
      throw const ApiException(kind: ApiFailureKind.timeout, message: '请求超时');
    }
    return const GiftReceipt(
      success: true,
      remainingBalance: 1190,
      transferId: 'retry-transfer-1',
      roomId: '880217',
      senderUserId: 10001,
      receiverUserId: 20001,
      giftId: '101',
      giftName: '玫瑰',
      quantity: 1,
      source: 'WALLET',
      deliveryMode: 'FIRST_PARTY_LEDGER_COMMITTED',
      providerInvocation: false,
      status: 'SUCCEEDED',
    );
  }
}

class _RetryClassificationRoomRepository extends MockRoomRepository {
  final List<String?> chatRequestIds = <String?>[];
  final List<String?> giftRequestIds = <String?>[];
  int _chatAttempts = 0;
  int _giftAttempts = 0;

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    chatRequestIds.add(requestId);
    _chatAttempts += 1;
    if (_chatAttempts == 1) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应解析失败',
      );
    }
    if (_chatAttempts == 3) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请求参数无效',
      );
    }
    return RoomMessage(
      roomId: roomId,
      messageId: 'classification-chat-$_chatAttempts',
      senderId: 10001,
      sender: '我',
      content: content,
      createdAt: DateTime.utc(2026, 8, 22),
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    giftRequestIds.add(requestId);
    _giftAttempts += 1;
    if (_giftAttempts == 1) {
      throw const ApiException(kind: ApiFailureKind.server, message: '服务端响应未知');
    }
    return const GiftReceipt(success: true, remainingBalance: 1190);
  }
}

class _IdempotencyPendingRoomRepository extends MockRoomRepository {
  final List<String?> chatRequestIds = <String?>[];
  final List<String?> giftRequestIds = <String?>[];
  int _chatAttempts = 0;
  int _giftAttempts = 0;

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    chatRequestIds.add(requestId);
    _chatAttempts += 1;
    if (_chatAttempts == 1) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40902,
        httpStatus: 409,
        message: '请求仍在处理中',
      );
    }
    return RoomMessage(
      roomId: roomId,
      messageId: 'pending-chat-$_chatAttempts',
      senderId: 10001,
      sender: '我',
      content: content,
      createdAt: DateTime.utc(2026, 8, 23),
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    giftRequestIds.add(requestId);
    _giftAttempts += 1;
    if (_giftAttempts == 1) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40902,
        httpStatus: 409,
        message: '请求仍在处理中',
      );
    }
    return const GiftReceipt(success: true, remainingBalance: 1190);
  }
}

class _ConcurrentChatRoomRepository extends MockRoomRepository {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> firstGate = Completer<void>();
  final List<String> contents = <String>[];
  final List<String?> requestIds = <String?>[];
  int _concurrentCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    contents.add(content);
    requestIds.add(requestId);
    _concurrentCalls += 1;
    if (_concurrentCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = _concurrentCalls;
    }
    try {
      if (contents.length == 1) {
        firstStarted.complete();
        await firstGate.future;
      }
      return RoomMessage(
        roomId: roomId,
        messageId: 'concurrent-chat-${contents.length}',
        senderId: 10001,
        sender: '我',
        content: content,
        createdAt: DateTime.utc(2026, 8, 23),
        deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
        realtimeStatus: 'VENDOR_BLOCKED',
      );
    } finally {
      _concurrentCalls -= 1;
    }
  }
}

class _ReceiptRecoveryRoomRepository extends MockRoomRepository
    implements GiftReceiptRepository {
  int sendCalls = 0;
  final List<String?> receiptRequestIds = <String?>[];
  final List<int?> receiptParticipants = <int?>[];

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    sendCalls += 1;
    throw const ApiException(kind: ApiFailureKind.server, message: '响应未知');
  }

  @override
  Future<GiftReceipt> fetchGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  }) async {
    receiptRequestIds.add(requestId);
    receiptParticipants.add(currentUserId);
    return const GiftReceipt(
      success: true,
      remainingBalance: 1189,
      transferId: '00000000-0000-0000-0000-00000000c001',
      requestId: 'room-gift-recovery-1',
      reconciled: true,
    );
  }

  @override
  Future<GiftReceipt> queryGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  }) => fetchGiftReceipt(
    transferId: transferId,
    requestId: requestId,
    participantUserId: participantUserId,
    senderUserId: senderUserId,
    receiverUserId: receiverUserId,
    currentUserId: currentUserId,
  );
}
