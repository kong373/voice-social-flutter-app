import 'dart:async';

import 'package:voice_social_app/features/im/domain/im_room_events.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/tencent_im_room_models.dart';

/// The result of applying a server-authorized room-enter response.
enum TencentImAvChatRoomJoinMode { joined, httpOnly, stale }

class TencentImAvChatRoomJoinResult {
  const TencentImAvChatRoomJoinResult({
    required this.mode,
    required this.session,
  });

  final TencentImAvChatRoomJoinMode mode;
  final TencentImAvChatRoomSession? session;

  bool get providerJoined => mode == TencentImAvChatRoomJoinMode.joined;

  bool get isHttpOnly => mode == TencentImAvChatRoomJoinMode.httpOnly;
}

/// Minimal safe AVChatRoom coordinator.
///
/// Room enter remains an authoritative HTTP operation owned by the room
/// repository. Once that operation has returned the strict
/// `roomId/sessionId/version/realtimeGroup` data, call [enter] (or
/// [enterFromBackend]) to make the optional provider join. A group custom
/// element is never rendered or treated as authorization: after the adapter's
/// sender/group trust boundary, it only invokes [refreshRoom], which must call
/// the first-party public-messages/snapshot endpoints.
class TencentImAvChatRoomCoordinator {
  TencentImAvChatRoomCoordinator({
    required ImSessionAdapter sessionAdapter,
    Future<void> Function(String roomId)? refreshRoom,
    // Compatibility aliases keep this seam easy to wire from room code while
    // retaining one callback contract.
    Future<void> Function(String roomId)? onAuthoritativeRefresh,
    Future<void> Function(String roomId)? onRefresh,
    DateTime Function()? now,
    this.operationTimeout = const Duration(seconds: 15),
  }) : assert(operationTimeout > Duration.zero),
       _sessionAdapter = sessionAdapter,
       _groupCapability = sessionAdapter is ImRoomGroupCapability
           ? sessionAdapter as ImRoomGroupCapability
           : null,
       _refreshRoom =
           refreshRoom ?? onAuthoritativeRefresh ?? onRefresh ?? _ignoreRefresh,
       _now = now ?? DateTime.now {
    final ImRoomGroupCapability? capability = _groupCapability;
    if (capability != null) {
      _roomEventSubscription = capability.roomEvents.listen(_handleRoomEvent);
    }
    // A room may be entered while the account-scoped Tencent login is still
    // in flight. Keep the HTTP room usable in that window, then retry the
    // exact current READY authorization when the adapter announces readiness.
    _sessionStateSubscription = _sessionAdapter.states.listen(
      _handleSessionState,
    );
  }

  final ImSessionAdapter _sessionAdapter;
  final ImRoomGroupCapability? _groupCapability;
  final Future<void> Function(String roomId) _refreshRoom;
  final DateTime Function() _now;
  final Duration operationTimeout;

  StreamSubscription<ImRoomRefreshEvent>? _roomEventSubscription;
  StreamSubscription<ImSessionState>? _sessionStateSubscription;
  Future<void> _serialTail = Future<void>.value();
  final Map<String, _RoomRefreshHandler> _refreshHandlers =
      <String, _RoomRefreshHandler>{};
  TencentImAvChatRoomSession? _activeSession;
  TencentImAvChatRoomSession? _pendingSession;
  String? _joinedGroupId;
  int _generation = 0;
  int? _lastAcceptedEventVersion;
  final Map<String, int> _acceptedVersionsByMessage = <String, int>{};
  bool _disposed = false;

  TencentImAvChatRoomSession? get activeSession => _activeSession;

  String? get activeGroupId => _joinedGroupId;

  bool get providerAvailable =>
      !_disposed &&
      (_groupCapability?.supportsAvChatRoom ?? false) &&
      _sessionAdapter.isReady;

  /// Registers the room controller's authoritative HTTP refresh callback on
  /// the shared app coordinator. The returned registration is token-scoped:
  /// disposing an older controller can never remove a newer controller's
  /// callback for the same room ID.
  TencentImRoomRefreshRegistration registerRefreshHandler({
    required String roomId,
    required Future<void> Function(String roomId) onRefresh,
  }) {
    _ensureNotDisposed();
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', '房间 ID 不能为空');
    }
    final _RoomRefreshHandler handler = _RoomRefreshHandler(onRefresh);
    _refreshHandlers[normalizedRoomId] = handler;
    return TencentImRoomRefreshRegistration(() {
      if (identical(_refreshHandlers[normalizedRoomId], handler)) {
        _refreshHandlers.remove(normalizedRoomId);
      }
    });
  }

  /// Parses a successful HTTP enter `data` object and then applies the room
  /// join gate. The optional expected room ID prevents a response for another
  /// room from being rebound to the current navigation target.
  Future<TencentImAvChatRoomJoinResult> enterFromBackend(
    Object? raw, {
    String? expectedRoomId,
  }) => enter(
    TencentImAvChatRoomSession.fromBackendData(
      raw,
      now: _now(),
      expectedRoomId: expectedRoomId,
    ),
  );

  /// Applies one strict server-enter result. An unavailable or not-yet-ready
  /// provider deliberately returns [TencentImAvChatRoomJoinMode.httpOnly]; it
  /// never fabricates a vendor success or blocks the authoritative HTTP room.
  Future<TencentImAvChatRoomJoinResult> enter(
    TencentImAvChatRoomSession session,
  ) {
    _ensureNotDisposed();
    _pendingSession = session;
    final int generation = ++_generation;
    final TencentImAvChatRoomSession? previous = _activeSession;
    // Fence callbacks synchronously, before the bounded old-group cleanup is
    // queued. This is what drops late events during a room switch.
    _activeSession = null;
    _joinedGroupId = null;
    _resetEventDedupe();
    return _serialize(
      () => _enterInternal(session, previous: previous, generation: generation),
    );
  }

  /// Leaves the provider group, if any, without making room HTTP state depend
  /// on a vendor response. The group call is bounded by the adapter and this
  /// coordinator's timeout, and local fences are cleared first.
  Future<void> leave() {
    if (_disposed) {
      return Future<void>.value();
    }
    final int generation = ++_generation;
    final TencentImAvChatRoomSession? previous = _activeSession;
    _pendingSession = null;
    _activeSession = null;
    _joinedGroupId = null;
    _resetEventDedupe();
    return _serialize(() => _leaveInternal(previous, generation: generation));
  }

  /// Leaves only when the active (or still-pending) binding belongs to the
  /// caller. This matters because [AppDependencies] owns one coordinator
  /// while a route can dispose an older controller after a newer room has
  /// already taken over the shared Tencent account.
  Future<void> leaveIfCurrent({required String roomId, String? sessionId}) {
    if (_disposed) {
      return Future<void>.value();
    }
    final String normalizedRoomId = roomId.trim();
    final TencentImAvChatRoomSession? active = _activeSession;
    final TencentImAvChatRoomSession? pending = _pendingSession;
    final TencentImAvChatRoomSession? candidate = active ?? pending;
    if (candidate == null || candidate.roomId != normalizedRoomId) {
      return Future<void>.value();
    }
    if (sessionId != null && candidate.sessionId != sessionId) {
      return Future<void>.value();
    }
    return leave();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    final int generation = ++_generation;
    final TencentImAvChatRoomSession? previous = _activeSession;
    _pendingSession = null;
    _activeSession = null;
    _joinedGroupId = null;
    _resetEventDedupe();
    _disposed = true;
    _refreshHandlers.clear();
    await _serialize(() => _leaveInternal(previous, generation: generation));
    await _roomEventSubscription?.cancel();
    _roomEventSubscription = null;
    await _sessionStateSubscription?.cancel();
    _sessionStateSubscription = null;
  }

  Future<TencentImAvChatRoomJoinResult> _enterInternal(
    TencentImAvChatRoomSession session, {
    required TencentImAvChatRoomSession? previous,
    required int generation,
  }) async {
    await _leaveInternal(previous, generation: generation);
    if (!_isCurrentGeneration(generation)) {
      return const TencentImAvChatRoomJoinResult(
        mode: TencentImAvChatRoomJoinMode.stale,
        session: null,
      );
    }
    if (!session.hasActiveLease(_now())) {
      return const TencentImAvChatRoomJoinResult(
        mode: TencentImAvChatRoomJoinMode.stale,
        session: null,
      );
    }
    _activeSession = session;
    _pendingSession = null;
    // PENDING is an explicit HTTP-only state. It is retained by the room
    // controller for a bounded readiness poll, but it can never authorize a
    // native AVChatRoom join.
    if (!session.isReady) {
      return TencentImAvChatRoomJoinResult(
        mode: TencentImAvChatRoomJoinMode.httpOnly,
        session: session,
      );
    }
    final ImRoomGroupCapability? capability = _groupCapability;
    if (capability == null ||
        !capability.supportsAvChatRoom ||
        !_sessionAdapter.isReady) {
      return TencentImAvChatRoomJoinResult(
        mode: TencentImAvChatRoomJoinMode.httpOnly,
        session: session,
      );
    }

    bool joined = false;
    try {
      joined = await capability
          .joinGroup(groupId: session.groupId, groupType: session.groupType)
          .timeout(operationTimeout);
    } on Object {
      // A provider rejection or outage must not replace the authoritative
      // room snapshot. Keep the session HTTP-only and expose no SDK details.
      joined = false;
    }
    if (!joined || !_isCurrentBinding(session, generation)) {
      if (joined) {
        await _quitGroupBounded(capability, session.groupId);
      }
      return TencentImAvChatRoomJoinResult(
        mode: _isCurrentGeneration(generation)
            ? TencentImAvChatRoomJoinMode.httpOnly
            : TencentImAvChatRoomJoinMode.stale,
        session: _isCurrentGeneration(generation) ? session : null,
      );
    }
    if (!session.hasActiveLease(_now())) {
      await _quitGroupBounded(capability, session.groupId);
      _activeSession = null;
      _joinedGroupId = null;
      return const TencentImAvChatRoomJoinResult(
        mode: TencentImAvChatRoomJoinMode.stale,
        session: null,
      );
    }
    _joinedGroupId = session.groupId;
    return TencentImAvChatRoomJoinResult(
      mode: TencentImAvChatRoomJoinMode.joined,
      session: session,
    );
  }

  Future<void> _leaveInternal(
    TencentImAvChatRoomSession? previous, {
    required int generation,
  }) async {
    final ImRoomGroupCapability? capability = _groupCapability;
    final String? groupId = previous?.groupId ?? _joinedGroupId;
    if (capability == null || groupId == null || groupId.isEmpty) {
      return;
    }
    // The local fence has already been cleared. A late provider completion
    // therefore cannot make a previous group current again.
    await _quitGroupBounded(capability, groupId);
  }

  Future<void> _handleRoomEvent(ImRoomRefreshEvent event) async {
    if (_disposed) {
      return;
    }
    final TencentImAvChatRoomSession? session = _activeSession;
    final ImRoomGroupCapability? capability = _groupCapability;
    if (session == null ||
        capability == null ||
        !capability.supportsAvChatRoom) {
      return;
    }
    if (_joinedGroupId != session.groupId || event.groupId != session.groupId) {
      return;
    }
    if (event.sessionId != null && event.sessionId != session.sessionId) {
      return;
    }
    if (!session.hasActiveLease(_now())) {
      return;
    }
    final ImRefreshHintVersionFence fence = ImRefreshHintVersionFence(
      event.hint.messageId,
      event.hint.eventVersion,
      _acceptedVersionsByMessage,
      _lastAcceptedEventVersion,
    );
    if (!fence.accept()) {
      return;
    }
    _lastAcceptedEventVersion = fence.nextLastVersion;
    final int generation = _generation;
    // A custom group element carries no message body, room decision, or
    // authorization. It can only cause a current-room authoritative refresh.
    if (!_isCurrentSession(session, generation)) {
      return;
    }
    final Future<void> Function(String roomId) refresh =
        _refreshHandlers[session.roomId]?.callback ?? _refreshRoom;
    try {
      await refresh(session.roomId);
    } on Object {
      // Keep the current HTTP-rendered state on refresh failure. Error details
      // from the provider/repository are intentionally not re-emitted here.
    }
  }

  void _handleSessionState(ImSessionState state) {
    if (_disposed || !state.isReady) {
      return;
    }
    final TencentImAvChatRoomSession? session = _activeSession;
    final ImRoomGroupCapability? capability = _groupCapability;
    if (session == null ||
        !session.isReady ||
        _joinedGroupId != null ||
        capability == null ||
        !capability.supportsAvChatRoom) {
      return;
    }
    final int generation = _generation;
    // Serialize with enter/leave so a late login cannot race a room switch.
    // Provider errors are intentionally swallowed by the retry operation and
    // leave the authoritative HTTP room in place.
    unawaited(_serialize<void>(() => _retryCurrentJoin(session, generation)));
  }

  Future<void> _retryCurrentJoin(
    TencentImAvChatRoomSession session,
    int generation,
  ) async {
    final ImRoomGroupCapability? capability = _groupCapability;
    if (capability == null ||
        !capability.supportsAvChatRoom ||
        !_sessionAdapter.isReady ||
        !session.isReady ||
        !_isCurrentBinding(session, generation) ||
        _joinedGroupId != null) {
      return;
    }
    bool joined = false;
    try {
      joined = await capability
          .joinGroup(groupId: session.groupId, groupType: session.groupType)
          .timeout(operationTimeout);
    } on Object {
      joined = false;
    }
    if (!joined || !_isCurrentBinding(session, generation)) {
      if (joined) {
        await _quitGroupBounded(capability, session.groupId);
      }
      return;
    }
    _joinedGroupId = session.groupId;
  }

  bool _isCurrentGeneration(int generation) =>
      !_disposed && generation == _generation;

  bool _isCurrentSession(TencentImAvChatRoomSession session, int generation) =>
      _isCurrentBinding(session, generation) &&
      _joinedGroupId == session.groupId;

  bool _isCurrentBinding(TencentImAvChatRoomSession session, int generation) =>
      _isCurrentGeneration(generation) &&
      identical(_activeSession, session) &&
      session.hasActiveLease(_now());

  Future<void> _quitGroupBounded(
    ImRoomGroupCapability capability,
    String groupId,
  ) async {
    try {
      await capability.quitGroup(groupId: groupId).timeout(operationTimeout);
    } on Object {
      // Bounded cleanup is best effort. The local generation fence is already
      // invalidated, so a timed-out native call cannot authorize old events.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<void> previous = _serialTail;
    final Future<T> operation = previous.then<T>((_) => action());
    _serialTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  void _resetEventDedupe() {
    _lastAcceptedEventVersion = null;
    _acceptedVersionsByMessage.clear();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('腾讯 IM 房间适配器已释放');
    }
  }

  static Future<void> _ignoreRefresh(String _) async {}
}

class _RoomRefreshHandler {
  const _RoomRefreshHandler(this.callback);

  final Future<void> Function(String roomId) callback;
}

/// Token-scoped registration for a room controller callback.
class TencentImRoomRefreshRegistration {
  TencentImRoomRefreshRegistration(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _onCancel();
  }
}

/// Small value helper kept private to the coordinator so duplicate/stale
/// event-version policy cannot be bypassed by a callback implementation.
class ImRefreshHintVersionFence {
  ImRefreshHintVersionFence(
    this.messageId,
    this.version,
    this.seenByMessage,
    this.previousGlobalVersion,
  );

  final String messageId;
  final int version;
  final Map<String, int> seenByMessage;
  final int? previousGlobalVersion;

  int? nextLastVersion;

  bool accept() {
    final int? previousForMessage = seenByMessage[messageId];
    if (previousForMessage != null && version <= previousForMessage) {
      return false;
    }
    if (previousGlobalVersion != null && version <= previousGlobalVersion!) {
      return false;
    }
    seenByMessage[messageId] = version;
    nextLastVersion = version;
    return true;
  }
}

// Compatibility aliases for room integration code that uses the shorter
// AVChatRoom spelling.
typedef TencentImAVChatRoomCoordinator = TencentImAvChatRoomCoordinator;
typedef TencentImRoomCoordinator = TencentImAvChatRoomCoordinator;
