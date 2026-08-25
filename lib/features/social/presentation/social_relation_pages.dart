part of 'social_pages.dart';

class RelationsPage extends StatefulWidget {
  const RelationsPage({
    this.initialType = SocialRelationList.following,
    super.key,
  });

  final SocialRelationList initialType;

  @override
  State<RelationsPage> createState() => _RelationsPageState();
}

class _RelationsPageState extends State<RelationsPage> {
  late SocialRelationList _type;
  final List<SocialUser> _items = <SocialUser>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _items.isEmpty && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SocialPage<SocialUser> page = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchRelations(type: _type, page: 1, pageSize: 50);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(page.items);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('关注、粉丝与好友')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: _OxygenPanel(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _OxygenInlineTabs<SocialRelationList>(
                items: const <SocialRelationList, String>{
                  SocialRelationList.following: '关注',
                  SocialRelationList.followers: '粉丝',
                  SocialRelationList.friends: '好友',
                },
                value: _type,
                onChanged: (SocialRelationList value) {
                  setState(() => _type = value);
                  _load();
                },
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _items.isEmpty
                ? const Center(child: Text('当前没有符合条件的用户'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                      children: <Widget>[
                        _OxygenPanel(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: <Widget>[
                              for (
                                int index = 0;
                                index < _items.length;
                                index += 1
                              ) ...<Widget>[
                                _OxygenUserRow(
                                  user: _items[index],
                                  subtitle: _items[index].signature.isEmpty
                                      ? '对方还没有留下签名'
                                      : _items[index].signature,
                                  onTap: () => Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext context) =>
                                          PublicProfilePage(
                                            userId: _items[index].userId,
                                          ),
                                    ),
                                  ),
                                ),
                                if (index < _items.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  List<FriendRequest>? _items;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final List<FriendRequest> value = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchFriendRequests();
      if (mounted) {
        setState(() => _items = value);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _resolve(FriendRequest request, bool accepted) async {
    try {
      await AppDependencyScope.of(context).socialRepository
          .resolveFriendRequest(requestId: request.id, accepted: accepted);
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SocialRepository repository = AppDependencyScope.of(
      context,
    ).socialRepository;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('好友请求')),
      body: !repository.supportsFriendRequestWorkflow
          ? const _Unavailable(
              title: '好友请求协议尚未接入',
              message: '当前后端只确认了关注与互相关注关系，不能伪造接受或拒绝流程。',
            )
          : _items == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorState(message: _error!, onRetry: _load)
          : _items!.isEmpty
          ? const Center(child: Text('暂无好友请求'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
              children: <Widget>[
                _OxygenPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < _items!.length;
                        index += 1
                      ) ...<Widget>[
                        Builder(
                          builder: (BuildContext context) {
                            final FriendRequest request = _items![index];
                            return _OxygenUserRow(
                              user: request.user,
                              subtitle: request.message,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      PublicProfilePage(
                                        userId: request.user.userId,
                                      ),
                                ),
                              ),
                              trailing:
                                  request.status == FriendRequestStatus.pending
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        TextButton(
                                          onPressed: () =>
                                              _resolve(request, false),
                                          style: TextButton.styleFrom(
                                            minimumSize: const Size(42, 34),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                          ),
                                          child: const Text(
                                            '拒绝',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              _resolve(request, true),
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(52, 34),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                            ),
                                          ),
                                          child: const Text(
                                            '接受',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _friendRequestLabel(request.status),
                                      style: const TextStyle(
                                        color: SocialColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                            );
                          },
                        ),
                        if (index < _items!.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class VisitorRecordsPage extends StatefulWidget {
  const VisitorRecordsPage({super.key});

  @override
  State<VisitorRecordsPage> createState() => _VisitorRecordsPageState();
}

class _VisitorRecordsPageState extends State<VisitorRecordsPage> {
  VisitorRecordType _type = VisitorRecordType.viewedMe;
  List<SocialUser>? _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final SocialPage<SocialUser> value = await AppDependencyScope.of(
      context,
    ).socialRepository.fetchVisitors(type: _type, page: 1, pageSize: 50);
    if (mounted) {
      setState(() => _items = value.items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('访客记录')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: _OxygenPanel(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _OxygenInlineTabs<VisitorRecordType>(
                items: const <VisitorRecordType, String>{
                  VisitorRecordType.viewedMe: '谁看过我',
                  VisitorRecordType.viewedByMe: '我看过谁',
                },
                value: _type,
                onChanged: (VisitorRecordType value) {
                  setState(() {
                    _type = value;
                    _items = null;
                  });
                  _load();
                },
              ),
            ),
          ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                ? const Center(child: Text('暂无访客记录'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                    children: <Widget>[
                      _OxygenPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: <Widget>[
                            for (
                              int index = 0;
                              index < _items!.length;
                              index += 1
                            ) ...<Widget>[
                              _OxygenUserRow(
                                user: _items![index],
                                subtitle: '访问 ${_items![index].visitCount} 次',
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (BuildContext context) =>
                                        PublicProfilePage(
                                          userId: _items![index].userId,
                                        ),
                                  ),
                                ),
                              ),
                              if (index < _items!.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class PrivacyBlacklistPage extends StatefulWidget {
  const PrivacyBlacklistPage({super.key});

  @override
  State<PrivacyBlacklistPage> createState() => _PrivacyBlacklistPageState();
}

class _PrivacyBlacklistPageState extends State<PrivacyBlacklistPage> {
  PrivacySettings? _settings;
  List<SocialUser>? _blacklist;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final SocialRepository repository = AppDependencyScope.of(
      context,
    ).socialRepository;
    final List<Object> values = await Future.wait<Object>(<Future<Object>>[
      repository.fetchPrivacySettings(),
      repository.fetchBlacklist(page: 1, pageSize: 100),
    ]);
    if (mounted) {
      setState(() {
        _settings = values[0] as PrivacySettings;
        _blacklist = (values[1] as SocialPage<SocialUser>).items;
      });
    }
  }

  Future<void> _togglePrivacy(bool value) async {
    final PrivacySettings updated = await AppDependencyScope.of(
      context,
    ).socialRepository.updatePrivacySettings(onlyFollowedCanFollow: value);
    if (mounted) {
      setState(() => _settings = updated);
    }
  }

  Future<void> _unblock(SocialUser user) async {
    await AppDependencyScope.of(
      context,
    ).socialRepository.setBlocked(userId: user.userId, blocked: false);
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('隐私与黑名单')),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
              children: <Widget>[
                _OxygenPanel(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF8FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          color: SocialColors.accent,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '仅允许我关注的人关注我',
                              style: TextStyle(
                                color: SocialColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _settings!.serverValueKnown
                                  ? '已与服务端同步'
                                  : '首次修改后可确认服务端状态',
                              style: const TextStyle(
                                color: SocialColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _settings!.onlyFollowedCanFollow,
                        onChanged: _togglePrivacy,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const _OxygenSectionLabel(title: '黑名单'),
                const SizedBox(height: 8),
                if (_blacklist!.isEmpty)
                  const _OxygenPanel(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('黑名单为空'),
                      ),
                    ),
                  )
                else
                  _OxygenPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < _blacklist!.length;
                          index += 1
                        ) ...<Widget>[
                          _OxygenUserRow(
                            user: _blacklist![index],
                            subtitle: '已屏蔽对方的关系与互动',
                            onTap: () {},
                            trailing: TextButton(
                              onPressed: () => _unblock(_blacklist![index]),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 34),
                              ),
                              child: const Text(
                                '移出',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          if (index < _blacklist!.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
