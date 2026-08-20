import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';

enum _ManagementSection { members, seats, requests }

class RoomManagementPage extends StatefulWidget {
  const RoomManagementPage({
    required this.roomId,
    required this.currentUserId,
    required this.currentRole,
    required this.seats,
    this.initialMemberId,
    super.key,
  });

  final String roomId;
  final int currentUserId;
  final RoomRole currentRole;
  final List<MicSeat> seats;
  final int? initialMemberId;

  @override
  State<RoomManagementPage> createState() => _RoomManagementPageState();
}

class _RoomManagementPageState extends State<RoomManagementPage> {
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  final List<RoomMember> _members = <RoomMember>[];
  final List<MicAccessRequest> _requests = <MicAccessRequest>[];
  late List<MicSeat> _seats;
  _ManagementSection _section = _ManagementSection.members;
  bool _loading = true;
  bool _changed = false;
  String? _error;
  int? _busyUserId;
  int? _busySeatNumber;

  bool get _isOwner => widget.currentRole == RoomRole.owner;

  @override
  void initState() {
    super.initState();
    _seats = List<MicSeat>.of(widget.seats);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(
      context,
    ).roomOperationsRepository;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchOnlineMembers(
          roomId: widget.roomId,
          page: 1,
          pageSize: 100,
        ),
        _repository.fetchMutedUsers(widget.roomId),
        _repository.fetchManagers(widget.roomId),
        _repository.fetchMicRequests(widget.roomId),
      ]);
      final RoomMemberPage page = results[0] as RoomMemberPage;
      final List<RoomMember> muted = results[1] as List<RoomMember>;
      final List<RoomMember> managers = results[2] as List<RoomMember>;
      final List<MicAccessRequest> requests =
          results[3] as List<MicAccessRequest>;
      final Set<int> mutedIds = muted
          .map((RoomMember member) => member.userId)
          .toSet();
      final Map<int, RoomRole> roles = <int, RoomRole>{
        for (final RoomMember manager in managers) manager.userId: manager.role,
      };
      final Map<int, RoomMember> onMicBySeat = <int, RoomMember>{
        for (final RoomMember member in page.items)
          if (member.isOnMic && member.seatNumber != null)
            member.seatNumber!: member,
      };
      final List<MicSeat> reconciledSeats = <MicSeat>[
        for (final MicSeat seat in _seats)
          if (onMicBySeat[seat.number] case final RoomMember member)
            seat.copyWith(
              state: member.isMuted
                  ? MicSeatState.occupiedMuted
                  : MicSeatState.occupied,
              userId: member.userId,
              userName: member.name,
              userRole: roles[member.userId] ?? member.role,
            )
          else if (seat.isOccupied)
            seat.copyWith(
              state: MicSeatState.available,
              clearUserId: true,
              clearUserName: true,
              clearAvatarUrl: true,
              isSpeaking: false,
              userRole: RoomRole.listener,
            )
          else
            seat,
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
        if (left.userId == widget.initialMemberId) {
          return -1;
        }
        if (right.userId == widget.initialMemberId) {
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
        _requests
          ..clear()
          ..addAll(
            requests.where(
              (MicAccessRequest request) =>
                  request.status == MicRequestStatus.pending,
            ),
          );
        _seats = reconciledSeats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
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
        appBar: AppBar(
          title: const Text('房间管理'),
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
            _buildSectionPicker(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionPicker() {
    final bool supportsRequests =
        _repository.micCoordinationMode == MicCoordinationMode.approval;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
              label: Text('上麦申请 ${_requests.length}'),
              icon: const Icon(Icons.mark_unread_chat_alt_outlined),
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
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
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
    };
  }

  Widget _buildMembers() {
    final List<RoomMember> manageable = _members
        .where((RoomMember member) => member.userId != widget.currentUserId)
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
        return Material(
          color: RoomColors.surfaceHigh.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
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
            onTap: _busyUserId == null ? () => _showMemberMenu(member) : null,
          ),
        );
      },
    );
  }

  Widget _buildSeats() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 184,
      ),
      itemCount: _seats.length,
      itemBuilder: (BuildContext context, int index) {
        final MicSeat seat = _seats[index];
        final bool locked = seat.state == MicSeatState.locked;
        final bool muted =
            seat.state == MicSeatState.mutedAvailable ||
            seat.state == MicSeatState.occupiedMuted;
        return Card(
          color: RoomColors.surfaceHigh.withValues(alpha: 0.9),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '${seat.number} 号麦',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (_busySeatNumber == seat.number)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  seat.userName ?? _seatStateLabel(seat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    ActionChip(
                      avatar: Icon(
                        locked
                            ? Icons.lock_open_rounded
                            : Icons.lock_outline_rounded,
                        size: 16,
                      ),
                      label: Text(locked ? '解锁' : '锁定'),
                      onPressed: _busySeatNumber == null
                          ? () => _setSeatLocked(seat, !locked)
                          : null,
                    ),
                    ActionChip(
                      avatar: Icon(
                        muted ? Icons.mic_rounded : Icons.mic_off_rounded,
                        size: 16,
                      ),
                      label: Text(muted ? '开麦' : '闭麦'),
                      onPressed: locked || _busySeatNumber != null
                          ? null
                          : () => _setSeatMuted(seat, !muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequests() {
    if (_requests.isEmpty) {
      return const Center(child: Text('当前没有待处理的上麦申请'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final MicAccessRequest request = _requests[index];
        return Material(
          color: RoomColors.surfaceHigh.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            leading: RuntimeAvatar(
              seed: '${request.member.userId}',
              size: 44,
              ringColor: RoomColors.primary.withValues(alpha: 0.78),
            ),
            title: Text(request.member.name),
            subtitle: Text('申请 ${request.seatNumber} 号麦'),
            trailing: Wrap(
              spacing: 6,
              children: <Widget>[
                TextButton(
                  onPressed: () => _resolveRequest(request, false),
                  child: const Text('拒绝'),
                ),
                FilledButton.tonal(
                  onPressed: () => _resolveRequest(request, true),
                  child: const Text('同意'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMemberMenu(RoomMember member) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: RuntimeAvatar(
                seed: '${member.userId}',
                size: 46,
                ringColor: RoomColors.primary.withValues(alpha: 0.78),
              ),
              title: Text(member.name),
              subtitle: Text(
                member.isOnMic ? '${member.seatNumber} 号麦' : '听众席',
              ),
            ),
            const Divider(),
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
            if (_repository.micCoordinationMode ==
                    MicCoordinationMode.approval &&
                !member.isOnMic)
              ListTile(
                leading: const Icon(Icons.mic_external_on_outlined),
                title: const Text('邀请上麦'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _inviteToMic(member);
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
        roomId: widget.roomId,
        userId: member.userId,
        muted: muted,
      ),
      successMessage: muted ? '已禁言 ${member.name}' : '已解除 ${member.name} 的禁言',
    );
  }

  Future<void> _setManager(RoomMember member, bool manager) async {
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
        roomId: widget.roomId,
        userId: member.userId,
        manager: manager,
      ),
      successMessage: manager ? '已设为房管' : '已解除房管',
    );
  }

  Future<void> _kickMember(RoomMember member) async {
    final bool confirmed = await _confirm(
      title: '移出房间？',
      message: '${member.name} 将立即离开当前房间。本次操作不会自动加入永久黑名单。',
      confirmLabel: '确认移出',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runMemberOperation(
      member,
      () => _repository.kickUser(roomId: widget.roomId, userId: member.userId),
      successMessage: '已将 ${member.name} 移出房间',
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
        backendMicIndex: seat!.backendIndex,
        userId: member.userId,
      ),
      successMessage: '已将 ${member.name} 移下麦位',
    );
  }

  Future<void> _inviteToMic(RoomMember member) async {
    final List<MicSeat> available = _seats
        .where((MicSeat seat) => seat.isAvailable)
        .toList(growable: false);
    if (available.isEmpty) {
      _showMessage('当前没有可邀请的空麦位');
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
              '邀请 ${member.name} 上麦',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('对方接受后才会上麦。', style: Theme.of(context).textTheme.bodySmall),
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
      () => _repository.inviteUserToMic(
        roomId: widget.roomId,
        userId: member.userId,
        seatNumber: seatNumber,
      ),
      successMessage: '已发送上麦邀请',
    );
  }

  Future<void> _runMemberOperation(
    RoomMember member,
    Future<void> Function() operation, {
    required String successMessage,
  }) async {
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _messageFor(Object error) {
    if (error is ApiException) {
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
