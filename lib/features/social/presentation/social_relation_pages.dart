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
      final SocialPage<SocialUser> page = await AppDependencyScope.of(context)
          .socialRepository
          .fetchRelations(type: _type, page: 1, pageSize: 50);
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
    return Scaffold(
      appBar: AppBar(title: const Text('关注、粉丝与好友')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<SocialRelationList>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<SocialRelationList>>[
                ButtonSegment<SocialRelationList>(
                  value: SocialRelationList.following,
                  label: Text('关注'),
                ),
                ButtonSegment<SocialRelationList>(
                  value: SocialRelationList.followers,
                  label: Text('粉丝'),
                ),
                ButtonSegment<SocialRelationList>(
                  value: SocialRelationList.friends,
                  label: Text('好友'),
                ),
              ],
              selected: <SocialRelationList>{_type},
              onSelectionChanged: (Set<SocialRelationList> value) {
                setState(() => _type = value.first);
                _load();
              },
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
                            child: ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final SocialUser user = _items[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(_initial(user.name)),
                                  ),
                                  title: Text(user.name),
                                  subtitle: Text(user.signature),
                                  trailing: user.roomId == null
                                      ? const Icon(Icons.chevron_right_rounded)
                                      : const Icon(Icons.headphones_rounded),
                                  onTap: () => Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext context) =>
                                          PublicProfilePage(userId: user.userId),
                                    ),
                                  ),
                                );
                              },
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
      final List<FriendRequest> value = await AppDependencyScope.of(context)
          .socialRepository
          .fetchFriendRequests();
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
      await AppDependencyScope.of(context).socialRepository.resolveFriendRequest(
            requestId: request.id,
            accepted: accepted,
          );
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SocialRepository repository =
        AppDependencyScope.of(context).socialRepository;
    return Scaffold(
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
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final FriendRequest request = _items![index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(request.user.name),
                          subtitle: Text(request.message),
                          trailing: request.status == FriendRequestStatus.pending
                              ? Wrap(
                                  spacing: 4,
                                  children: <Widget>[
                                    TextButton(
                                      onPressed: () => _resolve(request, false),
                                      child: const Text('拒绝'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () => _resolve(request, true),
                                      child: const Text('接受'),
                                    ),
                                  ],
                                )
                              : Text(_friendRequestLabel(request.status)),
                        );
                      },
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
    final SocialPage<SocialUser> value = await AppDependencyScope.of(context)
        .socialRepository
        .fetchVisitors(type: _type, page: 1, pageSize: 50);
    if (mounted) {
      setState(() => _items = value.items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('访客记录')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<VisitorRecordType>(
              segments: const <ButtonSegment<VisitorRecordType>>[
                ButtonSegment<VisitorRecordType>(
                  value: VisitorRecordType.viewedMe,
                  label: Text('谁看过我'),
                ),
                ButtonSegment<VisitorRecordType>(
                  value: VisitorRecordType.viewedByMe,
                  label: Text('我看过谁'),
                ),
              ],
              selected: <VisitorRecordType>{_type},
              onSelectionChanged: (Set<VisitorRecordType> value) {
                setState(() {
                  _type = value.first;
                  _items = null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                    ? const Center(child: Text('暂无访客记录'))
                    : ListView.builder(
                        itemCount: _items!.length,
                        itemBuilder: (BuildContext context, int index) {
                          final SocialUser user = _items![index];
                          return ListTile(
                            leading: CircleAvatar(child: Text(_initial(user.name))),
                            title: Text(user.name),
                            subtitle: Text('访问 ${user.visitCount} 次'),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    PublicProfilePage(userId: user.userId),
                              ),
                            ),
                          );
                        },
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
    final SocialRepository repository =
        AppDependencyScope.of(context).socialRepository;
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
    final PrivacySettings updated = await AppDependencyScope.of(context)
        .socialRepository
        .updatePrivacySettings(onlyFollowedCanFollow: value);
    if (mounted) {
      setState(() => _settings = updated);
    }
  }

  Future<void> _unblock(SocialUser user) async {
    await AppDependencyScope.of(context).socialRepository.setBlocked(
          userId: user.userId,
          blocked: false,
        );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私与黑名单')),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仅允许我关注的人关注我'),
                  subtitle: Text(_settings!.serverValueKnown
                      ? '当前设置已与服务端同步'
                      : '服务端未提供读取接口，首次修改后才可确认'),
                  value: _settings!.onlyFollowedCanFollow,
                  onChanged: _togglePrivacy,
                ),
                const Divider(),
                Text('黑名单', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_blacklist!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('黑名单为空'),
                  )
                else
                  for (final SocialUser user in _blacklist!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.name),
                      trailing: TextButton(
                        onPressed: () => _unblock(user),
                        child: const Text('移出'),
                      ),
                    ),
              ],
            ),
    );
  }
}
