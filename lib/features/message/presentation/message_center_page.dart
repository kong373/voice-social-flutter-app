part of 'message_pages.dart';

class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({this.isActive = true, super.key});

  final bool isActive;

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage>
    with AutomaticKeepAliveClientMixin<MessageCenterPage> {
  List<ConversationSummary>? _conversations;
  bool _loading = true;
  String? _error;
  int _loadRequestId = 0;
  ImAuthoritativeRefreshBus? _refreshBus;
  ImAuthoritativeRefreshSubscription? _refreshSubscription;
  Future<void>? _refreshFlight;
  bool _refreshAgain = false;
  int _refreshGeneration = 0;
  AppDependencies? _dependencies;
  (int?, int)? _viewer;
  bool _identityLost = false;
  _MessageVisibility? _visibility;
  PrivateHistoryState? _privateHistory;
  final ValueNotifier<int> _searchRevision = ValueNotifier(0);
  bool get _canRead => _currentIdentity && _visibility?.viewerReason == null;

  List<ConversationSummary> get _visibleConversations => [
    for (final conversation in _conversations ?? <ConversationSummary>[])
      if (_visibility?.reasonFor(conversation.targetUserId) == null)
        _privateHistory?.project(conversation) ?? conversation,
  ];

  void _visibilityChanged() {
    if (!mounted || !_currentIdentity) return;
    setState(() {
      if (_visibility?.viewerReason != null) {
        _cancelPendingLoads();
        _conversations = null;
        _loading = false;
        _error = _visibility!.viewerReason;
      } else {
        _conversations = _visibleConversations;
        _error = null;
      }
    });
    _searchRevision.value++;
  }

  void _historyChanged() {
    if (!mounted || !_currentIdentity) return;
    setState(() => _conversations = _visibleConversations);
    _searchRevision.value++;
  }

  (int?, int) get _currentViewer => (
    _dependencies!.sessionManager.session?.userId,
    _dependencies!.sessionManager.identityGeneration,
  );
  bool get _currentIdentity => !_identityLost && _viewer == _currentViewer;

  void _identityChanged() {
    if (!mounted || _currentIdentity) return;
    _identityLost = true;
    _cancelPendingLoads();
    setState(() {
      _conversations = null;
      _loading = false;
      _error = '登录状态已改变，请重新进入消息。';
    });
  }

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant MessageCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _cancelPendingLoads();
      return;
    }
    if (widget.isActive && !oldWidget.isActive) {
      _load(showLoading: false, revalidateDeniedPeers: true).ignore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = AppDependencyScope.of(context);
    if (!identical(deps, _dependencies)) {
      _dependencies?.sessionManager.removeListener(_identityChanged);
      _visibility?.removeListener(_visibilityChanged);
      _privateHistory?.removeListener(_historyChanged);
      if (_dependencies != null) _identityLost = true;
      _dependencies = deps;
      _viewer ??= _currentViewer;
      if (deps.messageRepository is ClearablePrivateHistoryRepository) {
        _privateHistory =
            (deps.messageRepository as ClearablePrivateHistoryRepository)
                .privateHistory
              ..addListener(_historyChanged);
      }
      _visibility = _MessageVisibility.forViewer(
        deps.messageRepository,
        _currentViewer,
      )..addListener(_visibilityChanged);
      deps.sessionManager.addListener(_identityChanged);
      _identityChanged();
      if (_visibility!.viewerReason != null) _visibilityChanged();
    }
    final ImAuthoritativeRefreshBus refreshBus = AppDependencyScope.of(
      context,
    ).imAuthoritativeRefreshBus;
    if (!identical(_refreshBus, refreshBus)) {
      _refreshSubscription?.cancel();
      _refreshBus = refreshBus;
      _refreshSubscription = refreshBus.subscribe(_onAuthoritativeRefresh);
    }
    if (_conversations == null && _loading) {
      _load(revalidateDeniedPeers: widget.isActive);
    }
  }

  Future<void> _onAuthoritativeRefresh(ImAuthoritativeRefreshRequest request) {
    if (!mounted || !widget.isActive || !_canRead) return Future<void>.value();
    final Future<void>? active = _refreshFlight;
    if (active != null) {
      _refreshAgain = true;
      return active;
    }
    final Future<void> operation = _drainRefresh(_refreshGeneration);
    _refreshFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_refreshFlight, operation)) {
          _refreshFlight = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_refreshFlight, operation)) {
          _refreshFlight = null;
        }
      },
    );
    return operation;
  }

  Future<void> _drainRefresh(int generation) async {
    // Coalesce hints received during a read, but do not lose the newer
    // authoritative snapshot when the first response was already in flight.
    do {
      _refreshAgain = false;
      await _load(showLoading: false);
    } while (mounted &&
        widget.isActive &&
        generation == _refreshGeneration &&
        _canRead &&
        _refreshAgain);
  }

  Future<void> _load({
    bool showLoading = true,
    bool revalidate = false,
    bool revalidateDeniedPeers = false,
  }) async {
    if (!mounted || !_currentIdentity || (!revalidate && !_canRead)) {
      return;
    }
    final int requestId = ++_loadRequestId;
    final MessageRepository repository = _repository;
    final AppDependencies dependencies = AppDependencyScope.of(context);
    final viewer = _currentViewer;
    bool accepts() =>
        mounted &&
        _currentIdentity &&
        (!revalidateDeniedPeers || widget.isActive) &&
        (revalidate || _canRead) &&
        identical(dependencies, AppDependencyScope.of(context)) &&
        viewer == _currentViewer &&
        requestId == _loadRequestId;
    final bool replaceWithLoading = showLoading && _conversations == null;
    if (replaceWithLoading || _error != null) {
      setState(() {
        _loading = replaceWithLoading;
        _error = null;
      });
    }
    try {
      final List<ConversationSummary> value = await repository
          .fetchConversations();
      if (!accepts()) {
        return;
      }
      if (revalidateDeniedPeers) {
        final Set<int>? restoredPeers = await _revalidateDeniedPeers(
          value,
          accepts: accepts,
        );
        if (restoredPeers == null || !accepts()) return;
        for (final peer in restoredPeers) {
          _visibility!.restore(peer: peer);
        }
      }
      if (revalidate) _visibility!.restore();
      setState(() {
        _conversations = [
          for (final conversation in value)
            if (_visibility?.reasonFor(conversation.targetUserId) == null)
              conversation,
        ];
        _loading = false;
      });
      _searchRevision.value++;
    } catch (error) {
      if (!accepts()) {
        return;
      }
      final denial = _MessageReadDenial.from(error);
      if (denial != null) {
        _visibility!.deny(denial);
        setState(() {
          _loading = false;
          _conversations = null;
          _error = _visibility!.viewerReason;
        });
        return;
      }
      setState(() {
        _loading = false;
        if (_conversations == null) {
          _error = _messageFor(error);
        }
      });
    }
  }

  Future<Set<int>?> _revalidateDeniedPeers(
    List<ConversationSummary> conversations, {
    required bool Function() accepts,
  }) async {
    final visibility = _visibility;
    final repository = _repository;
    if (visibility == null || repository is! PagedPrivateMessageRepository) {
      return const <int>{};
    }
    final Map<int, ConversationSummary> available = {
      for (final conversation in conversations)
        if (conversation.available) conversation.targetUserId: conversation,
    };
    final Set<int> restored = <int>{};
    for (final peer in visibility.deniedPeers.toList()) {
      final conversation = available[peer];
      if (conversation == null) continue;
      try {
        await repository.fetchVisiblePrivateMessagePage(
          conversation,
          isCurrent: accepts,
        );
        if (!accepts()) return null;
        restored.add(peer);
      } catch (error) {
        if (!accepts()) return null;
        final denial = _MessageReadDenial.from(error);
        if (denial != null) visibility.deny(denial, peer: peer);
        // A denial or transient failure is not proof that access returned.
      }
    }
    return restored;
  }

  void _cancelPendingLoads() {
    _loadRequestId += 1;
    _refreshGeneration += 1;
    _refreshAgain = false;
    _refreshFlight = null;
  }

  void _close() {
    _cancelPendingLoads();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _cancelPendingLoads();
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _dependencies?.sessionManager.removeListener(_identityChanged);
    _visibility?.removeListener(_visibilityChanged);
    _privateHistory?.removeListener(_historyChanged);
    _searchRevision.dispose();
    super.dispose();
  }

  Future<void> _openConversation(ConversationSummary conversation) async {
    if (!_canRead || _visibility?.reasonFor(conversation.targetUserId) != null)
      return;
    if (!conversation.available) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => NotificationTargetUnavailablePage(
            title: '会话不可用',
            reason: conversation.unavailableReason.isEmpty
                ? '当前会话对象不可用'
                : conversation.unavailableReason,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PrivateChatPage(conversation: conversation),
      ),
    );
    if (!mounted) {
      return;
    }
    _load(showLoading: false).ignore();
  }

  Future<void> _openMessageSearch() async {
    final ConversationSummary? selected =
        await showSearch<ConversationSummary?>(
          context: context,
          delegate: _MessageConversationSearchDelegate(
            conversations: () => mounted && _canRead
                ? _visibleConversations
                : const <ConversationSummary>[],
            isCurrent: () => mounted && _canRead,
            identityChanges: Listenable.merge([
              _dependencies!.sessionManager,
              _searchRevision,
            ]),
          ),
        );
    if (!mounted ||
        !_canRead ||
        selected == null ||
        !_visibleConversations.any(
          (row) =>
              row.targetUserId == selected.targetUserId &&
              row.id == selected.id,
        )) {
      return;
    }
    await _openConversation(selected);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<ConversationSummary> conversations = _visibleConversations;
    return PopScope<void>(
      onPopInvokedWithResult: (bool didPop, void result) {
        if (didPop) {
          _cancelPendingLoads();
        }
      },
      child: SocialPageScaffold(
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? !_canRead
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            if (_currentIdentity)
                              TextButton(
                                onPressed: () => _load(revalidate: true),
                                child: const Text('检查账号状态'),
                              ),
                          ],
                        ),
                      )
                    : _MessageError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          if (Navigator.canPop(context)) ...<Widget>[
                            _HeaderRoundButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: '返回上一页',
                              onTap: _close,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            '消息',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: SocialColors.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const Spacer(),
                          _HeaderRoundButton(
                            icon: Icons.search_rounded,
                            tooltip: '搜索消息',
                            onTap: _openMessageSearch,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Tooltip(
                        message: '通知权限与消息恢复',
                        child: _MessageSearchHint(
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) =>
                                  const MessagePermissionRecoveryPage(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Tooltip(
                              message: '系统与互动通知',
                              child: _MessageShortcutCard(
                                icon: Icons.notifications_none_rounded,
                                title: '官方消息',
                                accent: const Color(0xFF6D9BFF),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (BuildContext context) =>
                                        const NotificationCenterPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _MessageShortcutCard(
                              icon: Icons.notifications_active_outlined,
                              title: '系统通知',
                              accent: const Color(0xFF55D6E8),
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const NotificationCenterPage(),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _MessageShortcutCard(
                              icon: Icons.waving_hand_outlined,
                              title: '打招呼',
                              accent: const Color(0xFFFFC454),
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const NotificationCenterPage(
                                        initialCategory:
                                            NotificationCategory.interaction,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _MessageShortcutCard(
                              icon: Icons.favorite_border_rounded,
                              title: '互动消息',
                              accent: const Color(0xFFFF75B8),
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const NotificationCenterPage(
                                        initialCategory:
                                            NotificationCategory.interaction,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _MessageSupportRow(
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const HelpCenterPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_repository.supportsPrivateRealtime)
                        const _MessageInfoCard(
                          icon: Icons.chat_bubble_outline_rounded,
                          text: '实时消息暂不可用，已保存的消息记录仍可查看。',
                        ),
                      if (!_repository.supportsConversationList) ...<Widget>[
                        const SizedBox(height: 10),
                        const _MessageInfoCard(
                          icon: Icons.list_alt_rounded,
                          text: '当前后端没有确认用户侧会话列表协议，正式会话索引等待腾讯 IM 接入。',
                        ),
                      ],
                      const SizedBox(height: 16),
                      const SizedBox(height: 14),
                      Text(
                        '最近消息',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: SocialColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (conversations.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 54),
                            child: Column(
                              children: <Widget>[
                                const Icon(Icons.forum_outlined, size: 48),
                                const SizedBox(height: 14),
                                const Text('暂无可展示会话'),
                                const SizedBox(height: 6),
                                Text(
                                  _repository.supportsConversationList
                                      ? '建立好友关系或收到新消息后，会话会出现在这里。'
                                      : '会话索引将在腾讯 IM 接入后恢复。',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        _MessageListPanel(
                          child: Column(
                            children: <Widget>[
                              for (
                                int index = 0;
                                index < conversations.length;
                                index += 1
                              ) ...<Widget>[
                                _MessageConversationRow(
                                  conversation: conversations[index],
                                  onTap: () =>
                                      _openConversation(conversations[index]),
                                ),
                                if (index < conversations.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _MessageConversationSearchDelegate
    extends SearchDelegate<ConversationSummary?> {
  _MessageConversationSearchDelegate({
    required this.conversations,
    required this.isCurrent,
    required this.identityChanges,
  }) : super(searchFieldLabel: '搜索联系人或消息内容');

  final List<ConversationSummary> Function() conversations;
  final bool Function() isCurrent;
  final Listenable identityChanges;

  @override
  List<Widget>? buildActions(BuildContext context) => <Widget>[
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清空搜索',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回消息',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _guardedMatches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _guardedMatches(context);

  Widget _guardedMatches(BuildContext context) => ListenableBuilder(
    listenable: identityChanges,
    builder: (context, _) => isCurrent()
        ? _buildMatches(context)
        : const Center(child: Text('登录状态已改变，请重新进入消息。')),
  );

  Widget _buildMatches(BuildContext context) {
    final String keyword = query.trim().toLowerCase();
    final List<ConversationSummary> matches = conversations()
        .where(
          (ConversationSummary item) =>
              keyword.isEmpty ||
              item.title.toLowerCase().contains(keyword) ||
              item.lastMessage.toLowerCase().contains(keyword),
        )
        .toList(growable: false);
    return SocialSkySurface(
      child: matches.isEmpty
          ? const Center(child: Text('没有找到相关消息'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: <Widget>[
                _MessageListPanel(
                  child: Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < matches.length;
                        index += 1
                      ) ...<Widget>[
                        _MessageConversationRow(
                          conversation: matches[index],
                          onTap: () => close(context, matches[index]),
                        ),
                        if (index < matches.length - 1)
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
