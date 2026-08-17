part of 'community_pages.dart';

class GuildMembersEntryPage extends StatefulWidget {
  const GuildMembersEntryPage({super.key});

  @override
  State<GuildMembersEntryPage> createState() => _GuildMembersEntryPageState();
}

class _GuildMembersEntryPageState extends State<GuildMembersEntryPage> {
  GuildHomeSnapshot? _snapshot;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final GuildHomeSnapshot value = await AppDependencyScope.of(context)
          .communityRepository
          .fetchGuildHome();
      if (mounted) {
        setState(() => _snapshot = value);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GuildSummary? guild = _snapshot?.currentGuild;
    return Scaffold(
      appBar: AppBar(title: const Text('公会加入与成员管理')),
      body: _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : _snapshot == null
              ? const Center(child: CircularProgressIndicator())
              : guild == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.group_off_outlined, size: 46),
                            const SizedBox(height: 14),
                            const Text('尚未加入公会'),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pushReplacement<void, void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) => const GuildHomePage(),
                                ),
                              ),
                              child: const Text('浏览公会'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GuildMembersPage(guildId: guild.id, embedded: true),
    );
  }
}

class GuildMembersPage extends StatefulWidget {
  const GuildMembersPage({
    required this.guildId,
    this.embedded = false,
    super.key,
  });

  final String guildId;
  final bool embedded;

  @override
  State<GuildMembersPage> createState() => _GuildMembersPageState();
}

class _GuildMembersPageState extends State<GuildMembersPage> {
  GuildSummary? _guild;
  final List<GuildMember> _members = <GuildMember>[];
  final List<GuildApplication> _applications = <GuildApplication>[];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  String? _busyId;

  CommunityRepository get _repository =>
      AppDependencyScope.of(context).communityRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_guild == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GuildSummary guild = await _repository.fetchGuild(widget.guildId);
      final List<GuildMember> members =
          await _repository.fetchGuildMembers(widget.guildId);
      List<GuildApplication> applications = const <GuildApplication>[];
      if (guild.role.canManage) {
        applications = await _repository.fetchGuildApplications(widget.guildId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _guild = guild;
        _members
          ..clear()
          ..addAll(members);
        _applications
          ..clear()
          ..addAll(applications);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _operate(String id, Future<void> Function() action) async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = id);
    try {
      await action();
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _remove(GuildMember member) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('移出 ${member.nickname}？'),
        content: const Text('移出后，该用户的公会身份和相关权限会立即失效。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认移出'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _operate(
        member.recordId,
        () => _repository.removeGuildMember(member.recordId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canManage = _guild?.role.canManage ?? false;
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _StateError(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: <Widget>[
                    if (canManage)
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: <ButtonSegment<int>>[
                          const ButtonSegment<int>(value: 0, label: Text('成员')),
                          ButtonSegment<int>(
                            value: 1,
                            label: Text('申请 ${_applications.length}'),
                          ),
                        ],
                        selected: <int>{_tab},
                        onSelectionChanged: (Set<int> value) =>
                            setState(() => _tab = value.first),
                      ),
                    const SizedBox(height: 12),
                    if (_tab == 0)
                      if (_members.isEmpty)
                        const _InfoCard(
                          icon: Icons.group_off_outlined,
                          text: '当前没有公会成员。',
                        )
                      else
                        for (final GuildMember member in _members)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(18),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                leading: CircleAvatar(
                                  child: Text(_initial(member.nickname)),
                                ),
                                title: Row(
                                  children: <Widget>[
                                    Expanded(child: Text(member.nickname)),
                                    _SmallTag(label: member.role.label),
                                    if (member.isMuted) ...<Widget>[
                                      const SizedBox(width: 5),
                                      const _SmallTag(label: '已禁言'),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  member.roomId == null
                                      ? (member.isSigned ? '今日已签到' : '当前未在公会房')
                                      : '正在公会房间 ${member.roomId}',
                                ),
                                trailing: _busyId == member.recordId
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : canManage && member.role != GuildRole.owner
                                        ? PopupMenuButton<String>(
                                            onSelected: (String value) {
                                              if (value == 'mute') {
                                                _operate(
                                                  member.recordId,
                                                  () => _repository.setGuildMemberMuted(
                                                    memberRecordId: member.recordId,
                                                    muted: !member.isMuted,
                                                  ),
                                                );
                                              } else {
                                                _remove(member);
                                              }
                                            },
                                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                              PopupMenuItem<String>(
                                                value: 'mute',
                                                child: Text(member.isMuted ? '解除禁言' : '禁言成员'),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: 'remove',
                                                child: Text('移出公会'),
                                              ),
                                            ],
                                          )
                                        : null,
                                onTap: member.userId > 0
                                    ? () => Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (BuildContext context) =>
                                                PublicProfilePage(userId: member.userId),
                                          ),
                                        )
                                    : null,
                              ),
                            ),
                          )
                    else if (_applications.isEmpty)
                      const _InfoCard(
                        icon: Icons.mark_email_read_outlined,
                        text: '当前没有待处理的入会申请。',
                      )
                    else
                      for (final GuildApplication application in _applications)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              leading: CircleAvatar(
                                child: Text(_initial(application.nickname)),
                              ),
                              title: Text(application.nickname),
                              subtitle: Text(
                                <String>[
                                  application.appliedAt,
                                  if (application.message.isNotEmpty) application.message,
                                ].join(' · '),
                              ),
                              trailing: _busyId == application.id
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Wrap(
                                      spacing: 4,
                                      children: <Widget>[
                                        TextButton(
                                          onPressed: () => _operate(
                                            application.id,
                                            () => _repository.resolveGuildApplication(
                                              applicationId: application.id,
                                              accepted: false,
                                            ),
                                          ),
                                          child: const Text('拒绝'),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: () => _operate(
                                            application.id,
                                            () => _repository.resolveGuildApplication(
                                              applicationId: application.id,
                                              accepted: true,
                                            ),
                                          ),
                                          child: const Text('通过'),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                  ],
                ),
              );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('公会成员管理')),
            body: body,
          );
  }
}
