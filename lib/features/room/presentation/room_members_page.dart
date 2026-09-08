import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/room_authority_display.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

enum _MemberFilter { all, onMic, listeners }

class RoomMembersPage extends StatefulWidget {
  const RoomMembersPage({
    required this.roomId,
    required this.currentUserId,
    required this.currentRole,
    required this.seats,
    this.roomTitle,
    this.roomCode,
    this.controller,
    super.key,
  });

  final String roomId;
  final int currentUserId;
  final RoomRole currentRole;
  final List<MicSeat> seats;
  final String? roomTitle;
  final String? roomCode;
  final RoomController? controller;

  @override
  State<RoomMembersPage> createState() => _RoomMembersPageState();
}

class _RoomMembersPageState extends State<RoomMembersPage>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;
  bool _invalidIdentity = false;
  bool _reading = false;
  bool _pending = false;
  int _generation = 0;
  int? _identityGeneration;
  int? _leaseGeneration;
  String? _controllerSessionId;

  bool _checkController() {
    final controller = widget.controller;
    if (controller == null) return true;
    if (controller.roomId != widget.roomId ||
        controller.currentUserId != widget.currentUserId ||
        controller.snapshot == null ||
        controller.snapshot!.sessionId != _controllerSessionId ||
        (controller.status != RoomSessionStatus.joined &&
            controller.status != RoomSessionStatus.reconnecting)) {
      if (!_invalidIdentity) _invalidate();
      return false;
    }
    return true;
  }

  void _controllerChanged() {
    if (!mounted || _invalidIdentity) return;
    if (_checkController()) setState(() {});
  }

  bool _checkLease() {
    final repository = _repositoryInstance;
    if (repository is BackendRoomOperationsRepository &&
        repository.leaseBinding.generation != _leaseGeneration) {
      _invalidate();
      return false;
    }
    return true;
  }

  ModalRoute<dynamic>? _route;
  bool get _active =>
      mounted &&
      _foreground &&
      _visible &&
      (_route?.isCurrent ?? true) &&
      !_invalidIdentity;
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  final List<RoomMember> _members = <RoomMember>[];
  _MemberFilter _filter = _MemberFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = false;

  bool get _canManage {
    final controller = widget.controller;
    if (controller != null) {
      return !_invalidIdentity &&
          controller.allows(RoomCapability.manageMembers);
    }
    final role = widget.currentRole;
    return !_invalidIdentity &&
        (role == RoomRole.owner ||
            role == RoomRole.moderator ||
            role == RoomRole.platformModerator);
  }

  @override
  void initState() {
    super.initState();
    _controllerSessionId = widget.controller?.snapshot?.sessionId;
    widget.controller?.addListener(_controllerChanged);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _pause() {
    _timer?.cancel();
    _generation++;
    _pending = false;
  }

  void _identityChanged() {
    if (_dependencies!.sessionManager.identityGeneration == _identityGeneration)
      return;
    _invalidate();
  }

  void _invalidate() {
    _pause();
    setState(() {
      _invalidIdentity = true;
      _members.clear();
      _loading = false;
      _loadingMore = false;
      _hasMore = false;
      _error = '登录或房间状态已改变，请重新进入成员页。';
    });
  }

  @override
  void didUpdateWidget(RoomMembersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
      _invalidate();
      return;
    }
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.currentUserId != widget.currentUserId) {
      _pause();
      _members.clear();
      _page = 1;
      _hasMore = false;
      _loading = true;
      _load(reset: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pause();
    if (_repositoryInstance != null) _load(reset: true);
  }

  @override
  void dispose() {
    _pause();
    widget.controller?.removeListener(_controllerChanged);
    _dependencies?.sessionManager.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependencyScope.of(context);
    _route = ModalRoute.of(context);
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_dependencies == null) {
      _dependencies = dependencies;
      _repositoryInstance = dependencies.roomOperationsRepository;
      final repository = _repositoryInstance;
      if (repository is BackendRoomOperationsRepository) {
        _leaseGeneration = repository.leaseBinding.generation;
      }
      _identityGeneration = dependencies.sessionManager.identityGeneration;
      dependencies.sessionManager.addListener(_identityChanged);
      _visible = visible;
      _load(reset: true);
    } else if (!identical(_dependencies, dependencies)) {
      _invalidate();
    } else if (_visible != visible) {
      _visible = visible;
      _pause();
      _load(reset: true);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (!_active || !_checkController() || !_checkLease()) return;
    if (_reading) {
      if (reset) _pending = true;
      return;
    }
    if (!reset && (!_hasMore || _loading)) return;
    _timer?.cancel();
    _reading = true;
    try {
      do {
        _pending = false;
        final generation = _generation;
        final roomId = widget.roomId;
        final targetPage = reset ? _page : _page + 1;
        setState(() => _loadingMore = !reset);
        try {
          // Re-read the loaded prefix atomically so pagination never retains
          // departed members or mixes an old tail with a new first page.
          final refreshed = <RoomMember>[];
          RoomMemberPage? last;
          for (
            var number = reset ? 1 : targetPage;
            number <= targetPage;
            number++
          ) {
            final page = await _repository.fetchOnlineMembers(
              roomId: roomId,
              page: number,
            );
            if (!_active ||
                generation != _generation ||
                !_checkController() ||
                !_checkLease())
              break;
            refreshed.addAll(_withSeatPresence(page.items));
            last = page;
            if (!page.hasMore) break;
          }
          if (_active && generation == _generation && last != null) {
            setState(() {
              if (reset) _members.clear();
              _appendUnique(refreshed);
              _page = last!.page;
              _hasMore = last.hasMore;
              _loading = false;
              _loadingMore = false;
              _error = null;
            });
          }
        } catch (error) {
          if (_active &&
              generation == _generation &&
              _checkController() &&
              _checkLease()) {
            setState(() {
              _error = error.toString();
              _loading = false;
              _loadingMore = false;
            });
          }
        }
        reset = true;
      } while (_pending && _active);
    } finally {
      _reading = false;
      if (_active && _dependencies!.environment.isLive) {
        _timer = Timer(const Duration(seconds: 2), () => _load(reset: true));
      }
    }
  }

  List<RoomMember> _withSeatPresence(List<RoomMember> members) {
    if (_dependencies!.environment.isLive) return members;
    final Map<int, MicSeat> seatsByUser = <int, MicSeat>{
      for (final MicSeat seat in widget.seats)
        if (seat.userId != null) seat.userId!: seat,
    };
    return <RoomMember>[
      for (final RoomMember member in members)
        if (seatsByUser[member.userId] case final MicSeat seat)
          member.copyWith(
            role: seat.userRole,
            presence: RoomMemberPresence.onMic,
            seatNumber: seat.number,
            isMuted: seat.state == MicSeatState.occupiedMuted,
          )
        else
          member,
    ];
  }

  void _appendUnique(List<RoomMember> additions) {
    final Set<int> existing = _members
        .map((RoomMember item) => item.userId)
        .toSet();
    for (final RoomMember member in additions) {
      if (existing.add(member.userId)) {
        _members.add(member);
      }
    }
  }

  List<RoomMember> get _visibleMembers {
    return switch (_filter) {
      _MemberFilter.all => _members,
      _MemberFilter.onMic =>
        _members
            .where((RoomMember member) => member.isOnMic)
            .toList(growable: false),
      _MemberFilter.listeners =>
        _members
            .where((RoomMember member) => !member.isOnMic)
            .toList(growable: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final roomCode = widget.roomCode?.trim().isNotEmpty == true
        ? widget.roomCode
        : (_dependencies!.environment.isLive ? null : widget.roomId);
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(
        title: '在线成员与听众席',
        actions: <Widget>[
          if (!_invalidIdentity)
            IconButton(
              tooltip: '刷新',
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: RoomOxygenContextBar(
              title: roomAuthorityTitle(widget.roomTitle),
              subtitle:
                  '${roomCode != null ? '房间号 $roomCode' : '房间号不可用'} · ${_invalidIdentity ? '请重新进入成员页' : '${_members.length} 人在线'}',
              seed: widget.roomId,
              status: _invalidIdentity ? '已失效' : (_canManage ? '可管理' : '在线'),
              statusColor: _invalidIdentity
                  ? RoomColors.textSecondary
                  : (_canManage ? RoomColors.primary : RoomColors.success),
            ),
          ),
          if (!_invalidIdentity) _buildFilters(),
          if (_error != null && _members.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('成员更新失败，显示上次结果，正在重试'),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final int onMic = _members
        .where((RoomMember member) => member.isOnMic)
        .length;
    final int listeners = _members.length - onMic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        children: <Widget>[
          ChoiceChip(
            label: Text('全部 ${_members.length}'),
            selected: _filter == _MemberFilter.all,
            onSelected: (_) => setState(() => _filter = _MemberFilter.all),
          ),
          ChoiceChip(
            label: Text('麦上 $onMic'),
            selected: _filter == _MemberFilter.onMic,
            onSelected: (_) => setState(() => _filter = _MemberFilter.onMic),
          ),
          ChoiceChip(
            label: Text('听众 $listeners'),
            selected: _filter == _MemberFilter.listeners,
            onSelected: (_) =>
                setState(() => _filter = _MemberFilter.listeners),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _members.isEmpty) {
      return _MembersMessage(
        icon: Icons.cloud_off_rounded,
        title: _invalidIdentity ? '成员页已失效' : '成员列表加载失败',
        message: _invalidIdentity ? _error! : '保留当前房间上下文，请稍后重试。',
        actionLabel: _invalidIdentity ? null : '重新加载',
        onAction: _invalidIdentity ? null : () => _load(reset: true),
      );
    }
    final List<RoomMember> members = _visibleMembers;
    if (members.isEmpty) {
      return const _MembersMessage(
        icon: Icons.people_outline_rounded,
        title: '当前分组暂无成员',
        message: '切换其他分组查看房间成员。',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: members.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == members.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: _loadingMore ? null : () => _load(reset: false),
                  icon: _loadingMore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? '正在加载' : '加载更多'),
                ),
              ),
            );
          }
          return _MemberTile(
            member: members[index],
            isCurrentUser: members[index].userId == widget.currentUserId,
            canManage:
                _canManage && members[index].userId != widget.currentUserId,
            onTap: () => _showMemberActions(members[index]),
          );
        },
      ),
    );
  }

  Future<void> _showMemberActions(RoomMember member) async {
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
              subtitle: _memberSubtitle(member),
              seed: '${member.userId}',
              status: member.isOnMic ? '麦上' : '听众',
              statusColor: member.isOnMic
                  ? RoomColors.accent
                  : RoomColors.textSecondary,
            ),
            const SizedBox(height: 12),
            RoomGlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('查看主页'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openMemberPage(PublicProfilePage(userId: member.userId));
                    },
                  ),
                  const Divider(height: 1, indent: 52),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline_rounded),
                    title: const Text('发起私聊'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openMemberPage(
                        PrivateChatPage(
                          conversation: ConversationSummary.draft(
                            kind: ConversationKind.privateChat,
                            title: member.name,
                            lastMessage: '',
                            unreadCount: 0,
                            targetUserId: member.userId,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 52),
                  ListTile(
                    leading: const Icon(Icons.report_outlined),
                    title: const Text('举报用户'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openMemberPage(
                        ReportPage(
                          targetType: ReportTargetType.user,
                          targetId: '${member.userId}',
                          targetName: member.name,
                        ),
                      );
                    },
                  ),
                  if (_canManage &&
                      member.userId != widget.currentUserId) ...<Widget>[
                    const Divider(height: 1, indent: 52),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('房间管理操作'),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        final bool? changed = await Navigator.of(context)
                            .push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (BuildContext context) =>
                                    RoomManagementPage(
                                      roomId: widget.roomId,
                                      currentUserId: widget.currentUserId,
                                      currentRole: widget.currentRole,
                                      seats: widget.seats,
                                      roomTitle: widget.roomTitle,
                                      initialMemberId: member.userId,
                                    ),
                              ),
                            );
                        if (changed == true && mounted) {
                          await _load(reset: true);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMemberPage(Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  static String _memberSubtitle(RoomMember member) {
    final String role = switch (member.role) {
      RoomRole.owner => '房主',
      RoomRole.moderator => '房管',
      RoomRole.platformModerator => '平台管理',
      RoomRole.speaker => '麦上用户',
      RoomRole.guest || RoomRole.listener => '听众',
    };
    if (member.seatNumber != null) {
      return '$role · ${member.seatNumber} 号麦${member.isMuted ? ' · 已闭麦' : ''}';
    }
    return role;
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isCurrentUser,
    required this.canManage,
    required this.onTap,
  });

  final RoomMember member;
  final bool isCurrentUser;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RoomGlassCard(
      padding: EdgeInsets.zero,
      radius: 16,
      onTap: onTap,
      child: ListTile(
        minVerticalPadding: 9,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: _MemberAvatar(member: member),
        title: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrentUser) ...<Widget>[
              const SizedBox(width: 6),
              const _TinyTag(label: '我'),
            ],
            if (member.isManager) ...<Widget>[
              const SizedBox(width: 6),
              _TinyTag(label: member.role == RoomRole.owner ? '房主' : '房管'),
            ],
          ],
        ),
        subtitle: Text(_RoomMembersPageState._memberSubtitle(member)),
        trailing: Icon(
          canManage ? Icons.tune_rounded : Icons.chevron_right_rounded,
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final RoomMember member;

  @override
  Widget build(BuildContext context) {
    return RuntimeAvatar(
      seed: '${member.userId}',
      size: 46,
      ringColor: RoomColors.primary.withValues(alpha: 0.78),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.label});

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

class _MembersMessage extends StatelessWidget {
  const _MembersMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: RoomGlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 44, color: RoomColors.textSecondary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 18),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
