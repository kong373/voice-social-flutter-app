import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
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

  bool get _isOwner => configuration.currentRole == RoomRole.owner;
  bool get _canManage =>
      _isOwner ||
      configuration.currentRole == RoomRole.moderator ||
      configuration.currentRole == RoomRole.platformModerator;
  bool get _supportsMicRequests => _canManage;

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

  void _pauseQueueSync() {
    _queueTimer?.cancel();
    _queueTimer = null;
    _queueGeneration++;
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshQueue() => _refreshMicQueue();

  // Single-flight and visible-only; a write invalidates any older response.
  Future<void> _refreshMicQueue() async {
    if (!_canSyncQueue) return;
    _queuePending = true;
    if (_queueReading || _busyMicRequestId != null) return;
    _queueTimer?.cancel();
    _queueReading = true;
    try {
      do {
        _queuePending = false;
        final generation = _queueGeneration;
        try {
          final requests = await _repository.fetchMicRequests(
            configuration.roomId,
          );
          if (!_canSyncQueue || generation != _queueGeneration) continue;
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
          if (_canSyncQueue && generation == _queueGeneration) {
            setState(() => _queueError = _messageFor(error));
          }
        }
      } while (_queuePending && _canSyncQueue && _busyMicRequestId == null);
    } finally {
      _queueReading = false;
      if (_canSyncQueue && _busyMicRequestId == null) {
        _queueTimer = Timer(const Duration(seconds: 2), _refreshMicQueue);
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    unawaited(_refreshQueue());
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
        futures.add(
          authority.fetchRoomAuthority(
            roomId: configuration.roomId,
            currentUserId: configuration.currentUserId,
          ),
        );
      }
      final List<Object> results = await Future.wait<Object>(futures);
      if (!mounted || generation != _loadGeneration) return;
      final projection = authority == null
          ? null
          : results.last as RoomAuthorityProjection;
      if (projection != null &&
          (projection.snapshot.roomId != configuration.roomId ||
              projection.viewerUserId != configuration.currentUserId)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '麦位权威响应与当前房间不一致',
        );
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
      final List<MicSeat> reconciledSeats = List.of(
        projection?.snapshot.seats ?? _seats,
      );
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
        _members
          ..clear()
          ..addAll(members);
        _bannedUsers
          ..clear()
          ..addAll(bannedUserPage?.items ?? const <RoomBannedUser>[]);
        _seats = reconciledSeats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
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
                status: _isOwner ? '房主' : '房管',
                statusColor: _isOwner ? RoomColors.gold : RoomColors.primary,
              ),
            ),
            _buildSectionPicker(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

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
    final bool locked = seat.state == MicSeatState.locked;
    final bool muted =
        seat.state == MicSeatState.mutedAvailable ||
        seat.state == MicSeatState.occupiedMuted;
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
                  '${seat.number} 号麦',
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
          Wrap(
            spacing: 4,
            children: <Widget>[
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
                  muted ? Icons.mic_rounded : Icons.mic_off_rounded,
                  size: 16,
                ),
                label: Text(muted ? '开麦' : '闭麦'),
                onPressed:
                    !_canManage ||
                        (seat.isOccupied &&
                            (seat.userRole == RoomRole.owner ||
                                (!_isOwner &&
                                    (seat.userRole == RoomRole.moderator ||
                                        seat.userRole ==
                                            RoomRole.platformModerator)))) ||
                        locked ||
                        _busySeatNumber != null
                    ? null
                    : () => _setSeatMuted(seat, !muted),
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
        final bool busy = _busyMicRequestId == request.id;
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
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
    final bool confirmed = await _confirm(
      title: manager ? '设为房管？' : '解除房管？',
      message: manager
          ? '${member.name} 将获得房间治理权限。'
          : '${member.name} 将失去房间治理权限。',
      confirmLabel: manager ? '确认任命' : '确认解除',
    );
    if (!confirmed || !mounted) {
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
    final bool confirmed = await _confirm(
      title: '移出房间？',
      message: '${member.name} 将立即离开当前房间，10 分钟内不能再次进入本房间。',
      confirmLabel: '确认移出并限制',
    );
    if (!confirmed || !mounted) {
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
    final bool confirmed = await _confirm(
      title: '移下麦位？',
      message: '${member.name} 将停止发言并回到听众席。',
      confirmLabel: '确认移下麦',
    );
    if (!confirmed || !mounted) {
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
    final List<MicSeat> available = _seats
        .where((MicSeat seat) => seat.isAvailable)
        .toList(growable: false);
    if (available.isEmpty) {
      _showMessage('当前没有可安排的空麦位');
      return;
    }
    final int? seatNumber = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
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
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(seat.number),
                    child: Text('${seat.number} 号麦'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (seatNumber == null || !mounted) {
      return;
    }
    await _runMemberOperation(
      member,
      () => _repository.assignUserToMic(
        roomId: configuration.roomId,
        userId: member.userId,
        backendMicIndex: _seats
            .firstWhere((seat) => seat.number == seatNumber)
            .backendIndex,
      ),
      successMessage: '已安排 ${member.name} 上麦',
    );
  }

  Future<void> _runMemberOperation(
    RoomMember member,
    Future<void> Function() operation, {
    required String successMessage,
  }) async {
    if (!_canGovern(member) || _busyUserId != null) return;
    setState(() => _busyUserId = member.userId);
    try {
      await operation();
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage(successMessage);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _busyUserId = null);
      }
    }
  }

  Future<void> _setSeatLocked(MicSeat seat, bool locked) async {
    setState(() => _busySeatNumber = seat.number);
    try {
      await _repository.setSeatLocked(
        roomId: configuration.roomId,
        backendMicIndex: seat.backendIndex,
        locked: locked,
      );
      if (!mounted) {
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
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busySeatNumber = null);
      }
    }
  }

  Future<void> _setSeatMuted(MicSeat seat, bool muted) async {
    setState(() => _busySeatNumber = seat.number);
    try {
      await _repository.setSeatMuted(
        roomId: configuration.roomId,
        backendMicIndex: seat.backendIndex,
        muted: muted,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _seats = <MicSeat>[
          for (final MicSeat item in _seats)
            if (item.number == seat.number)
              item.copyWith(
                state: item.isOccupied
                    ? (muted
                          ? MicSeatState.occupiedMuted
                          : MicSeatState.occupied)
                    : (muted
                          ? MicSeatState.mutedAvailable
                          : MicSeatState.available),
              )
            else
              item,
        ];
        _changed = true;
      });
      _showMessage(muted ? '麦位已闭麦' : '麦位已开麦');
      if (_authorityRepository != null) await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busySeatNumber = null);
      }
    }
  }

  Future<void> _resolveRequest(MicAccessRequest request, bool accepted) async {
    if (!_canGovern(request.member) ||
        !request.isRequest ||
        !request.isPending ||
        _busyMicRequestId != null) {
      return;
    }
    _pauseQueueSync();
    setState(() => _busyMicRequestId = request.id);
    try {
      await _repository.resolveMicRequest(
        requestId: request.id,
        accepted: accepted,
      );
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage(accepted ? '已同意上麦申请' : '已拒绝上麦申请');
      await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyMicRequestId = null);
        unawaited(_refreshQueue());
      }
    }
  }

  Future<void> _unbanUser(RoomBannedUser banned) async {
    final RoomBanRepository? repository = _banRepository;
    if (repository == null || !_canGovern(banned.member)) {
      return;
    }
    final bool confirmed = await _confirm(
      title: '解除房间限制？',
      message: '踢出后的 10 分钟冷却期不能提前解除。到期后，${banned.member.name} 可以再次尝试进入房间。',
      confirmLabel: '确认解除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busyUserId = banned.member.userId);
    try {
      await repository.unbanUser(
        roomId: configuration.roomId,
        userId: banned.member.userId,
      );
      _changed = true;
      if (!mounted) {
        return;
      }
      _showMessage('已解除 ${banned.member.name} 的房间限制');
      await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyUserId = null);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
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
