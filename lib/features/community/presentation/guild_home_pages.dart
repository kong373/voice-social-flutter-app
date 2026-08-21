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
    return Scaffold(
      appBar: AppBar(title: const Text('公会主页')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
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
                    Row(
                      children: <Widget>[
                        Text(
                          '搜索结果',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              setState(() => _searchResults = null),
                          child: const Text('清除'),
                        ),
                      ],
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
                    Text('我的公会', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (_snapshot?.currentGuild == null)
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
                    const SizedBox(height: 22),
                    Text('推荐公会', style: Theme.of(context).textTheme.titleLarge),
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
    return Scaffold(
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
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: <Widget>[
                  _GuildHero(guild: guild),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: <Widget>[
                      if (!guild.joined)
                        FilledButton(
                          onPressed: _busy || guild.applicationPending
                              ? null
                              : () => _run(
                                  () => _repository.applyToJoinGuild(guild.id),
                                  '入会申请已提交',
                                ),
                          child: Text(
                            guild.applicationPending ? '申请审核中' : '申请加入',
                          ),
                        ),
                      if (guild.joined)
                        FilledButton.tonal(
                          onPressed: _busy || guild.hasSignedToday
                              ? null
                              : () => _run(
                                  () => _repository.signGuild(guild.id),
                                  '公会签到成功',
                                ),
                          child: Text(guild.hasSignedToday ? '今日已签到' : '公会签到'),
                        ),
                      if (guild.joined)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext context) =>
                                          GuildMembersPage(guildId: guild.id),
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
                  const SizedBox(height: 22),
                  Text('公会房间', style: Theme.of(context).textTheme.titleLarge),
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
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            leading: const Icon(Icons.graphic_eq_rounded),
                            title: Text(room.name),
                            subtitle: Text('${room.onlineUsers} 人在线'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    RoomDeepLinkPage(input: room.roomId),
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
