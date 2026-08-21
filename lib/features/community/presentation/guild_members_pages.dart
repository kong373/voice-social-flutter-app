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
      final GuildHomeSnapshot value = await AppDependencyScope.of(
        context,
      ).communityRepository.fetchGuildHome();
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
    return SocialPageScaffold(
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
                      onPressed: () =>
                          Navigator.of(context).pushReplacement<void, void>(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) =>
                                  const GuildHomePage(),
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
      final List<GuildMember> members = await _repository.fetchGuildMembers(
        widget.guildId,
      );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
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

  Widget _memberCard(GuildMember member, bool canManage) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommunitySection(
        onTap: member.userId > 0
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      PublicProfilePage(userId: member.userId),
                ),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: <Widget>[
            _LetterAvatar(
              label: member.nickname,
              prominent: member.role == GuildRole.owner,
              imagePath: member.role == GuildRole.owner
                  ? 'assets/runtime/avatar-rose.png'
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          member.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _CommunityPalette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _SmallTag(label: member.role.label),
                      if (member.isMuted) ...<Widget>[
                        const SizedBox(width: 4),
                        const _SmallTag(label: '已禁言', tint: AppColors.error),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: <Widget>[
                      Icon(
                        member.roomId == null
                            ? Icons.circle_outlined
                            : Icons.graphic_eq_rounded,
                        size: 13,
                        color: member.roomId == null
                            ? _CommunityPalette.muted
                            : AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          member.roomId == null
                              ? (member.isSigned ? '今日已签到' : '当前未在公会房')
                              : '正在公会房间 ${member.roomId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _CommunityPalette.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_busyId == member.recordId)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (canManage && member.role != GuildRole.owner)
              PopupMenuButton<String>(
                tooltip: '成员操作',
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _applicationCard(GuildApplication application) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommunitySection(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _LetterAvatar(label: application.nickname),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        application.nickname,
                        style: const TextStyle(
                          color: _CommunityPalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        application.appliedAt,
                        style: const TextStyle(
                          color: _CommunityPalette.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const _SmallTag(label: '待审核', tint: _CommunityPalette.gold),
              ],
            ),
            if (application.message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Text(
                application.message,
                style: const TextStyle(
                  color: _CommunityPalette.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _busyId == application.id
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Wrap(
                      spacing: 6,
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
          ],
        ),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                if (_guild != null) ...<Widget>[
                  _CommunityHero(
                    eyebrow: 'GUILD OPERATIONS',
                    title: _guild!.name,
                    subtitle:
                        '${_members.length} 位成员  ·  ${_applications.length} 条待审核申请',
                    icon: Icons.manage_accounts_rounded,
                    colors: const <Color>[
                      Color(0xFF477EDB),
                      Color(0xFF6DBCE7),
                      Color(0xFFA184EF),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
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
                const SizedBox(height: 18),
                _SectionHeading(
                  title: _tab == 0 ? '成员列表' : '加入申请',
                  subtitle: _tab == 0
                      ? '点击成员查看主页，管理操作保留权限校验'
                      : '仅管理员可以处理，结果以服务端为准',
                ),
                const SizedBox(height: 10),
                if (_tab == 0)
                  if (_members.isEmpty)
                    const _InfoCard(
                      icon: Icons.group_off_outlined,
                      text: '当前没有公会成员。',
                    )
                  else
                    for (final GuildMember member in _members)
                      _memberCard(member, canManage)
                else if (_applications.isEmpty)
                  const _InfoCard(
                    icon: Icons.mark_email_read_outlined,
                    text: '当前没有待处理的入会申请。',
                  )
                else
                  for (final GuildApplication application in _applications)
                    _applicationCard(application),
              ],
            ),
          );
    return widget.embedded
        ? body
        : SocialPageScaffold(
            appBar: AppBar(title: const Text('公会成员管理')),
            body: body,
          );
  }
}
