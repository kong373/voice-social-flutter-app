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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<ConversationSummary> value =
          await _repository.fetchConversations();
      if (mounted) {
        setState(() {
          _conversations = value;
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
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<ConversationSummary> conversations =
        _conversations ?? const <ConversationSummary>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: <Widget>[
          IconButton(
            tooltip: '系统与互动通知',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const NotificationCenterPage(),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: '通知权限与消息恢复',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    const MessagePermissionRecoveryPage(),
              ),
            ),
            icon: const Icon(Icons.settings_backup_restore_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _MessageError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                    children: <Widget>[
                      if (!_repository.supportsPrivateSend)
                        const _MessageInfoCard(
                          icon: Icons.chat_bubble_outline_rounded,
                          text: '腾讯 IM 尚未接入。Live 模式不伪造私聊发送、漫游或未读状态；服务端已落库通知仍可独立刷新。',
                        ),
                      if (!_repository.supportsConversationList) ...<Widget>[
                        const SizedBox(height: 10),
                        const _MessageInfoCard(
                          icon: Icons.list_alt_rounded,
                          text: '当前后端没有确认用户侧会话列表协议，正式会话索引等待腾讯 IM 接入。',
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '会话列表',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    const NotificationCenterPage(),
                              ),
                            ),
                            icon: const Icon(Icons.notifications_outlined),
                            label: const Text('查看通知'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                        for (final ConversationSummary conversation
                            in conversations)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(18),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 5,
                                ),
                                leading: CircleAvatar(
                                  child: Text(_initial(conversation.title)),
                                ),
                                title: Text(conversation.title),
                                subtitle: Text(
                                  conversation.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: SizedBox(
                                  width: 54,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Text(
                                        _formatMessageTime(
                                          conversation.updatedAt,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 5),
                                      _UnreadBadge(
                                        count: conversation.unreadCount,
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () => _openConversation(conversation),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}
