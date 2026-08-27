part of 'message_pages.dart';

class PrivateChatPage extends StatefulWidget {
  const PrivateChatPage({required this.conversation, super.key});

  final ConversationSummary conversation;

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  late ConversationSummary _conversation;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _loadRequestId = 0;
  String? _pendingSendRequestId;
  String? _pendingSendContent;
  ImAuthoritativeRefreshBus? _refreshBus;
  ImAuthoritativeRefreshSubscription? _refreshSubscription;
  Future<void>? _refreshFlight;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ImAuthoritativeRefreshBus refreshBus = AppDependencyScope.of(
      context,
    ).imAuthoritativeRefreshBus;
    if (!identical(_refreshBus, refreshBus)) {
      _refreshSubscription?.cancel();
      _refreshBus = refreshBus;
      _refreshSubscription = refreshBus.subscribe(_onAuthoritativeRefresh);
    }
    if (_loading && _messages.isEmpty) {
      _load();
    }
  }

  Future<void> _onAuthoritativeRefresh(ImAuthoritativeRefreshRequest request) {
    final Future<void>? active = _refreshFlight;
    if (active != null) {
      return active;
    }
    final Future<void> operation = _load(showLoading: false);
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

  @override
  void dispose() {
    _loadRequestId += 1;
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) {
      return;
    }
    final int requestId = ++_loadRequestId;
    final MessageRepository repository = _repository;
    final AppDependencies dependencies = AppDependencyScope.of(context);
    final int authUserIdAtStart =
        dependencies.sessionManager.session?.userId ?? 0;
    if (showLoading || _error != null) {
      setState(() {
        _loading = showLoading;
        _error = null;
      });
    }
    try {
      final List<ChatMessage> value = await repository.fetchPrivateMessages(
        _conversation,
      );
      final int authUserIdAfterFetch =
          dependencies.sessionManager.session?.userId ?? 0;
      if (!mounted ||
          requestId != _loadRequestId ||
          authUserIdAfterFetch != authUserIdAtStart) {
        return;
      }
      if (_conversation.isDraft) {
        final ChatMessage? identifiedMessage = value
            .where(
              (ChatMessage item) =>
                  item.conversationId != null &&
                  item.conversationId!.trim().isNotEmpty,
            )
            .firstOrNull;
        if (identifiedMessage?.conversationId != null) {
          final DateTime serverUpdatedAt = value
              .map((ChatMessage item) => item.createdAt)
              .reduce(
                (DateTime left, DateTime right) =>
                    left.isAfter(right) ? left : right,
              );
          _conversation = _conversation.withServerIdentity(
            conversationId: identifiedMessage!.conversationId!,
            serverUpdatedAt: serverUpdatedAt,
          );
        }
      }
      final List<ChatMessage> mergedMessages = _mergeMessages(value);
      setState(() {
        _messages
          ..clear()
          ..addAll(mergedMessages);
        _loading = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _loading = false;
        // A provider hint only requests an authoritative refresh.  If that
        // HTTP refresh fails after messages are already visible, keep the
        // last first-party snapshot on screen and let the next hint/manual
        // refresh retry it; do not replace trusted content with a transient
        // error page.
        _error = !showLoading && _messages.isNotEmpty
            ? null
            : _messageFor(error);
      });
    }
  }

  Future<void> _send() async {
    if (_sending || !_repository.supportsPrivateSend) {
      return;
    }
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (_pendingSendRequestId == null || _pendingSendContent != text) {
      _pendingSendRequestId = createMessageRequestId();
      _pendingSendContent = text;
    }
    final String requestId = _pendingSendRequestId!;
    setState(() => _sending = true);
    try {
      final ChatMessage message = await _repository.sendPrivateMessage(
        conversation: _conversation,
        content: text,
        requestId: requestId,
      );
      if (!mounted) {
        return;
      }
      if (_conversation.isDraft && message.conversationId != null) {
        _conversation = _conversation.withServerIdentity(
          conversationId: message.conversationId!,
          serverUpdatedAt: message.createdAt,
        );
      }
      // A history/refresh request that started before this authoritative send
      // must not overwrite the newly stored message when it completes later.
      _loadRequestId += 1;
      final List<ChatMessage> mergedMessages = _mergeMessages(<ChatMessage>[
        message,
      ]);
      setState(() {
        _messages
          ..clear()
          ..addAll(mergedMessages);
        _loading = false;
        _error = null;
        _controller.clear();
      });
      _pendingSendRequestId = null;
      _pendingSendContent = null;
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<ChatMessage> _mergeMessages(List<ChatMessage> incoming) {
    final Map<String, ChatMessage> byId = <String, ChatMessage>{
      for (final ChatMessage item in _messages) item.id: item,
    };
    for (final ChatMessage item in incoming) {
      byId[item.id] = item;
    }
    final List<ChatMessage> merged = byId.values.toList()
      ..sort(
        (ChatMessage left, ChatMessage right) =>
            left.createdAt.compareTo(right.createdAt),
      );
    return merged;
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PublicProfilePage(userId: _conversation.targetUserId),
      ),
    );
  }

  void _report() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReportPage(
          targetType: ReportTargetType.user,
          targetId: '${_conversation.targetUserId}',
          targetName: _conversation.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend =
        _repository.supportsPrivateSend && _conversation.available && !_sending;
    return SocialPageScaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            RuntimeAvatar(
              seed: _conversation.id ?? 'user-${_conversation.targetUserId}',
              size: 34,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _repository.supportsPrivateRealtime
                        ? '实时在线'
                        : _repository.supportsPrivateSend
                        ? '服务端留存'
                        : '只读历史',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _repository.supportsPrivateRealtime
                          ? SocialColors.success
                          : SocialColors.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'profile') {
                _openProfile();
              } else {
                _report();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'profile',
                    child: Text('查看公开主页'),
                  ),
                  PopupMenuItem<String>(value: 'report', child: Text('举报用户')),
                ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_repository.supportsPrivateRealtime)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: const _MessageInfoCard(
                icon: Icons.lock_outline_rounded,
                text: '第一方消息可写入并恢复；腾讯 IM 实时投递仍为 VENDOR_BLOCKED，不伪造在线状态。',
              ),
            ),
          if (_conversation.isDraft)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _MessageInfoCard(
                icon: Icons.pending_outlined,
                text:
                    '新会话草稿：服务端尚未返回会话 ID；首条消息留存后会尽可能从权威会话列表解析，未解析前不会生成本地会话 ID。',
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _MessageError(message: _error!, onRetry: _load)
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      _repository.supportsPrivateHistory
                          ? '还没有消息，认真说第一句话吧'
                          : '当前没有可恢复的私聊历史',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                      itemCount: _messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _ChatBubble(message: _messages[index]);
                      },
                    ),
                  ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.86),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: '语音功能暂未开放',
                      onPressed: null,
                      icon: const Icon(Icons.mic_none_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: canSend,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: canSend ? '输入消息（服务端留存）…' : '当前发送不可用',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SocialColors.brandGradient,
                      ),
                      child: IconButton(
                        tooltip: '发送消息',
                        onPressed: canSend ? _send : null,
                        color: Colors.white,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final DateTime now = AppDependencyScope.of(context).currentTime();
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 286),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMine ? null : Colors.white.withValues(alpha: 0.86),
          gradient: message.isMine
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF8A70F6), Color(0xFFAF7DE8)],
                )
              : null,
          border: message.isMine
              ? null
              : Border.all(color: const Color(0x1417213C)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x0A0F1C3D), blurRadius: 8),
          ],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isMine ? 18 : 4),
            bottomRight: Radius.circular(message.isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message.content,
              style: TextStyle(
                color: message.isMine ? Colors.white : SocialColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (message.status ==
                    ChatMessageStatus.storedPendingDelivery) ...<Widget>[
                  Text(
                    '已留存·实时未送达',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: message.isMine
                          ? Colors.white.withValues(alpha: 0.86)
                          : SocialColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  _formatMessageTime(message.createdAt, now),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: message.isMine
                        ? Colors.white.withValues(alpha: 0.78)
                        : SocialColors.textTertiary,
                  ),
                ),
                if (message.status == ChatMessageStatus.failed) ...<Widget>[
                  const SizedBox(width: 5),
                  const Icon(Icons.error_outline_rounded, size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
