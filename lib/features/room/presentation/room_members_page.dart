import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

enum _MemberFilter { all, onMic, listeners }

class RoomMembersPage extends StatefulWidget {
  const RoomMembersPage({
    required this.roomId,
    required this.currentUserId,
    required this.currentRole,
    required this.seats,
    super.key,
  });

  final String roomId;
  final int currentUserId;
  final RoomRole currentRole;
  final List<MicSeat> seats;

  @override
  State<RoomMembersPage> createState() => _RoomMembersPageState();
}

class _RoomMembersPageState extends State<RoomMembersPage> {
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  final List<RoomMember> _members = <RoomMember>[];
  _MemberFilter _filter = _MemberFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasMore = false;

  bool get _canManage =>
      widget.currentRole == RoomRole.owner ||
      widget.currentRole == RoomRole.moderator ||
      widget.currentRole == RoomRole.platformModerator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(
      context,
    ).roomOperationsRepository;
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() => _loadingMore = true);
    }

    try {
      final int requestedPage = reset ? 1 : _page + 1;
      final RoomMemberPage page = await _repository.fetchOnlineMembers(
        roomId: widget.roomId,
        page: requestedPage,
      );
      final List<RoomMember> enriched = _withSeatPresence(page.items);
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _members
            ..clear()
            ..addAll(enriched);
        } else {
          _appendUnique(enriched);
        }
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<RoomMember> _withSeatPresence(List<RoomMember> members) {
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
    return RoomPageScaffold(
      appBar: AppBar(
        title: const Text('在线成员与听众席'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildFilters(),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
        title: '成员列表加载失败',
        message: '保留当前房间上下文，请稍后重试。',
        actionLabel: '重新加载',
        onAction: () => _load(reset: true),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _MemberAvatar(member: member),
              title: Text(member.name),
              subtitle: Text(_memberSubtitle(member)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('查看主页'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openMemberPage(PublicProfilePage(userId: member.userId));
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('发起私聊'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openMemberPage(
                  PrivateChatPage(
                    conversation: ConversationSummary(
                      id: 'conversation-${member.userId}',
                      kind: ConversationKind.privateChat,
                      title: member.name,
                      lastMessage: '',
                      updatedAt: DateTime.now(),
                      unreadCount: 0,
                      targetUserId: member.userId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('举报用户'),
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
            if (_canManage && member.userId != widget.currentUserId)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('房间管理操作'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final bool? changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (BuildContext context) => RoomManagementPage(
                        roomId: widget.roomId,
                        currentUserId: widget.currentUserId,
                        currentRole: widget.currentRole,
                        seats: widget.seats,
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
    return Material(
      color: RoomColors.surfaceHigh.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        onTap: onTap,
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
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: RoomColors.surfaceHigh.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
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
    );
  }
}
