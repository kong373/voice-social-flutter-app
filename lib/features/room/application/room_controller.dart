import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

class RoomController extends ChangeNotifier {
  RoomController({
    required this.roomId,
    required this.title,
    required int currentUserId,
    required String accessToken,
    required RoomRepository repository,
    required RtcAdapter rtcAdapter,
    required RoomRealtimeGateway realtimeGateway,
    RoomPermissionPolicy permissionPolicy = const RoomPermissionPolicy(),
  }) : _currentUserId = currentUserId,
       _accessToken = accessToken,
       _repository = repository,
       _rtcAdapter = rtcAdapter,
       _realtimeGateway = realtimeGateway,
       _permissionPolicy = permissionPolicy;

  final String roomId;
  final String title;
  final int _currentUserId;
  final String _accessToken;
  final RoomRepository _repository;
  final RtcAdapter _rtcAdapter;
  final RoomRealtimeGateway _realtimeGateway;
  final RoomPermissionPolicy _permissionPolicy;

  RoomSnapshot? _snapshot;
  final List<RoomMessage> _messages = <RoomMessage>[];
  RoomSessionStatus _status = RoomSessionStatus.idle;
  StreamSubscription<RoomRealtimeEvent>? _realtimeSubscription;
  bool _micRequestPending = false;
  bool _giftSubmitting = false;
  bool _realtimeDegraded = false;
  bool _mutedInRoom = false;
  bool _refreshingFromEvent = false;
  bool _joinCancelled = false;
  bool _disposed = false;
  String? _errorMessage;

  RoomSnapshot? get snapshot => _snapshot;
  RoomSessionStatus get status => _status;
  int get currentUserId => _currentUserId;
  String get displayTitle => _snapshot?.title ?? title;
  String get roomCode => _snapshot?.roomCode ?? roomId;
  String get topic => _snapshot?.topic ?? '';
  List<MicSeat> get seats =>
      List<MicSeat>.unmodifiable(_snapshot?.seats ?? _emptySeats);
  List<RoomMessage> get messages => List<RoomMessage>.unmodifiable(_messages);
  RoomRole get role => _snapshot?.role ?? RoomRole.listener;
  int? get giftBalance => _snapshot?.giftBalance;
  bool get micRequestPending => _micRequestPending;
  bool get giftSubmitting => _giftSubmitting;
  bool get realtimeDegraded => _realtimeDegraded;
  bool get isSnapshotOnly => _snapshot?.isSnapshotOnly ?? false;
  bool get mutedInRoom => _mutedInRoom;
  bool get canSendPublicMessage =>
      !_mutedInRoom && allows(RoomCapability.sendPublicMessage);
  String? get errorMessage => _errorMessage;

  void applyAuthoritativeTopic(String topic) {
    final RoomSnapshot? snapshot = _snapshot;
    if (snapshot == null || snapshot.topic == topic) {
      return;
    }
    _snapshot = snapshot.copyWith(topic: topic);
    _notify();
  }

  bool get isOnMic => seats.any(
    (MicSeat seat) => seat.userId == _currentUserId && seat.isOccupied,
  );

  bool get micMuted {
    final MicSeat? seat = _ownSeat();
    return seat?.state == MicSeatState.occupiedMuted;
  }

  bool allows(RoomCapability capability) {
    final RoomSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      return false;
    }
    return _permissionPolicy.allows(
      snapshot: snapshot,
      capability: capability,
      isOnMic: isOnMic,
    );
  }

  static final List<MicSeat> _emptySeats = <MicSeat>[
    for (int index = 1; index <= 8; index += 1)
      MicSeat(
        number: index,
        backendIndex: index,
        state: MicSeatState.available,
      ),
  ];

  Future<void> join({
    RoomEntrySource source = RoomEntrySource.home,
    String? password,
  }) async {
    if (_status == RoomSessionStatus.joining ||
        _status == RoomSessionStatus.joined ||
        _status == RoomSessionStatus.reconnecting ||
        _status == RoomSessionStatus.leaving) {
      return;
    }
    _joinCancelled = false;
    _mutedInRoom = false;
    _status = RoomSessionStatus.joining;
    _errorMessage = null;
    _realtimeDegraded = false;
    _notify();

    RoomSnapshot? enteredSnapshot;
    try {
      final RoomSnapshot snapshot = await _repository.enterRoom(
        roomId: roomId,
        password: password,
        source: source,
        currentUserId: _currentUserId,
      );
      enteredSnapshot = snapshot;
      if (_joinCancelled || _disposed) {
        await _abandonEnteredRoom(snapshot);
        return;
      }
      if (!snapshot.isSnapshotOnly) {
        await _rtcAdapter.join(snapshot.rtc);
        if (_joinCancelled || _disposed) {
          await _abandonEnteredRoom(snapshot);
          return;
        }
        await _replaceRealtimeSubscription();
        try {
          await _realtimeGateway.connect(
            roomId: snapshot.roomId,
            userId: _currentUserId,
            accessToken: _accessToken,
          );
        } catch (_) {
          _realtimeDegraded = true;
        }
      }
      if (_joinCancelled || _disposed) {
        await _abandonEnteredRoom(snapshot);
        return;
      }
      _snapshot = snapshot;
      _messages
        ..clear()
        ..addAll(<RoomMessage>[
          const RoomMessage(
            sender: '系统',
            content: '欢迎进入房间，请友善交流。',
            isSystem: true,
          ),
          if (!snapshot.isSnapshotOnly && _realtimeDegraded)
            const RoomMessage(
              sender: '系统',
              content: '实时消息通道暂未连接，房间状态可能延迟。',
              isSystem: true,
            ),
        ]);
      _status = RoomSessionStatus.joined;
    } catch (error) {
      if (_joinCancelled || _disposed) {
        await _cleanupTransport(swallowErrors: true);
        _status = RoomSessionStatus.left;
        _notify();
        return;
      }
      final RoomSnapshot? snapshot = enteredSnapshot;
      if (snapshot != null) {
        try {
          await _repository.exitRoom(snapshot.roomId);
        } catch (_) {
          // Preserve the original join failure while cleanup remains best effort.
        }
      }
      await _cleanupTransport(swallowErrors: true);
      _errorMessage = _messageFor(error, fallback: '进入房间失败，请重试');
      _status = RoomSessionStatus.failed;
    }
    _notify();
  }

  Future<bool> requestMic(int seatNumber) async {
    if (_micRequestPending ||
        !allows(RoomCapability.requestMic) ||
        _status != RoomSessionStatus.joined) {
      return false;
    }
    final MicSeat? seat = _seatByNumber(seatNumber);
    if (seat == null || !seat.isAvailable) {
      _errorMessage = '麦位状态已变化，请重新选择';
      _notify();
      return false;
    }
    _micRequestPending = true;
    _errorMessage = null;
    _notify();
    try {
      await _repository.requestMic(seat.backendIndex);
      final RoomSnapshot refreshed = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!refreshed.seats.any(
        (MicSeat item) => item.userId == _currentUserId && item.isOccupied,
      )) {
        throw const ApiException(
          kind: ApiFailureKind.business,
          message: '麦位状态尚未确认，请刷新后重试',
        );
      }
      _snapshot = refreshed;
      await _rtcAdapter.setLocalAudioEnabled(true);
      _messages.add(
        RoomMessage(
          sender: '系统',
          content: '你已上 $seatNumber 号麦。',
          isSystem: true,
        ),
      );
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '申请上麦失败');
      return false;
    } finally {
      _micRequestPending = false;
      _notify();
    }
  }

  Future<bool> leaveMic() async {
    if (!allows(RoomCapability.leaveMic) ||
        _status != RoomSessionStatus.joined) {
      return false;
    }
    try {
      await _repository.leaveMic();
      await _rtcAdapter.setLocalAudioEnabled(false);
      _snapshot = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      _messages.add(
        const RoomMessage(sender: '系统', content: '你已离开麦位。', isSystem: true),
      );
      _notify();
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '下麦失败');
      _notify();
      return false;
    }
  }

  Future<bool> toggleMicrophone() async {
    if (!allows(RoomCapability.toggleMicrophone) ||
        _status != RoomSessionStatus.joined) {
      return false;
    }
    final MicSeat? ownSeat = _ownSeat();
    if (ownSeat == null) {
      return false;
    }
    final bool nextMuted = !micMuted;
    try {
      await _repository.setSelfMicrophoneMuted(
        backendMicIndex: ownSeat.backendIndex,
        muted: nextMuted,
      );
      await _rtcAdapter.setLocalAudioEnabled(!nextMuted);
      final RoomSnapshot? snapshot = _snapshot;
      if (snapshot != null) {
        final List<MicSeat> updated = <MicSeat>[
          for (final MicSeat seat in snapshot.seats)
            if (seat.number == ownSeat.number)
              seat.copyWith(
                state: nextMuted
                    ? MicSeatState.occupiedMuted
                    : MicSeatState.occupied,
              )
            else
              seat,
        ];
        _snapshot = snapshot.copyWith(seats: updated);
      }
      _notify();
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '麦克风状态更新失败');
      _notify();
      return false;
    }
  }

  Future<bool> sendPublicMessage(String content) async {
    final String normalized = content.trim();
    final RoomSnapshot? snapshot = _snapshot;
    if (normalized.isEmpty ||
        snapshot == null ||
        _status != RoomSessionStatus.joined ||
        !canSendPublicMessage) {
      return false;
    }
    try {
      await _repository.sendPublicMessage(
        roomId: snapshot.roomId,
        content: normalized,
      );
      _messages.add(
        RoomMessage(
          senderId: _currentUserId,
          sender: '我',
          content: normalized,
          createdAt: DateTime.now(),
        ),
      );
      _notify();
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '消息发送失败');
      _notify();
      return false;
    }
  }

  Future<bool> sendGift({
    required int giftId,
    required String giftName,
    required int receiverUserId,
    required String targetName,
    required int quantity,
    int giftFrom = 0,
  }) async {
    final RoomSnapshot? snapshot = _snapshot;
    if (_giftSubmitting ||
        snapshot == null ||
        _status != RoomSessionStatus.joined ||
        !allows(RoomCapability.sendGift)) {
      return false;
    }
    _giftSubmitting = true;
    _errorMessage = null;
    _notify();
    try {
      final GiftReceipt receipt = await _repository.sendGift(
        roomId: snapshot.roomId,
        giftId: giftId,
        receiverUserIds: <int>[receiverUserId],
        quantity: quantity,
        giftFrom: giftFrom,
      );
      if (!receipt.success) {
        _errorMessage = '礼物赠送未完成，请刷新余额后重试';
        return false;
      }
      final int? remainingBalance = receipt.remainingBalance;
      if (remainingBalance != null) {
        _snapshot = snapshot.copyWith(giftBalance: remainingBalance);
      }
      _messages.add(
        RoomMessage(
          sender: '系统',
          content: '我送给 $targetName $giftName ×$quantity',
          isSystem: true,
          createdAt: DateTime.now(),
        ),
      );
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '礼物赠送失败');
      return false;
    } finally {
      _giftSubmitting = false;
      _notify();
    }
  }

  Future<void> reconnect() async {
    if (_status != RoomSessionStatus.joined) {
      return;
    }
    _status = RoomSessionStatus.reconnecting;
    _errorMessage = null;
    _notify();
    try {
      final RoomSnapshot snapshot = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!snapshot.isSnapshotOnly) {
        await _rtcAdapter.reconnect(snapshot.rtc);
        try {
          await _realtimeGateway.reconnect();
          _realtimeDegraded = false;
        } catch (_) {
          _realtimeDegraded = true;
        }
      } else {
        _realtimeDegraded = false;
      }
      _snapshot = snapshot;
      _messages.add(
        const RoomMessage(
          sender: '系统',
          content: '已恢复连接。断线期间公屏消息可能未显示。',
          isSystem: true,
        ),
      );
      _status = RoomSessionStatus.joined;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '房间恢复失败，请重试');
      _realtimeDegraded = true;
      _status = _snapshot == null
          ? RoomSessionStatus.failed
          : RoomSessionStatus.joined;
    }
    _notify();
  }

  Future<bool> leaveRoom() async {
    if (_status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left) {
      return false;
    }
    if (_status == RoomSessionStatus.joining ||
        _status == RoomSessionStatus.idle ||
        (_status == RoomSessionStatus.failed && _snapshot == null)) {
      _joinCancelled = true;
      _status = RoomSessionStatus.left;
      await _cleanupTransport(swallowErrors: true);
      _notify();
      return true;
    }
    _status = RoomSessionStatus.leaving;
    _errorMessage = null;
    _notify();
    try {
      await _repository.exitRoom(_snapshot?.roomId ?? roomId);
      await _cleanupTransport(swallowErrors: true);
      _status = RoomSessionStatus.left;
      _notify();
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, fallback: '离开房间失败，请重试');
      _status = RoomSessionStatus.joined;
      _notify();
      return false;
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    _notify();
  }

  Future<void> _replaceRealtimeSubscription() async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = _realtimeGateway.events.listen(
      _handleRealtimeEvent,
      onError: (Object _, StackTrace __) {
        _realtimeDegraded = true;
        _notify();
      },
    );
  }

  void _handleRealtimeEvent(RoomRealtimeEvent event) {
    if (!RoomRealtimeEventCodes.allowed.contains(event.code)) {
      return;
    }
    switch (event.code) {
      case RoomRealtimeEventCodes.publicChat:
        final String content = event.payload['message']?.toString() ?? '';
        if (content.isNotEmpty) {
          _messages.add(
            RoomMessage(
              senderId: int.tryParse(event.payload['userId']?.toString() ?? ''),
              sender: event.payload['nickname']?.toString() ?? '房间成员',
              content: content,
            ),
          );
          _notify();
        }
        return;
      case RoomRealtimeEventCodes.gift:
        _messages.add(
          RoomMessage(
            sender: '系统',
            content: event.payload['displayText']?.toString() ?? '房间收到一份礼物',
            isSystem: true,
          ),
        );
        _notify();
        return;
      case RoomRealtimeEventCodes.kickedOut:
        _status = RoomSessionStatus.kicked;
        _errorMessage = '你已被移出房间';
        unawaited(_cleanupTransport(swallowErrors: true));
        _notify();
        return;
      case RoomRealtimeEventCodes.roomBanned:
        _status = RoomSessionStatus.closed;
        _errorMessage = '房间当前不可用';
        unawaited(_cleanupTransport(swallowErrors: true));
        _notify();
        return;
      case RoomRealtimeEventCodes.mutedInRoom:
        _mutedInRoom = true;
        _messages.add(
          const RoomMessage(
            sender: '系统',
            content: '你已被房间管理禁言。',
            isSystem: true,
          ),
        );
        _notify();
        return;
      case RoomRealtimeEventCodes.unmutedInRoom:
        _mutedInRoom = false;
        _messages.add(
          const RoomMessage(sender: '系统', content: '房间禁言已解除。', isSystem: true),
        );
        _notify();
        return;
      case RoomRealtimeEventCodes.putOnMic:
      case RoomRealtimeEventCodes.takeDownMic:
      case RoomRealtimeEventCodes.closeMic:
      case RoomRealtimeEventCodes.openMic:
      case RoomRealtimeEventCodes.micInfo:
      case RoomRealtimeEventCodes.roomTopic:
      case RoomRealtimeEventCodes.roomName:
      case RoomRealtimeEventCodes.roomAutoLock:
        unawaited(_refreshAfterRealtimeEvent());
        return;
      case RoomRealtimeEventCodes.pkInvited:
      case RoomRealtimeEventCodes.pkAccepted:
      case RoomRealtimeEventCodes.pkRejected:
      case RoomRealtimeEventCodes.pkProgress:
      case RoomRealtimeEventCodes.pkResult:
        return;
    }
  }

  Future<void> _refreshAfterRealtimeEvent() async {
    if (_refreshingFromEvent || _status != RoomSessionStatus.joined) {
      return;
    }
    _refreshingFromEvent = true;
    try {
      _snapshot = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      _notify();
    } catch (_) {
      _realtimeDegraded = true;
      _notify();
    } finally {
      _refreshingFromEvent = false;
    }
  }

  Future<void> _abandonEnteredRoom(RoomSnapshot snapshot) async {
    try {
      await _repository.exitRoom(snapshot.roomId);
    } catch (_) {
      // The route has already been abandoned. Best-effort server cleanup only.
    }
    await _cleanupTransport(swallowErrors: true);
    _status = RoomSessionStatus.left;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _cleanupTransport({required bool swallowErrors}) async {
    Object? firstError;
    final StreamSubscription<RoomRealtimeEvent>? subscription =
        _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      await _realtimeGateway.disconnect();
    } catch (error) {
      firstError ??= error;
    }
    try {
      await _rtcAdapter.leave();
    } catch (error) {
      firstError ??= error;
    }
    if (!swallowErrors && firstError != null) {
      throw firstError;
    }
  }

  MicSeat? _seatByNumber(int number) {
    for (final MicSeat seat in seats) {
      if (seat.number == number) {
        return seat;
      }
    }
    return null;
  }

  MicSeat? _ownSeat() {
    for (final MicSeat seat in seats) {
      if (seat.userId == _currentUserId) {
        return seat;
      }
    }
    return null;
  }

  static String _messageFor(Object error, {required String fallback}) =>
      error is ApiException ? error.message : fallback;

  @override
  void dispose() {
    _disposed = true;
    _joinCancelled = true;
    final StreamSubscription<RoomRealtimeEvent>? subscription =
        _realtimeSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    unawaited(_realtimeGateway.disconnect());
    unawaited(_rtcAdapter.leave());
    super.dispose();
  }
}
