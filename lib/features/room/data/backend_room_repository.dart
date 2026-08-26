import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/fixed_eight_seat_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_intent_digest.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_rtc_token_repository.dart';
import 'package:voice_social_app/features/room/data/room_write_guard.dart';

/// M3.2A live repository.
///
/// It exposes the authoritative HTTP room snapshot and the first-party room
/// writes. RTC credentials are an explicit opt-in capability; realtime and
/// audio remain fail-closed unless the app supplies the corresponding adapter.
class BackendRoomRepository
    implements RoomRepository, GiftReceiptRepository, RtcTokenRepository {
  BackendRoomRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
    FixedEightSeatAdapter seatAdapter = const FixedEightSeatAdapter(),
    RtcTokenRepository? rtcTokenRepository,
    DateTime Function()? now,
  }) : _apiClient = apiClient,
       _routes = routes,
       _seatAdapter = seatAdapter,
       _rtcTokenRepository = rtcTokenRepository,
       _now = now ?? DateTime.now;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final FixedEightSeatAdapter _seatAdapter;
  final RtcTokenRepository? _rtcTokenRepository;
  final DateTime Function() _now;
  final RoomWriteGuard _writeGuard = RoomWriteGuard(scope: 'room-session');
  final RoomWriteGuard _giftWriteGuard = RoomWriteGuard(scope: 'room-gift');
  String? _activeRoomId;
  int? _activeCurrentUserId;

  static const int _publicMessagesPageSize = 50;
  static const int _maximumPublicMessagePages = 100;

  static const Set<String> _authoritativeGiftSuccessStatuses = <String>{
    'SUCCESS',
    'SUCCEEDED',
    'COMPLETED',
    'COMMITTED',
    'DELIVERED',
  };
  static const Set<String> _authoritativeGiftFailureStatuses = <String>{
    'FAILED',
    'FAILURE',
    'REJECTED',
    'DECLINED',
    'CANCELLED',
    'CANCELED',
  };
  static const Set<String> _blockedProviderStatuses = <String>{
    'VENDOR_BLOCKED',
    'PROVIDER_BLOCKED',
    'BLOCKED',
    'UNAVAILABLE',
    'NOT_CONFIGURED',
    'VENDOR_UNAVAILABLE',
    'PROVIDER_UNAVAILABLE',
    'VENDOR_ERROR',
    'PROVIDER_ERROR',
    'DISABLED',
    'NOT_SUPPORTED',
  };
  static final RegExp _giftUuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const List<String> _giftAmountContainerAliases = <String>[
    'cost',
    'costs',
    'amount',
    'amounts',
    'pricing',
    'price',
    'giftCost',
    'money',
  ];
  static const List<String> _giftUnitAmountAliases = <String>[
    'unitCostMinor',
    'unitPriceMinor',
    'unitAmountMinor',
    'unitMinor',
    'priceMinor',
    'unitCost',
    'unitPrice',
    'unitCostGiftCoin',
  ];
  static const List<String> _giftTotalAmountAliases = <String>[
    'giftCoinCost',
    'totalCostMinor',
    'totalPriceMinor',
    'totalAmountMinor',
    'totalMinor',
    'amountMinor',
    'totalCost',
    'totalPrice',
    'totalAmount',
    'totalCostGiftCoin',
  ];
  static const List<String> _giftCurrencyAliases = <String>[
    'currency',
    'currencyCode',
    'currencyType',
    'costCurrency',
  ];

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final String normalizedRoomId = roomId.trim();
    final String? normalizedPassword = password?.trim();
    return _writeGuard.run<RoomSnapshot>(
      intent: roomIntentDigest(
        scope: 'enter-room',
        fields: <String>[
          normalizedRoomId,
          '${source.backendCode}',
          normalizedPassword ?? '',
          '$currentUserId',
        ],
      ),
      action: (Map<String, String> headers) async {
        final Map<String, Object?> body = <String, Object?>{
          'roomId': normalizedRoomId,
          'source': source.backendCode,
        };
        if (normalizedPassword != null && normalizedPassword.isNotEmpty) {
          body['password'] = normalizedPassword;
        }
        final ApiResponse response = await _apiClient.post(
          _routes.enterRoom,
          headers: headers,
          body: body,
        );
        RoomWriteGuard.validateMutationResponse(response, operation: '进入房间');
        _assertRawRequestedRoomIdentity(
          response,
          requestedRoomId: normalizedRoomId,
        );
        final RoomSnapshot snapshot = _snapshotFromResponse(
          response,
          currentUserId: currentUserId,
        );
        _assertRequestedRoomIdentity(
          response,
          snapshot,
          requestedRoomId: normalizedRoomId,
        );
        final RoomSnapshot transportReady = await _withRtcCredentials(
          snapshot,
          currentUserId: currentUserId,
        );
        _activeRoomId = transportReady.roomId;
        _activeCurrentUserId = currentUserId;
        return transportReady;
      },
    );
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    final String normalizedRoomId = roomId.trim();
    return _writeGuard.run<RoomSnapshot>(
      intent: 'reconnect:$normalizedRoomId:$currentUserId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.reconnectRoom,
          headers: headers,
          body: <String, Object?>{'roomId': normalizedRoomId},
        );
        RoomWriteGuard.validateMutationResponse(response, operation: '恢复房间会话');
        _assertRawRequestedRoomIdentity(
          response,
          requestedRoomId: normalizedRoomId,
        );
        final RoomSnapshot snapshot = _snapshotFromResponse(
          response,
          currentUserId: currentUserId,
        );
        _assertRequestedRoomIdentity(
          response,
          snapshot,
          requestedRoomId: normalizedRoomId,
        );
        final RoomSnapshot transportReady = await _withRtcCredentials(
          snapshot,
          currentUserId: currentUserId,
        );
        _activeRoomId = transportReady.roomId;
        _activeCurrentUserId = currentUserId;
        return transportReady;
      },
    );
  }

  /// Fetches a short-lived provider token through the authenticated
  /// first-party route. The default live room graph leaves this capability
  /// unset until the app has explicitly enabled the RTC readiness gate.
  @override
  Future<RtcCredentials> buildRtcToken({
    required String roomId,
    required int currentUserId,
    String? requestId,
  }) {
    final RtcTokenRepository? repository = _rtcTokenRepository;
    if (repository == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: 'RTC 凭证能力尚未启用',
      );
    }
    return repository.buildRtcToken(
      roomId: roomId,
      currentUserId: currentUserId,
      requestId: requestId,
    );
  }

  Future<RoomSnapshot> _withRtcCredentials(
    RoomSnapshot snapshot, {
    required int currentUserId,
  }) async {
    if (_rtcTokenRepository == null) {
      return snapshot;
    }
    try {
      final RtcCredentials credentials = await buildRtcToken(
        roomId: snapshot.roomId,
        currentUserId: currentUserId,
      );
      if (credentials.uid != currentUserId ||
          credentials.channelId != snapshot.roomId ||
          !credentials.hasUsablePublicCredentials ||
          (credentials.expiresAt != null &&
              !credentials.expiresAt!.isAfter(_now().toUtc()))) {
        return snapshot;
      }
      return snapshot.copyWith(
        rtc: credentials,
        transportMode: RoomTransportMode.interactive,
      );
    } on Object {
      // A room snapshot remains safe to display when the optional provider
      // token/readiness endpoint is unavailable or malformed. In particular,
      // never fall back to a mock token or invoke a vendor without a complete
      // public credential set.
      return snapshot;
    }
  }

  RoomSnapshot _snapshotFromResponse(
    ApiResponse response, {
    required int currentUserId,
  }) {
    final Map<String, Object?> data = _asMap(response.data);
    final String status = _nonEmptyString(data['status'])?.toUpperCase() ?? '';
    if ((data.containsKey('joined') && !_asBool(data['joined'])) ||
        status == 'PENDING_APPROVAL') {
      throw RoomJoinRequestPendingException(
        roomId: _nonEmptyString(data['roomId']) ?? '',
        joinRequestId: _nonEmptyString(data['joinRequestId']),
      );
    }
    return _snapshotFromData(data, currentUserId: currentUserId);
  }

  static void _assertRequestedRoomIdentity(
    ApiResponse response,
    RoomSnapshot snapshot, {
    required String requestedRoomId,
  }) {
    final Map<String, Object?> data = _asMap(response.data);
    final bool aliasesMatch = <String>['roomIdStr', 'roomId', 'id']
        .where(data.containsKey)
        .every((String key) => _nonEmptyString(data[key]) == requestedRoomId);
    if (!aliasesMatch || snapshot.roomId != requestedRoomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间快照响应与请求房间不一致',
      );
    }
  }

  static void _assertRawRequestedRoomIdentity(
    ApiResponse response, {
    required String requestedRoomId,
  }) {
    final Map<String, Object?> data = _asMap(response.data);
    final List<String> identities = <String>[
      for (final String key in <String>['roomIdStr', 'roomId', 'id'])
        if (data.containsKey(key)) _nonEmptyString(data[key]) ?? '',
    ];
    if (identities.isEmpty ||
        identities.any(
          (String identity) => identity.isEmpty || identity != requestedRoomId,
        )) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间响应与请求房间不一致',
      );
    }
  }

  RoomSnapshot _snapshotFromData(
    Map<String, Object?> data, {
    required int currentUserId,
  }) {
    final String resolvedRoomId =
        _nonEmptyString(data['roomIdStr']) ??
        _nonEmptyString(data['roomId']) ??
        _nonEmptyString(data['id']) ??
        '';
    if (resolvedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间快照缺少房间 ID',
      );
    }
    final int ownerId = _ownerIdFromData(data);
    final List<BackendMicSeat> backendSeats = <BackendMicSeat>[
      for (final Object? raw in _asList(data['seats']))
        if (raw is Map<String, Object?>)
          BackendMicSeat(
            index: _asInt(raw['index']) ?? -1,
            status: _seatStatus(raw),
            userId: _asInt(raw['userId']),
            userName: _nonEmptyString(raw['userName'] ?? raw['nickname']),
            avatarUrl: _safeAvatarUrl(raw['avatarUrl'] ?? raw['headImageUrl']),
            userRoleCode: _asInt(raw['userId']) == ownerId
                ? 3
                : _roleCode(raw['role'] ?? raw['userRole']),
          ),
    ];
    final String memberRole = _memberRoleFromData(data);
    return RoomSnapshot(
      roomId: resolvedRoomId,
      roomCode: _nonEmptyString(data['roomCode']) ?? resolvedRoomId,
      title:
          _nonEmptyString(data['roomName']) ??
          _nonEmptyString(data['name']) ??
          '语音房',
      topic:
          _nonEmptyString(data['topic']) ??
          _nonEmptyString(data['topicContent']) ??
          _nonEmptyString(data['description']) ??
          '',
      ownerId: ownerId,
      role: _roomRole(
        memberRole,
        ownerId: ownerId,
        currentUserId: currentUserId,
      ),
      seats: _seatAdapter.adapt(backendSeats),
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: resolvedRoomId,
        userId: currentUserId,
      ),
      transportMode: RoomTransportMode.snapshotOnly,
      // These are server-authoritative capabilities. Missing or malformed
      // values must remain disabled until the backend explicitly authorizes
      // them for the current member and room snapshot.
      publicScreenEnabled: _strictCapabilityBool(data['publicScreenEnabled']),
      pictureMessagesAllowed: false,
      autoLockMic: _strictCapabilityBool(data['autoLockMic']),
      giftCatalogAvailable: _strictCapabilityBool(data['giftCatalogAvailable']),
      giftBalance: null,
      accessMode: _nonEmptyString(data['accessMode'])?.toUpperCase() ?? '',
      onlineCount: _asInt(data['onlineNum']) ?? _asInt(data['liveCount']),
      coverUrl:
          _nonEmptyString(data['coverImgUrl']) ??
          _nonEmptyString(data['coverImage']),
    );
  }

  @override
  Future<void> exitRoom(String roomId) async {
    final String normalizedRoomId = roomId.trim();
    await _writeGuard.run<void>(
      intent: 'exit:$normalizedRoomId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.exitRoom,
          headers: headers,
          body: <String, Object?>{'roomId': normalizedRoomId},
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '退出房间',
          requiredFields: <String>['roomId', 'exited', 'status'],
        );
        if (_nonEmptyString(data['roomId']) != normalizedRoomId ||
            !_asBool(data['exited']) ||
            _nonEmptyString(data['status'])?.toUpperCase() != 'EXITED') {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '退出房间响应与请求状态不一致',
          );
        }
      },
    );
    if (_activeRoomId == normalizedRoomId) {
      _activeRoomId = null;
      _activeCurrentUserId = null;
    }
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    final String roomId = _requireActiveRoom();
    await _writeGuard.run<void>(
      intent: 'up-mic:$roomId:$backendMicIndex',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.userUpMic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'seatNumber': backendMicIndex,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '申请上麦',
          requiredFields: <String>[
            'roomId',
            'seatNumber',
            'userId',
            'occupied',
          ],
        );
        _assertRoomSeatState(
          data,
          roomId: roomId,
          seatNumber: backendMicIndex,
          userId: _requireActiveCurrentUser(),
          operation: '申请上麦',
        );
        if (!_asBool(data['occupied'])) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '申请上麦响应未确认 occupied=true',
          );
        }
      },
    );
  }

  @override
  Future<void> leaveMic() async {
    final String roomId = _requireActiveRoom();
    await _writeGuard.run<void>(
      intent: 'leave-mic:$roomId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.userLeaveMic,
          headers: headers,
          body: <String, Object?>{'roomId': roomId},
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '下麦',
          requiredFields: <String>['roomId', 'leftMic', 'previousSeat'],
        );
        if (_nonEmptyString(data['roomId']) != roomId ||
            !_asBool(data['leftMic'])) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '下麦响应与请求状态不一致',
          );
        }
      },
    );
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    final String roomId = _requireActiveRoom();
    final int userId = _requireActiveCurrentUser();
    await _writeGuard.run<void>(
      intent: 'self-mute:$roomId:$userId:$backendMicIndex:$muted',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          muted ? _routes.closeMic : _routes.openMic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'userId': userId,
            'seatNumber': backendMicIndex,
            'muted': muted,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: muted ? '闭麦' : '开麦',
          requiredFields: <String>['roomId', 'seatNumber', 'userId', 'muted'],
        );
        _assertRoomSeatState(
          data,
          roomId: roomId,
          seatNumber: backendMicIndex,
          userId: userId,
          operation: muted ? '闭麦' : '开麦',
        );
        if (_asBool(data['muted']) != muted) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '闭麦响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  }) async {
    if (content.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '公屏内容不能为空',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.sendPublicMessage,
      headers: _requestHeaders(requestId),
      body: <String, Object?>{'roomId': roomId, 'content': content.trim()},
    );
    final Map<String, Object?> raw = _asMap(response.data);
    final Map<String, Object?> data = raw['message'] is Map<String, Object?>
        ? raw['message']! as Map<String, Object?>
        : raw;
    return _messageFromSendMap(data, roomId: roomId, content: content.trim());
  }

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async {
    final List<RoomMessage> messages = <RoomMessage>[];
    final Set<String> seenMessageIds = <String>{};
    _RoomPageMetadata? expectedMetadata;
    int requestedPage = 1;

    while (true) {
      if (requestedPage > _maximumPublicMessagePages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史超过客户端安全分页上限',
        );
      }

      final ApiResponse response = await _apiClient.get(
        _routes.publicMessages,
        query: <String, String>{
          'roomId': roomId,
          'pageNum': '$requestedPage',
          'pageSize': '$_publicMessagesPageSize',
        },
      );
      final Map<String, Object?> data = _asMap(response.data);
      final _RoomPageMetadata metadata = _requiredRoomPageMetadata(
        data,
        requestedPage: requestedPage,
        requestedPageSize: _publicMessagesPageSize,
      );
      if (metadata.pages > _maximumPublicMessagePages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史超过客户端安全分页上限',
        );
      }
      if (expectedMetadata == null) {
        expectedMetadata = metadata;
      } else if (metadata.total != expectedMetadata.total ||
          metadata.pages != expectedMetadata.pages ||
          metadata.pageSize != expectedMetadata.pageSize) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史分页元数据在请求间发生变化',
        );
      }

      final List<Object?> rawMessages = _requiredRoomList(data);
      if (rawMessages.length > metadata.pageSize) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史单页记录超过服务端 pageSize',
        );
      }
      if (metadata.current < metadata.pages && rawMessages.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史仍有后续页但当前页为空',
        );
      }

      for (final Object? raw in rawMessages) {
        if (raw is! Map<String, Object?>) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '公屏历史消息结构无法识别',
          );
        }
        final RoomMessage message = _messageFromHistoryMap(raw, roomId: roomId);
        final String messageId = message.messageId ?? '';
        if (!seenMessageIds.add(messageId)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '公屏历史分页包含重复消息',
          );
        }
        messages.add(message);
      }
      if (messages.length > metadata.total) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史记录超过服务端 total',
        );
      }

      if (metadata.pages == 0 || metadata.current == metadata.pages) {
        if (messages.length != metadata.total) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '公屏历史记录总数与服务端 total 不一致',
          );
        }
        // The backend intentionally returns newest-first for efficient paging;
        // the room timeline renders oldest-to-newest.
        return messages.reversed.toList(growable: false);
      }

      requestedPage += 1;
    }
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
    final String normalizedRoomId = roomId.trim();
    final String normalizedGiftId = giftId.trim();
    if (normalizedRoomId.isEmpty ||
        receiverUserIds.length != 1 ||
        quantity < 1 ||
        quantity > 999 ||
        !_giftUuidPattern.hasMatch(normalizedGiftId)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '礼物、接收人和数量无效',
      );
    }
    if (giftFrom != 0) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '仅支持礼物币余额送礼',
      );
    }
    final String intent = roomIntentDigest(
      scope: 'send-gift',
      fields: <String>[
        normalizedRoomId,
        normalizedGiftId,
        '${receiverUserIds.first}',
        '$quantity',
        'WALLET',
      ],
    );
    return _giftWriteGuard.run<GiftReceipt>(
      intent: intent,
      fingerprint: intent,
      requestId: requestId,
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.sendGift,
          headers: headers,
          body: <String, Object?>{
            'roomId': normalizedRoomId,
            'giftId': normalizedGiftId,
            'receiverUserId': receiverUserIds.first,
            'quantity': quantity,
            'source': 'WALLET',
          },
        );
        final Map<String, Object?> raw = _asMap(response.data);
        final Map<String, Object?> data = raw['receipt'] is Map<String, Object?>
            ? raw['receipt']! as Map<String, Object?>
            : raw;
        return _giftReceiptFromData(
          data,
          roomId: normalizedRoomId,
          giftId: normalizedGiftId,
          receiverUserId: receiverUserIds.first,
          quantity: quantity,
          expectedRequestId: headers['X-Request-Id'],
        );
      },
    );
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
    final String? normalizedTransferId = _optionalTrimmedString(transferId);
    final String? normalizedRequestId = _optionalTrimmedString(requestId);
    if (normalizedTransferId == null && normalizedRequestId == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '礼物回执查询至少需要 transferId 或 requestId',
      );
    }
    final int? expectedParticipant =
        currentUserId ?? participantUserId ?? _activeCurrentUserId;
    if (expectedParticipant == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '礼物回执查询缺少当前用户参与者上下文',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.giftReceipt,
      query: <String, String>{
        if (normalizedTransferId != null) 'transferId': normalizedTransferId,
        if (normalizedRequestId != null) 'requestId': normalizedRequestId,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    return _giftReceiptFromData(
      data,
      requireReceiptAuthority: true,
      expectedTransferId: normalizedTransferId,
      expectedRequestId: normalizedRequestId,
      expectedParticipantUserId: expectedParticipant,
      expectedSenderUserId: senderUserId,
      expectedReceiverUserId: receiverUserId,
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

  GiftReceipt _giftReceiptFromData(
    Map<String, Object?> data, {
    String? roomId,
    String? giftId,
    int? receiverUserId,
    int? quantity,
    String? expectedRequestId,
    String? expectedTransferId,
    int? expectedParticipantUserId,
    int? expectedSenderUserId,
    int? expectedReceiverUserId,
    bool requireReceiptAuthority = false,
  }) {
    final String transferId = _requiredString(
      data,
      'transferId',
      field: '礼物 transferId',
    );
    final String responseRoomId = _requiredString(
      data,
      'roomId',
      field: '礼物房间 ID',
    );
    final int senderUserId = _requiredPositiveInt(
      data,
      'senderUserId',
      field: '礼物发送者 ID',
    );
    final int responseReceiverUserId = _requiredPositiveInt(
      data,
      'receiverUserId',
      field: '礼物接收者 ID',
    );
    final String responseGiftId = _requiredString(
      data,
      'giftId',
      field: '礼物 ID',
    );
    if (!_giftUuidPattern.hasMatch(responseGiftId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执 giftId 不是有效 UUID',
      );
    }
    final String giftName = _requiredString(data, 'giftName', field: '礼物名称');
    final int responseQuantity = _requiredPositiveInt(
      data,
      'quantity',
      field: '礼物数量',
    );
    final String source = _requiredString(data, 'source', field: '礼物来源');
    final String deliveryMode = _requiredString(
      data,
      'deliveryMode',
      field: '礼物投递模式',
    ).toUpperCase();
    final bool providerInvocation = _requiredBool(
      data,
      'providerInvocation',
      field: '礼物厂商调用状态',
    );
    final String? status = data.containsKey('status')
        ? _requiredString(data, 'status', field: '礼物状态').toUpperCase()
        : null;
    final String? providerStatus = _optionalString(data['providerStatus']);
    final String? responseRequestId = data.containsKey('requestId')
        ? _requiredString(data, 'requestId', field: '礼物请求 ID')
        : null;
    final int? creatorIncomeMinor = _optionalNonNegativeInt(
      data['creatorIncomeMinor'],
      field: '礼物创作者收益',
    );
    final int? charmValue = _optionalNonNegativeInt(
      data['charmValue'],
      field: '礼物魅力值',
    );
    final bool? reconciled = data.containsKey('reconciled')
        ? _requiredBool(data, 'reconciled', field: '礼物回执 reconciled')
        : null;
    final DateTime? createdAt = data.containsKey('createdAt')
        ? _requiredDateTime(data, 'createdAt', field: '礼物回执时间')
        : null;
    if (expectedTransferId != null && transferId != expectedTransferId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执 transferId 与请求不一致',
      );
    }
    if (requireReceiptAuthority && responseRequestId == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执缺少 requestId 权威',
      );
    }
    if (expectedRequestId != null &&
        responseRequestId != null &&
        responseRequestId != expectedRequestId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执 requestId 与请求不一致',
      );
    }
    final int? participant = expectedParticipantUserId;
    if (participant != null &&
        senderUserId != participant &&
        responseReceiverUserId != participant) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执参与者与当前用户不一致',
      );
    }
    if (expectedSenderUserId != null && senderUserId != expectedSenderUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执发送者与请求不一致',
      );
    }
    if (expectedReceiverUserId != null &&
        responseReceiverUserId != expectedReceiverUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执接收者与请求不一致',
      );
    }
    if (requireReceiptAuthority && reconciled != true) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物回执缺少已对账权威',
      );
    }
    if (providerInvocation || source.toUpperCase() == 'BACKPACK') {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '服务端返回了不支持的礼物来源或渠道状态',
      );
    }
    if ((roomId != null && responseRoomId != roomId) ||
        (receiverUserId != null && responseReceiverUserId != receiverUserId) ||
        (giftId != null && responseGiftId != giftId) ||
        (quantity != null && responseQuantity != quantity) ||
        (roomId != null &&
            _activeCurrentUserId != null &&
            senderUserId != _activeCurrentUserId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应与请求上下文不一致',
      );
    }
    if (source.toUpperCase() != 'WALLET' ||
        !<String>{
          'FIRST_PARTY_LEDGER_COMMITTED',
          'HTTP_PERSISTED_NO_REALTIME',
        }.contains(deliveryMode)) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '服务端返回了不支持的礼物来源或投递模式',
      );
    }
    if (providerStatus != null &&
        (_blockedProviderStatuses.contains(providerStatus.toUpperCase()) ||
            providerStatus.toUpperCase().contains('BLOCKED') ||
            providerStatus.toUpperCase().contains('UNAVAILABLE'))) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '礼物厂商状态被阻断，不能当作成功',
      );
    }
    if (status != null &&
        (_blockedProviderStatuses.contains(status) ||
            status.contains('BLOCKED') ||
            status.contains('UNAVAILABLE'))) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '礼物服务端状态被阻断，不能当作成功',
      );
    }
    final bool? explicitSuccess = data.containsKey('success')
        ? _asNullableBool(data['success'])
        : data.containsKey('isSuccess')
        ? _asNullableBool(data['isSuccess'])
        : null;
    if ((data.containsKey('success') || data.containsKey('isSuccess')) &&
        explicitSuccess == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应成功字段无法识别',
      );
    }
    final bool statusSuccess =
        status != null && _authoritativeGiftSuccessStatuses.contains(status);
    final bool statusFailure =
        status != null && _authoritativeGiftFailureStatuses.contains(status);
    if (status != null && !statusSuccess && !statusFailure) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应缺少有效服务端状态',
      );
    }
    final bool firstPartyLedgerCommitted =
        source.toUpperCase() == 'WALLET' &&
        !providerInvocation &&
        deliveryMode == 'FIRST_PARTY_LEDGER_COMMITTED';
    if (status == null && !firstPartyLedgerCommitted) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应缺少有效服务端状态',
      );
    }
    final bool authoritativeSuccess = status == null
        ? firstPartyLedgerCommitted
        : statusSuccess;
    final bool authoritativeFailure = explicitSuccess == false || statusFailure;

    if (authoritativeSuccess && authoritativeFailure) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应同时声明成功和失败',
      );
    }
    if (!authoritativeSuccess && !authoritativeFailure) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '送礼响应缺少有效服务端状态',
      );
    }
    if (authoritativeSuccess &&
        roomId != null &&
        giftId != null &&
        receiverUserId != null &&
        quantity != null) {
      _validateGiftAmountAuthority(
        data,
        roomId: roomId,
        senderUserId: senderUserId,
        receiverUserId: receiverUserId,
        giftId: giftId,
        quantity: quantity,
      );
    }
    return GiftReceipt(
      success: authoritativeSuccess,
      remainingBalance: _optionalInt(
        data['remainingBalance'] ??
            data['balance'] ??
            data['availableBalance'] ??
            data['availableMinor'],
      ),
      transferId: transferId,
      roomId: responseRoomId,
      senderUserId: senderUserId,
      receiverUserId: responseReceiverUserId,
      giftId: responseGiftId,
      giftName: giftName,
      quantity: responseQuantity,
      source: source,
      deliveryMode: deliveryMode,
      providerInvocation: providerInvocation,
      providerStatus: providerStatus,
      status: status,
      requestId: responseRequestId,
      creatorIncomeMinor: creatorIncomeMinor,
      charmValue: charmValue,
      reconciled: reconciled,
      createdAt: createdAt,
    );
  }

  static void _validateGiftAmountAuthority(
    Map<String, Object?> data, {
    required String roomId,
    required int senderUserId,
    required int receiverUserId,
    required String giftId,
    required int quantity,
  }) {
    final List<Map<String, Object?>> authorities = _giftAuthorityMaps(data);
    _validateOptionalNonNegativeGiftSummary(
      data,
      'creatorIncomeMinor',
      field: '礼物创作者收益',
    );
    _validateOptionalNonNegativeGiftSummary(data, 'charmValue', field: '礼物魅力值');
    final bool hasAmount = authorities.any(
      (Map<String, Object?> map) =>
          _containsAnyKey(map, _giftUnitAmountAliases) ||
          _containsAnyKey(map, _giftTotalAmountAliases),
    );
    if (!hasAmount) {
      return;
    }

    final int? unitCost = _resolveGiftAmountAlias(
      authorities,
      _giftUnitAmountAliases,
      field: '礼物单位金额',
    );
    final int? totalCost = _resolveGiftAmountAlias(
      authorities,
      _giftTotalAmountAliases,
      field: '礼物总金额',
    );
    if (totalCost == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物金额权威缺少总金额',
      );
    }
    if (unitCost != null && totalCost != unitCost * quantity) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物总金额与单位金额、数量不一致',
      );
    }

    // Currency is optional in the frozen b709 response, but every currency
    // alias that is present must describe the same ledger unit.
    final String? currency = _resolveGiftCurrencyAlias(authorities);
    if (currency != null && currency != 'GIFT_COIN') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物金额币种不是 GIFT_COIN',
      );
    }
    for (final Map<String, Object?> authority in authorities) {
      if (!_containsAnyKey(authority, <String>[
        ..._giftUnitAmountAliases,
        ..._giftTotalAmountAliases,
        ..._giftCurrencyAliases,
        'roomId',
        'roomIdStr',
        'giftId',
        'giftIdStr',
        'senderUserId',
        'senderId',
        'fromUserId',
        'receiverUserId',
        'receiverId',
        'recipientUserId',
        'toUserId',
        'quantity',
        'giftQuantity',
      ])) {
        continue;
      }
      _assertGiftAmountIdentity(
        authority,
        roomId: roomId,
        senderUserId: senderUserId,
        receiverUserId: receiverUserId,
        giftId: giftId,
        quantity: quantity,
      );
    }
  }

  static void _validateOptionalNonNegativeGiftSummary(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    if (!data.containsKey(key)) {
      return;
    }
    final int? value = _asInt(data[key]);
    if (value == null || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field不是有效非负整数',
      );
    }
  }

  static List<Map<String, Object?>> _giftAuthorityMaps(
    Map<String, Object?> data,
  ) {
    final List<Map<String, Object?>> maps = <Map<String, Object?>>[data];
    for (final String alias in _giftAmountContainerAliases) {
      if (!data.containsKey(alias)) {
        continue;
      }
      final Map<String, Object?>? nested = _mapOrNull(data[alias]);
      if (nested == null) {
        // `amount`/`price` are also used by legacy responses as scalar
        // display metadata. They are not an authority container unless they
        // actually carry the structured minor-unit fields.
        if (<String>{
          'cost',
          'costs',
          'pricing',
          'giftCost',
          'money',
        }.contains(alias)) {
          throw ApiException(
            kind: ApiFailureKind.protocol,
            message: '礼物金额 $alias 不是对象',
          );
        }
        continue;
      }
      maps.add(nested);
    }
    return maps;
  }

  static int? _resolveGiftAmountAlias(
    List<Map<String, Object?>> maps,
    List<String> aliases, {
    required String field,
  }) {
    int? resolved;
    bool found = false;
    for (final Map<String, Object?> map in maps) {
      for (final String alias in aliases) {
        if (!map.containsKey(alias)) {
          continue;
        }
        found = true;
        final int? candidate = _asInt(map[alias]);
        if (candidate == null || candidate < 0) {
          throw ApiException(
            kind: ApiFailureKind.protocol,
            message: '$field不是有效非负整数',
          );
        }
        if (resolved != null && resolved != candidate) {
          throw ApiException(
            kind: ApiFailureKind.protocol,
            message: '$field别名值不一致',
          );
        }
        resolved ??= candidate;
      }
    }
    return found ? resolved : null;
  }

  static String? _resolveGiftCurrencyAlias(List<Map<String, Object?>> maps) {
    String? resolved;
    for (final Map<String, Object?> map in maps) {
      for (final String alias in _giftCurrencyAliases) {
        if (!map.containsKey(alias)) {
          continue;
        }
        final Object? raw = map[alias];
        if (raw is! String || raw.trim().isEmpty) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '礼物金额币种不是有效字符串',
          );
        }
        final String candidate = raw.trim().toUpperCase();
        if (resolved != null && resolved != candidate) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '礼物金额币种别名值不一致',
          );
        }
        resolved ??= candidate;
      }
    }
    return resolved;
  }

  static void _assertGiftAmountIdentity(
    Map<String, Object?> data, {
    required String roomId,
    required int senderUserId,
    required int receiverUserId,
    required String giftId,
    required int quantity,
  }) {
    _assertGiftStringIdentity(
      data,
      <String>['roomId', 'roomIdStr'],
      roomId,
      field: '礼物金额房间 ID',
    );
    _assertGiftStringIdentity(
      data,
      <String>['giftId', 'giftIdStr'],
      giftId,
      field: '礼物金额礼物 ID',
    );
    _assertGiftIntIdentity(
      data,
      <String>['senderUserId', 'senderId', 'fromUserId'],
      senderUserId,
      field: '礼物金额发送者 ID',
    );
    _assertGiftIntIdentity(
      data,
      <String>['receiverUserId', 'receiverId', 'recipientUserId', 'toUserId'],
      receiverUserId,
      field: '礼物金额接收者 ID',
    );
    _assertGiftIntIdentity(
      data,
      <String>['quantity', 'giftQuantity'],
      quantity,
      field: '礼物金额数量',
    );
  }

  static void _assertGiftStringIdentity(
    Map<String, Object?> data,
    List<String> aliases,
    String expected, {
    required String field,
  }) {
    String? resolved;
    for (final String alias in aliases) {
      if (!data.containsKey(alias)) {
        continue;
      }
      final String? candidate = _nonEmptyString(data[alias]);
      if (candidate == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field不是有效字符串',
        );
      }
      if (resolved != null && resolved != candidate) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field别名值不一致',
        );
      }
      resolved ??= candidate;
    }
    if (resolved != null && resolved != expected) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field与送礼请求不一致',
      );
    }
  }

  static void _assertGiftIntIdentity(
    Map<String, Object?> data,
    List<String> aliases,
    int expected, {
    required String field,
  }) {
    int? resolved;
    for (final String alias in aliases) {
      if (!data.containsKey(alias)) {
        continue;
      }
      final int? candidate = _asInt(data[alias]);
      if (candidate == null || candidate <= 0) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field不是有效正整数',
        );
      }
      if (resolved != null && resolved != candidate) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field别名值不一致',
        );
      }
      resolved ??= candidate;
    }
    if (resolved != null && resolved != expected) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field与送礼请求不一致',
      );
    }
  }

  static bool _containsAnyKey(
    Map<String, Object?> data,
    Iterable<String> aliases,
  ) => aliases.any(data.containsKey);

  static Map<String, Object?>? _mapOrNull(Object? value) {
    if (value is! Map) {
      return null;
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is String) {
        result[entry.key! as String] = entry.value;
      }
    }
    return result;
  }

  String _requireActiveRoom() {
    final String? roomId = _activeRoomId;
    if (roomId == null || roomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前未加入房间，无法执行房间操作',
      );
    }
    return roomId;
  }

  int _requireActiveCurrentUser() {
    final int? userId = _activeCurrentUserId;
    if (userId == null || userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前登录用户未绑定房间会话',
      );
    }
    return userId;
  }

  static int _seatStatus(Map<String, Object?> raw) {
    if (raw.containsKey('status')) {
      final int? status = _asInt(raw['status']);
      if (status == null || status < 0 || status > 4) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '麦位 status 不是冻结契约中的 0～4 状态',
        );
      }
      final bool expectedOccupied = status == 3 || status == 4;
      final bool expectedLocked = status == 1;
      final bool expectedMuted = status == 2 || status == 4;
      _assertSeatStatusBoolAlias(
        raw,
        field: 'occupied',
        expected: expectedOccupied,
      );
      _assertSeatStatusBoolAlias(
        raw,
        field: 'locked',
        expected: expectedLocked,
      );
      _assertSeatStatusBoolAlias(raw, field: 'muted', expected: expectedMuted);
      if (raw.containsKey('userId') && raw['userId'] != null) {
        final int? userId = _asInt(raw['userId']);
        if (userId == null || userId <= 0 || !expectedOccupied) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '麦位 status 与 userId 别名不一致',
          );
        }
      }
      return status;
    }
    final bool occupied =
        _asBool(raw['occupied']) || _asInt(raw['userId']) != null;
    final bool locked = _asBool(raw['locked']);
    final bool muted = _asBool(raw['muted']);
    if (occupied) {
      return muted ? 4 : 3;
    }
    if (locked) {
      return 1;
    }
    return muted ? 2 : 0;
  }

  static void _assertSeatStatusBoolAlias(
    Map<String, Object?> raw, {
    required String field,
    required bool expected,
  }) {
    if (!raw.containsKey(field)) {
      return;
    }
    final bool? value = _asNullableBool(raw[field]);
    if (value == null || value != expected) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '麦位 status 与 $field 别名不一致',
      );
    }
  }

  static int? _roleCode(Object? value) {
    final int? numeric = _asInt(value);
    if (numeric != null) return numeric;
    return switch (value?.toString().trim().toUpperCase()) {
      'OWNER' => 3,
      'MANAGER' || 'MODERATOR' => 1,
      'PLATFORM_MODERATOR' => 2,
      _ => null,
    };
  }

  static RoomRole _roomRole(
    String role, {
    required int ownerId,
    required int currentUserId,
  }) {
    if (ownerId == currentUserId || role.toUpperCase() == 'OWNER') {
      return RoomRole.owner;
    }
    return switch (role.toUpperCase()) {
      'MANAGER' || 'MODERATOR' => RoomRole.moderator,
      'PLATFORM_MODERATOR' => RoomRole.platformModerator,
      'SPEAKER' => RoomRole.speaker,
      _ => RoomRole.listener,
    };
  }

  static int _ownerIdFromData(Map<String, Object?> data) {
    int? resolved;
    for (final String alias in <String>[
      'ownerId',
      'ownerUserId',
      // The legacy room snapshot contract used userId for the room owner.
      // Keep that fallback, but never let it silently disagree with an
      // explicit owner alias.
      'userId',
    ]) {
      if (!data.containsKey(alias)) {
        continue;
      }
      final int? candidate = _asInt(data[alias]);
      if (candidate == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间快照 $alias 不是有效房主 ID',
        );
      }
      if (resolved != null && resolved != candidate) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间快照房主 ID 别名值不一致',
        );
      }
      resolved ??= candidate;
    }
    return resolved ?? 0;
  }

  static String _memberRoleFromData(Map<String, Object?> data) {
    String? resolved;
    for (final String alias in <String>['memberRole', 'role']) {
      if (!data.containsKey(alias)) {
        continue;
      }
      final String? candidate = _canonicalMemberRole(data[alias]);
      if (candidate == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间快照 $alias 不是有效成员角色',
        );
      }
      if (resolved != null && resolved != candidate) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间快照成员角色别名值不一致',
        );
      }
      resolved ??= candidate;
    }
    return resolved ?? '';
  }

  static String? _canonicalMemberRole(Object? value) {
    final int? numeric = _asInt(value);
    if (numeric != null) {
      return switch (numeric) {
        0 => 'MEMBER',
        1 => 'MODERATOR',
        2 => 'PLATFORM_MODERATOR',
        3 => 'OWNER',
        4 => 'SPEAKER',
        _ => 'ROLE_$numeric',
      };
    }
    final String? normalized = _nonEmptyString(value)?.toUpperCase();
    if (normalized == null) {
      return null;
    }
    return switch (normalized) {
      'OWNER' => 'OWNER',
      'MANAGER' || 'MODERATOR' => 'MODERATOR',
      'PLATFORM_MODERATOR' => 'PLATFORM_MODERATOR',
      'SPEAKER' => 'SPEAKER',
      'MEMBER' || 'LISTENER' || 'USER' => 'MEMBER',
      _ => normalized,
    };
  }

  static bool _strictCapabilityBool(Object? value) => value is bool && value;

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static Map<String, Object?> _requiredMutationMap(
    ApiResponse response, {
    required String operation,
    required Iterable<String> requiredFields,
  }) {
    RoomWriteGuard.validateMutationResponse(
      response,
      operation: operation,
      requiredFields: requiredFields,
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应结构为空',
      );
    }
    return data;
  }

  static void _assertRoomSeatState(
    Map<String, Object?> data, {
    required String roomId,
    required int seatNumber,
    required int userId,
    required String operation,
  }) {
    if (_nonEmptyString(data['roomId']) != roomId ||
        _asInt(data['seatNumber']) != seatNumber ||
        _asInt(data['userId']) != userId) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应房间、麦位或用户不一致',
      );
    }
  }

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      _ => false,
    };
  }

  static bool? _asNullableBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return null;
  }

  static Map<String, String>? _requestHeaders(String? requestId) {
    final String normalized = requestId?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(normalized)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请求幂等 ID 格式无效',
      );
    }
    return <String, String>{'X-Request-Id': normalized};
  }

  static List<Object?> _requiredRoomList(Map<String, Object?> data) {
    final Object? listValue = data['list'];
    final Object? recordsValue = data['records'];
    if (listValue is List<Object?> && recordsValue is List<Object?>) {
      if (!_sameValue(listValue, recordsValue)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史 list 与 records 不一致',
        );
      }
      return listValue;
    }
    for (final String key in <String>['list', 'records', 'items', 'messages']) {
      final Object? value = data[key];
      if (value is List<Object?>) return value;
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '公屏历史缺少服务端消息列表',
    );
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_sameValue(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (int index = 0; index < left.length; index++) {
        if (!_sameValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static _RoomPageMetadata _requiredRoomPageMetadata(
    Map<String, Object?> data, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final int current = _requiredPageField(
      data,
      keys: <String>['current', 'pageNum'],
      field: 'current',
      allowZero: false,
    );
    final int pageSize = _requiredPageField(
      data,
      keys: <String>['pageSize', 'size'],
      field: 'pageSize',
      allowZero: false,
    );
    final int total = _requiredPageField(
      data,
      keys: <String>['total'],
      field: 'total',
      allowZero: true,
    );
    final int pages = _requiredPageField(
      data,
      keys: <String>['pages'],
      field: 'pages',
      allowZero: true,
    );
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公屏历史分页 current 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages || (pages > 0 && current > pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公屏历史分页 pages 与 total 不一致',
      );
    }
    return _RoomPageMetadata(
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
  }

  static int _requiredPageField(
    Map<String, Object?> data, {
    required List<String> keys,
    required String field,
    required bool allowZero,
  }) {
    int? resolved;
    for (final String key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }
      final int? candidate = _asInt(data[key]);
      if (candidate == null || candidate < (allowZero ? 0 : 1)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史 $field 不是有效服务端分页数字',
        );
      }
      if (resolved != null && resolved != candidate) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史 $field 别名值不一致',
        );
      }
      resolved = candidate;
    }
    if (resolved == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '公屏历史缺少有效服务端 $field',
      );
    }
    return resolved;
  }

  RoomMessage _messageFromSendMap(
    Map<String, Object?> raw, {
    required String roomId,
    required String content,
  }) {
    final String messageId = _requiredString(
      raw,
      'messageId',
      field: '公屏消息 ID',
    );
    final String responseRoomId = _requiredString(
      raw,
      'roomId',
      field: '公屏消息房间 ID',
    );
    final int senderId = _requiredPositiveInt(
      raw,
      'senderUserId',
      field: '公屏消息发送者 ID',
    );
    final String responseContent = _requiredString(
      raw,
      'content',
      field: '公屏消息内容',
    );
    final DateTime createdAt = _requiredDateTime(
      raw,
      'createdAt',
      field: '公屏消息时间',
    );
    final String deliveryMode = _requiredString(
      raw,
      'deliveryMode',
      field: '公屏消息投递模式',
    ).toUpperCase();
    final String realtimeStatus = _requiredString(
      raw,
      'realtimeStatus',
      field: '公屏消息实时状态',
    ).toUpperCase();
    if (responseRoomId != roomId ||
        responseContent != content ||
        (_activeCurrentUserId != null && senderId != _activeCurrentUserId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公屏消息响应与请求上下文不一致',
      );
    }
    if (deliveryMode != 'HTTP_PERSISTED_NO_REALTIME' ||
        realtimeStatus != 'VENDOR_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '公屏消息实时能力未按服务端契约阻断',
      );
    }
    final String? optionalType = _optionalString(raw['type']);
    if (raw.containsKey('type') &&
        (optionalType == null || optionalType.toUpperCase() != 'TEXT')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公屏发送响应类型不是 TEXT',
      );
    }
    return RoomMessage(
      roomId: responseRoomId,
      messageId: messageId,
      senderId: senderId,
      sender: '我',
      type: 'TEXT',
      content: responseContent,
      isSystem: false,
      createdAt: createdAt,
      deliveryMode: deliveryMode,
      realtimeStatus: realtimeStatus,
    );
  }

  RoomMessage _messageFromHistoryMap(
    Map<String, Object?> raw, {
    required String roomId,
  }) {
    final String messageId = _requiredString(
      raw,
      'messageId',
      field: '公屏历史消息 ID',
    );
    final int senderId = _requiredPositiveInt(
      raw,
      'senderUserId',
      field: '公屏历史发送者 ID',
    );
    final String sender = _requiredString(
      raw,
      'senderName',
      field: '公屏历史发送者名称',
    );
    final String type = _requiredString(raw, 'type', field: '公屏历史消息类型');
    final String content = _requiredString(raw, 'content', field: '公屏历史消息内容');
    final DateTime createdAt = _requiredDateTime(
      raw,
      'createdAt',
      field: '公屏历史消息时间',
    );
    if (raw.containsKey('roomId')) {
      final String responseRoomId = _requiredString(
        raw,
        'roomId',
        field: '公屏历史消息房间 ID',
      );
      if (responseRoomId != roomId) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '公屏历史消息房间 ID 与请求不一致',
        );
      }
    }
    if (raw.containsKey('deliveryMode')) {
      final String deliveryMode = _requiredString(
        raw,
        'deliveryMode',
        field: '公屏历史消息投递模式',
      ).toUpperCase();
      if (deliveryMode != 'HTTP_PERSISTED_NO_REALTIME') {
        throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '公屏历史消息实时能力未按服务端契约阻断',
        );
      }
    }
    if (raw.containsKey('realtimeStatus')) {
      final String realtimeStatus = _requiredString(
        raw,
        'realtimeStatus',
        field: '公屏历史消息实时状态',
      ).toUpperCase();
      if (realtimeStatus != 'VENDOR_BLOCKED') {
        throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '公屏历史消息实时能力未按服务端契约阻断',
        );
      }
    }
    final String normalizedType = type.toUpperCase();
    return RoomMessage(
      roomId: roomId,
      messageId: messageId,
      senderId: senderId,
      sender: sender,
      type: type,
      content: content,
      isSystem:
          normalizedType == 'SYSTEM' ||
          normalizedType == 'NOTICE' ||
          normalizedType == 'GIFT',
      createdAt: createdAt,
      deliveryMode: 'HTTP_PERSISTED_NO_REALTIME',
      realtimeStatus: 'VENDOR_BLOCKED',
    );
  }

  static int _requiredPositiveInt(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final int value = _requiredInt(data, key, field: field);
    if (value <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field不能为零或负数',
      );
    }
    return value;
  }

  static int _requiredInt(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    if (!data.containsKey(key)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少服务端整数',
      );
    }
    final int? value = _asInt(data[key]);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field不是有效服务端整数',
      );
    }
    return value;
  }

  static bool _requiredBool(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    if (!data.containsKey(key)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少服务端布尔值',
      );
    }
    final bool? value = _asNullableBool(data[key]);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field不是有效服务端布尔值',
      );
    }
    return value;
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final String? value = _nonEmptyString(data[key]);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端字符串',
      );
    }
    return value;
  }

  static String? _optionalString(Object? value) => _nonEmptyString(value);

  static String? _optionalTrimmedString(Object? value) {
    final String? string = _nonEmptyString(value);
    return string?.trim().isEmpty == true ? null : string?.trim();
  }

  static int? _optionalInt(Object? value) {
    if (value == null) {
      return null;
    }
    final int? parsed = _asInt(value);
    if (parsed == null || parsed < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端余额不是有效非负整数',
      );
    }
    return parsed;
  }

  static int? _optionalNonNegativeInt(Object? value, {required String field}) {
    if (value == null) {
      return null;
    }
    final int? parsed = _asInt(value);
    if (parsed == null || parsed < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field不是有效非负整数',
      );
    }
    return parsed;
  }

  static DateTime _requiredDateTime(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final DateTime? value = _asDateTime(data[key]);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端时间',
      );
    }
    return value;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
      } on RangeError {
        return null;
      }
    }
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final int? epoch = int.tryParse(raw);
    if (epoch != null) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
      } on RangeError {
        return null;
      }
    }
    return DateTime.tryParse(raw);
  }

  static String? _nonEmptyString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static String? _safeAvatarUrl(Object? value) {
    final String? normalized = _nonEmptyString(value);
    if (normalized == null) {
      return null;
    }
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.isAbsolute ||
        uri.host.isEmpty ||
        !<String>{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri.toString();
  }
}

class _RoomPageMetadata {
  const _RoomPageMetadata({
    required this.current,
    required this.pageSize,
    required this.total,
    required this.pages,
  });

  final int current;
  final int pageSize;
  final int total;
  final int pages;
}
