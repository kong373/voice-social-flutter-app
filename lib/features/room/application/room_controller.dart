import 'dart:async';
import 'dart:math';
import 'gift_send_coordinator.dart';

import 'package:flutter/widgets.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/im/application/tencent_im_avchat_room_coordinator.dart';
import 'package:voice_social_app/features/im/domain/tencent_im_room_models.dart';
import 'package:voice_social_app/features/room/domain/room_intent_digest.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

class RoomController extends ChangeNotifier with WidgetsBindingObserver {
  final GiftSendCoordinator? giftSendCoordinator;

  /// The backend IM outbox is a 30-second fixed-delay worker. Keep the
  /// default client window above two worker periods so a room entered just
  /// after a worker tick can still observe the next two attempts. Tests may
  /// inject shorter values without changing this production guarantee.
  static const Duration _defaultTencentImReadinessPollInterval = Duration(
    seconds: 5,
  );
  static const Duration _defaultTencentImReadinessPollWindow = Duration(
    seconds: 65,
  );
  static final Random _secureRandom = Random.secure();
  static final Expando<Object> _rtcTransportOwners = Expando<Object>(
    'roomRtcTransportOwner',
  );
  static final Expando<Object> _realtimeTransportOwners = Expando<Object>(
    'roomRealtimeTransportOwner',
  );

  RoomController({
    this.giftSendCoordinator,
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
    TencentImAvChatRoomCoordinator? tencentImAvChatRoomCoordinator,
    Duration authoritySyncInterval = const Duration(seconds: 3),
    Listenable? sessionChanges,
    int? Function()? activeUserId,
    int Function()? identityGeneration,
    WidgetsBinding? lifecycleBinding,
    Duration Function()? leaseElapsed,
    Duration tencentImReadinessPollInterval =
        _defaultTencentImReadinessPollInterval,
    Duration tencentImReadinessPollWindow =
        _defaultTencentImReadinessPollWindow,
  }) : _currentUserId = currentUserId,
       _accessToken = accessToken,
       _repository = repository,
       _rtcAdapter = rtcAdapter,
       _realtimeGateway = realtimeGateway,
       _roomOperationsRepository = roomOperationsRepository,
       _permissionPolicy = permissionPolicy,
       _allowSyntheticPublicMessages = allowSyntheticPublicMessages,
       _requestIdGenerator = requestIdGenerator ?? _secureRequestId,
       _tencentImAvChatRoomCoordinator = tencentImAvChatRoomCoordinator,
       _authoritySyncInterval = _positiveDuration(
         authoritySyncInterval,
         'authoritySyncInterval',
       ),
       _sessionChanges = sessionChanges,
       _activeUserId = activeUserId,
       _identityGenerationSource = identityGeneration,
       _boundIdentityGeneration = identityGeneration?.call(),
       _lifecycleBinding = lifecycleBinding,
       _leaseElapsedSource = leaseElapsed,
       _tencentImReadinessPollInterval = _positiveDuration(
         tencentImReadinessPollInterval,
         'tencentImReadinessPollInterval',
       ),
       _tencentImReadinessPollWindow = _positiveDuration(
         tencentImReadinessPollWindow,
         'tencentImReadinessPollWindow',
       ) {
    _sessionChanges?.addListener(_onSessionChanged);
    _lifecycleBinding?.addObserver(this);
    final AppLifecycleState? lifecycle = _lifecycleBinding?.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final TencentImAvChatRoomCoordinator? coordinator =
        _tencentImAvChatRoomCoordinator;
    if (coordinator != null) {
      _tencentImRefreshRegistration = coordinator.registerRefreshHandler(
        roomId: roomId,
        onRefresh: _refreshFromTencentHint,
      );
    }
  }

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
  final TencentImAvChatRoomCoordinator? _tencentImAvChatRoomCoordinator;
  final Duration _tencentImReadinessPollInterval;
  final Duration _tencentImReadinessPollWindow;
  final Duration _authoritySyncInterval;
  final Listenable? _sessionChanges;
  final int? Function()? _activeUserId;
  final int Function()? _identityGenerationSource;
  final int? _boundIdentityGeneration;
  bool _identityInvalidated = false;
  final WidgetsBinding? _lifecycleBinding;
  final Duration Function()? _leaseElapsedSource;
  final Stopwatch _leaseClock = Stopwatch()..start();
  Duration get _leaseElapsed =>
      _leaseElapsedSource?.call() ?? _leaseClock.elapsed;
  RoomSessionLease? _lease;
  Duration? _leaseDeadline;
  Timer? _heartbeatTimer;
  Timer? _leaseExpiryTimer;
  Object? _leaseFlight;
  String? _leaseRequestId;
  bool get _leaseUnexpired =>
      _leaseDeadline == null || _leaseElapsed < _leaseDeadline!;
  Timer? _authorityTimer;
  Future<void>? _authorityFlight;
  bool _authorityPending = false;
  bool _foregroundReadInFlight = false;
  bool _foregroundReadPending = false;
  bool _foreground = true;
  StreamSubscription<void>? _backgroundAudioSubscription;
  bool _authorityKnown = false;
  bool _authoritySyncDegraded = false;
  int _authorityGeneration = 0;
  int _authorityMutationCount = 0;
  int _authorityVersion = -1;
  TencentImRoomRefreshRegistration? _tencentImRefreshRegistration;
  TencentImAvChatRoomSession? _tencentImSession;
  _CancelableTencentImReadinessWait? _tencentImReadinessWait;

  RoomSnapshot? _roomSnapshot;
  RoomSnapshot? get _snapshot => _roomSnapshot;
  set _snapshot(RoomSnapshot? value) {
    if (value != null &&
        _lease != null &&
        (value.roomId != roomId || value.sessionId != _lease!.sessionId)) {
      _endAuthoritySession('房间会话已变化，请重新进入房间');
      return;
    }
    // Every local mutation/explicit reconnect invalidates older GET results.
    _authorityGeneration += 1;
    _roomSnapshot = value == null || _lease == null
        ? value
        : value.copyWith(roomLease: _lease);
  }

  final List<RoomMessage> _messages = <RoomMessage>[];
  RoomSessionStatus _status = RoomSessionStatus.idle;
  StreamSubscription<RoomRealtimeEvent>? _realtimeSubscription;
  bool _micRequestPending = false;
  Future<bool>? _micToggleFlight;
  (int, bool)? _pendingMicToggle;
  (int, int, bool)? _pendingMicPlacement;
  bool _micPlacementCommitted = false;
  bool _suppressAutomaticGrant = false;
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
  int _tencentImReadinessPollGeneration = 0;
  Object? _transportLeaseId;
  String? _errorMessage;
  int? _joinErrorCode;
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
  int? get pendingMicPlacementSeat => _pendingMicPlacement?.$1;
  bool get micQueueLoading => _micQueueLoading;
  List<MicAccessRequest> get micRequests =>
      List<MicAccessRequest>.unmodifiable(_micRequests);
  MicCoordinationMode get micCoordinationMode {
    if (isOnMic || role == RoomRole.owner || role == RoomRole.moderator) {
      return MicCoordinationMode.direct;
    }
    return MicCoordinationMode.approval;
  }

  bool get giftSubmitting => _giftSubmitting;
  bool get realtimeDegraded => _realtimeDegraded || _authoritySyncDegraded;
  bool get isSnapshotOnly => _snapshot?.isSnapshotOnly ?? false;
  bool get allowsSyntheticPublicMessages =>
      _allowSyntheticPublicMessages && !isSnapshotOnly;
  bool get mutedInRoom => _mutedInRoom;
  bool get canSendPublicMessage =>
      !_mutedInRoom && allows(RoomCapability.sendPublicMessage);
  String? get errorMessage => _errorMessage;

  /// Admission UI must use a server code, never role/name or error text.
  bool get requiresEntryPassword =>
      isEntryIdentityCurrent &&
      _status == RoomSessionStatus.failed &&
      _joinErrorCode == 40332;

  bool get isEntryIdentityCurrent => !_disposed && _sameIdentity;
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
    return seat != null &&
        seat.isOccupied &&
        (!_transportPublishing || seat.state == MicSeatState.occupiedMuted);
  }

  bool get _transportPublishing =>
      _rtcPublicationActive &&
      (_rtcAdapter is! RtcPublicationState ||
          (_rtcAdapter as RtcPublicationState).localAudioEnabled);

  bool allows(RoomCapability capability) {
    final RoomSnapshot? snapshot = _snapshot;
    if (_disposed ||
        snapshot == null ||
        !_sameIdentity ||
        !_leaseUnexpired ||
        (_lease != null && _status != RoomSessionStatus.joined) ||
        (_repository is RoomAuthorityRepository &&
            (!_authorityKnown || _status != RoomSessionStatus.joined))) {
      return false;
    }
    return _permissionPolicy.allows(
      snapshot: snapshot,
      capability: capability,
      isOnMic: isOnMic,
    );
  }

  static final List<MicSeat> _emptySeats = <MicSeat>[
    for (int index = 1; index <= 9; index += 1)
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
    if (_disposed || !_sameIdentity) {
      return;
    }
    if (_status == RoomSessionStatus.joining ||
        _status == RoomSessionStatus.joined ||
        _status == RoomSessionStatus.reconnecting ||
        _status == RoomSessionStatus.leaving) {
      return;
    }
    _invalidateTencentImReadinessPoll();
    _stopRoomLease();
    _lease = null;
    _leaseDeadline = null;
    _stopAuthoritySync();
    _authorityKnown = false;
    _authorityVersion = -1;
    final int sessionEpoch = ++_sessionEpoch;
    _joinCancelled = false;
    _pendingJoinRequestRoomId = null;
    _pendingJoinRequestId = null;
    _mutedInRoom = false;
    _pendingMicPlacement = null;
    _micPlacementCommitted = false;
    _pendingMicToggle = null;
    _micToggleFlight = null;
    _suppressAutomaticGrant = false;
    _rtcAudioRequested = false;
    _rtcConnected = false;
    _status = RoomSessionStatus.joining;
    _joinErrorCode = null;
    _errorMessage = null;
    _historyErrorKind = null;
    _historyErrorMessage = null;
    _realtimeDegraded = false;
    _notify();

    RoomSnapshot? enteredSnapshot;
    final Duration enterStarted = _leaseElapsed;
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
      // Only an actual room entry switches the shared IM binding. A closed
      // management view has no membership and must not leave another room.
      final tencentCoordinator = _tencentImAvChatRoomCoordinator;
      if (!snapshot.isClosedManagementView && tencentCoordinator != null) {
        unawaited(_ignoreTencentLeave(tencentCoordinator.leave()));
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
      if (snapshot.isClosedManagementView) {
        await refreshRoomAuthority();
        _notify();
        return;
      }
      _startRoomLease(snapshot, enterStarted);
      if (!_isJoinedEpoch(sessionEpoch)) return;
      await _bindTencentImRoom(snapshot, sessionEpoch: sessionEpoch);
      if (!_isCurrent(sessionEpoch) || _joinCancelled) {
        await _abandonEnteredRoom(snapshot, sessionEpoch: sessionEpoch);
        return;
      }
      if (_repository is RoomAuthorityRepository) {
        await refreshRoomAuthority();
      } else {
        await _loadPublicHistory(snapshot, sessionEpoch: sessionEpoch);
        if (micCoordinationMode == MicCoordinationMode.approval) {
          await _loadMicRequests(sessionEpoch: sessionEpoch);
        }
      }
    } catch (error) {
      if (!_isCurrent(sessionEpoch) || _joinCancelled) {
        final RoomSnapshot? snapshot = enteredSnapshot;
        if (snapshot != null &&
            !snapshot.isClosedManagementView &&
            _canCompensateJoin(sessionEpoch)) {
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
      if (snapshot != null &&
          !snapshot.isClosedManagementView &&
          _canCompensateJoin(sessionEpoch)) {
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
      if (!_isCurrent(sessionEpoch) || _joinCancelled) return;
      _joinErrorCode = enteredSnapshot == null && error is ApiException
          ? error.code
          : null;
      _errorMessage = _joinErrorCode == 40332
          ? '请输入正确的房间密码后重试'
          : _messageFor(error, fallback: '进入房间失败，请重试');
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

  Future<void> _bindTencentImRoom(
    RoomSnapshot snapshot, {
    required int sessionEpoch,
  }) async {
    _invalidateTencentImReadinessPoll();
    final int readinessPollGeneration = _tencentImReadinessPollGeneration;
    final TencentImAvChatRoomCoordinator? coordinator =
        _tencentImAvChatRoomCoordinator;
    if (coordinator == null || !_isCurrent(sessionEpoch)) {
      return;
    }
    final TencentImRoomSessionSource? source =
        _repository is TencentImRoomSessionSource
        ? _repository as TencentImRoomSessionSource
        : null;
    final TencentImAvChatRoomSession? session = source
        ?.takeTencentImRoomSession(snapshot.roomId);
    final TencentImAvChatRoomSession? roomBoundSession =
        session?.roomId == snapshot.roomId ? session : null;
    _tencentImSession = roomBoundSession;
    if (roomBoundSession == null) {
      // A provider-blocked/malformed projection is deliberately HTTP-only;
      // clear only this room's current provider binding if one remains.
      await coordinator.leaveIfCurrent(roomId: snapshot.roomId);
      return;
    }
    // The coordinator fences the current room synchronously and serializes
    // the bounded SDK join behind any prior cleanup. The authoritative HTTP
    // room and its history must not wait for that optional provider call.
    unawaited(_ignoreTencentEnter(coordinator.enter(roomBoundSession)));
    if (!_isCurrent(sessionEpoch) ||
        !identical(_tencentImSession, roomBoundSession) ||
        roomBoundSession.isReady) {
      return;
    }
    final TencentImRoomReadinessSource? readinessSource =
        _repository is TencentImRoomReadinessSource
        ? _repository as TencentImRoomReadinessSource
        : null;
    if (readinessSource == null) {
      return;
    }
    // Enter already succeeded over HTTP. Polling is deliberately detached so
    // a slow/blocked provider readiness projection cannot delay room UI.
    unawaited(
      _pollTencentImReadiness(
        coordinator: coordinator,
        readinessSource: readinessSource,
        pendingSession: roomBoundSession,
        sessionEpoch: sessionEpoch,
        pollGeneration: readinessPollGeneration,
      ),
    );
  }

  Future<void> _pollTencentImReadiness({
    required TencentImAvChatRoomCoordinator coordinator,
    required TencentImRoomReadinessSource readinessSource,
    required TencentImAvChatRoomSession pendingSession,
    required int sessionEpoch,
    required int pollGeneration,
  }) async {
    final Stopwatch pollWindow = Stopwatch()..start();
    for (int attempt = 0; ; attempt += 1) {
      if (!_isCurrentTencentImReadinessPoll(
        sessionEpoch: sessionEpoch,
        pollGeneration: pollGeneration,
        pendingSession: pendingSession,
      )) {
        return;
      }
      if (attempt > 0) {
        final Duration? remaining = _remainingReadinessPollWindow(pollWindow);
        if (remaining == null) {
          return;
        }
        final Duration delay = remaining < _tencentImReadinessPollInterval
            ? remaining
            : _tencentImReadinessPollInterval;
        if (!await _waitForTencentImReadiness(delay)) {
          return;
        }
        if (!_isCurrentTencentImReadinessPoll(
              sessionEpoch: sessionEpoch,
              pollGeneration: pollGeneration,
              pendingSession: pendingSession,
            ) ||
            _remainingReadinessPollWindow(pollWindow) == null) {
          return;
        }
      }

      final Duration? fetchBudget = _remainingReadinessPollWindow(pollWindow);
      if (fetchBudget == null) {
        return;
      }
      TencentImAvChatRoomSession? latest;
      try {
        latest = await readinessSource
            .fetchTencentImRoomReadiness(pendingSession.roomId)
            .timeout(fetchBudget);
      } on Object {
        // A readiness route outage leaves the already successful HTTP room
        // usable. The bounded loop gives transient recovery a chance without
        // surfacing provider details or blocking navigation.
        continue;
      }
      if (latest == null) {
        continue;
      }
      // A read response from another navigation/session is never rebound,
      // even when its room is otherwise valid. The session handle is the
      // first-party lease fence; version may advance while the member stays
      // in the same room, but it may not move backwards.
      if (latest.roomId != pendingSession.roomId ||
          latest.sessionId != pendingSession.sessionId ||
          latest.groupId != pendingSession.groupId ||
          latest.groupType != pendingSession.groupType ||
          latest.version < pendingSession.version) {
        return;
      }
      // A response that completed after the bounded window cannot authorize
      // a provider join, even when it reports READY.
      if (_remainingReadinessPollWindow(pollWindow) == null) {
        return;
      }
      if (!latest.isReady) {
        continue;
      }
      if (!_isCurrentTencentImReadinessPoll(
        sessionEpoch: sessionEpoch,
        pollGeneration: pollGeneration,
        pendingSession: pendingSession,
      )) {
        return;
      }
      _tencentImSession = latest;
      try {
        await coordinator.enter(latest);
      } on Object {
        // Provider readiness is optional. A coordinator disposal or provider
        // rejection must not turn the detached polling task into an
        // unhandled asynchronous error.
      }
      return;
    }
  }

  bool _isCurrentTencentImReadinessPoll({
    required int sessionEpoch,
    required int pollGeneration,
    required TencentImAvChatRoomSession pendingSession,
  }) {
    return _isCurrent(sessionEpoch) &&
        pollGeneration == _tencentImReadinessPollGeneration &&
        _tencentImSession?.roomId == pendingSession.roomId &&
        _tencentImSession?.sessionId == pendingSession.sessionId &&
        _tencentImSession?.groupId == pendingSession.groupId;
  }

  Duration? _remainingReadinessPollWindow(Stopwatch pollWindow) {
    final Duration remaining =
        _tencentImReadinessPollWindow - pollWindow.elapsed;
    return remaining <= Duration.zero ? null : remaining;
  }

  Future<bool> _waitForTencentImReadiness(Duration duration) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    final _CancelableTencentImReadinessWait wait =
        _CancelableTencentImReadinessWait(duration);
    _tencentImReadinessWait = wait;
    return wait.future.whenComplete(() {
      if (identical(_tencentImReadinessWait, wait)) {
        _tencentImReadinessWait = null;
      }
    });
  }

  void _invalidateTencentImReadinessPoll() {
    _tencentImReadinessPollGeneration += 1;
    _tencentImReadinessWait?.cancel();
    _tencentImReadinessWait = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setForeground(state == AppLifecycleState.resumed);
  }

  /// A minimized room keeps one controller, so it also keeps just one loop.
  /// Background HTTP-only rooms pause reads. An owned live RTC connection
  /// keeps authority checks so moderation can still revoke publication.
  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    // Background continuation may keep already-published audio, but must not
    // finish a pending foreground grant/unmute and start a new microphone.
    if (!foreground && !_transportPublishing) {
      _rtcAudioAuthorityGeneration += 1;
      _rtcAudioRequested = false;
    }
    if (foreground && _lease != null && !_leaseUnexpired) {
      _endAuthoritySession('房间会话已到期，请重新进入房间');
      return;
    }
    final rtc = _rtcAdapter;
    if (rtc is AgoraRtcAdapter && _ownsRtcTransport(_transportLeaseId)) {
      rtc.setForeground(foreground);
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (foreground && _lease != null) {
      unawaited(_renewRoomLease());
    } else {
      _scheduleHeartbeat();
    }
    _stopAuthoritySync();
    if (_canSyncAuthority) unawaited(refreshRoomAuthority());
  }

  void _onSessionChanged() {
    if (_disposed || _sameIdentity) return;
    _identityInvalidated = true;
    _endAuthoritySession('登录状态已变化，请重新进入房间');
    _snapshot = null;
    _messages.clear();
    _notify();
  }

  void _stopRoomLease() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _leaseExpiryTimer?.cancel();
    _leaseExpiryTimer = null;
    _leaseFlight = null;
    _leaseRequestId = null;
  }

  void _startRoomLease(RoomSnapshot snapshot, Duration started) {
    final RoomSessionLease? lease = snapshot.roomLease;
    if (lease == null) return;
    _lease = lease;
    if (!lease.isValid || lease.sessionId != snapshot.sessionId) {
      _endAuthoritySession('房间租约响应无效，请重新进入房间');
      return;
    }
    _setLeaseDeadline(lease, started);
    _scheduleHeartbeat();
  }

  void _setLeaseDeadline(
    RoomSessionLease lease,
    Duration started, {
    RoomSessionLease? previous,
  }) {
    // Charge the entire HTTP round trip against server remaining time. This
    // is conservative and cannot gain lifetime from network delay or wall time.
    Duration deadline = started + lease.remaining;
    if (previous != null && _leaseDeadline != null) {
      // A replay returns the original server timestamps. Map its absolute
      // expiry through the preceding server/monotonic anchor as well, so a
      // delayed retry never grants the original remaining time again.
      final Duration anchored =
          _leaseDeadline! + lease.expiresAt.difference(previous.expiresAt);
      if (anchored < deadline) deadline = anchored;
    }
    _leaseDeadline = deadline;
    _leaseExpiryTimer?.cancel();
    final Duration remaining = _leaseDeadline! - _leaseElapsed;
    if (remaining <= Duration.zero) {
      _endAuthoritySession('房间会话已到期，请重新进入房间');
      return;
    }
    _leaseExpiryTimer = Timer(remaining, () {
      _endAuthoritySession('房间会话已到期，请重新进入房间');
    });
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (!_canAttemptHeartbeat || _repository is! RoomLeaseRepository) return;
    _heartbeatTimer = Timer(const Duration(seconds: 20), () {
      _heartbeatTimer = null;
      unawaited(_renewRoomLease());
    });
  }

  // Native activity is only an admission condition for a real authenticated
  // POST, never a source of server/client lease time. Snapshot-only has no
  // background exception even if an injected transport exposes a capability.
  bool get _canAttemptHeartbeat {
    if (_lease == null || !_isJoinedEpoch(_sessionEpoch)) return false;
    if (_foreground) return true;
    final rtc = _rtcAdapter;
    return _snapshot?.isSnapshotOnly == false &&
        _rtcConnected &&
        _ownsRtcTransport(_transportLeaseId) &&
        rtc is AgoraRtcAdapter &&
        rtc.hasBackgroundAudioLease;
  }

  void _onBackgroundAudioChanged() {
    if (!_disposed && !_foreground && _ownsRtcTransport(_transportLeaseId)) {
      _scheduleHeartbeat();
    }
  }

  Future<void> _renewRoomLease() async {
    if (!_sameIdentity) {
      _onSessionChanged();
      return;
    }
    final RoomSessionLease? lease = _lease;
    if (lease == null || _disposed || _status != RoomSessionStatus.joined)
      return;
    if (!_leaseUnexpired) {
      _endAuthoritySession('房间会话已到期，请重新进入房间');
      return;
    }
    if (!_canAttemptHeartbeat) return;
    if (_leaseFlight != null || _repository is! RoomLeaseRepository) return;
    if (lease.sequence >= 9007199254740991) {
      _endAuthoritySession('房间租约序号已耗尽，请重新进入房间');
      return;
    }
    final int epoch = _sessionEpoch;
    final Object flight = Object();
    _leaseFlight = flight;
    final Object? transportLease = _transportLeaseId;
    bool ownsFlight() =>
        identical(_leaseFlight, flight) &&
        _isCurrent(epoch) &&
        _lease?.sessionId == lease.sessionId;
    try {
      if (!_foreground) {
        final rtc = _rtcAdapter;
        if (rtc is! AgoraRtcAdapter ||
            !await rtc.confirmBackgroundAudioActive())
          return;
        // Await may cross logout, ownership transfer, a native stop or the
        // exact deadline. Recheck all fences before creating/sending a POST.
        if (!ownsFlight() ||
            !_canAttemptHeartbeat ||
            !_ownsRtcTransport(transportLease))
          return;
      }
      if (!ownsFlight() || !_isJoinedEpoch(epoch)) return;
      final Duration started = _leaseElapsed;
      final String requestId = _leaseRequestId ??= _newRequestId('room-lease');
      final RoomSessionLease renewed =
          await (_repository as RoomLeaseRepository).renewRoomLease(
            roomId: roomId,
            sessionId: lease.sessionId,
            sequence: lease.sequence + 1,
            requestId: requestId,
            currentUserId: _currentUserId,
          );
      if (!ownsFlight() || !_isJoinedEpoch(epoch)) return;
      if (!renewed.isValid ||
          renewed.sessionId != lease.sessionId ||
          renewed.sequence != lease.sequence + 1 ||
          renewed.serverTime.isBefore(lease.serverTime) ||
          renewed.expiresAt.isBefore(lease.expiresAt))
        return;
      _lease = renewed;
      _leaseRequestId = null;
      _roomSnapshot = _snapshot?.copyWith(roomLease: renewed);
      _setLeaseDeadline(renewed, started, previous: lease);
      _notify();
    } catch (error) {
      // A reconnect does not change lease ownership. Its in-flight heartbeat
      // must still revoke the session on an explicit authentication/lease error.
      if (!ownsFlight()) return;
      if (error is ApiException &&
          (error.code == 40936 ||
              error.code == 40937 ||
              error.code == 40101 ||
              error.kind == ApiFailureKind.unauthorized)) {
        _endAuthoritySession('房间会话已失效，请重新进入房间');
      }
      // Ambiguous failures retain both identifiers. Even sequence conflicts
      // cannot be used to guess a new sequence or extend the local deadline.
    } finally {
      if (identical(_leaseFlight, flight)) {
        _leaseFlight = null;
        _scheduleHeartbeat();
      }
    }
  }

  bool get _canSyncAuthority =>
      !_disposed &&
      (_foreground ||
          (_rtcConnected && _ownsRtcTransport(_transportLeaseId))) &&
      _repository is RoomAuthorityRepository &&
      _status == RoomSessionStatus.joined &&
      _sameIdentity;

  bool get _sameIdentity =>
      !_identityInvalidated &&
      (_activeUserId == null || _activeUserId() == _currentUserId) &&
      (_identityGenerationSource == null ||
          _identityGenerationSource() == _boundIdentityGeneration);

  bool _authorityReadIsCurrent(int epoch, int generation) =>
      _canSyncAuthority &&
      _isJoinedEpoch(epoch) &&
      generation == _authorityGeneration &&
      _authorityMutationCount == 0;

  void _stopAuthoritySync() {
    _authorityTimer?.cancel();
    _authorityTimer = null;
    _authorityGeneration += 1;
    _micQueueEpoch += 1;
    _micQueueLoading = false;
    _authorityPending = false;
    _foregroundReadPending = false;
  }

  void _scheduleAuthoritySync() {
    _authorityTimer?.cancel();
    _authorityTimer = null;
    if (!_canSyncAuthority || _authorityMutationCount != 0) return;
    _authorityTimer = Timer(_authoritySyncInterval, () {
      _authorityTimer = null;
      unawaited(refreshRoomAuthority());
    });
  }

  /// Single-flight, read-only synchronization. Hints arriving during a read
  /// coalesce into a subsequent read; failures retry on the bounded timer.
  Future<void> refreshRoomAuthority() {
    if (!_canSyncAuthority) return Future<void>.value();
    _authorityPending = true;
    if (_authorityMutationCount != 0) return Future<void>.value();
    final Future<void>? flight = _authorityFlight;
    if (flight != null) return flight;
    _authorityTimer?.cancel();
    _authorityTimer = null;
    final Completer<void> completion = Completer<void>();
    _authorityFlight = completion.future;
    unawaited(() async {
      try {
        do {
          _authorityPending = false;
          await _readRoomAuthorityOnce();
        } while (_authorityPending &&
            _canSyncAuthority &&
            _authorityMutationCount == 0);
      } finally {
        _authorityFlight = null;
        _scheduleAuthoritySync();
        completion.complete();
      }
    }());
    return completion.future;
  }

  Future<void> _readRoomAuthorityOnce() async {
    final int epoch = _sessionEpoch;
    final int generation = _authorityGeneration;
    if (!_authorityReadIsCurrent(epoch, generation)) return;
    try {
      final RoomAuthorityProjection projection =
          await (_repository as RoomAuthorityRepository).fetchRoomAuthority(
            roomId: roomId,
            currentUserId: _currentUserId,
          );
      if (!_authorityReadIsCurrent(epoch, generation)) return;
      final RoomSnapshot? previous = _snapshot;
      if (projection.viewerUserId != _currentUserId ||
          projection.snapshot.roomId != roomId ||
          projection.version < 0) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间状态响应与当前会话不一致',
        );
      }
      if (projection.version < _authorityVersion) return;
      if (previous?.isClosedManagementView == true) {
        if (!projection.snapshot.isClosedManagementView) {
          _endAuthoritySession('房间状态已变化，请重新进入房间');
          return;
        }
        _authorityVersion = projection.version;
        _authorityKnown = true;
        _authoritySyncDegraded = false;
        _roomSnapshot = projection.snapshot;
        _notify();
        return;
      }
      if (!projection.memberActive ||
          (previous?.sessionId != null &&
              projection.snapshot.sessionId != previous!.sessionId)) {
        _endAuthoritySession('当前房间会话已结束，请重新进入房间');
        return;
      }
      if (previous == null) return;
      _authorityVersion = projection.version;
      _authorityKnown = true;
      _authoritySyncDegraded = false;
      _mutedInRoom = projection.roomMuted;
      // A read alone never resumes audio. A newly observed occupancy grant
      // may create one foreground publication attempt with a fresh token.
      final RoomSnapshot next = projection.snapshot.copyWith(
        roomLease: _lease ?? previous.roomLease,
        rtc: previous.rtc,
        transportMode: previous.transportMode,
        giftBalance: projection.snapshot.giftBalance ?? previous.giftBalance,
      );
      _roomSnapshot = next;
      final automaticGrant =
          !_suppressAutomaticGrant && _isNewMicGrant(previous, next);
      if (_seatInSnapshot(next)?.isOccupied == true)
        _suppressAutomaticGrant = false;
      if (!_seatPermitsAudio(next)) {
        _rtcAudioAuthorityGeneration += 1;
        _rtcAudioRequested = false;
        await _disableRtcPublication();
      } else if (_foreground && !previous.isSnapshotOnly && automaticGrant) {
        final audioGeneration = _rtcAudioAuthorityGeneration;
        try {
          final fresh = await _repository.reconnectRoom(
            roomId: roomId,
            currentUserId: _currentUserId,
          );
          if (!_authorityReadIsCurrent(epoch, generation) ||
              audioGeneration != _rtcAudioAuthorityGeneration ||
              !_foreground)
            return;
          if (!_sameGrant(next, fresh)) return;
          await _reconcileAuthoritativeRtc(previous, fresh, freshGrant: true);
          if (!_authorityReadIsCurrent(epoch, generation) ||
              audioGeneration != _rtcAudioAuthorityGeneration)
            return;
          _roomSnapshot = fresh.copyWith(roomLease: _lease ?? fresh.roomLease);
        } catch (error) {
          if (!_authorityReadIsCurrent(epoch, generation)) return;
          _rtcAudioRequested = false;
          await _disableRtcPublication();
          _errorMessage = _messageFor(error, fallback: '已上麦，麦克风未开启，请手动重试');
        }
      }
      if (!_authorityReadIsCurrent(epoch, generation)) return;
      _notify();
    } catch (error) {
      if (!_authorityReadIsCurrent(epoch, generation)) return;
      if (_snapshot?.isClosedManagementView == true &&
          error is ApiException &&
          (error.kind == ApiFailureKind.protocol ||
              error.code == 40431 ||
              error.httpStatus == 403 ||
              error.httpStatus == 404)) {
        _endAuthoritySession('房间管理权限已变化，请重新进入房间');
        return;
      }
      if (error is ApiException && error.kind == ApiFailureKind.unauthorized) {
        _endAuthoritySession('登录状态已失效，请重新登录');
        return;
      }
      // Retain the last confirmed view during transient failures, and expose
      // the degradation; never infer membership/permission from an error.
      _authoritySyncDegraded = true;
      _notify();
    }
    if (!_authorityReadIsCurrent(epoch, generation) ||
        !_authorityKnown ||
        !_foreground)
      return;
    _refreshForegroundRoomData();
  }

  // A slow public-history request must never block a background RTC revoke.
  // This lane is independently single-flight and foreground-only.
  void _refreshForegroundRoomData() {
    if (_snapshot?.isClosedManagementView == true) return;
    if (!_canSyncAuthority || !_foreground) return;
    _foregroundReadPending = true;
    if (_foregroundReadInFlight) return;
    _foregroundReadInFlight = true;
    unawaited(() async {
      try {
        do {
          _foregroundReadPending = false;
          final int epoch = _sessionEpoch;
          final int generation = _authorityGeneration;
          await _refreshPublicHistoryReadOnly(epoch, generation);
          if (_foreground &&
              _authorityReadIsCurrent(epoch, generation) &&
              micCoordinationMode == MicCoordinationMode.approval) {
            await _loadMicRequests(sessionEpoch: epoch, quiet: true);
          }
        } while (_foregroundReadPending &&
            _canSyncAuthority &&
            _foreground &&
            _authorityMutationCount == 0);
      } finally {
        _foregroundReadInFlight = false;
      }
    }());
  }

  Future<void> _refreshPublicHistoryReadOnly(int epoch, int generation) async {
    final Set<String?> before = _messages.map((item) => item.messageId).toSet();
    try {
      final List<RoomMessage> history = await _repository.fetchPublicMessages(
        roomId,
      );
      if (!_foreground || !_authorityReadIsCurrent(epoch, generation)) return;
      final Set<String?> incoming = history
          .map((item) => item.messageId)
          .toSet();
      // A send may finish while GET is in flight. Preserve that newer receipt,
      // but otherwise replace history so server removals are respected.
      final List<RoomMessage> appended = _messages
          .where(
            (item) =>
                item.messageId != null &&
                !before.contains(item.messageId) &&
                !incoming.contains(item.messageId),
          )
          .toList();
      _messages
        ..clear()
        ..addAll(history)
        ..addAll(appended);
      _historyErrorKind = null;
      _historyErrorMessage = null;
      _notify();
    } catch (error) {
      if (!_foreground || !_authorityReadIsCurrent(epoch, generation)) return;
      _historyErrorKind = error is ApiException
          ? error.kind
          : ApiFailureKind.protocol;
      _historyErrorMessage = '公屏同步暂时不可用，正在自动重试';
      _notify();
    }
  }

  void _endAuthoritySession(String message) {
    final Object? transportLease = _transportLeaseId;
    final TencentImAvChatRoomSession? imSession = _tencentImSession;
    _invalidateSession();
    // Publication teardown must not wait behind realtime subscription cancel
    // or disconnect. The transport ownership check also fences newer rooms.
    if (_ownsRtcTransport(transportLease)) {
      unawaited(_disposeOwnedRtcTransport(transportLease!));
    }
    _status = RoomSessionStatus.left;
    _authorityKnown = false;
    _errorMessage = message;
    _tencentImSession = null;
    if (imSession != null && _tencentImAvChatRoomCoordinator != null) {
      unawaited(
        _ignoreTencentLeave(
          _tencentImAvChatRoomCoordinator.leaveIfCurrent(
            roomId: imSession.roomId,
            sessionId: imSession.sessionId,
          ),
        ),
      );
    }
    unawaited(
      _cleanupTransport(swallowErrors: true, transportLease: transportLease),
    );
    _notify();
  }

  void _beginAuthorityMutation() {
    _authorityMutationCount += 1;
    _stopAuthoritySync();
  }

  void _endAuthorityMutation(int epoch) {
    if (!_isCurrent(epoch)) return;
    _authorityMutationCount -= 1;
    _authorityGeneration += 1;
    if (_authorityMutationCount == 0) unawaited(refreshRoomAuthority());
  }

  /// Provider custom elements are metadata-only invalidation hints. The
  /// authoritative HTTP history replaces the rendered list; no custom payload
  /// is ever parsed into a message or permission decision here.
  Future<void> _refreshFromTencentHint(String hintedRoomId) async {
    if (_repository is RoomAuthorityRepository) {
      if (hintedRoomId.trim() == roomId) await refreshRoomAuthority();
      return;
    }
    final RoomSnapshot? snapshot = _snapshot;
    final String normalizedRoomId = hintedRoomId.trim();
    if (_disposed ||
        _status != RoomSessionStatus.joined ||
        snapshot == null ||
        normalizedRoomId != roomId ||
        snapshot.roomId != normalizedRoomId ||
        _refreshingFromEvent) {
      return;
    }
    final int sessionEpoch = _sessionEpoch;
    _refreshingFromEvent = true;
    try {
      final List<RoomMessage> history = await _repository.fetchPublicMessages(
        normalizedRoomId,
      );
      if (!_isJoinedEpoch(sessionEpoch) ||
          _snapshot?.roomId != normalizedRoomId) {
        return;
      }
      _historyErrorKind = null;
      _historyErrorMessage = null;
      _messages
        ..clear()
        ..addAll(history);
      _notify();
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
      _notify();
    } finally {
      if (_isCurrent(sessionEpoch)) {
        _refreshingFromEvent = false;
      }
    }
  }

  Future<void> _loadPublicHistory(
    RoomSnapshot snapshot, {
    required int sessionEpoch,
  }) async {
    if (_repository is RoomAuthorityRepository) {
      if (_isJoinedEpoch(sessionEpoch)) await refreshRoomAuthority();
      return;
    }
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
    final int audioGeneration = _rtcAudioAuthorityGeneration;
    final retained = _pendingMicPlacement;
    if (retained != null && retained.$1 != seatNumber) {
      _errorMessage = '原上麦操作结果待确认，请重试原麦位';
      _notify();
      return false;
    }
    final MicSeat? seat = _seatByNumber(seatNumber);
    if (retained == null &&
        (seat == null || !seat.isAvailable || !seat.canUse(role))) {
      _errorMessage = '麦位状态已变化，请重新选择';
      _notify();
      return false;
    }
    final placement =
        retained ??
        (
          seatNumber,
          seat!.backendIndex,
          micCoordinationMode == MicCoordinationMode.approval,
        );
    _pendingMicPlacement = placement;
    if (micCoordinationMode == MicCoordinationMode.approval) {
      _invalidateMicQueueReads();
    }
    _micRequestPending = true;
    _errorMessage = null;
    _notify();
    bool snapshotConfirmed = false;
    final bool moving = isOnMic;
    _beginAuthorityMutation();
    try {
      if (placement.$3) {
        final RoomOperationsRepository? operations = _roomOperationsRepository;
        if (operations == null) {
          throw const ApiException(
            kind: ApiFailureKind.configuration,
            message: '当前环境缺少上麦申请能力',
          );
        }
        await operations.submitMicRequest(
          roomId: roomId,
          userId: _currentUserId,
          seatNumber: placement.$2,
        );
        if (_isJoinedEpoch(sessionEpoch)) _pendingMicPlacement = null;
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
      _suppressAutomaticGrant = true;
      if (!_micPlacementCommitted) {
        await _repository.requestMic(placement.$2);
        if (_isJoinedEpoch(sessionEpoch)) _micPlacementCommitted = true;
      }
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
      if (audioGeneration != _rtcAudioAuthorityGeneration) return false;
      _snapshot = refreshed;
      snapshotConfirmed = true;
      _suppressAutomaticGrant = false;
      _pendingMicPlacement = null;
      _micPlacementCommitted = false;
      if (!refreshed.seats.any(
        (MicSeat item) =>
            item.userId == _currentUserId &&
            item.isOccupied &&
            item.backendIndex == placement.$2,
      )) {
        throw const ApiException(
          kind: ApiFailureKind.business,
          message: '麦位状态尚未确认，请刷新后重试',
        );
      }
      final int authorityGeneration = audioGeneration;
      final bool publishAudio =
          (!moving || _rtcAudioRequested) &&
          _snapshotAllowsRtcPublication(refreshed);
      await _reconcileRtcForSnapshot(refreshed, publishAudio: publishAudio);
      if (!_isJoinedEpoch(sessionEpoch)) return false;
      // A successful first-party seat mutation may still return a
      // snapshot-only projection when the token/readiness endpoint is
      // unavailable. Keep the server seat result, but never retain a local
      // publication intent that could later publish without a fresh token.
      _rtcAudioRequested =
          authorityGeneration == _rtcAudioAuthorityGeneration &&
          publishAudio &&
          _transportPublishing &&
          _snapshotAllowsRtcPublication(refreshed);
      if (!_rtcAudioRequested && publishAudio) {
        await _disableRtcPublication();
      }
      if (!_isJoinedEpoch(sessionEpoch) ||
          audioGeneration != _rtcAudioAuthorityGeneration) {
        return false;
      }
      _snapshot = refreshed;
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
      if (snapshotConfirmed ||
          (!_micPlacementCommitted && !_unknownMicResult(error))) {
        _pendingMicPlacement = null;
        _micPlacementCommitted = false;
        _suppressAutomaticGrant = false;
      }
      _rtcAudioRequested = false;
      await _disableRtcPublication();
      _errorMessage = _messageFor(error, fallback: '申请上麦失败');
      return false;
    } finally {
      _endAuthorityMutation(sessionEpoch);
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
    if (_micRequestPending || !_isJoinedEpoch(_sessionEpoch)) {
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
    _beginAuthorityMutation();
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
      _endAuthorityMutation(sessionEpoch);
      if (_isCurrent(sessionEpoch)) {
        _micRequestPending = false;
        _notify();
      }
    }
  }

  // Historical callers fail locally; retired INVITE never dispatches a write.
  Future<bool> resolveMicInvite({
    required String requestId,
    required bool accepted,
  }) async => false;

  Future<void> _loadMicRequests({
    required int sessionEpoch,
    bool quiet = false,
  }) async {
    final RoomOperationsRepository? operations = _roomOperationsRepository;
    if (operations == null ||
        !_isJoinedEpoch(sessionEpoch) ||
        micCoordinationMode != MicCoordinationMode.approval) {
      return;
    }
    final int queueEpoch = ++_micQueueEpoch;
    _micQueueLoading = true;
    if (!quiet) _notify();
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
      if (!quiet &&
          _isJoinedEpoch(sessionEpoch) &&
          queueEpoch == _micQueueEpoch) {
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
    _beginAuthorityMutation();
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
    } finally {
      _endAuthorityMutation(sessionEpoch);
    }
  }

  Future<bool> toggleMicrophone() {
    if (_pendingMicPlacement != null) return Future.value(false);
    final flight = _micToggleFlight;
    if (flight != null) return flight;
    if (!allows(RoomCapability.toggleMicrophone) ||
        !_isJoinedEpoch(_sessionEpoch))
      return Future.value(false);
    final operation = _toggleMicrophone();
    _micToggleFlight = operation;
    operation.then<void>((_) {
      if (identical(_micToggleFlight, operation)) _micToggleFlight = null;
    });
    return operation;
  }

  Future<bool> _toggleMicrophone() async {
    final ownSeat = _ownSeat();
    if (ownSeat == null || !ownSeat.isOccupied || !ownSeat.isOnline)
      return false;
    final epoch = _sessionEpoch;
    final audioGeneration = _rtcAudioAuthorityGeneration;
    final pending =
        _pendingMicToggle ?? (ownSeat.backendIndex, _transportPublishing);
    final nextMuted = pending.$2;
    final audio = ownSeat.audioMute;
    if (!nextMuted &&
        (audio == null ||
            audio.forcedMuted ||
            (audio.legacyMuted && role != RoomRole.owner))) {
      _errorMessage = audio == null ? '麦克风状态待同步' : '当前有管理静音限制，不能自行开麦';
      _notify();
      return false;
    }
    _pendingMicToggle = pending;
    _beginAuthorityMutation();
    _rtcAudioRequested = false;
    bool confirmed = false;
    try {
      // A local close is safe immediately, even if the server result is unknown.
      if (nextMuted) await _disableRtcPublication();
      if (!_isJoinedEpoch(epoch) ||
          audioGeneration != _rtcAudioAuthorityGeneration)
        return false;
      await _repository.setSelfMicrophoneMuted(
        backendMicIndex: pending.$1,
        muted: nextMuted,
      );
      confirmed = true;
      if (!_isJoinedEpoch(epoch)) return false;
      _pendingMicToggle = null;
      if (!_isJoinedEpoch(epoch) ||
          audioGeneration != _rtcAudioAuthorityGeneration)
        return false;
      final fresh = await _repository.reconnectRoom(
        roomId: roomId,
        currentUserId: _currentUserId,
      );
      if (!_isJoinedEpoch(epoch) ||
          audioGeneration != _rtcAudioAuthorityGeneration)
        return false;
      final publish = !nextMuted && _snapshotAllowsRtcPublication(fresh);
      await _reconcileRtcForSnapshot(fresh, publishAudio: publish);
      if (!_isJoinedEpoch(epoch) ||
          audioGeneration != _rtcAudioAuthorityGeneration)
        return false;
      _snapshot = fresh;
      _rtcAudioRequested = publish && _transportPublishing;
      if (!nextMuted && !_rtcAudioRequested) {
        _errorMessage = '麦克风尚未开启，请确认权限和房间状态后重试';
        _notify();
        return false;
      }
      _errorMessage = null;
      _notify();
      return true;
    } catch (error) {
      if (!_isJoinedEpoch(epoch)) return false;
      if (confirmed || !_unknownMicResult(error)) _pendingMicToggle = null;
      _rtcAudioRequested = false;
      await _disableRtcPublication();
      if (!_isJoinedEpoch(epoch)) return false;
      _errorMessage = _messageFor(error, fallback: '麦克风未开启，请重试');
      _notify();
      return false;
    } finally {
      _endAuthorityMutation(epoch);
    }
  }

  static bool _unknownMicResult(Object error) =>
      error is! ApiException ||
      error.code == 40901 ||
      error.code == 40902 ||
      (error.code != 40903 &&
          const [
            ApiFailureKind.network,
            ApiFailureKind.timeout,
            ApiFailureKind.protocol,
            ApiFailureKind.server,
          ].contains(error.kind));

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
        _snapshot = (_snapshot ?? snapshot).copyWith(
          giftBalance: remainingBalance,
        );
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
    if (_snapshot?.isClosedManagementView == true) {
      await refreshRoomAuthority();
      return;
    }
    if (!_sameIdentity ||
        !_leaseUnexpired ||
        _status != RoomSessionStatus.joined) {
      return;
    }
    final int sessionEpoch = _sessionEpoch;
    final Duration reconnectStarted = _leaseElapsed;
    _stopAuthoritySync();
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
      if (_lease != null &&
          (snapshot.sessionId != _lease!.sessionId || !_leaseUnexpired)) {
        _endAuthoritySession('房间会话已变化，请重新进入房间');
        return;
      }
      if (!snapshot.isSnapshotOnly) {
        _claimTransportLease();
        final bool publishAudio =
            _rtcAudioRequested &&
            _transportPublishing &&
            _snapshotAllowsRtcPublication(snapshot);
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
      await _bindTencentImRoom(snapshot, sessionEpoch: sessionEpoch);
      if (!_isCurrent(sessionEpoch)) {
        return;
      }
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
      if (_lease == null) _startRoomLease(snapshot, reconnectStarted);
    } catch (error) {
      if (!_isCurrent(sessionEpoch)) {
        return;
      }
      _errorMessage = _messageFor(error, fallback: '房间恢复失败，请重试');
      _rtcAudioRequested = false;
      await _disableRtcPublication();
      if (!_isCurrent(sessionEpoch)) return;
      _realtimeDegraded = true;
      _status = _snapshot == null
          ? RoomSessionStatus.failed
          : RoomSessionStatus.joined;
    }
    if (_isCurrent(sessionEpoch)) {
      _notify();
      _scheduleHeartbeat();
      unawaited(refreshRoomAuthority());
    }
  }

  Future<bool> leaveRoom() async {
    if (_disposed) return false;
    if (_snapshot?.isClosedManagementView == true) {
      _invalidateSession();
      _stopAuthoritySync();
      _status = RoomSessionStatus.left;
      _notify();
      return true;
    }
    if (!_sameIdentity) {
      _onSessionChanged();
      return false;
    }
    if (!_leaseUnexpired) {
      _endAuthoritySession('房间会话已到期，请重新进入房间');
      return false;
    }
    if (_status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left) {
      return false;
    }
    final RoomSessionStatus previousStatus = _status;
    final Object? transportLease = _transportLeaseId;
    final int sessionEpoch = _invalidateSession();
    final TencentImAvChatRoomCoordinator? tencentCoordinator =
        _tencentImAvChatRoomCoordinator;
    final TencentImAvChatRoomSession? tencentSession = _tencentImSession;
    _tencentImSession = null;
    if (tencentCoordinator != null) {
      // leaveIfCurrent fences the local session synchronously and starts a
      // bounded provider quit. The first-party HTTP exit must not wait for or
      // depend on that vendor operation.
      unawaited(
        _ignoreTencentLeave(
          tencentCoordinator.leaveIfCurrent(
            roomId: _snapshot?.roomId ?? roomId,
            sessionId: tencentSession?.sessionId,
          ),
        ),
      );
    }
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
      if (_lease != null) {
        _endAuthoritySession('离房结果未确认，当前本地会话已结束');
        return false;
      }
      _status = previousStatus;
      _notify();
      unawaited(refreshRoomAuthority());
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
    if (_repository is RoomAuthorityRepository) {
      if (_isJoinedEpoch(sessionEpoch)) await refreshRoomAuthority();
      return;
    }
    if (_refreshingFromEvent || !_isJoinedEpoch(sessionEpoch)) {
      return;
    }
    _refreshingFromEvent = true;
    final audioGeneration = _rtcAudioAuthorityGeneration;
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
        if (audioGeneration != _rtcAudioAuthorityGeneration) return;
        await _reconcileAuthoritativeRtc(
          previous,
          refreshed,
          freshGrant:
              !_suppressAutomaticGrant &&
              _foreground &&
              _isNewMicGrant(previous, refreshed),
        );
        if (_seatInSnapshot(refreshed)?.isOccupied == true)
          _suppressAutomaticGrant = false;
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
    if (snapshot.isClosedManagementView) return;
    final TencentImAvChatRoomCoordinator? tencentCoordinator =
        _tencentImAvChatRoomCoordinator;
    final TencentImAvChatRoomSession? tencentSession = _tencentImSession;
    _tencentImSession = null;
    if (tencentCoordinator != null) {
      unawaited(
        _ignoreTencentLeave(
          tencentCoordinator.leaveIfCurrent(
            roomId: tencentSession?.roomId ?? snapshot.roomId,
            sessionId: tencentSession?.sessionId,
          ),
        ),
      );
    }
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
    // The shared API client follows the current login. Late old-account
    // compensation must not use a new login, including A -> B -> A.
    if (!_sameIdentity) return false;
    if (_sessionEpoch == sessionEpoch || _disposed) {
      return true;
    }
    return _status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left ||
        _status == RoomSessionStatus.closed ||
        _status == RoomSessionStatus.kicked;
  }

  int _invalidateSession() {
    _stopRoomLease();
    _sessionEpoch += 1;
    _stopAuthoritySync();
    _authorityMutationCount = 0;
    _authorityKnown = false;
    _invalidateTencentImReadinessPoll();
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
      !_disposed && _sameIdentity && sessionEpoch == _sessionEpoch;

  bool _isJoinedEpoch(int sessionEpoch) =>
      _isCurrent(sessionEpoch) &&
      _leaseUnexpired &&
      _status == RoomSessionStatus.joined;

  Object _claimTransportLease() {
    final Object lease = Object();
    _transportLeaseId = lease;
    _rtcTransportOwners[_rtcAdapter] = lease;
    _realtimeTransportOwners[_realtimeGateway] = lease;
    final rtc = _rtcAdapter;
    if (rtc is AgoraRtcAdapter) {
      rtc.setForeground(_foreground);
      _backgroundAudioSubscription ??= rtc.backgroundAudioChanges.listen(
        (_) => _onBackgroundAudioChanged(),
      );
    }
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
    final transportLease = _transportLeaseId;
    if (_disposed || !_ownsRtcTransport(transportLease)) {
      return;
    }
    if (_lease != null &&
        (snapshot.sessionId != _lease!.sessionId || !_leaseUnexpired)) {
      _endAuthoritySession('房间会话已变化，请重新进入房间');
      return;
    }
    if (snapshot.isSnapshotOnly) {
      await _withRtcAudioMutex<void>(() async {
        if (_ownsRtcTransport(transportLease)) await _rtcAdapter.leave();
      });
      if (!_ownsRtcTransport(transportLease)) return;
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
        if (_disposed ||
            !_ownsRtcTransport(transportLease) ||
            authorityGeneration != _rtcAudioAuthorityGeneration) {
          return;
        }
        if (forceReconnect || !_rtcConnected) {
          await _rtcAdapter.reconnect(snapshot.rtc);
          if (_disposed ||
              !_ownsRtcTransport(transportLease) ||
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
        if (!_ownsRtcTransport(transportLease)) return;
        _rtcPublicationActive = effectivePublishAudio;
        if (effectivePublishAudio && !_transportPublishing) {
          throw const RtcAdapterException(
            failure: RtcAdapterFailure.mute,
            message: 'SDK 未确认麦克风开启',
          );
        }
        if (effectivePublishAudio &&
            (_disposed ||
                authorityGeneration != _rtcAudioAuthorityGeneration ||
                !_snapshotAllowsRtcPublication(snapshot))) {
          await _rtcAdapter.setLocalAudioEnabled(false);
          _rtcPublicationActive = false;
        }
      });
    } catch (_) {
      // The provider may have changed native publication before throwing.
      // Clear it while this controller still owns the transport, regardless
      // of local connection flags. Never clean up a replacement session.
      if (_ownsRtcTransport(transportLease)) {
        await _disableRtcPublication(force: true);
        if (_ownsRtcTransport(transportLease)) {
          _rtcConnected = false;
          _rtcPublicationActive = false;
        }
      }
      rethrow;
    }
  }

  Future<void> _reconcileAuthoritativeRtc(
    RoomSnapshot? previous,
    RoomSnapshot refreshed, {
    bool freshGrant = false,
  }) async {
    final epoch = _sessionEpoch;
    final audioGeneration = _rtcAudioAuthorityGeneration;
    final bool wasAudioRequested = _rtcAudioRequested;
    final bool mayPublish = _snapshotAllowsRtcPublication(refreshed);
    final bool shouldPublish =
        ((_rtcAudioRequested && _transportPublishing) || freshGrant) &&
        mayPublish;
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
    if (!_isCurrent(epoch) || audioGeneration != _rtcAudioAuthorityGeneration)
      return;
    _rtcAudioRequested = shouldPublish && _transportPublishing;
  }

  bool _snapshotAllowsRtcPublication(RoomSnapshot snapshot) {
    if (!_sameIdentity ||
        !_leaseUnexpired ||
        snapshot.isSnapshotOnly ||
        snapshot.roomId != roomId ||
        snapshot.rtc.userId != _currentUserId ||
        snapshot.rtc.token.isEmpty ||
        (snapshot.rtc.expiresAt != null &&
            !snapshot.rtc.expiresAt!.isAfter(DateTime.now())) ||
        !_seatPermitsAudio(snapshot)) {
      return false;
    }
    final MicSeat? ownSeat = _seatInSnapshot(snapshot);
    if (ownSeat == null ||
        !ownSeat.isOccupied ||
        !ownSeat.isOnline ||
        ownSeat.state == MicSeatState.occupiedMuted) {
      return false;
    }
    return switch (snapshot.rtc.role.trim().toLowerCase()) {
      'broadcaster' || 'publisher' || 'host' || 'speaker' || 'anchor' => true,
      _ => false,
    };
  }

  bool _seatPermitsAudio(RoomSnapshot snapshot) {
    final seat = _seatInSnapshot(snapshot);
    return seat != null &&
        seat.isOccupied &&
        seat.isOnline &&
        seat.state != MicSeatState.occupiedMuted &&
        seat.audioMute != null &&
        !seat.audioMute!.effectiveMuted;
  }

  bool _isNewMicGrant(RoomSnapshot? previous, RoomSnapshot next) {
    final seat = _seatInSnapshot(next);
    return previous != null &&
        previous.sessionId == next.sessionId &&
        _seatInSnapshot(previous)?.isOccupied != true &&
        seat?.isOccupied == true &&
        seat!.occupantJoinedAt != null &&
        DateTime.tryParse(seat.occupantJoinedAt!) != null;
  }

  bool _sameGrant(RoomSnapshot expected, RoomSnapshot next) {
    final before = _seatInSnapshot(expected), after = _seatInSnapshot(next);
    return expected.roomId == next.roomId &&
        expected.sessionId == next.sessionId &&
        before?.isOccupied == true &&
        after?.isOccupied == true &&
        before!.number == after!.number &&
        before.occupantJoinedAt == after.occupantJoinedAt;
  }

  bool _isRtcAuthorityEvent(int code) {
    return switch (code) {
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

  Future<void> _disableRtcPublication({bool force = false}) async {
    final transportLease = _transportLeaseId;
    await _withRtcAudioMutex<void>(() async {
      if (!_ownsRtcTransport(transportLease) ||
          (!force && !_rtcConnected && !_rtcPublicationActive)) {
        return;
      }
      try {
        await _rtcAdapter.setLocalAudioEnabled(false);
      } catch (_) {
        // If a provider refuses the mute operation during a role revoke, leave
        // the channel so publication is still fail-closed.
        try {
          if (_ownsRtcTransport(transportLease)) await _rtcAdapter.leave();
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

  static Future<void> _ignoreTencentLeave(Future<void> leave) async {
    try {
      await leave;
    } catch (_) {
      // Provider cleanup is best effort. The first-party HTTP room state owns
      // the user-visible leave/compensation result.
    }
  }

  static Future<void> _ignoreTencentEnter(
    Future<TencentImAvChatRoomJoinResult> enter,
  ) async {
    try {
      await enter;
    } catch (_) {
      // Provider join is optional. The first-party HTTP room stays usable
      // when the SDK rejects, times out, or is unavailable.
    }
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
    _stopRoomLease();
    _stopAuthoritySync();
    _sessionChanges?.removeListener(_onSessionChanged);
    _lifecycleBinding?.removeObserver(this);
    unawaited(_backgroundAudioSubscription?.cancel());
    _backgroundAudioSubscription = null;
    _invalidateTencentImReadinessPoll();
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
    final TencentImAvChatRoomCoordinator? tencentCoordinator =
        _tencentImAvChatRoomCoordinator;
    final TencentImAvChatRoomSession? tencentSession = _tencentImSession;
    _tencentImSession = null;
    _tencentImRefreshRegistration?.cancel();
    _tencentImRefreshRegistration = null;
    if (tencentCoordinator != null && tencentSession != null) {
      unawaited(
        tencentCoordinator.leaveIfCurrent(
          roomId: tencentSession.roomId,
          sessionId: tencentSession.sessionId,
        ),
      );
    }
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

  static Duration _positiveDuration(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'duration must be positive');
    }
    return value;
  }
}

class _CancelableTencentImReadinessWait {
  _CancelableTencentImReadinessWait(Duration duration) {
    _timer = Timer(duration, () => _complete(true));
  }

  final Completer<bool> _completer = Completer<bool>();
  late final Timer _timer;

  Future<bool> get future => _completer.future;

  void cancel() {
    _timer.cancel();
    _complete(false);
  }

  void _complete(bool value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }
}

class _PublicMessageSubmission {
  const _PublicMessageSubmission(this.future);

  final Future<bool> future;
}
