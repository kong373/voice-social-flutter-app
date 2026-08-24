part of 'community_pages.dart';

class GuildHomePage extends StatefulWidget {
  const GuildHomePage({super.key});

  @override
  State<GuildHomePage> createState() => _GuildHomePageState();
}

class _GuildHomePageState extends State<GuildHomePage> {
  final TextEditingController _searchController = TextEditingController();
  GuildHomeSnapshot? _snapshot;
  List<GuildSummary>? _searchResults;
  bool _loading = true;
  bool _searching = false;
  String? _error;

  CommunityRepository get _repository =>
      AppDependencyScope.of(context).communityRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GuildHomeSnapshot value = await _repository.fetchGuildHome();
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _search() async {
    final String keyword = _searchController.text.trim();
    if (_searching) {
      return;
    }
    setState(() => _searching = true);
    try {
      final List<GuildSummary> result = await _repository.searchGuilds(keyword);
      if (mounted) {
        setState(() => _searchResults = result);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _openGuild(GuildSummary guild) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GuildDetailPage(guildId: guild.id),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('公会主页')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  const _CommunityHero(
                    eyebrow: 'GUILD SQUARE',
                    title: '找到你的同频社群',
                    subtitle: '一起开房、聊天和完成公会日常，所有加入关系都由服务端确认。',
                    icon: Icons.groups_2_rounded,
                    colors: <Color>[
                      Color(0xFF3D76D8),
                      Color(0xFF68B6EA),
                      Color(0xFF9D81F2),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            hintText: '搜索公会名称或公会号',
                            prefixIcon: Icon(Icons.search_rounded),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '搜索',
                        onPressed: _searching ? null : _search,
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_searchResults != null) ...<Widget>[
                    _SectionHeading(
                      title: '搜索结果',
                      subtitle: '共找到 ${_searchResults!.length} 个公会',
                      trailing: TextButton(
                        onPressed: () => setState(() => _searchResults = null),
                        child: const Text('清除'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_searchResults!.isEmpty)
                      const _InfoCard(
                        icon: Icons.search_off_rounded,
                        text: '没有找到匹配公会。',
                      )
                    else
                      for (final GuildSummary guild in _searchResults!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GuildTile(
                            guild: guild,
                            onTap: () => _openGuild(guild),
                          ),
                        ),
                  ] else ...<Widget>[
                    const _SectionHeading(title: '我的公会', subtitle: '常驻社群与当前身份'),
                    const SizedBox(height: 10),
                    if (_snapshot?.currentGuildAuthority ==
                        GuildCurrentAuthority.unavailable)
                      const _InfoCard(
                        icon: Icons.cloud_off_outlined,
                        text: '当前公会信息暂不可用',
                      )
                    else if (_snapshot?.currentGuild == null)
                      const _InfoCard(
                        icon: Icons.groups_outlined,
                        text: '当前没有加入公会，可从推荐列表选择后提交申请。',
                      )
                    else
                      _GuildTile(
                        guild: _snapshot!.currentGuild!,
                        prominent: true,
                        onTap: () => _openGuild(_snapshot!.currentGuild!),
                      ),
                    const SizedBox(height: 20),
                    const _SectionHeading(
                      title: '推荐公会',
                      subtitle: '根据活跃主题与房间氛围推荐',
                    ),
                    const SizedBox(height: 10),
                    if (_snapshot?.recommended.isEmpty ?? true)
                      const _InfoCard(
                        icon: Icons.auto_awesome_outlined,
                        text: '当前没有可推荐的公会。',
                      )
                    else
                      for (final GuildSummary guild in _snapshot!.recommended)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GuildTile(
                            guild: guild,
                            onTap: () => _openGuild(guild),
                          ),
                        ),
                  ],
                ],
              ),
            ),
    );
  }
}

class GuildDetailPage extends StatefulWidget {
  const GuildDetailPage({required this.guildId, super.key});

  final String guildId;

  @override
  State<GuildDetailPage> createState() => _GuildDetailPageState();
}

class _GuildDetailPageState extends State<GuildDetailPage> {
  GuildSummary? _guild;
  String? _error;
  bool _loading = true;
  bool _busy = false;

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
      final GuildSummary value = await _repository.fetchGuild(widget.guildId);
      if (mounted) {
        setState(() {
          _guild = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _quit() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('退出公会？'),
        content: const Text('退出后公会身份、管理权限和关联入口将立即失效。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => _repository.quitGuild(widget.guildId), '已退出公会');
    }
  }

  @override
  Widget build(BuildContext context) {
    final GuildSummary? guild = _guild;
    final bool isClosed = guild?.status == GuildStatus.closed;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('公会详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : guild == null
          ? const Center(child: Text('公会不可用'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  _GuildHero(guild: guild),
                  if (isClosed) ...<Widget>[
                    const SizedBox(height: 12),
                    const _InfoCard(
                      icon: Icons.lock_outline_rounded,
                      text: '公会已关闭',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _CommunitySection(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const _CommunityGlyph(
                              icon: Icons.workspace_premium_outlined,
                              tint: _CommunityPalette.gold,
                              size: 38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    guild.joined
                                        ? '你是${guild.role.label}'
                                        : '尚未加入',
                                    style: const TextStyle(
                                      color: _CommunityPalette.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '会长 ${guild.ownerName.isEmpty ? '未公开' : guild.ownerName}  ·  ${guild.memberCount} 人',
                                    style: const TextStyle(
                                      color: _CommunityPalette.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (guild.joined && !isClosed)
                              _SmallTag(
                                label: switch (guild.hasSignedToday) {
                                  true => '今日已签到',
                                  false => '待签到',
                                  null => '签到状态未知',
                                },
                                tint: guild.hasSignedToday == true
                                    ? AppColors.success
                                    : _CommunityPalette.gold,
                              ),
                          ],
                        ),
                        if (!isClosed) ...<Widget>[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              if (!guild.joined)
                                FilledButton(
                                  onPressed:
                                      _busy || guild.applicationPending != false
                                      ? null
                                      : () => _run(
                                          () => _repository.applyToJoinGuild(
                                            guild.id,
                                          ),
                                          '入会申请已提交',
                                        ),
                                  child: Text(
                                    switch (guild.applicationPending) {
                                      true => '申请审核中',
                                      false => '申请加入',
                                      null => '申请状态未知',
                                    },
                                  ),
                                ),
                              if (guild.joined)
                                FilledButton.tonal(
                                  onPressed:
                                      _busy || guild.hasSignedToday != false
                                      ? null
                                      : () => _run(
                                          () => _repository.signGuild(guild.id),
                                          '公会签到成功',
                                        ),
                                  child: Text(switch (guild.hasSignedToday) {
                                    true => '今日已签到',
                                    false => '公会签到',
                                    null => '签到状态未知',
                                  }),
                                ),
                              if (guild.joined)
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          Navigator.of(context).push<void>(
                                            MaterialPageRoute<void>(
                                              builder: (BuildContext context) =>
                                                  GuildMembersPage(
                                                    guildId: guild.id,
                                                  ),
                                            ),
                                          );
                                        },
                                  child: const Text('成员与管理'),
                                ),
                              if (guild.joined && guild.role != GuildRole.owner)
                                OutlinedButton(
                                  onPressed: _busy ? null : _quit,
                                  child: const Text('退出公会'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeading(title: '公会房间', subtitle: '正在发生的声音现场'),
                  const SizedBox(height: 10),
                  if (guild.rooms.isEmpty)
                    const _InfoCard(
                      icon: Icons.meeting_room_outlined,
                      text: '当前没有可进入的有效公会房间。',
                    )
                  else
                    for (final GuildRoom room in guild.rooms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _CommunitySection(
                          onTap: isClosed
                              ? null
                              : () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (BuildContext context) =>
                                        RoomDeepLinkPage(input: room.roomId),
                                  ),
                                ),
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  gradient: const LinearGradient(
                                    colors: <Color>[
                                      Color(0xFF5D4BBD),
                                      Color(0xFFE07DA8),
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.graphic_eq_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      room.name,
                                      style: const TextStyle(
                                        color: _CommunityPalette.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: <Widget>[
                                        const Icon(
                                          Icons.circle,
                                          color: AppColors.success,
                                          size: 7,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          room.onlineUsers == null
                                              ? '在线人数未知'
                                              : '${room.onlineUsers} 人正在房间',
                                          style: const TextStyle(
                                            color: _CommunityPalette.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isClosed
                                    ? Icons.lock_outline_rounded
                                    : Icons.chevron_right_rounded,
                                color: _CommunityPalette.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
