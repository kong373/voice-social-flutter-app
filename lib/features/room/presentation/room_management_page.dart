import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_authority_display.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

enum _ManagementSection { members, seats, requests, bannedUsers }

class RoomManagementPage extends StatelessWidget {
  const RoomManagementPage({
    required this.roomId,
    required this.currentUserId,
    required this.currentRole,
    required this.seats,
    this.roomCode,
    this.roomTitle,
    this.initialMemberId,
    this.coordinationMode,
    this.repositoryOverride,
    this.authorityRepositoryOverride,
    super.key,
  });

  final String roomId;
  final int currentUserId;
  final RoomRole currentRole;
  final List<MicSeat> seats;
  final String? roomCode;
  final String? roomTitle;
  final int? initialMemberId;
  final MicCoordinationMode? coordinationMode;
  final RoomOperationsRepository? repositoryOverride;
  final RoomAuthorityRepository? authorityRepositoryOverride;

  @override
  Widget build(BuildContext context) => _RoomManagementSession(
    key: ValueKey((
      roomId,
      currentUserId,
      currentRole,
      coordinationMode,
      repositoryOverride,
      authorityRepositoryOverride,
    )),
    configuration: this,
  );
}

// Bind all cached reads and pending operations to one room/viewer identity.
// Replacing the public widget disposes this state before old replies can apply.
class _RoomManagementSession extends StatefulWidget {
  const _RoomManagementSession({required this.configuration, super.key});

  final RoomManagementPage configuration;

  @override
  State<_RoomManagementSession> createState() => _RoomManagementPageState();
}

class _RoomManagementPageState extends State<_RoomManagementSession>
    with WidgetsBindingObserver {
  static const String _managementOverlayRouteName = 'room-management-overlay';

  RoomManagementPage get configuration => widget.configuration;
  Timer? _queueTimer;
  bool _foreground = true;
  bool _routeVisible = false;
  bool _queueReading = false;
  bool _queueKnown = false;
  bool _queuePending = false;
  int _queueGeneration = 0;
  String? _queueError;
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  RoomBanRepository? _banRepository;
  RoomAuthorityRepository? _authorityRepository;
  int _loadGeneration = 0;
  final List<RoomMember> _members = <RoomMember>[];
  final List<MicAccessRequest> _requests = <MicAccessRequest>[];
  final List<RoomBannedUser> _bannedUsers = <RoomBannedUser>[];
  late List<MicSeat> _seats;
  _ManagementSection _section = _ManagementSection.members;
  bool _loading = true;
  bool _changed = false;
  String? _error;
  int? _busyUserId;
  int? _busySeatNumber;
  String? _busyMicRequestId;
  bool _selectingMicTarget = false;
  (MicAccessRequest, bool, int?)? _pendingMicDecision;
  (RoomMember, MicSeat)? _pendingAssignment;
  (MicSeat, bool)? _pendingAudioDecision;
  AuthSessionManager? _session;
  int? _identity;
  int? _leaseGeneration;
  RoomRole? _authoritativeRole;
  int _managementGeneration = 0;
  int _authorityRequestGeneration = 0;
  Future<RoomAuthorityProjection>? _authorityFlight;
  int? _authorityFlightGeneration;
  int _managementOverlayDepth = 0;
  bool _managementWasAuthorized = false;

  bool get _currentSession =>
      mounted &&
      _session?.identityGeneration == _identity &&
      (_repositoryInstance is! BackendRoomOperationsRepository ||
          (_repositoryInstance as BackendRoomOperationsRepository)
                  .leaseBinding
                  .generation ==
              _leaseGeneration);

  RoomRole get _role =>
      _authoritativeRole ??
      (_authorityRepository != null ||
              _repositoryInstance is BackendRoomOperationsRepository
          ? RoomRole.guest
          : configuration.currentRole);

  bool get _isOwner => _role == RoomRole.owner;
  bool get _canManage =>
      _currentSession && (_isOwner || _role == RoomRole.moderator);
  bool get _supportsMicRequests => _canManage;

  bool get _canSyncAuthority =>
      mounted &&
      _foreground &&
      _routeVisible &&
      _authorityRepository != null &&
      _currentSession &&
      (_authoritativeRole == null || _canManage);

  bool get _canScheduleManagementSync =>
      _canSyncAuthority ||
      (_canSyncQueue &&
          _pendingMicDecision == null &&
          _busyMicRequestId == null);

  bool _isCurrentOperation(int generation) =>
      generation == _managementGeneration && _currentSession;

  bool _canGovern(RoomMember member) =>
      _canManage &&
      member.userId != configuration.currentUserId &&
      member.role != RoomRole.owner &&
      (_isOwner || !member.isManager);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _seats = List<MicSeat>.of(configuration.seats);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeVisible != visible) {
      _routeVisible = visible;
      _pauseQueueSync();
      if (_repositoryInstance != null) _refreshQueue();
    }
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance =
        configuration.repositoryOverride ??
        AppDependencyScope.of(context).roomOperationsRepository;
    _banRepository = _repositoryInstance!.roomBanCapability;
    _session = context
        .dependOnInheritedWidgetOfExactType<AppDependencyScope>()
        ?.dependencies
        .sessionManager;
    _identity = _session?.identityGeneration;
    _session?.addListener(_onSessionChanged);
    final repository = _repositoryInstance;
    if (repository is BackendRoomOperationsRepository) {
      _leaseGeneration = repository.leaseBinding.generation;
      repository.leaseBinding.addListener(_onLeaseChanged);
    }
    final roomRepository =
        configuration.authorityRepositoryOverride ??
        (configuration.repositoryOverride == null
            ? AppDependencyScope.of(context).roomRepository
            : null);
    if (roomRepository is RoomAuthorityRepository) {
      _authorityRepository = roomRepository;
    }
    _load();
  }

  bool get _canSyncQueue =>
      mounted && _foreground && _routeVisible && _supportsMicRequests;

  void _onSessionChanged() {
    if (_currentSession) return;
    _invalidateManagementState(message: '账号或房间会话已变化，请退出后重新打开');
  }

  void _onLeaseChanged() {
    if (_currentSession) return;
    _invalidateManagementState(message: '账号或房间会话已变化，请退出后重新打开');
  }

  void _pauseQueueSync() {
    _queueTimer?.cancel();
    _queueTimer = null;
    _queueGeneration++;
    _authorityRequestGeneration++;
    _queuePending = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pauseQueueSync();
    if (_repositoryInstance != null) _refreshQueue();
  }

  @override
  void dispose() {
    _pauseQueueSync();
    _session?.removeListener(_onSessionChanged);
    if (_repositoryInstance
        case final BackendRoomOperationsRepository repository) {
      repository.leaseBinding.removeListener(_onLeaseChanged);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshQueue() => _refreshMicQueue();

  Future<RoomAuthorityProjection> _readAuthority() async {
    final authority = _authorityRepository;
    if (authority == null) {
      throw StateError('Room authority capability is unavailable');
    }
    final int requestGeneration = _authorityRequestGeneration;
    final existing = _authorityFlight;
    if (existing != null) {
      if (_authorityFlightGeneration == requestGeneration) {
        return existing;
      }
      try {
        await existing;
      } catch (_) {
        // A read from the previous visibility, lease, or identity generation
        // is only a fence. The current caller must start a fresh read below.
      }
      if (identical(_authorityFlight, existing)) {
        _authorityFlight = null;
        _authorityFlightGeneration = null;
      }
      return _readAuthority();
    }
    final Future<RoomAuthorityProjection> flight =
        Future<RoomAuthorityProjection>.sync(
          () => authority.fetchRoomAuthority(
            roomId: configuration.roomId,
            currentUserId: configuration.currentUserId,
          ),
        );
    _authorityFlight = flight;
    _authorityFlightGeneration = requestGeneration;
    unawaited(
      flight.then<void>(
        (_) => _clearAuthorityFlight(flight),
        onError: (Object _, StackTrace __) => _clearAuthorityFlight(flight),
      ),
    );
    return flight;
  }

  void _clearAuthorityFlight(Future<RoomAuthorityProjection> flight) {
    if (identical(_authorityFlight, flight)) {
      _authorityFlight = null;
      _authorityFlightGeneration = null;
    }
  }

  bool _isCurrentQueueRead(int generation) =>
      _currentSession &&
      generation == _queueGeneration &&
      _foreground &&
      _routeVisible;

  void _validateAuthorityProjection(RoomAuthorityProjection projection) {
    if (projection.snapshot.roomId != configuration.roomId ||
        projection.viewerUserId != configuration.currentUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '麦位权威响应与当前房间不一致',
      );
    }
  }

  static bool _projectionAllowsManagement(RoomAuthorityProjection projection) {
    return projection.memberActive &&
        (projection.snapshot.role == RoomRole.owner ||
            projection.snapshot.role == RoomRole.moderator);
  }

  bool _isAuthorityDowngrade(RoomAuthorityProjection projection) {
    if (_projectionAllowsManagement(projection)) return false;
    return _managementWasAuthorized ||
        (_authoritativeRole == null &&
            (configuration.currentRole == RoomRole.owner ||
                configuration.currentRole == RoomRole.moderator));
  }

  static bool _isGovernanceDenied(Object error) {
    if (error is! ApiException) return false;
    final int? code = error.code;
    return error.kind == ApiFailureKind.forbidden ||
        error.httpStatus == 403 ||
        code == 40335 ||
        (code != null && code >= 40300 && code < 40400);
  }

  void _handleGovernanceDenied(
    Object error, {
    required int managementGeneration,
  }) {
    if (!mounted || managementGeneration != _managementGeneration) return;
    _invalidateManagementState();
    if (mounted) _showMessage(_messageFor(error));
  }

  void _invalidateManagementState({String message = '房间治理权限已变化，请退出后重新打开'}) {
    if (!mounted) return;
    _managementGeneration++;
    _loadGeneration++;
    _pauseQueueSync();
    _dismissManagementOverlays();
    if (!mounted) return;
    setState(() {
      _members.clear();
      _requests.clear();
      _bannedUsers.clear();
      _seats = <MicSeat>[];
      _pendingMicDecision = null;
      _pendingAssignment = null;
      _pendingAudioDecision = null;
      _selectingMicTarget = false;
      _busyUserId = null;
      _busySeatNumber = null;
      _busyMicRequestId = null;
      _queueKnown = false;
      _queueError = null;
      _authoritativeRole = RoomRole.guest;
      _section = _ManagementSection.members;
      _loading = false;
      _error = message;
    });
  }

  void _beginManagementOverlay() => _managementOverlayDepth++;

  void _endManagementOverlay() {
    if (_managementOverlayDepth > 0) _managementOverlayDepth--;
  }

  void _dismissManagementOverlays() {
    if (!mounted || _managementOverlayDepth == 0) return;
    Navigator.of(context).popUntil(
      (Route<dynamic> route) =>
          route.settings.name != _managementOverlayRouteName,
    );
    _managementOverlayDepth = 0;
  }

  // One visible timer drives both authority and queue reads. Authority is
  // read first so a stale manager cannot continue to fetch or act on a queue.
  Future<void> _refreshMicQueue() async {
    final bool hasAuthority = _authorityRepository != null;
    if ((hasAuthority && !_canSyncAuthority) ||
        (!hasAuthority && !_canSyncQueue) ||
        (!hasAuthority && _pendingMicDecision != null)) {
      return;
    }
    _queuePending = true;
    if (_queueReading) return;
    _queueTimer?.cancel();
    _queueReading = true;
    try {
      do {
        _queuePending = false;
        final generation = _queueGeneration;
        final managementGeneration = _managementGeneration;
        try {
          if (hasAuthority) {
            final projection = await _readAuthority();
            if (!_isCurrentQueueRead(generation)) continue;
            _validateAuthorityProjection(projection);
            if (!_projectionAllowsManagement(projection)) {
              if (_isAuthorityDowngrade(projection)) {
                _invalidateManagementState();
                return;
              }
              if (_authoritativeRole != projection.snapshot.role) {
                setState(() => _authoritativeRole = projection.snapshot.role);
              }
              continue;
            }
            _managementWasAuthorized = true;
            if (_authoritativeRole != projection.snapshot.role) {
              setState(() => _authoritativeRole = projection.snapshot.role);
            }
          }
          if (!_canSyncQueue ||
              _pendingMicDecision != null ||
              _busyMicRequestId != null) {
            continue;
          }
          final requests = await _repository.fetchMicRequests(
            configuration.roomId,
          );
          if (!_isCurrentQueueRead(generation) || !_canSyncQueue) continue;
          setState(() {
            _requests
              ..clear()
              ..addAll(
                requests.where((item) => item.isRequest && item.isPending),
              );
            _queueError = null;
            _queueKnown = true;
          });
        } catch (error) {
          if (_isGovernanceDenied(error)) {
            _handleGovernanceDenied(
              error,
              managementGeneration: managementGeneration,
            );
            return;
          }
          if (_isCurrentQueueRead(generation) && _canSyncQueue) {
            setState(() => _queueError = _messageFor(error));
          }
        }
      } while (_queuePending &&
          (_canSyncAuthority || _canSyncQueue) &&
          (hasAuthority || _pendingMicDecision == null) &&
          (hasAuthority || _busyMicRequestId == null));
    } finally {
      _queueReading = false;
      if (_canScheduleManagementSync) {
        _queueTimer = Timer(const Duration(seconds: 2), _refreshMicQueue);
      }
    }
  }

  Future<void> _load() async {
    _pauseQueueSync();
    final generation = ++_loadGeneration;
    final managementGeneration = _managementGeneration;
    if (_authorityRepository == null) unawaited(_refreshQueue());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Future<Object>> futures = <Future<Object>>[
        _repository.fetchOnlineMembers(
          roomId: configuration.roomId,
          page: 1,
          // Backend room-member pages cap pageSize at 50.
          pageSize: 50,
        ),
        _repository.fetchMutedUsers(configuration.roomId),
        _repository.fetchManagers(configuration.roomId),
      ];
      if (_banRepository != null) {
        futures.add(
          _banRepository!.fetchBannedUsers(
            roomId: configuration.roomId,
            page: 1,
            pageSize: 50,
          ),
        );
      }
      final authority = _authorityRepository;
      if (authority != null) {
        futures.add(_readAuthority());
      }
      final List<Object> results = await Future.wait<Object>(futures);
      if (!_currentSession || generation != _loadGeneration) return;
      final projection = authority == null
          ? null
          : results.last as RoomAuthorityProjection;
      if (projection != null &&
          (projection.snapshot.roomId != configuration.roomId ||
              projection.viewerUserId != configuration.currentUserId)) {
        _validateAuthorityProjection(projection);
      }
      if (projection != null && !_projectionAllowsManagement(projection)) {
        if (_isAuthorityDowngrade(projection)) {
          _invalidateManagementState();
          return;
        }
      }
      if (projection != null && _projectionAllowsManagement(projection)) {
        _managementWasAuthorized = true;
      }
      final RoomMemberPage page = results[0] as RoomMemberPage;
      final List<RoomMember> muted = results[1] as List<RoomMember>;
      final List<RoomMember> managers = results[2] as List<RoomMember>;
      final RoomBannedUserPage? bannedUserPage = _banRepository == null
          ? null
          : results[3] as RoomBannedUserPage;
      final Set<int> mutedIds = muted
          .map((RoomMember member) => member.userId)
          .toSet();
      final Map<int, RoomRole> roles = <int, RoomRole>{
        for (final RoomMember manager in managers) manager.userId: manager.role,
      };
      // Member pagination cannot prove seat occupancy or empty-seat locks.
      // Offline previews without authority retain their supplied seat snapshot.
      final List<MicSeat> reconciledSeats = [
        for (final seat in projection?.snapshot.seats ?? _seats)
          seat.copyWith(userRole: roles[seat.userId] ?? seat.userRole),
      ];
      final List<RoomMember> members = <RoomMember>[
        for (final RoomMember member in page.items)
          member.copyWith(
            role: roles[member.userId] ?? member.role,
            presence: member.presence,
            seatNumber: member.seatNumber,
            clearSeatNumber: !member.isOnMic,
            isMuted: mutedIds.contains(member.userId),
          ),
      ];
      members.sort((RoomMember left, RoomMember right) {
        if (left.userId == configuration.initialMemberId) {
          return -1;
        }
        if (right.userId == configuration.initialMemberId) {
          return 1;
        }
        if (left.isManager != right.isManager) {
          return left.isManager ? -1 : 1;
        }
        return left.name.compareTo(right.name);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _authoritativeRole = projection?.snapshot.role ?? _authoritativeRole;
        _members
          ..clear()
          ..addAll(members);
        _bannedUsers
          ..clear()
          ..addAll(bannedUserPage?.items ?? const <RoomBannedUser>[]);
        _seats = reconciledSeats;
        _loading = false;
      });
      unawaited(_refreshQueue());
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: managementGeneration,
        );
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, bool? result) {},
      child: RoomPageScaffold(
        appBar: roomOxygenAppBar(
          title: '房间管理',
          leading: IconButton(
            tooltip: '返回房间',
            onPressed: () => Navigator.of(context).pop(_changed),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: '刷新权威状态',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: RoomOxygenContextBar(
                title: roomAuthorityTitle(configuration.roomTitle),
                subtitle:
                    '房间号 ${configuration.roomCode ?? configuration.roomId} · 权威状态管理',
                seed: configuration.roomId,
                status: _roleLabel,
                statusColor: _roleColor,
              ),
            ),
            _buildSectionPicker(),
            if (_pendingAssignment != null)
              TextButton(
                onPressed: _currentSession && _busyUserId == null
                    ? _retryAssignment
                    : null,
                child: const Text('重试原安排'),
              ),
            if (_pendingAudioDecision != null)
              TextButton(
                onPressed: _currentSession && _busySeatNumber == null
                    ? () => _setSeatMuted(
                        _pendingAudioDecision!.$1,
                        _pendingAudioDecision!.$2,
                      )
                    : null,
                child: const Text('重试原静音操作'),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  String get _roleLabel => switch (_role) {
    RoomRole.owner => '房主',
    RoomRole.moderator => '房管',
    RoomRole.platformModerator => '平台管理',
    _ => '成员',
  };

  Color get _roleColor => switch (_role) {
    RoomRole.owner => RoomColors.gold,
    RoomRole.moderator => RoomColors.primary,
    _ => RoomColors.accent,
  };

  Widget _buildSectionPicker() {
    final bool supportsRequests = _supportsMicRequests;
    final bool supportsBannedUsers = _banRepository != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<_ManagementSection>(
        showSelectedIcon: false,
        segments: <ButtonSegment<_ManagementSection>>[
          const ButtonSegment<_ManagementSection>(
            value: _ManagementSection.members,
            label: Text('成员治理'),
            icon: Icon(Icons.group_outlined),
          ),
          const ButtonSegment<_ManagementSection>(
            value: _ManagementSection.seats,
            label: Text('麦位管理'),
            icon: Icon(Icons.mic_none_rounded),
          ),
          if (supportsRequests)
            ButtonSegment<_ManagementSection>(
              value: _ManagementSection.requests,
              label: Text(_queueKnown ? '上麦申请 ${_requests.length}' : '上麦申请'),
              icon: const Icon(Icons.mark_unread_chat_alt_outlined),
            ),
          if (supportsBannedUsers)
            ButtonSegment<_ManagementSection>(
              value: _ManagementSection.bannedUsers,
              label: Text('房间限制 ${_bannedUsers.length}'),
              icon: const Icon(Icons.block_outlined),
            ),
        ],
        selected: <_ManagementSection>{_section},
        onSelectionChanged: (Set<_ManagementSection> value) {
          setState(() => _section = value.first);
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error =
        _error ??
        (_section == _ManagementSection.requests ? _queueError : null);
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
            ],
          ),
        ),
      );
    }
    return switch (_section) {
      _ManagementSection.members => _buildMembers(),
      _ManagementSection.seats => _buildSeats(),
      _ManagementSection.requests => _buildRequests(),
      _ManagementSection.bannedUsers => _buildBannedUsers(),
    };
  }

  Widget _buildMembers() {
    final List<RoomMember> manageable = _members
        .where(
          (RoomMember member) => member.userId != configuration.currentUserId,
        )
        .toList(growable: false);
    if (manageable.isEmpty) {
      return const Center(child: Text('当前没有可管理成员'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: manageable.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final RoomMember member = manageable[index];
        return RoomGlassCard(
          padding: EdgeInsets.zero,
          radius: 16,
          onTap: _busyUserId == null && _canGovern(member)
              ? () => _showMemberMenu(member)
              : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: RuntimeAvatar(
              seed: '${member.userId}',
              size: 44,
              ringColor: RoomColors.primary.withValues(alpha: 0.78),
            ),
            title: Row(
              children: <Widget>[
                Flexible(child: Text(member.name)),
                if (member.isManager) ...<Widget>[
                  const SizedBox(width: 6),
                  _ManagementTag(
                    label: member.role == RoomRole.owner ? '房主' : '房管',
                  ),
                ],
                if (member.isMuted) ...<Widget>[
                  const SizedBox(width: 6),
                  const _ManagementTag(label: '已禁言'),
                ],
              ],
            ),
            subtitle: Text(
              member.isOnMic && member.seatNumber != null
                  ? '${member.seatNumber} 号麦'
                  : '听众席',
            ),
            trailing: _busyUserId == member.userId
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_horiz_rounded),
          ),
        );
      },
    );
  }

  Widget _buildSeats() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: (_seats.length + 1) ~/ 2,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final int first = index * 2;
        // Action chips may wrap to two rows, especially with larger text.
        // Let each pair size to its content instead of clipping fixed-height
        // grid cells. No intrinsic layout or font-size reduction is needed.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _buildSeatCard(context, _seats[first])),
            const SizedBox(width: 10),
            Expanded(
              child: first + 1 < _seats.length
                  ? _buildSeatCard(context, _seats[first + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeatCard(BuildContext context, MicSeat seat) {
    final RoomMember? occupant = seat.isOccupied && seat.userId != null
        ? RoomMember(
            userId: seat.userId!,
            name: seat.userName ?? '用户 ${seat.userId}',
            role: seat.userRole,
            presence: RoomMemberPresence.onMic,
            seatNumber: seat.number,
          )
        : null;
    final bool locked = seat.state == MicSeatState.locked;
    final audio = seat.audioMute;
    final bool managementMuted =
        audio != null && (audio.forcedMuted || audio.legacyMuted);
    return RoomGlassCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  seat.isSpecial ? '1 号特殊麦 · 房主/房管' : '${seat.number} 号麦',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_busySeatNumber == seat.number)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            seat.userName ?? _seatStateLabel(seat),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (seat.isOccupied && !seat.isOnline) const Text('离线 · 占位保留'),
          if (seat.isOccupied && audio == null) const Text('音频权限待确认'),
          if (seat.isOccupied && audio?.selfMuted == true) const Text('个人静音'),
          if (seat.isOccupied && audio?.forcedMuted == true) const Text('管理静音'),
          if (seat.isOccupied && audio?.legacyMuted == true)
            const Text('历史静音限制'),
          Wrap(
            spacing: 4,
            children: <Widget>[
              if (occupant != null && _canGovern(occupant)) ...[
                ActionChip(
                  label: const Text('移下麦位'),
                  onPressed: _busyUserId == null
                      ? () => _takeOffMic(occupant)
                      : null,
                ),
                ActionChip(
                  label: const Text('移出房间'),
                  onPressed: _busyUserId == null
                      ? () => _kickMember(occupant)
                      : null,
                ),
              ],
              ActionChip(
                avatar: Icon(
                  locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  size: 16,
                ),
                label: Text(locked ? '解锁' : '锁定'),
                onPressed:
                    _canManage && !seat.isOccupied && _busySeatNumber == null
                    ? () => _setSeatLocked(seat, !locked)
                    : null,
              ),
              ActionChip(
                avatar: Icon(
                  managementMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                  size: 16,
                ),
                label: Text(managementMuted ? '解除管理静音' : '强制静音'),
                onPressed:
                    occupant == null ||
                        !_canGovern(occupant) ||
                        audio == null ||
                        _busySeatNumber != null
                    ? null
                    : () => _setSeatMuted(seat, !managementMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequests() {
    if (!_queueKnown) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requests.isEmpty) {
      return const Center(child: Text('当前没有待处理的上麦申请'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final MicAccessRequest request = _requests[index];
        final bool busy =
            _busyMicRequestId == request.id && !_selectingMicTarget;
        return RoomGlassCard(
          padding: EdgeInsets.zero,
          radius: 16,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: RuntimeAvatar(
              seed: '${request.member.userId}',
              size: 44,
              ringColor: RoomColors.primary.withValues(alpha: 0.78),
            ),
            title: Text(request.member.name),
            subtitle: Text('申请 ${request.seatNumber} 号麦'),
            trailing: busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _pendingMicDecision?.$1.id == request.id
                ? TextButton(
                    onPressed: _canManage
                        ? () =>
                              _resolveRequest(request, _pendingMicDecision!.$2)
                        : null,
                    child: const Text('重试原处理'),
                  )
                : Wrap(
                    spacing: 6,
                    children: <Widget>[
                      TextButton(
                        onPressed:
                            _canGovern(request.member) &&
                                _busyMicRequestId == null
                            ? () => _resolveRequest(request, false)
                            : null,
                        child: const Text('拒绝'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _canGovern(request.member) &&
                                _busyMicRequestId == null
                            ? () => _resolveRequest(request, true)
                            : null,
                        child: const Text('同意'),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildBannedUsers() {
    if (_bannedUsers.isEmpty) {
      return const Center(child: Text('当前没有受限用户'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _bannedUsers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final RoomBannedUser banned = _bannedUsers[index];
        final RoomMember member = banned.member;
        final bool busy = _busyUserId == member.userId;
        final String reason = banned.reason?.trim() ?? '';
        final String expiry = banned.expiresAt == null
            ? '无期限'
            : '限制至 ${_formatDateTime(banned.expiresAt!)}';
        return RoomGlassCard(
          padding: EdgeInsets.zero,
          radius: 16,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: RuntimeAvatar(
              seed: '${member.userId}',
              size: 44,
              ringColor: RoomColors.error.withValues(alpha: 0.82),
            ),
            title: Text(member.name),
            subtitle: Text(
              reason.isEmpty ? expiry : '$reason · $expiry',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _canGovern(member)
                        ? () => _unbanUser(banned)
                        : null,
                    child: const Text('解除限制'),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _showMemberMenu(RoomMember member) async {
    if (!_canGovern(member)) return;
    _beginManagementOverlay();
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        routeSettings: const RouteSettings(name: _managementOverlayRouteName),
        builder: (BuildContext sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RoomOxygenContextBar(
                title: member.name,
                subtitle: member.isOnMic ? '${member.seatNumber} 号麦' : '听众席',
                seed: '${member.userId}',
                status: member.isManager ? '管理' : '成员',
                statusColor: member.isManager
                    ? RoomColors.gold
                    : RoomColors.accent,
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(
                  member.isMuted
                      ? Icons.chat_rounded
                      : Icons.comments_disabled_outlined,
                ),
                title: Text(member.isMuted ? '解除禁言' : '禁言用户'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _setUserMuted(member, !member.isMuted);
                },
              ),
              if (member.isOnMic && member.seatNumber != null)
                ListTile(
                  leading: const Icon(Icons.keyboard_voice_outlined),
                  title: const Text('移下麦位'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _takeOffMic(member);
                  },
                ),
              if (!member.isManager && !member.isOnMic)
                ListTile(
                  leading: const Icon(Icons.mic_external_on_outlined),
                  title: const Text('安排上麦'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _assignToMic(member);
                  },
                ),
              if (_isOwner && member.role != RoomRole.owner)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(member.isManager ? '解除房管' : '设为房管'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setManager(member, !member.isManager);
                  },
                ),
              if (member.role != RoomRole.owner)
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFFF7A8D),
                  ),
                  title: const Text('移出房间'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _kickMember(member);
                  },
                ),
            ],
          ),
        ),
      );
    } finally {
      _endManagementOverlay();
    }
  }

  Future<void> _setUserMuted(RoomMember member, bool muted) async {
    await _runMemberOperation(
      member,
      () => _repository.setUserMuted(
        roomId: configuration.roomId,
        userId: member.userId,
        muted: muted,
      ),
      successMessage: muted ? '已禁言 ${member.name}' : '已解除 ${member.name} 的禁言',
    );
  }

  Future<void> _setManager(RoomMember member, bool manager) async {
    if (!_isOwner || !_canGovern(member)) return;
    final int operationGeneration = _managementGeneration;
    final bool confirmed = await _confirm(
      title: manager ? '设为房管？' : '解除房管？',
      message: manager
          ? '${member.name} 将获得房间治理权限。'
          : '${member.name} 将失去房间治理权限。',
      confirmLabel: manager ? '确认任命' : '确认解除',
    );
    if (!confirmed ||
        !mounted ||
        !_isCurrentOperation(operationGeneration) ||
        !_canGovern(member)) {
      return;
    }
    await _runMemberOperation(
      member,
      () => _repository.setUserRole(
        roomId: configuration.roomId,
        userId: member.userId,
        manager: manager,
      ),
      successMessage: manager ? '已设为房管' : '已解除房管',
    );
  }

  Future<void> _kickMember(RoomMember member) async {
    final int operationGeneration = _managementGeneration;
    final bool confirmed = await _confirm(
      title: '移出房间？',
      message: '${member.name} 将立即离开当前房间，10 分钟内不能再次进入本房间。',
      confirmLabel: '确认移出并限制',
    );
    if (!confirmed ||
        !mounted ||
        !_isCurrentOperation(operationGeneration) ||
        !_canGovern(member)) {
      return;
    }
    await _runMemberOperation(
      member,
      () => _repository.kickUser(
        roomId: configuration.roomId,
        userId: member.userId,
      ),
      successMessage: '已将 ${member.name} 移出房间，禁入 10 分钟',
    );
  }

  Future<void> _takeOffMic(RoomMember member) async {
    MicSeat? seat;
    for (final MicSeat item in _seats) {
      if (item.userId == member.userId) {
        seat = item;
        break;
      }
    }
    if (seat == null) {
      _showMessage('麦位状态已变化，请刷新');
      return;
    }
    final int operationGeneration = _managementGeneration;
    final bool confirmed = await _confirm(
      title: '移下麦位？',
      message: '${member.name} 将停止发言并回到听众席。',
      confirmLabel: '确认移下麦',
    );
    if (!confirmed ||
        !mounted ||
        !_isCurrentOperation(operationGeneration) ||
        !_canGovern(member)) {
      return;
    }
    await _runMemberOperation(
      member,
      () => _repository.takeUserOffMic(
        roomId: configuration.roomId,
        backendMicIndex: seat!.backendIndex,
        userId: member.userId,
      ),
      successMessage: '已将 ${member.name} 移下麦位',
    );
  }

  Future<void> _assignToMic(RoomMember member) async {
    if (!_canGovern(member) || _busyUserId != null) return;
    if (_pendingAssignment != null) {
      _showMessage('原安排结果待确认，请重试原安排');
      return;
    }
    final List<MicSeat> available = _seats
        .where((MicSeat seat) => seat.isAvailable && seat.canUse(member.role))
        .toList(growable: false);
    if (available.isEmpty) {
      _showMessage('当前没有可安排的空麦位');
      return;
    }
    final int operationGeneration = _managementGeneration;
    _beginManagementOverlay();
    final int? seatNumber;
    try {
      seatNumber = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        routeSettings: const RouteSettings(name: _managementOverlayRouteName),
        builder: (BuildContext sheetContext) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '安排 ${member.name} 上麦',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '安排到所选麦位；发言仍需对方设备的麦克风授权。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final MicSeat seat in available)
                    FilledButton.tonal(
                      onPressed:
                          _isCurrentOperation(operationGeneration) &&
                              _canGovern(member)
                          ? () => Navigator.of(sheetContext).pop(seat.number)
                          : null,
                      child: Text('${seat.number} 号麦'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    } finally {
      _endManagementOverlay();
    }
    if (seatNumber == null ||
        !_isCurrentOperation(operationGeneration) ||
        !_canGovern(member)) {
      return;
    }
    final seat = available.firstWhere((seat) => seat.number == seatNumber);
    _pendingAssignment = (member, seat);
    await _retryAssignment();
  }

  Future<void> _retryAssignment() async {
    final pending = _pendingAssignment;
    if (pending == null || !_canGovern(pending.$1) || _busyUserId != null)
      return;
    final int operationGeneration = _managementGeneration;
    setState(() => _busyUserId = pending.$1.userId);
    try {
      await _repository.assignUserToMic(
        roomId: configuration.roomId,
        userId: pending.$1.userId,
        backendMicIndex: pending.$2.backendIndex,
      );
      if (!_isCurrentOperation(operationGeneration) ||
          !_canGovern(pending.$1)) {
        return;
      }
      _pendingAssignment = null;
      _changed = true;
      _showMessage('已安排 ${pending.$1.name} 上麦');
      await _load();
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        if (!_unknownMicResult(error)) _pendingAssignment = null;
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busyUserId = null);
      }
    }
  }

  Future<void> _runMemberOperation(
    RoomMember member,
    Future<void> Function() operation, {
    required String successMessage,
  }) async {
    if (!_canGovern(member) || _busyUserId != null) return;
    final int operationGeneration = _managementGeneration;
    setState(() => _busyUserId = member.userId);
    try {
      await operation();
      if (!_isCurrentOperation(operationGeneration) || !_canGovern(member)) {
        return;
      }
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage(successMessage);
      await _load();
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busyUserId = null);
      }
    }
  }

  Future<void> _setSeatLocked(MicSeat seat, bool locked) async {
    if (!_isCurrentOperation(_managementGeneration) ||
        !_canManage ||
        seat.isOccupied ||
        _busySeatNumber != null) {
      return;
    }
    final int operationGeneration = _managementGeneration;
    setState(() => _busySeatNumber = seat.number);
    try {
      await _repository.setSeatLocked(
        roomId: configuration.roomId,
        backendMicIndex: seat.backendIndex,
        locked: locked,
      );
      if (!_isCurrentOperation(operationGeneration)) {
        return;
      }
      setState(() {
        _seats = <MicSeat>[
          for (final MicSeat item in _seats)
            if (item.number == seat.number)
              item.copyWith(
                state: locked ? MicSeatState.locked : MicSeatState.available,
              )
            else
              item,
        ];
        _changed = true;
      });
      _showMessage(locked ? '麦位已锁定' : '麦位已解锁');
      if (_authorityRepository != null) await _load();
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busySeatNumber = null);
      }
    }
  }

  Future<void> _setSeatMuted(MicSeat seat, bool muted) async {
    if (!_currentSession ||
        !_canManage ||
        _busySeatNumber != null ||
        !seat.isOccupied ||
        seat.audioMute == null)
      return;
    final retained = _pendingAudioDecision;
    if (retained != null &&
        (retained.$1.userId != seat.userId ||
            retained.$1.backendIndex != seat.backendIndex ||
            retained.$2 != muted)) {
      _showMessage('原静音操作结果待确认，请重试原操作');
      return;
    }
    final int operationGeneration = _managementGeneration;
    _pendingAudioDecision = (seat, muted);
    setState(() => _busySeatNumber = seat.number);
    try {
      await _repository.setSeatMuted(
        roomId: configuration.roomId,
        backendMicIndex: seat.backendIndex,
        muted: muted,
        targetUserId: seat.userId,
      );
      if (!_isCurrentOperation(operationGeneration)) {
        return;
      }
      _pendingAudioDecision = null;
      setState(() {
        // Live state comes only from a fresh authority read. The offline
        // preview applies the same reason-specific change, never a fake open.
        if (_authorityRepository == null)
          _seats = <MicSeat>[
            for (final MicSeat item in _seats)
              if (item.number == seat.number && item.userId == seat.userId)
                item.copyWith(
                  audioMute: RoomAudioMuteState(
                    selfMuted: item.audioMute!.selfMuted,
                    forcedMuted: muted,
                    legacyMuted: muted && item.audioMute!.legacyMuted,
                  ),
                  state: item.audioMute!.selfMuted || muted
                      ? MicSeatState.occupiedMuted
                      : MicSeatState.occupied,
                )
              else
                item,
          ];
        _changed = true;
      });
      if (_authorityRepository != null) await _load();
      if (_currentSession) _showMessage(muted ? '管理静音已设置' : '管理静音已解除；个人静音保持不变');
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        if (!_unknownMicResult(error)) _pendingAudioDecision = null;
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busySeatNumber = null);
      }
    }
  }

  Future<void> _resolveRequest(MicAccessRequest request, bool accepted) async {
    if (!_canGovern(request.member) ||
        !request.isRequest ||
        !request.isPending ||
        _busyMicRequestId != null ||
        (_pendingMicDecision != null &&
            (_pendingMicDecision!.$1.id != request.id ||
                _pendingMicDecision!.$2 != accepted))) {
      return;
    }
    final int operationGeneration = _managementGeneration;
    _pauseQueueSync();
    setState(() => _busyMicRequestId = request.id);
    try {
      var decision = _pendingMicDecision;
      if (decision == null) {
        final authority = _authorityRepository;
        if (authority != null) {
          final projection = await _readAuthority();
          if (!_isCurrentOperation(operationGeneration)) return;
          _validateAuthorityProjection(projection);
          if (!_projectionAllowsManagement(projection)) {
            if (_isAuthorityDowngrade(projection)) {
              _invalidateManagementState();
            }
            return;
          }
          _managementWasAuthorized = true;
          setState(() {
            _authoritativeRole = projection.snapshot.role;
            _seats = projection.snapshot.seats;
          });
        }
        if (!_isCurrentOperation(operationGeneration) ||
            !_canGovern(request.member)) {
          return;
        }
        int? target;
        if (accepted &&
            !_seats.any(
              (s) =>
                  s.number == request.seatNumber &&
                  s.isAvailable &&
                  s.canUse(request.member.role),
            )) {
          setState(() => _selectingMicTarget = true);
          target = await _chooseAlternateSeat(request);
          if (mounted && _managementGeneration == operationGeneration) {
            setState(() => _selectingMicTarget = false);
          }
          if (target == null || !_isCurrentOperation(operationGeneration)) {
            return;
          }
        }
        decision = (request, accepted, target);
        _pendingMicDecision = decision;
      }
      if (!_isCurrentOperation(operationGeneration)) return;
      await _repository.resolveMicRequest(
        requestId: decision.$1.id,
        accepted: decision.$2,
        expectedVersion: decision.$1.version,
        targetSeatNumber: decision.$3,
      );
      if (!_isCurrentOperation(operationGeneration)) return;
      _pendingMicDecision = null;
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage(accepted ? '已同意上麦申请' : '已拒绝上麦申请');
      await _load();
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        if (!_unknownMicResult(error)) _pendingMicDecision = null;
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busyMicRequestId = null);
        unawaited(_refreshQueue());
      }
    }
  }

  Future<int?> _chooseAlternateSeat(MicAccessRequest request) async {
    _beginManagementOverlay();
    try {
      return await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        routeSettings: const RouteSettings(name: _managementOverlayRouteName),
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('原申请麦位不可用，请选择备用空位'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final seat in _seats.where(
                    (s) => s.isAvailable && s.canUse(request.member.role),
                  ))
                    FilledButton.tonal(
                      key: Key('resolve-mic-seat-${seat.number}'),
                      onPressed: _canManage
                          ? () => Navigator.of(sheetContext).pop(seat.number)
                          : null,
                      child: Text('${seat.number} 号麦'),
                    ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _endManagementOverlay();
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

  Future<void> _unbanUser(RoomBannedUser banned) async {
    final RoomBanRepository? repository = _banRepository;
    if (repository == null || !_canGovern(banned.member)) {
      return;
    }
    final int operationGeneration = _managementGeneration;
    final bool confirmed = await _confirm(
      title: '解除房间限制？',
      message: '踢出后的 10 分钟冷却期不能提前解除。到期后，${banned.member.name} 可以再次尝试进入房间。',
      confirmLabel: '确认解除',
    );
    if (!confirmed ||
        !mounted ||
        !_isCurrentOperation(operationGeneration) ||
        !_canGovern(banned.member)) {
      return;
    }
    setState(() => _busyUserId = banned.member.userId);
    try {
      await repository.unbanUser(
        roomId: configuration.roomId,
        userId: banned.member.userId,
      );
      if (!_isCurrentOperation(operationGeneration) ||
          !_canGovern(banned.member)) {
        return;
      }
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage('已解除 ${banned.member.name} 的房间限制');
      await _load();
    } catch (error) {
      if (_isGovernanceDenied(error)) {
        _handleGovernanceDenied(
          error,
          managementGeneration: operationGeneration,
        );
      } else if (_isCurrentOperation(operationGeneration)) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted && _managementGeneration == operationGeneration) {
        setState(() => _busyUserId = null);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    _beginManagementOverlay();
    try {
      final bool? result = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: _managementOverlayRouteName),
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _canManage
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
      return result == true;
    } finally {
      _endManagementOverlay();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _messageFor(Object error) {
    if (error is ApiException) {
      if (error.code == 40949) return '10 分钟禁入冷却期尚未结束，不能提前解除';
      return error.message;
    }
    return '操作失败，请刷新后重试';
  }

  static String _seatStateLabel(MicSeat seat) {
    return switch (seat.state) {
      MicSeatState.available => '空闲',
      MicSeatState.locked => '已锁定',
      MicSeatState.mutedAvailable => '空麦闭麦',
      MicSeatState.occupied => '麦上用户',
      MicSeatState.occupiedMuted => '麦上闭麦',
    };
  }

  static String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ManagementTag extends StatelessWidget {
  const _ManagementTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: RoomColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
