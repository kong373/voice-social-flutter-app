import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import '../domain/room_pk_models.dart';
import '../domain/room_pk_repository.dart';

/// PK-only HTTP recovery. The existing room controller remains the permission
/// and membership owner; this object never joins a room or accepts an invite.
class RoomPkSyncController extends ChangeNotifier with WidgetsBindingObserver {
  RoomPkSyncController({
    required this.repository,
    required this.room,
    required this.session,
    this.battleId,
    this.routeIsCurrent,
  }) : _identity = session.identityGeneration,
       _userId = session.session?.userId,
       _roomSession = room.snapshot?.sessionId {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    session.addListener(_authorityChanged);
    room.addListener(_authorityChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final RoomPkRepository repository;
  final RoomController room;
  final AuthSessionManager session;
  final String? battleId;
  final bool Function()? routeIsCurrent;
  final int _identity;
  final int? _userId;
  final String? _roomSession;
  final Set<String> _waiting = {};
  // The banner and preparation route share only navigation IDs for this room
  // entry. Weak keys release them with the RoomController, not with a child page.
  static final _openedByRoom = Expando<Set<String>>();
  Set<String> get _opened => _openedByRoom[room] ??= <String>{};
  Timer? _timer;
  Future<void>? _flight;
  bool _pending = false, _writing = false, _visible = false;
  bool _foreground = true, _disposed = false, _invalid = false;
  bool _lastAllowed = false;
  int _generation = 0;
  int _flightGeneration = -1;
  RoomPkProcess? process;
  String? error;

  bool get _sameIdentity =>
      !_invalid &&
      !_disposed &&
      session.identityGeneration == _identity &&
      session.session?.userId == _userId &&
      _userId == room.currentUserId &&
      room.isEntryIdentityCurrent &&
      room.snapshot?.roomId == room.roomId &&
      room.snapshot?.sessionId == _roomSession;
  bool get _authorized =>
      _sameIdentity &&
      room.status == RoomSessionStatus.joined &&
      room.allows(RoomCapability.startPk);
  bool get canRead =>
      _authorized &&
      _foreground &&
      _visible &&
      (routeIsCurrent?.call() ?? true);
  bool get busy => _writing;
  bool get invalidated => !_sameIdentity;

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _pause();
    if (canRead) unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pause();
    if (canRead) unawaited(refresh());
  }

  void _authorityChanged() {
    if (_disposed) return;
    if (!_sameIdentity ||
        const [
          RoomSessionStatus.left,
          RoomSessionStatus.closed,
          RoomSessionStatus.kicked,
        ].contains(room.status))
      _invalid = true;
    final allowed = canRead;
    if (!_authorized) {
      _waiting.clear();
      _pause();
    } else if (!_lastAllowed) {
      unawaited(refresh());
    }
    _lastAllowed = allowed;
  }

  void _pause() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending = false;
    process = null;
    error = null;
    if (!_disposed) notifyListeners();
  }

  void Function() captureCurrent() {
    final generation = _generation;
    return () {
      if (!canRead || generation != _generation) {
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: 'PK 登录或房间读取状态已改变',
        );
      }
    };
  }

  Future<void> refresh() {
    if (!canRead || _writing) return Future.value();
    if (_flight != null) {
      if (_flightGeneration != _generation) _pending = true;
      return _flight!;
    }
    _timer?.cancel();
    final completion = Completer<void>();
    _flight = completion.future;
    unawaited(() async {
      try {
        do {
          _pending = false;
          _flightGeneration = _generation;
          final current = captureCurrent();
          try {
            current();
            final value = await repository.fetchProcess(
              roomId: room.roomId,
              requireCurrent: current,
            );
            current();
            if (value.invitation?.currentRoomId != null &&
                    value.invitation!.currentRoomId != room.roomId ||
                value.battle?.currentRoomId != null &&
                    value.battle!.currentRoomId != room.roomId ||
                battleId != null && value.battle?.id != battleId) {
              throw const ApiException(
                kind: ApiFailureKind.conflict,
                message: '当前 PK 对局已变化',
              );
            }
            process = value;
            error = null;
            final invitation = value.invitation;
            _waiting.retainWhere((id) => id == invitation?.id);
            if (invitation?.status == RoomPkInvitationStatus.pending)
              _waiting.add(invitation!.id);
            if (invitation != null &&
                invitation.status != RoomPkInvitationStatus.pending &&
                invitation.status != RoomPkInvitationStatus.accepted)
              _waiting.remove(invitation.id);
            notifyListeners();
          } catch (cause) {
            try {
              current();
            } catch (_) {
              continue;
            }
            process = null;
            error = cause is ApiException ? cause.message : 'PK 状态暂未更新，正在重试';
            if (cause is ApiException &&
                (cause.httpStatus == 401 ||
                    cause.httpStatus == 403 ||
                    cause.httpStatus == 404)) {
              _invalid = true;
              _waiting.clear();
            }
            notifyListeners();
          }
        } while (_pending && canRead && !_writing);
      } finally {
        _flight = null;
        if (canRead &&
            !_writing &&
            !(battleId != null && process?.battle?.isActive == false)) {
          _timer = Timer(
            const Duration(seconds: 3),
            () => unawaited(refresh()),
          );
        }
        completion.complete();
      }
    }());
    return completion.future;
  }

  /// Explicit user writes only. A post response is not navigation authority:
  /// completion triggers a fresh GET of the current room before opening battle.
  Future<T> write<T>(Future<T> Function(void Function()) action) async {
    if (_writing) throw StateError('PK 操作进行中');
    captureCurrent()();
    _generation++;
    _timer?.cancel();
    _writing = true;
    final current = captureCurrent();
    notifyListeners();
    try {
      final value = await action(current);
      current();
      if (value is RoomPkInvitation) _waiting.add(value.id);
      if (value is RoomPkBattle && value.invitationId != null)
        _waiting.add(value.invitationId!);
      return value;
    } finally {
      _writing = false;
      if (!_disposed) {
        notifyListeners();
        if (canRead) unawaited(refresh());
      }
    }
  }

  RoomPkBattle? claimAutomaticBattle() {
    final value = process?.battle;
    if (!canRead ||
        battleId != null ||
        value == null ||
        !value.isActive ||
        process?.invitation?.status != RoomPkInvitationStatus.accepted ||
        process?.invitation?.id != value.invitationId ||
        !_waiting.contains(value.invitationId) ||
        _opened.contains(value.id))
      return null;
    _opened.add(value.id);
    return value;
  }

  void markOpened(RoomPkBattle battle) => _opened.add(battle.id);

  @override
  void dispose() {
    _disposed = true;
    _pause();
    _waiting.clear();
    session.removeListener(_authorityChanged);
    room.removeListener(_authorityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
