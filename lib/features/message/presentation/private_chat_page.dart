part of 'message_pages.dart';

class PrivateChatPage extends StatefulWidget {
  const PrivateChatPage({required this.conversation, super.key});

  final ConversationSummary conversation;

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage>
    with WidgetsBindingObserver {
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
  Timer? _syncTimer;
  AppDependencies? _dependencies;
  ModalRoute<void>? _route;
  int? _accountId;
  bool _loadStarted = false;
  bool _foreground = true;
  bool _visible = false;
  bool _accountChanged = false;
  final Set<String> _historyMessageIds = <String>{};
  Set<String>? _catchupBoundary;
  String? _catchupCursor;

  MessageRepository get _repository => _dependencies!.messageRepository;

  bool get _active => mounted && _foreground && (_route?.isCurrent ?? true);

  bool get _canAutoSync =>
      _active &&
      !_accountChanged &&
      _dependencies!.environment.isLive &&
      _conversation.available &&
      _repository.supportsPrivateHistory;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppDependencies nextDependencies = AppDependencyScope.of(context);
    if (!identical(_dependencies, nextDependencies)) {
      _dependencies?.sessionManager.removeListener(_onAccountChanged);
      _dependencies = nextDependencies;
      _dependencies!.sessionManager.addListener(_onAccountChanged);
    }
    _route = ModalRoute.of<void>(context);
    final bool wasVisible = _visible;
    _visible = _active;
    final ImAuthoritativeRefreshBus refreshBus =
        _dependencies!.imAuthoritativeRefreshBus;
    if (!identical(_refreshBus, refreshBus)) {
      _refreshSubscription?.cancel();
      _refreshBus = refreshBus;
      _refreshSubscription = refreshBus.subscribe(_onAuthoritativeRefresh);
    }
    if (!_loadStarted) {
      _loadStarted = true;
      _accountId = _dependencies!.sessionManager.session?.userId ?? 0;
      _load();
    } else if (!wasVisible && _visible) {
      _load(showLoading: false);
    } else if (!_visible) {
      _syncTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visible = _active;
    _syncTimer?.cancel();
    if (_visible && _loadStarted) {
      _load(showLoading: false);
    }
  }

  bool _checkAccount() {
    if (!mounted || _accountChanged) return false;
    if (!_dependencies!.environment.isLive ||
        (_dependencies!.sessionManager.session?.userId ?? 0) == _accountId) {
      return true;
    }
    _syncTimer?.cancel();
    _loadRequestId += 1;
    setState(() {
      _accountChanged = true;
      _messages.clear();
      _historyMessageIds.clear();
      _catchupBoundary = null;
      _catchupCursor = null;
      _controller.clear();
      _pendingSendRequestId = null;
      _pendingSendContent = null;
      _loading = false;
      _error = '登录状态已改变，请重新进入会话。';
    });
    return false;
  }

  void _onAccountChanged() {
    if (_loadStarted) _checkAccount();
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    if (!_canAutoSync) return;
    // IM hints remain the fast path. HTTP also repairs missed hints and works
    // when realtime delivery is unavailable; it is not an IM delivery receipt.
    // Leave time for the authoritative response and rendering within the
    // five-second foreground fallback budget. Requests still run single-flight.
    _syncTimer = Timer(const Duration(seconds: 2), () {
      if (_checkAccount() && _canAutoSync) _load(showLoading: false);
    });
  }

  Future<void> _onAuthoritativeRefresh(ImAuthoritativeRefreshRequest request) =>
      _load(showLoading: false);

  Future<void> _load({bool showLoading = true}) {
    if (!_checkAccount() || !_active) return Future<void>.value();
    final Future<void>? active = _refreshFlight;
    if (active != null) return active;
    _syncTimer?.cancel();
    final Future<void> operation = _performLoad(showLoading: showLoading);
    _refreshFlight = operation;
    void completed() {
      if (identical(_refreshFlight, operation)) {
        _refreshFlight = null;
        if (mounted) _scheduleSync();
      }
    }

    operation.then<void>(
      (_) => completed(),
      onError: (Object _, StackTrace __) {
        completed();
      },
    );
    return operation;
  }

  @override
  void dispose() {
    _loadRequestId += 1;
    WidgetsBinding.instance.removeObserver(this);
    _dependencies?.sessionManager.removeListener(_onAccountChanged);
    _syncTimer?.cancel();
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performLoad({required bool showLoading}) async {
    if (!mounted) {
      return;
    }
    final int requestId = ++_loadRequestId;
    final MessageRepository repository = _repository;
    if (showLoading || _error != null) {
      setState(() {
        _loading = showLoading;
        _error = null;
      });
    }
    try {
      final Set<String> historyBoundary =
          _catchupBoundary ?? Set<String>.of(_historyMessageIds);
      final PrivateMessageSyncBatch batch =
          repository is VisiblePrivateMessageRepository
          ? await repository.fetchVisiblePrivateMessages(
              _conversation,
              knownMessageIds: historyBoundary,
              resumeCursor: _catchupCursor,
              isCurrent: () =>
                  _active &&
                  requestId == _loadRequestId &&
                  !_accountChanged &&
                  (_dependencies!.sessionManager.session?.userId ?? 0) ==
                      _accountId,
            )
          : PrivateMessageSyncBatch(
              await repository.fetchPrivateMessages(_conversation),
            );
      if (!_checkAccount() || requestId != _loadRequestId || !_active) {
        return;
      }
      final List<ChatMessage> value = batch.messages;
      _historyMessageIds.addAll(value.map((item) => item.id));
      _catchupCursor = batch.nextCursor;
      _catchupBoundary = batch.nextCursor == null ? null : historyBoundary;
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
      final bool hasNewMessages = mergedMessages.length > _messages.length;
      final bool followLatest =
          _messages.isEmpty ||
          !_scrollController.hasClients ||
          _scrollController.position.extentAfter < 80;
      setState(() {
        _messages
          ..clear()
          ..addAll(mergedMessages);
        _loading = false;
      });
      if (hasNewMessages && followLatest) _scrollToEnd();
    } catch (error) {
      if (!_checkAccount() || requestId != _loadRequestId || !_active) {
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
    if (!_checkAccount() ||
        !_active ||
        _sending ||
        !_repository.supportsPrivateSend) {
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
      if (!_checkAccount()) {
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
      if (mounted && _checkAccount()) {
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
        !_accountChanged &&
        _repository.supportsPrivateSend &&
        _conversation.available &&
        !_sending;
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
