import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_intent_digest.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

class RoomController extends ChangeNotifier {
  static final Random _secureRandom = Random.secure();
  static final Expando<Object> _rtcTransportOwners = Expando<Object>(
    'roomRtcTransportOwner',
  );
  static final Expando<Object> _realtimeTransportOwners = Expando<Object>(
    'roomRealtimeTransportOwner',
  );

  RoomController({
    required this.roomId,
    required this.title,
    required int currentUserId,
    required String accessToken,
    required RoomRepository repository,
    required RtcAdapter rtcAdapter,
    required RoomRealtimeGateway realtimeGateway,
    RoomOperationsRepository? roomOperationsRepository,
    RoomPermissionPolicy permissionPolicy = const RoomPermissionPolicy(),
    bool allowSyntheticPublicMessages = true,
    String Function(String prefix)? requestIdGenerator,
  }) : _currentUserId = currentUserId,
       _accessToken = accessToken,
       _repository = repository,
       _rtcAdapter = rtcAdapter,
       _realtimeGateway = realtimeGateway,
       _roomOperationsRepository = roomOperationsRepository,
       _permissionPolicy = permissionPolicy,
       _allowSyntheticPublicMessages = allowSyntheticPublicMessages,
       _requestIdGenerator = requestIdGenerator ?? _secureRequestId;

  final String roomId;
  final String title;
  final int _currentUserId;
  final String _accessToken;
  final RoomRepository _repository;
  final RtcAdapter _rtcAdapter;
  final RoomRealtimeGateway _realtimeGateway;
  final RoomOperationsRepository? _roomOperationsRepository;
  final RoomPermissionPolicy _permissionPolicy;
  final bool _allowSyntheticPublicMessages;
  final String Function(String prefix) _requestIdGenerator;

  RoomSnapshot? _snapshot;
  final List<RoomMessage> _messages = <RoomMessage>[];
  RoomSessionStatus _status = RoomSessionStatus.idle;
  StreamSubscription<RoomRealtimeEvent>? _realtimeSubscription;
  bool _micRequestPending = false;
  bool _micQueueLoading = false;
  final List<MicAccessRequest> _micRequests = <MicAccessRequest>[];
  int _micQueueEpoch = 0;
  bool _giftSubmitting = false;
  bool _realtimeDegraded = false;
  bool _mutedInRoom = false;
  // Publication is an explicit user intent. Entering or reconnecting a room
  // never infers this from an occupied seat; authority refreshes may revoke
  // it and must clear it before any provider call can publish again.
  bool _rtcAudioRequested = false;
  bool _rtcConnected = false;
  bool _rtcPublicationActive = false;
  Future<void> _rtcAudioTail = Future<void>.value();
  int _rtcAudioAuthorityGeneration = 0;
  bool _refreshingFromEvent = false;
  bool _joinCancelled = false;
  bool _disposed = false;
  int _sessionEpoch = 0;
  Object? _transportLeaseId;
  String? _errorMessage;
  String? _pendingJoinRequestRoomId;
  String? _pendingJoinRequestId;
  ApiFailureKind? _historyErrorKind;
  String? _historyErrorMessage;
  final Map<String, String> _publicMessageRetryIds = <String, String>{};
  final Map<String, _PublicMessageSubmission> _publicMessageInFlight =
      <String, _PublicMessageSubmission>{};
  Future<void> _publicMessageTail = Future<void>.value();
  String? _giftRequestId;
  String? _giftRequestKey;

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
  bool get micQueueLoading => _micQueueLoading;
  List<MicAccessRequest> get micRequests =>
      List<MicAccessRequest>.unmodifiable(_micRequests);
  MicCoordinationMode get micCoordinationMode {
    final String mode = _snapshot?.accessMode.trim().toUpperCase() ?? '';
    if (mode == 'APPROVAL') {
      return MicCoordinationMode.approval;
    }
    if (mode == 'PUBLIC' || mode == 'PASSWORD' || mode == 'DIRECT') {
      return MicCoordinationMode.direct;
    }
    return _roomOperationsRepository?.micCoordinationMode ??
        MicCoordinationMode.unavailable;
  }

  bool get giftSubmitting => _giftSubmitting;
  bool get realtimeDegraded => _realtimeDegraded;
  bool get isSnapshotOnly => _snapshot?.isSnapshotOnly ?? false;
  bool get allowsSyntheticPublicMessages =>
      _allowSyntheticPublicMessages && !isSnapshotOnly;
  bool get mutedInRoom => _mutedInRoom;
  bool get canSendPublicMessage =>
      !_mutedInRoom && allows(RoomCapability.sendPublicMessage);
  String? get errorMessage => _errorMessage;
  String? get pendingJoinRequestRoomId => _pendingJoinRequestRoomId;
  String? get pendingJoinRequestId => _pendingJoinRequestId;
  ApiFailureKind? get historyErrorKind => _historyErrorKind;
  String? get historyErrorMessage => _historyErrorMessage;

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
    if (_disposed) {
      return;
    }
    if (_status == RoomSessionStatus.joining ||
        _status == RoomSessionStatus.joined ||
        _status == RoomSessionStatus.reconnecting ||
        _status == RoomSessionStatus.leaving) {
      return;
    }
    final int sessionEpoch = ++_sessionEpoch;
    _joinCancelled = false;
    _pendingJoinRequestRoomId = null;
    _pendingJoinRequestId = null;
    _mutedInRoom = false;
    _rtcAudioRequested = false;
    _rtcConnected = false;
    _status = RoomSessionStatus.joining;
    _errorMessage = null;
    _historyErrorKind = null;
    _historyErrorMessage = null;
    _realtimeDegraded = false;
    _notify();

    RoomSnapshot? enteredSnapshot;
    Object? transportLease;
    try {
      final RoomSnapshot snapshot = await _repository.enterRoom(
        roomId: roomId,
        password: password,
        source: source,
        currentUserId: _currentUserId,
      );
      enteredSnapshot = snapshot;
      if (!_isCurrent(sessionEpoch) || _joinCancelled) {
        await _abandonEnteredRoom(snapshot, sessionEpoch: sessionEpoch);
        return;
      }
      if (!snapshot.isSnapshotOnly) {
        transportLease = _claimTransportLease();
        await _rtcAdapter.join(snapshot.rtc);
        _rtcConnected = true;
        _rtcPublicationActive = false;
        if (!_isCurrent(sessionEpoch) || _joinCancelled) {
          await _abandonEnteredRoom(snapshot, sessionEpoch: sessionEpoch);
          return;
        }
        await _replaceRealtimeSubscription(sessionEpoch: sessionEpoch);
        if (!_isCurrent(sessionEpoch) || _joinCancelled) {
          await _abandonEnteredRoom(snapshot, sessionEpoch: sessionEpoch);
          return;
        }
        try {
          await _realtimeGateway.connect(
            roomId: snapshot.roomId,
            userId: _currentUserId,
            accessToken: _accessToken,
          );
        } catch (_) {
          if (_isCurrent(sessionEpoch)) {
            _realtimeDegraded = true;
          }
        }
      }
      if (!_isCurrent(sessionEpoch) || _joinCancelled) {
        await _abandonEnteredRoom(snapshot, sessionEpoch: sessionEpoch);
        return;
      }
      _snapshot = snapshot;
      _messages
        ..clear()
        ..addAll(<RoomMessage>[
          if (_allowSyntheticPublicMessages && !snapshot.isSnapshotOnly)
            const RoomMessage(
              sender: '系统',
              content: '欢迎进入房间，请友善交流。',
              isSystem: true,
            ),
          if (_allowSyntheticPublicMessages &&
              !snapshot.isSnapshotOnly &&
              _realtimeDegraded)
            const RoomMessage(
              sender: '系统',
              content: '实时消息通道暂未连接，房间状态可能延迟。',
              isSystem: true,
            ),
        ]);
      _status = RoomSessionStatus.joined;
      await _loadPublicHistory(snapshot, sessionEpoch: sessionEpoch);
      if (micCoordinationMode == MicCoordinationMode.approval) {
        await _loadMicRequests(sessionEpoch: sessionEpoch);
      }
    } catch (error) {
      if (!_isCurrent(sessionEpoch) || _joinCancelled) {
        final RoomSnapshot? snapshot = enteredSnapshot;
        if (snapshot != null && _canCompensateJoin(sessionEpoch)) {
          try {
            await _repository.exitRoom(snapshot.roomId);
          } catch (_) {
            // The invalidating leave/dispose owns transport cleanup. Keep this
            // server-side compensation best effort and session-local.
          }
        }
        return;
      }
      final RoomSnapshot? snapshot = enteredSnapshot;
      if (snapshot != null && _canCompensateJoin(sessionEpoch)) {
        try {
          await _repository.exitRoom(snapshot.roomId);
        } catch (_) {
          // Preserve the original join failure while cleanup remains best effort.
        }
      }
      await _cleanupTransport(
        swallowErrors: true,
        transportLease: transportLease,
      );
      _errorMessage = _messageFor(error, fallback: '进入房间失败，请重试');
      if (error is RoomJoinRequestPendingException) {
        _pendingJoinRequestRoomId = error.roomId;
        _pendingJoinRequestId = error.joinRequestId;
      }
      _status = RoomSessionStatus.failed;
    }
    if (_isCurrent(sessionEpoch)) {
      _notify();
    }
  }

  Future<void> _loadPublicHistory(
    RoomSnapshot snapshot, {
    required int sessionEpoch,
  }) async {
    if (!_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    try {
      final List<RoomMessage> history = await _repository.fetchPublicMessages(
        snapshot.roomId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      _historyErrorKind = null;
      _historyErrorMessage = null;
      if (history.isEmpty) {
        return;
      }
      _messages
        ..clear()
        ..addAll(history);
      if (_allowSyntheticPublicMessages &&
          !snapshot.isSnapshotOnly &&
          _realtimeDegraded) {
        _messages.add(
          const RoomMessage(
            sender: '系统',
            content: '实时消息通道暂未连接，房间状态可能延迟。',
            isSystem: true,
          ),
        );
      }
    } catch (error) {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      _historyErrorKind = error is ApiException
          ? error.kind
          : ApiFailureKind.protocol;
      _historyErrorMessage = error is ApiException
          ? error.message
          : '公屏历史暂时不可用';
    }
  }

  Future<bool> requestMic(int seatNumber) async {
    if (_micRequestPending ||
        !allows(RoomCapability.requestMic) ||
        _status != RoomSessionStatus.joined) {
      return false;
    }
    final int sessionEpoch = _sessionEpoch;
    final MicSeat? seat = _seatByNumber(seatNumber);
    if (seat == null || !seat.isAvailable) {
      _errorMessage = '麦位状态已变化，请重新选择';
      _notify();
      return false;
    }
    if (micCoordinationMode == MicCoordinationMode.approval) {
      _invalidateMicQueueReads();
    }
    _micRequestPending = true;
    _errorMessage = null;
    _notify();
    bool serverMicMutationCommitted = false;
    final RoomSnapshot? previousSnapshot = _snapshot;
    try {
      if (micCoordinationMode == MicCoordinationMode.approval) {
        final RoomOperationsRepository? operations = _roomOperationsRepository;
        if (operations == null) {
          throw const ApiException(
            kind: ApiFailureKind.configuration,
            message: '审批房缺少上麦申请能力',
          );
        }
        await operations.submitMicRequest(
          roomId: roomId,
          userId: _currentUserId,
          seatNumber: seat.backendIndex,
        );
        if (!_isJoinedEpoch(sessionEpoch)) {
          return false;
        }
        await _loadMicRequests(sessionEpoch: sessionEpoch);
        if (allowsSyntheticPublicMessages) {
          _messages.add(
            RoomMessage(
              sender: '系统',
              content: '已提交 $seatNumber 号麦申请，等待房主或房管审批。',
              isSystem: true,
            ),
          );
        }
        return true;
      }
      if (micCoordinationMode == MicCoordinationMode.unavailable &&
          _roomOperationsRepository != null) {
        throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '房间未返回权威上麦协调能力',
        );
      }
      await _repository.requestMic(seat.backendIndex);
      serverMicMutationCommitted = true;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      final RoomSnapshot refreshed = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (!refreshed.seats.any(
        (MicSeat item) => item.userId == _currentUserId && item.isOccupied,
      )) {
        throw const ApiException(
          kind: ApiFailureKind.business,
          message: '麦位状态尚未确认，请刷新后重试',
        );
      }
      final int authorityGeneration = _rtcAudioAuthorityGeneration;
      final bool publishAudio = _snapshotAllowsRtcPublication(refreshed);
      await _reconcileRtcForSnapshot(refreshed, publishAudio: publishAudio);
      // A successful first-party seat mutation may still return a
      // snapshot-only projection when the token/readiness endpoint is
      // unavailable. Keep the server seat result, but never retain a local
      // publication intent that could later publish without a fresh token.
      _rtcAudioRequested =
          authorityGeneration == _rtcAudioAuthorityGeneration &&
          publishAudio &&
          _snapshotAllowsRtcPublication(refreshed);
      if (!_rtcAudioRequested && publishAudio) {
        await _disableRtcPublication();
      }
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      _snapshot = refreshed;
      serverMicMutationCommitted = false;
      if (allowsSyntheticPublicMessages) {
        _messages.add(
          RoomMessage(
            sender: '系统',
            content: '你已上 $seatNumber 号麦。',
            isSystem: true,
          ),
        );
      }
      return true;
    } catch (error) {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (serverMicMutationCommitted) {
        await _rollbackMicMutation(
          sessionEpoch: sessionEpoch,
          fallbackSnapshot: previousSnapshot,
        );
      }
      _errorMessage = _messageFor(error, fallback: '申请上麦失败');
      return false;
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _micRequestPending = false;
        _notify();
      }
    }
  }

  /// Reloads the authenticated member's queue projection. The backend
  /// intentionally scopes regular members to their own REQUEST/INVITE rows,
  /// so this is safe to call on every foreground refresh.
  Future<void> refreshMicRequests() async {
    if (_status != RoomSessionStatus.joined) {
      return;
    }
    await _loadMicRequests(sessionEpoch: _sessionEpoch);
  }

  Future<bool> cancelMicRequest(String requestId) async {
    if (_micRequestPending || _status != RoomSessionStatus.joined) {
      return false;
    }
    final RoomOperationsRepository? operations = _roomOperationsRepository;
    if (operations == null ||
        micCoordinationMode != MicCoordinationMode.approval) {
      return false;
    }
    final int sessionEpoch = _sessionEpoch;
    _invalidateMicQueueReads();
    _micRequestPending = true;
    _errorMessage = null;
    _notify();
    try {
      await operations.cancelMicRequest(requestId: requestId);
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      await _loadMicRequests(sessionEpoch: sessionEpoch);
      return true;
    } catch (error) {
      if (_isJoinedEpoch(sessionEpoch)) {
        _errorMessage = _messageFor(error, fallback: '撤回上麦申请失败');
      }
      return false;
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _micRequestPending = false;
        _notify();
      }
    }
  }

  Future<bool> resolveMicInvite({
    required String requestId,
    required bool accepted,
  }) async {
    if (_micRequestPending || _status != RoomSessionStatus.joined) {
      return false;
    }
    final RoomOperationsRepository? operations = _roomOperationsRepository;
    if (operations == null ||
        micCoordinationMode != MicCoordinationMode.approval) {
      return false;
    }
    final int sessionEpoch = _sessionEpoch;
    _invalidateMicQueueReads();
    _micRequestPending = true;
    _errorMessage = null;
    _notify();
    bool serverInviteMutationCommitted = false;
    final RoomSnapshot? previousSnapshot = _snapshot;
    try {
      await operations.resolveMicRequest(
        requestId: requestId,
        accepted: accepted,
      );
      serverInviteMutationCommitted = true;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (accepted) {
        final RoomSnapshot refreshed = await _repository.reconnectRoom(
          roomId: roomId,
          currentUserId: _currentUserId,
        );
        if (!_isJoinedEpoch(sessionEpoch)) {
          return false;
        }
        final MicSeat? ownSeat = _seatInSnapshot(refreshed);
        if (ownSeat == null || !ownSeat.isOccupied) {
          throw const ApiException(
            kind: ApiFailureKind.business,
            message: '麦位状态尚未确认，请刷新后重试',
          );
        }
        final int authorityGeneration = _rtcAudioAuthorityGeneration;
        final bool publishAudio = _snapshotAllowsRtcPublication(refreshed);
        await _reconcileRtcForSnapshot(refreshed, publishAudio: publishAudio);
        _rtcAudioRequested =
            authorityGeneration == _rtcAudioAuthorityGeneration &&
            publishAudio &&
            _snapshotAllowsRtcPublication(refreshed);
        if (!_rtcAudioRequested && publishAudio) {
          await _disableRtcPublication();
        }
        if (!_isJoinedEpoch(sessionEpoch)) {
          return false;
        }
        _snapshot = refreshed;
      }
      serverInviteMutationCommitted = false;
      await _loadMicRequests(sessionEpoch: sessionEpoch);
      return true;
    } catch (error) {
      if (_isJoinedEpoch(sessionEpoch) && serverInviteMutationCommitted) {
        await _rollbackInviteMutation(
          operations,
          requestId: requestId,
          sessionEpoch: sessionEpoch,
          fallbackSnapshot: previousSnapshot,
        );
      }
      if (_isJoinedEpoch(sessionEpoch)) {
        _errorMessage = _messageFor(error, fallback: '处理上麦邀请失败');
      }
      return false;
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _micRequestPending = false;
        _notify();
      }
    }
  }

  Future<void> _loadMicRequests({required int sessionEpoch}) async {
    final RoomOperationsRepository? operations = _roomOperationsRepository;
    if (operations == null ||
        !_isJoinedEpoch(sessionEpoch) ||
        micCoordinationMode != MicCoordinationMode.approval) {
      return;
    }
    final int queueEpoch = ++_micQueueEpoch;
    _micQueueLoading = true;
    _notify();
    try {
      final List<MicAccessRequest> requests = await operations.fetchMicRequests(
        roomId,
      );
      if (_isJoinedEpoch(sessionEpoch) && queueEpoch == _micQueueEpoch) {
        _micRequests
          ..clear()
          ..addAll(requests);
      }
    } catch (error) {
      if (_isJoinedEpoch(sessionEpoch) && queueEpoch == _micQueueEpoch) {
        _errorMessage = _messageFor(error, fallback: '上麦申请状态暂时不可用');
      }
    } finally {
      if (_isCurrent(sessionEpoch) && queueEpoch == _micQueueEpoch) {
        _micQueueLoading = false;
        _notify();
      }
    }
  }

  void _invalidateMicQueueReads() {
    _micQueueEpoch += 1;
    _micQueueLoading = false;
  }

  Future<bool> leaveMic() async {
    if (!allows(RoomCapability.leaveMic) ||
        _status != RoomSessionStatus.joined) {
      return false;
    }
    final int sessionEpoch = _sessionEpoch;
    bool serverMicMutationCommitted = false;
    try {
      await _repository.leaveMic();
      serverMicMutationCommitted = true;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      final RoomSnapshot refreshed = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      await _reconcileRtcForSnapshot(refreshed, publishAudio: false);
      _rtcAudioRequested = false;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      _snapshot = refreshed;
      serverMicMutationCommitted = false;
      if (allowsSyntheticPublicMessages) {
        _messages.add(
          const RoomMessage(sender: '系统', content: '你已离开麦位。', isSystem: true),
        );
      }
      _notify();
      return true;
    } catch (error) {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (serverMicMutationCommitted) {
        // The first-party leave has already committed. Reconcile the local
        // snapshot and leave any stale provider channel rather than retaining
        // a publisher token after the member is off mic.
        try {
          await _rtcAdapter.leave();
        } catch (_) {
          // Preserve the original operation error.
        }
        try {
          final RoomSnapshot refreshed = await _repository.reconnectRoom(
            roomId: roomId,
            currentUserId: _currentUserId,
          );
          if (_isJoinedEpoch(sessionEpoch)) {
            await _reconcileRtcForSnapshot(refreshed, publishAudio: false);
          }
          if (_isJoinedEpoch(sessionEpoch)) {
            _snapshot = refreshed;
          }
        } catch (_) {
          // Keep the previous snapshot if the compensating read is unavailable.
        }
      }
      _errorMessage = _messageFor(error, fallback: '下麦失败');
      _notify();
      return false;
    }
  }

  Future<bool> toggleMicrophone() {
    if (!allows(RoomCapability.toggleMicrophone) ||
        _status != RoomSessionStatus.joined ||
        _mutedInRoom) {
      return Future<bool>.value(false);
    }
    return _withRtcAudioMutex<bool>(_toggleMicrophoneLocked);
  }

  Future<bool> _toggleMicrophoneLocked() async {
    if (!allows(RoomCapability.toggleMicrophone) ||
        _status != RoomSessionStatus.joined ||
        _mutedInRoom) {
      return false;
    }
    final int sessionEpoch = _sessionEpoch;
    final MicSeat? ownSeat = _ownSeat();
    if (ownSeat == null) {
      return false;
    }
    final bool nextMuted = !micMuted;
    final int authorityGeneration = _rtcAudioAuthorityGeneration;
    bool serverMicMutationCommitted = false;
    try {
      await _repository.setSelfMicrophoneMuted(
        backendMicIndex: ownSeat.backendIndex,
        muted: nextMuted,
      );
      serverMicMutationCommitted = true;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      final bool publishAudio =
          !nextMuted &&
          authorityGeneration == _rtcAudioAuthorityGeneration &&
          _snapshotAllowsRtcTogglePublication();
      await _rtcAdapter.setLocalAudioEnabled(publishAudio);
      _rtcPublicationActive = publishAudio;
      final bool authorityStillCurrent =
          authorityGeneration == _rtcAudioAuthorityGeneration &&
          _isJoinedEpoch(sessionEpoch) &&
          !_mutedInRoom &&
          (!publishAudio || _snapshotAllowsRtcTogglePublication());
      if (!authorityStillCurrent && _rtcPublicationActive) {
        await _rtcAdapter.setLocalAudioEnabled(false);
        _rtcPublicationActive = false;
      }
      _rtcAudioRequested = authorityStillCurrent && publishAudio;
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
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
      serverMicMutationCommitted = false;
      _notify();
      return true;
    } catch (error) {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (serverMicMutationCommitted) {
        try {
          await _repository.setSelfMicrophoneMuted(
            backendMicIndex: ownSeat.backendIndex,
            muted: !nextMuted,
          );
        } catch (_) {
          // Preserve the original error while keeping the rollback best effort.
        }
        final bool restoreAudio =
            nextMuted &&
            authorityGeneration == _rtcAudioAuthorityGeneration &&
            !_mutedInRoom &&
            _snapshotAllowsRtcTogglePublication();
        try {
          await _rtcAdapter.setLocalAudioEnabled(restoreAudio);
          _rtcPublicationActive = restoreAudio;
          _rtcAudioRequested = restoreAudio;
        } catch (_) {
          // Keep the transport muted if permission or provider state prevents
          // restoring the previous publication state.
          _rtcPublicationActive = false;
          _rtcAudioRequested = false;
        }
      }
      _errorMessage = _messageFor(error, fallback: '麦克风状态更新失败');
      _notify();
      return false;
    }
  }

  Future<bool> sendPublicMessage(String content) {
    final String normalized = content.trim();
    final RoomSnapshot? snapshot = _snapshot;
    if (normalized.isEmpty ||
        snapshot == null ||
        _status != RoomSessionStatus.joined ||
        !canSendPublicMessage) {
      return Future<bool>.value(false);
    }
    final String intentKey = roomIntentDigest(
      scope: 'public-message',
      fields: <String>[snapshot.roomId, normalized],
    );
    final _PublicMessageSubmission? existing =
        _publicMessageInFlight[intentKey];
    if (existing != null) {
      return existing.future;
    }

    final int sessionEpoch = _sessionEpoch;
    final String requestId =
        _publicMessageRetryIds.remove(intentKey) ?? _newRequestId('room-chat');
    late final _PublicMessageSubmission submission;
    final Future<bool> operation = _publicMessageTail.then<bool>((_) async {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      try {
        final RoomMessage message = await _repository.sendPublicMessage(
          roomId: snapshot.roomId,
          content: normalized,
          requestId: requestId,
        );
        if (!_isJoinedEpoch(sessionEpoch)) {
          return false;
        }
        _appendAuthoritativeMessage(message);
        _publicMessageRetryIds.remove(intentKey);
        _notify();
        return true;
      } catch (error) {
        if (!_isJoinedEpoch(sessionEpoch)) {
          return false;
        }
        if (_isRetryableRequestError(error)) {
          _publicMessageRetryIds[intentKey] = requestId;
        } else {
          _publicMessageRetryIds.remove(intentKey);
        }
        _errorMessage = _messageFor(error, fallback: '消息发送失败');
        _notify();
        return false;
      }
    });
    submission = _PublicMessageSubmission(operation);
    _publicMessageInFlight[intentKey] = submission;
    operation.whenComplete(() {
      if (identical(_publicMessageInFlight[intentKey], submission)) {
        _publicMessageInFlight.remove(intentKey);
      }
    });
    _publicMessageTail = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> sendGift({
    required String giftId,
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
    final int sessionEpoch = _sessionEpoch;
    final String requestKey = roomIntentDigest(
      scope: 'controller-gift',
      fields: <String>[
        snapshot.roomId,
        giftId.trim(),
        '$receiverUserId',
        '$quantity',
        '$giftFrom',
      ],
    );
    if (_giftRequestKey != requestKey || _giftRequestId == null) {
      _giftRequestKey = requestKey;
      _giftRequestId = _newRequestId('room-gift');
    }
    final String requestId = _giftRequestId!;
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
        requestId: requestId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (!receipt.success) {
        _giftRequestId = null;
        _giftRequestKey = null;
        _errorMessage = '礼物赠送未完成，请刷新余额后重试';
        return false;
      }
      final int? remainingBalance = receipt.remainingBalance;
      if (remainingBalance != null) {
        _snapshot = snapshot.copyWith(giftBalance: remainingBalance);
      }
      _giftRequestId = null;
      _giftRequestKey = null;
      await _loadPublicHistory(snapshot, sessionEpoch: sessionEpoch);
      return true;
    } catch (error) {
      if (!_isJoinedEpoch(sessionEpoch)) {
        return false;
      }
      if (_isRetryableRequestError(error)) {
        final bool recovered = await _recoverGiftAfterRetryableFailure(
          snapshot: snapshot,
          sessionEpoch: sessionEpoch,
          requestId: requestId,
        );
        if (recovered) {
          return true;
        }
      } else {
        _giftRequestId = null;
        _giftRequestKey = null;
      }
      _errorMessage = _messageFor(error, fallback: '礼物赠送失败');
      return false;
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _giftSubmitting = false;
        _notify();
      }
    }
  }

  /// Recovers a first-party gift after an ambiguous send without retrying the
  /// economic write. When no transfer id is known, the retained send request
  /// id is used and the authenticated controller user is always forwarded as
  /// the participant scope.
  Future<GiftReceipt?> fetchGiftReceipt({
    String? transferId,
    String? requestId,
  }) async {
    final RoomSnapshot? snapshot = _snapshot;
    if (_status != RoomSessionStatus.joined || snapshot == null) {
      return null;
    }
    final int sessionEpoch = _sessionEpoch;
    final GiftReceipt? receipt = await _readGiftReceipt(
      sessionEpoch: sessionEpoch,
      transferId: transferId,
      requestId: requestId,
      failureFallback: '礼物回执查询失败',
      setErrorOnFailure: true,
    );
    if (receipt == null) {
      if (_isJoinedEpoch(sessionEpoch)) {
        _notify();
      }
      return null;
    }
    if (receipt.success) {
      await _applySuccessfulGiftReceipt(
        receipt,
        snapshot: snapshot,
        sessionEpoch: sessionEpoch,
        refreshHistory: true,
      );
      if (_isJoinedEpoch(sessionEpoch)) {
        _notify();
      }
    }
    return _isJoinedEpoch(sessionEpoch) ? receipt : null;
  }

  Future<GiftReceipt?> queryGiftReceipt({
    String? transferId,
    String? requestId,
  }) => fetchGiftReceipt(transferId: transferId, requestId: requestId);

  Future<void> reconnect() async {
    if (_status != RoomSessionStatus.joined) {
      return;
    }
    final int sessionEpoch = _sessionEpoch;
    _status = RoomSessionStatus.reconnecting;
    _errorMessage = null;
    _notify();
    try {
      final RoomSnapshot snapshot = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isCurrent(sessionEpoch)) {
        return;
      }
      if (!snapshot.isSnapshotOnly) {
        _claimTransportLease();
        final bool publishAudio =
            _rtcAudioRequested && _snapshotAllowsRtcPublication(snapshot);
        if (!publishAudio && _rtcAudioRequested) {
          // A reconnect response is authoritative. If the member lost the
          // seat, was muted, or was downgraded to audience, stop publication
          // before applying the replacement token/role.
          _rtcAudioRequested = false;
          await _disableRtcPublication();
        }
        await _reconcileRtcForSnapshot(
          snapshot,
          publishAudio: publishAudio,
          forceReconnect: true,
        );
        _rtcConnected = true;
        if (!_isCurrent(sessionEpoch)) {
          return;
        }
        try {
          await _realtimeGateway.reconnect();
          if (_isCurrent(sessionEpoch)) {
            _realtimeDegraded = false;
          }
        } catch (_) {
          if (_isCurrent(sessionEpoch)) {
            _realtimeDegraded = true;
          }
        }
      } else {
        await _withRtcAudioMutex<void>(_rtcAdapter.leave);
        _rtcConnected = false;
        _rtcPublicationActive = false;
        _rtcAudioRequested = false;
        _realtimeDegraded = false;
      }
      if (!_isCurrent(sessionEpoch)) {
        return;
      }
      _snapshot = snapshot;
      if (_allowSyntheticPublicMessages && !snapshot.isSnapshotOnly) {
        _messages.add(
          const RoomMessage(
            sender: '系统',
            content: '已恢复连接。断线期间公屏消息可能未显示。',
            isSystem: true,
          ),
        );
      }
      _status = RoomSessionStatus.joined;
    } catch (error) {
      if (!_isCurrent(sessionEpoch)) {
        return;
      }
      _errorMessage = _messageFor(error, fallback: '房间恢复失败，请重试');
      _realtimeDegraded = true;
      _status = _snapshot == null
          ? RoomSessionStatus.failed
          : RoomSessionStatus.joined;
    }
    if (_isCurrent(sessionEpoch)) {
      _notify();
    }
  }

  Future<bool> leaveRoom() async {
    if (_status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left) {
      return false;
    }
    final RoomSessionStatus previousStatus = _status;
    final Object? transportLease = _transportLeaseId;
    final int sessionEpoch = _invalidateSession();
    if (_status == RoomSessionStatus.joining ||
        _status == RoomSessionStatus.idle ||
        (_status == RoomSessionStatus.failed && _snapshot == null)) {
      _joinCancelled = true;
      _status = RoomSessionStatus.left;
      await _cleanupTransport(
        swallowErrors: true,
        transportLease: transportLease,
      );
      if (!_isCurrent(sessionEpoch)) {
        return false;
      }
      _notify();
      return true;
    }
    _status = RoomSessionStatus.leaving;
    _errorMessage = null;
    _notify();
    try {
      await _repository.exitRoom(_snapshot?.roomId ?? roomId);
      if (!_isCurrent(sessionEpoch)) {
        return false;
      }
      await _cleanupTransport(
        swallowErrors: true,
        transportLease: transportLease,
      );
      if (!_isCurrent(sessionEpoch)) {
        return false;
      }
      _status = RoomSessionStatus.left;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrent(sessionEpoch)) {
        return false;
      }
      _errorMessage = _messageFor(error, fallback: '离开房间失败，请重试');
      _status = previousStatus;
      _notify();
      return false;
    }
  }

  void clearError() {
    if (_errorMessage == null &&
        _historyErrorKind == null &&
        _historyErrorMessage == null) {
      return;
    }
    _errorMessage = null;
    _historyErrorKind = null;
    _historyErrorMessage = null;
    _notify();
  }

  Future<void> _replaceRealtimeSubscription({required int sessionEpoch}) async {
    final StreamSubscription<RoomRealtimeEvent>? previous =
        _realtimeSubscription;
    _realtimeSubscription = null;
    await previous?.cancel();
    if (!_isCurrent(sessionEpoch)) {
      return;
    }
    final StreamSubscription<RoomRealtimeEvent> subscription = _realtimeGateway
        .events
        .listen(
          (RoomRealtimeEvent event) =>
              _handleRealtimeEvent(event, sessionEpoch: sessionEpoch),
          onError: (Object _, StackTrace __) {
            if (_isCurrent(sessionEpoch)) {
              _realtimeDegraded = true;
              _notify();
            }
          },
        );
    if (!_isCurrent(sessionEpoch)) {
      unawaited(subscription.cancel());
      return;
    }
    _realtimeSubscription = subscription;
  }

  void _handleRealtimeEvent(RoomRealtimeEvent event, {int? sessionEpoch}) {
    if (_disposed ||
        (sessionEpoch != null && !_isCurrent(sessionEpoch)) ||
        (sessionEpoch == null && !_isCurrent(_sessionEpoch))) {
      return;
    }
    if (!RoomRealtimeEventCodes.allowed.contains(event.code)) {
      return;
    }
    if (_isRtcAuthorityEvent(event.code)) {
      _rtcAudioAuthorityGeneration += 1;
    }
    final int activeEpoch = sessionEpoch ?? _sessionEpoch;
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
        final Object? transportLease = _transportLeaseId;
        _invalidateSession();
        _status = RoomSessionStatus.kicked;
        _errorMessage = '你已被移出房间';
        unawaited(
          _cleanupTransport(
            swallowErrors: true,
            transportLease: transportLease,
          ),
        );
        _notify();
        return;
      case RoomRealtimeEventCodes.roomBanned:
        final Object? transportLease = _transportLeaseId;
        _invalidateSession();
        _status = RoomSessionStatus.closed;
        _errorMessage = '房间当前不可用';
        unawaited(
          _cleanupTransport(
            swallowErrors: true,
            transportLease: transportLease,
          ),
        );
        _notify();
        return;
      case RoomRealtimeEventCodes.mutedInRoom:
        _mutedInRoom = true;
        _rtcAudioRequested = false;
        unawaited(_disableRtcPublication());
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
        unawaited(_refreshAfterRealtimeEvent(sessionEpoch: activeEpoch));
        return;
      case RoomRealtimeEventCodes.takeDownMic:
      case RoomRealtimeEventCodes.closeMic:
        _rtcAudioRequested = false;
        unawaited(_disableRtcPublication());
        unawaited(_refreshAfterRealtimeEvent(sessionEpoch: activeEpoch));
        return;
      case RoomRealtimeEventCodes.openMic:
      case RoomRealtimeEventCodes.micInfo:
      case RoomRealtimeEventCodes.roomTopic:
      case RoomRealtimeEventCodes.roomName:
      case RoomRealtimeEventCodes.roomAutoLock:
        unawaited(_refreshAfterRealtimeEvent(sessionEpoch: activeEpoch));
        return;
      case RoomRealtimeEventCodes.pkInvited:
      case RoomRealtimeEventCodes.pkAccepted:
      case RoomRealtimeEventCodes.pkRejected:
      case RoomRealtimeEventCodes.pkProgress:
      case RoomRealtimeEventCodes.pkResult:
        return;
    }
  }

  Future<void> _refreshAfterRealtimeEvent({required int sessionEpoch}) async {
    if (_refreshingFromEvent || !_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    _refreshingFromEvent = true;
    final RoomSnapshot? previous = _snapshot;
    try {
      final RoomSnapshot refreshed = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      Object? rtcError;
      try {
        await _reconcileAuthoritativeRtc(previous, refreshed);
      } catch (_) {
        // The HTTP snapshot remains authoritative even when the provider
        // transport cannot apply it. Publication is fail-closed and the next
        // explicit mic action will obtain another server token.
        rtcError = const RtcAdapterException(
          failure: RtcAdapterFailure.provider,
          message: '实时音频通道暂时不可用',
        );
        _rtcAudioRequested = false;
        await _disableRtcPublication();
      }
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      _snapshot = refreshed;
      if (rtcError != null) {
        _realtimeDegraded = true;
        _errorMessage = (rtcError as RtcAdapterException).message;
      }
      _notify();
    } catch (_) {
      if (_isJoinedEpoch(sessionEpoch)) {
        _realtimeDegraded = true;
        _notify();
      }
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _refreshingFromEvent = false;
      }
    }
  }

  Future<void> _abandonEnteredRoom(
    RoomSnapshot snapshot, {
    required int sessionEpoch,
  }) async {
    if (_canCompensateJoin(sessionEpoch)) {
      try {
        await _repository.exitRoom(snapshot.roomId);
      } catch (_) {
        // The route has already been abandoned. Best-effort server cleanup only.
      }
    }
    // The invalidating leave, kick/close, or dispose owns transport cleanup.
    // Cleaning it here could disconnect a newer session that reused the
    // shared adapter while this stale join was compensating on the server.
    if (_isCurrent(sessionEpoch)) {
      await _cleanupTransport(
        swallowErrors: true,
        transportLease: _transportLeaseId,
      );
      _status = RoomSessionStatus.left;
      _notify();
    }
  }

  bool _canCompensateJoin(int sessionEpoch) {
    if (_sessionEpoch == sessionEpoch || _disposed) {
      return true;
    }
    return _status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left ||
        _status == RoomSessionStatus.closed ||
        _status == RoomSessionStatus.kicked;
  }

  int _invalidateSession() {
    _sessionEpoch += 1;
    _rtcAudioAuthorityGeneration += 1;
    _micQueueEpoch += 1;
    _joinCancelled = true;
    _micRequestPending = false;
    _micQueueLoading = false;
    _micRequests.clear();
    _giftSubmitting = false;
    _publicMessageRetryIds.clear();
    _publicMessageInFlight.clear();
    _publicMessageTail = Future<void>.value();
    _giftRequestId = null;
    _giftRequestKey = null;
    _historyErrorKind = null;
    _historyErrorMessage = null;
    _refreshingFromEvent = false;
    _rtcAudioRequested = false;
    _rtcConnected = false;
    _rtcPublicationActive = false;
    return _sessionEpoch;
  }

  bool _isCurrent(int sessionEpoch) =>
      !_disposed && sessionEpoch == _sessionEpoch;

  bool _isJoinedEpoch(int sessionEpoch) =>
      _isCurrent(sessionEpoch) && _status == RoomSessionStatus.joined;

  Object _claimTransportLease() {
    final Object lease = Object();
    _transportLeaseId = lease;
    _rtcTransportOwners[_rtcAdapter] = lease;
    _realtimeTransportOwners[_realtimeGateway] = lease;
    return lease;
  }

  bool _ownsRtcTransport(Object? transportLease) =>
      transportLease != null &&
      _rtcTransportOwners[_rtcAdapter] == transportLease;

  Future<void> _leaveOwnedRtcTransport(Object transportLease) async {
    await _withRtcAudioMutex<void>(() async {
      // The lease may have been handed to a newer controller while this
      // cleanup waited behind an older audio operation. Never let a stale
      // queued cleanup leave that newer session.
      if (!_ownsRtcTransport(transportLease)) {
        return;
      }
      try {
        await _rtcAdapter.leave();
      } finally {
        if (_ownsRtcTransport(transportLease)) {
          _rtcTransportOwners[_rtcAdapter] = null;
        }
      }
    });
  }

  Future<void> _disposeOwnedRtcTransport(Object transportLease) async {
    try {
      await _leaveOwnedRtcTransport(transportLease);
    } catch (_) {
      // Disposal is best effort; the controller is already terminal and must
      // not surface an asynchronous provider error.
    }
  }

  bool _ownsRealtimeTransport(Object? transportLease) =>
      transportLease != null &&
      _realtimeTransportOwners[_realtimeGateway] == transportLease;

  /// Reconciles a first-party room snapshot with the provider transport. A
  /// snapshot-only response tears down any previously joined provider channel;
  /// an interactive response always rejoins with its current role/token before
  /// the caller explicitly chooses whether to publish audio.
  Future<void> _reconcileRtcForSnapshot(
    RoomSnapshot snapshot, {
    required bool publishAudio,
    bool forceReconnect = true,
  }) async {
    if (_disposed) {
      return;
    }
    if (snapshot.isSnapshotOnly) {
      await _withRtcAudioMutex<void>(_rtcAdapter.leave);
      _rtcConnected = false;
      _rtcPublicationActive = false;
      _rtcAudioRequested = false;
      return;
    }
    final int authorityGeneration = _rtcAudioAuthorityGeneration;
    try {
      await _withRtcAudioMutex<void>(() async {
        // Keep reconnect and the subsequent publication update in the same
        // serialized operation. Otherwise a local toggle could run between
        // them and be silently replaced by a stale role/token transition.
        if (_disposed || authorityGeneration != _rtcAudioAuthorityGeneration) {
          return;
        }
        if (forceReconnect || !_rtcConnected) {
          await _rtcAdapter.reconnect(snapshot.rtc);
          if (_disposed ||
              authorityGeneration != _rtcAudioAuthorityGeneration) {
            return;
          }
          _rtcConnected = true;
          _rtcPublicationActive = false;
        }
        // Re-evaluate authority after any reconnect await and immediately
        // before the native publication call. A realtime mute can arrive in
        // that window and must turn this into a safe disable.
        final bool effectivePublishAudio =
            publishAudio &&
            authorityGeneration == _rtcAudioAuthorityGeneration &&
            _snapshotAllowsRtcPublication(snapshot);
        await _rtcAdapter.setLocalAudioEnabled(effectivePublishAudio);
        _rtcPublicationActive = effectivePublishAudio;
        if (effectivePublishAudio &&
            (_disposed ||
                authorityGeneration != _rtcAudioAuthorityGeneration ||
                !_snapshotAllowsRtcPublication(snapshot))) {
          await _rtcAdapter.setLocalAudioEnabled(false);
          _rtcPublicationActive = false;
        }
      });
    } catch (_) {
      _rtcConnected = false;
      _rtcPublicationActive = false;
      rethrow;
    }
  }

  Future<void> _reconcileAuthoritativeRtc(
    RoomSnapshot? previous,
    RoomSnapshot refreshed,
  ) async {
    final bool wasAudioRequested = _rtcAudioRequested;
    final bool mayPublish = _snapshotAllowsRtcPublication(refreshed);
    final bool shouldPublish = _rtcAudioRequested && mayPublish;
    if (!mayPublish && wasAudioRequested) {
      // This is intentionally done before applying a replacement role/token.
      // A stale publisher must never remain live while a seat revoke or mute
      // is being reconciled.
      _rtcAudioRequested = false;
      await _disableRtcPublication();
    }

    if (refreshed.isSnapshotOnly) {
      await _reconcileRtcForSnapshot(refreshed, publishAudio: false);
      return;
    }

    final bool transportChanged =
        previous == null || previous.isSnapshotOnly != refreshed.isSnapshotOnly;
    final bool roleOrIdentityChanged =
        previous == null ||
        previous.rtc.provider.trim().toLowerCase() !=
            refreshed.rtc.provider.trim().toLowerCase() ||
        previous.rtc.appId != refreshed.rtc.appId ||
        previous.rtc.channelId != refreshed.rtc.channelId ||
        previous.rtc.uid != refreshed.rtc.uid ||
        previous.rtc.role.trim().toLowerCase() !=
            refreshed.rtc.role.trim().toLowerCase();
    final bool tokenChanged =
        previous == null || previous.rtc.token != refreshed.rtc.token;
    final bool needsReconnect =
        !_rtcConnected ||
        transportChanged ||
        roleOrIdentityChanged ||
        // A refreshed token is authoritative even after publication was
        // revoked above. Otherwise a broadcaster whose seat was removed
        // would stay joined with the old token and could later publish with
        // stale credentials when the seat is granted again.
        tokenChanged;

    await _reconcileRtcForSnapshot(
      refreshed,
      publishAudio: shouldPublish,
      forceReconnect: needsReconnect,
    );
  }

  bool _snapshotAllowsRtcPublication(RoomSnapshot snapshot) {
    if (snapshot.isSnapshotOnly || _mutedInRoom) {
      return false;
    }
    final MicSeat? ownSeat = _seatInSnapshot(snapshot);
    if (ownSeat == null ||
        !ownSeat.isOccupied ||
        ownSeat.state == MicSeatState.occupiedMuted) {
      return false;
    }
    return switch (snapshot.rtc.role.trim().toLowerCase()) {
      'broadcaster' || 'publisher' || 'host' || 'speaker' || 'anchor' => true,
      _ => false,
    };
  }

  /// Checks the stable authority needed for a local mic toggle. The seat's
  /// occupied-muted bit is intentionally ignored here because the next local
  /// unmute operation is the action that changes that bit; all realtime
  /// authority changes invalidate the captured generation before publication.
  bool _snapshotAllowsRtcTogglePublication() {
    final RoomSnapshot? snapshot = _snapshot;
    if (snapshot == null || snapshot.isSnapshotOnly || _mutedInRoom) {
      return false;
    }
    final MicSeat? ownSeat = _ownSeat();
    if (ownSeat == null || !ownSeat.isOccupied) {
      return false;
    }
    return switch (snapshot.rtc.role.trim().toLowerCase()) {
      'broadcaster' || 'publisher' || 'host' || 'speaker' || 'anchor' => true,
      _ => false,
    };
  }

  bool _isRtcAuthorityEvent(int code) {
    return switch (code) {
      RoomRealtimeEventCodes.mutedInRoom ||
      RoomRealtimeEventCodes.unmutedInRoom ||
      RoomRealtimeEventCodes.putOnMic ||
      RoomRealtimeEventCodes.takeDownMic ||
      RoomRealtimeEventCodes.closeMic ||
      RoomRealtimeEventCodes.openMic ||
      RoomRealtimeEventCodes.micInfo ||
      RoomRealtimeEventCodes.roomAutoLock => true,
      _ => false,
    };
  }

  MicSeat? _seatInSnapshot(RoomSnapshot snapshot) {
    for (final MicSeat seat in snapshot.seats) {
      if (seat.userId == _currentUserId) {
        return seat;
      }
    }
    return null;
  }

  Future<void> _disableRtcPublication() async {
    await _withRtcAudioMutex<void>(() async {
      if (!_rtcConnected && !_rtcPublicationActive) {
        return;
      }
      try {
        await _rtcAdapter.setLocalAudioEnabled(false);
      } catch (_) {
        // If a provider refuses the mute operation during a role revoke, leave
        // the channel so publication is still fail-closed.
        try {
          await _rtcAdapter.leave();
        } catch (_) {
          // Preserve the authority refresh result; the next action retries.
        }
        _rtcConnected = false;
      } finally {
        _rtcPublicationActive = false;
      }
    });
  }

  Future<T> _withRtcAudioMutex<T>(Future<T> Function() operation) {
    final Future<void> previous = _rtcAudioTail;
    final Completer<void> release = Completer<void>();
    final Future<void> ready = previous.catchError(
      (Object _, StackTrace __) {},
    );
    final Future<T> result = ready.then<T>((_) async {
      try {
        return await operation();
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
      }
    });
    _rtcAudioTail = ready.then<void>((_) => release.future);
    return result;
  }

  Future<void> _rollbackMicMutation({
    required int sessionEpoch,
    required RoomSnapshot? fallbackSnapshot,
  }) async {
    try {
      await _repository.leaveMic();
    } catch (_) {
      // Preserve the original failure; the authority rollback is best effort.
    }
    if (!_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    try {
      final RoomSnapshot restored = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      await _reconcileRtcForSnapshot(restored, publishAudio: false);
      if (_isJoinedEpoch(sessionEpoch)) {
        _snapshot = restored;
      }
    } catch (_) {
      try {
        await _rtcAdapter.leave();
      } catch (_) {
        // Keep rollback best effort and retain the original failure.
      }
      if (_isJoinedEpoch(sessionEpoch) && fallbackSnapshot != null) {
        _snapshot = fallbackSnapshot;
      }
    }
  }

  Future<void> _rollbackInviteMutation(
    RoomOperationsRepository operations, {
    required String requestId,
    required int sessionEpoch,
    required RoomSnapshot? fallbackSnapshot,
  }) async {
    try {
      await operations.resolveMicRequest(requestId: requestId, accepted: false);
    } catch (_) {
      // Preserve the original failure; an accepted invite may be immutable.
    }
    if (!_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    try {
      final RoomSnapshot restored = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(sessionEpoch)) {
        return;
      }
      await _reconcileRtcForSnapshot(restored, publishAudio: false);
      if (_isJoinedEpoch(sessionEpoch)) {
        _snapshot = restored;
      }
    } catch (_) {
      try {
        await _rtcAdapter.leave();
      } catch (_) {
        // Keep rollback best effort and retain the original failure.
      }
      if (_isJoinedEpoch(sessionEpoch) && fallbackSnapshot != null) {
        _snapshot = fallbackSnapshot;
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _cleanupTransport({
    required bool swallowErrors,
    Object? transportLease,
  }) async {
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
    if (_ownsRealtimeTransport(transportLease)) {
      try {
        await _realtimeGateway.disconnect();
      } catch (error) {
        firstError ??= error;
      }
      if (_ownsRealtimeTransport(transportLease)) {
        _realtimeTransportOwners[_realtimeGateway] = null;
      }
    }
    if (_ownsRtcTransport(transportLease)) {
      try {
        await _leaveOwnedRtcTransport(transportLease!);
      } catch (error) {
        firstError ??= error;
      }
      _rtcConnected = false;
      _rtcPublicationActive = false;
      _rtcAudioRequested = false;
    }
    if (_transportLeaseId == transportLease) {
      _transportLeaseId = null;
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

  static bool _isRetryableRequestError(Object error) {
    if (error is! ApiException) {
      // A transport/client exception without a classified kind may have
      // happened after the server committed the write. Preserve the same
      // idempotency key until the caller gets an authoritative answer.
      return true;
    }
    if (error.code == 40901 || error.code == 40902) {
      return true;
    }
    if (error.code == 40903) {
      return false;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.configuration ||
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden ||
      ApiFailureKind.validation ||
      ApiFailureKind.conflict ||
      ApiFailureKind.business => false,
    };
  }

  Future<bool> _recoverGiftAfterRetryableFailure({
    required RoomSnapshot snapshot,
    required int sessionEpoch,
    required String requestId,
  }) async {
    final GiftReceipt? receipt = await _readGiftReceipt(
      sessionEpoch: sessionEpoch,
      requestId: requestId,
      setErrorOnFailure: false,
    );
    if (receipt == null || !receipt.success || !_isJoinedEpoch(sessionEpoch)) {
      return false;
    }
    await _applySuccessfulGiftReceipt(
      receipt,
      snapshot: snapshot,
      sessionEpoch: sessionEpoch,
      refreshHistory: true,
    );
    return _isJoinedEpoch(sessionEpoch);
  }

  Future<GiftReceipt?> _readGiftReceipt({
    required int sessionEpoch,
    String? transferId,
    String? requestId,
    String failureFallback = '礼物回执查询失败',
    bool setErrorOnFailure = true,
  }) async {
    final String? normalizedTransferId = transferId?.trim().isEmpty == true
        ? null
        : transferId?.trim();
    final String? normalizedRequestId = requestId?.trim().isEmpty == true
        ? null
        : requestId?.trim();
    final String? recoveryRequestId = normalizedTransferId == null
        ? (normalizedRequestId ?? _giftRequestId)
        : normalizedRequestId;
    try {
      final GiftReceipt receipt = await _repository.fetchGiftReceipt(
        transferId: normalizedTransferId,
        requestId: recoveryRequestId,
        currentUserId: _currentUserId,
      );
      return _isJoinedEpoch(sessionEpoch) ? receipt : null;
    } catch (error) {
      if (setErrorOnFailure && _isJoinedEpoch(sessionEpoch)) {
        _errorMessage = _messageFor(error, fallback: failureFallback);
      }
      return null;
    }
  }

  Future<void> _applySuccessfulGiftReceipt(
    GiftReceipt receipt, {
    required RoomSnapshot snapshot,
    required int sessionEpoch,
    bool refreshHistory = false,
  }) async {
    if (!_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    final RoomSnapshot? currentSnapshot = _snapshot;
    final int? remainingBalance = receipt.remainingBalance;
    if (remainingBalance != null && currentSnapshot != null) {
      _snapshot = currentSnapshot.copyWith(giftBalance: remainingBalance);
    }
    _giftRequestId = null;
    _giftRequestKey = null;
    _errorMessage = null;
    if (refreshHistory) {
      await _loadPublicHistory(snapshot, sessionEpoch: sessionEpoch);
    }
  }

  String _newRequestId(String prefix) {
    final String value = _requestIdGenerator(prefix).trim();
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
      throw StateError('请求幂等 ID 生成器返回了无效值');
    }
    return value;
  }

  static String _secureRequestId(String prefix) {
    final String entropy = List<String>.generate(
      32,
      (_) => _secureRandom.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
    return '$prefix-$entropy';
  }

  void _appendAuthoritativeMessage(RoomMessage message) {
    final String? messageId = message.messageId?.trim();
    if (messageId == null || messageId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端消息缺少消息 ID',
      );
    }
    if (message.roomId != null && message.roomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端消息房间 ID 与当前房间不一致',
      );
    }
    if (_messages.any((RoomMessage item) => item.messageId == messageId)) {
      return;
    }
    _messages.add(message);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _sessionEpoch += 1;
    _rtcAudioAuthorityGeneration += 1;
    _micQueueEpoch += 1;
    _disposed = true;
    _joinCancelled = true;
    _micRequestPending = false;
    _giftSubmitting = false;
    _publicMessageRetryIds.clear();
    _publicMessageInFlight.clear();
    _publicMessageTail = Future<void>.value();
    _giftRequestId = null;
    _giftRequestKey = null;
    _refreshingFromEvent = false;
    _rtcAudioRequested = false;
    _rtcConnected = false;
    _rtcPublicationActive = false;
    final Object? transportLease = _transportLeaseId;
    final StreamSubscription<RoomRealtimeEvent>? subscription =
        _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (_ownsRealtimeTransport(transportLease)) {
      _realtimeTransportOwners[_realtimeGateway] = null;
      unawaited(_realtimeGateway.disconnect());
    }
    if (_ownsRtcTransport(transportLease)) {
      unawaited(_disposeOwnedRtcTransport(transportLease!));
    }
    if (_transportLeaseId == transportLease) {
      _transportLeaseId = null;
    }
    super.dispose();
  }
}

class _PublicMessageSubmission {
  const _PublicMessageSubmission(this.future);

  final Future<bool> future;
}
