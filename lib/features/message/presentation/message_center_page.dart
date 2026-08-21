part of 'message_pages.dart';

class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage>
    with AutomaticKeepAliveClientMixin<MessageCenterPage> {
  List<ConversationSummary>? _conversations;
  bool _loading = true;
  String? _error;
  int _loadRequestId = 0;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conversations == null && _loading) {
      _load();
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) {
      return;
    }
    final int requestId = ++_loadRequestId;
    final MessageRepository repository = _repository;
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
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _conversations = value;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
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

  void _cancelPendingLoads() {
    _loadRequestId += 1;
  }

  void _close() {
    _cancelPendingLoads();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _cancelPendingLoads();
    super.dispose();
  }

  Future<void> _openConversation(ConversationSummary conversation) async {
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
            conversations: _conversations ?? const <ConversationSummary>[],
          ),
        );
    if (!mounted || selected == null) {
      return;
    }
    await _openConversation(selected);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<ConversationSummary> conversations =
        _conversations ?? const <ConversationSummary>[];
    return PopScope<void>(
      onPopInvokedWithResult: (bool didPop, void result) {
        if (didPop) {
          _cancelPendingLoads();
        }
      },
      child: SocialPageScaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _MessageError(message: _error!, onRetry: _load)
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
                        Expanded(
                          child: _MessageShortcutCard(
                            icon: Icons.person_add_alt_1_rounded,
                            title: '好友请求',
                            accent: const Color(0xFFFF7D74),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    const RelationsPage(),
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
                    if (!_repository.supportsPrivateSend)
                      const _MessageInfoCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        text:
                            '腾讯 IM 尚未接入。Live 模式不伪造私聊发送、漫游或未读状态；服务端已落库通知仍可独立刷新。',
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
    );
  }
}

class _MessageConversationSearchDelegate
    extends SearchDelegate<ConversationSummary?> {
  _MessageConversationSearchDelegate({required this.conversations})
    : super(searchFieldLabel: '搜索联系人或消息内容');

  final List<ConversationSummary> conversations;

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
  Widget buildResults(BuildContext context) => _buildMatches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches(context);

  Widget _buildMatches(BuildContext context) {
    final String keyword = query.trim().toLowerCase();
    final List<ConversationSummary> matches = conversations
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
