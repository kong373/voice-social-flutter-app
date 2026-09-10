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
  int _conversationEpoch = 0;
  String? _pendingSendRequestId;
  String? _pendingSendContent;
  ImAuthoritativeRefreshBus? _refreshBus;
  ImAuthoritativeRefreshSubscription? _refreshSubscription;
  Future<void>? _refreshFlight;
  Timer? _syncTimer;
  AppDependencies? _dependencies;
  ModalRoute<void>? _route;
  int? _accountId;
  int? _accountGeneration;
  bool _loadStarted = false;
  bool _foreground = true;
  bool _visible = false;
  bool _accountChanged = false;
  final Set<String> _historyMessageIds = <String>{};
  Set<String>? _catchupBoundary;
  String? _catchupCursor;
  String? _readScanCursor;
  bool _historyComplete = false;
  final Set<String> _readScanCursors = {};
  final Set<String> _gapCursors = {};
  bool _refreshAgain = false;

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
      _accountGeneration = _dependencies!.sessionManager.identityGeneration;
      _load();
    } else if (!wasVisible && _visible) {
      _load(showLoading: false);
    } else if (!_visible) {
      _loadRequestId += 1;
      _syncTimer?.cancel();
    }
  }

  @override
  void didUpdateWidget(PrivateChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.targetUserId == widget.conversation.targetUserId)
      return;
    _conversationEpoch++;
    _loadRequestId++;
    _syncTimer?.cancel();
    _refreshFlight = null;
    _refreshAgain = false;
    _conversation = widget.conversation;
    _messages.clear();
    _historyMessageIds.clear();
    _catchupBoundary = null;
    _catchupCursor = null;
    _readScanCursor = null;
    _historyComplete = false;
    _readScanCursors.clear();
    _gapCursors.clear();
    _controller.clear();
    _pendingSendRequestId = null;
    _pendingSendContent = null;
    _sending = false;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visible = _active;
    if (!_visible) _loadRequestId += 1;
    _syncTimer?.cancel();
    if (_visible && _loadStarted) {
      _load(showLoading: false);
    }
  }

  bool _checkAccount() {
    if (!mounted || _accountChanged) return false;
    if (!_dependencies!.environment.isLive ||
        ((_dependencies!.sessionManager.session?.userId ?? 0) == _accountId &&
            _dependencies!.sessionManager.identityGeneration ==
                _accountGeneration)) {
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
      _readScanCursor = null;
      _historyComplete = false;
      _readScanCursors.clear();
      _gapCursors.clear();
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
    if (active != null) {
      if (_repository is PagedPrivateMessageRepository) _refreshAgain = true;
      return active;
    }
    _syncTimer?.cancel();
    final Future<void> operation = _performLoad(showLoading: showLoading);
    _refreshFlight = operation;
    if (_repository is PagedPrivateMessageRepository) _scheduleSync();
    void completed() {
      if (identical(_refreshFlight, operation)) {
        _refreshFlight = null;
        if (mounted && _refreshAgain && _canAutoSync) {
          _refreshAgain = false;
          _load(showLoading: false);
        } else if (mounted && _repository is! PagedPrivateMessageRepository) {
          _scheduleSync();
        }
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
      if (repository is PagedPrivateMessageRepository) {
        await _performPagedLoad(repository, requestId);
        return;
      }
      final Set<String> historyBoundary =
          _catchupBoundary ?? _readRefreshBoundary();
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
        _error =
            _messages.isNotEmpty &&
                (!showLoading || repository is PagedPrivateMessageRepository)
            ? null
            : _messageFor(error);
      });
    }
  }

  Future<void> _performPagedLoad(
    PagedPrivateMessageRepository repository,
    int requestId,
  ) async {
    bool current() =>
        _active &&
        !_accountChanged &&
        requestId == _loadRequestId &&
        (_dependencies!.sessionManager.session?.userId ?? 0) == _accountId;
    // Always start at the head, never at the old receipt cursor. Publish this
    // response before any lower-priority work, under the same visibility lease.
    final newest = await repository.fetchVisiblePrivateMessagePage(
      _conversation,
      isCurrent: current,
    );
    if (!current()) return;
    if (newest.nextCursor != null &&
        _historyMessageIds.isNotEmpty &&
        !newest.messages.any(
          (message) => _historyMessageIds.contains(message.id),
        )) {
      // More than one page arrived since the last head. Keep the original
      // overlap boundary until this gap is filled; old receipt progress is
      // independent and must not be used as an incremental message cursor.
      _catchupBoundary ??= Set.of(_historyMessageIds);
      _catchupCursor = newest.nextCursor;
      _gapCursors.clear();
    }
    _publishPage(newest.messages, followLatest: true);
    if (newest.nextCursor == null) {
      _historyComplete = true;
      _readScanCursor = null;
      _readScanCursors.clear();
      _catchupCursor = null;
      _catchupBoundary = null;
      _gapCursors.clear();
    } else if (_readScanCursor == null) {
      final newestIds = newest.messages.map((message) => message.id).toSet();
      if (!_historyComplete ||
          _messages.any(
            (message) =>
                message.isMine &&
                message.read != true &&
                !newestIds.contains(message.id),
          )) {
        _readScanCursor = newest.nextCursor;
        _readScanCursors.clear();
      }
    }
    // Guarantee bounded progress even when each head takes longer than the
    // polling interval. A due head must not indefinitely starve gap/receipt
    // work. One head + at most one old page per turn, all requests serialized;
    // the queued next turn still starts at the head before any old page.
    if ((_catchupCursor != null || _readScanCursor != null) && current()) {
      final isGap = _catchupCursor != null;
      final cursor = _catchupCursor ?? _readScanCursor!;
      final seen = isGap ? _gapCursors : _readScanCursors;
      final older = await repository.fetchVisiblePrivateMessagePage(
        _conversation,
        isCurrent: current,
        cursor: cursor,
      );
      if (!current()) return;
      if (older.nextCursor != null &&
          (older.nextCursor == cursor || seen.contains(older.nextCursor))) {
        throw StateError('私聊历史分页游标重复或无进展');
      }
      _publishPage(older.messages, followLatest: false);
      seen.add(cursor);
      if (isGap) {
        final overlaps = older.messages.any(
          (message) => _catchupBoundary!.contains(message.id),
        );
        _catchupCursor = overlaps ? null : older.nextCursor;
        if (_catchupCursor == null) {
          _catchupBoundary = null;
          _gapCursors.clear();
        }
      } else {
        _readScanCursor = older.nextCursor;
      }
      if (older.nextCursor == null && !isGap) {
        _historyComplete = true;
        _readScanCursors.clear();
      }
    }
    // A one-page newest response is not proof that older incoming rows have
    // been loaded. Only acknowledge after completing history, while visible.
    if (_historyComplete && _catchupCursor == null && current()) {
      await repository.markVisiblePrivateMessagesRead(
        _conversation,
        isCurrent: current,
      );
    }
  }

  void _publishPage(List<ChatMessage> messages, {required bool followLatest}) {
    _historyMessageIds.addAll(messages.map((message) => message.id));
    if (_conversation.isDraft && messages.isNotEmpty) {
      final identified = messages
          .where((message) => message.conversationId != null)
          .firstOrNull;
      if (identified != null) {
        _conversation = _conversation.withServerIdentity(
          conversationId: identified.conversationId!,
          serverUpdatedAt: messages.last.createdAt,
        );
      }
    }
    final merged = _mergeMessages(messages);
    final previousExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;
    final previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;
    final shouldScroll =
        merged.length > _messages.length &&
        (_messages.isEmpty ||
            !_scrollController.hasClients ||
            _scrollController.position.extentAfter < 80);
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
      _loading = false;
      _error = null;
    });
    if (shouldScroll) {
      _scrollToEnd();
    } else if (!followLatest &&
        previousExtent != null &&
        previousOffset != null) {
      // Prepending old history must not move a reader away from their anchor.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          final position = _scrollController.position;
          _scrollController.jumpTo(
            (previousOffset + position.maxScrollExtent - previousExtent).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        }
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
    final conversationEpoch = _conversationEpoch;
    setState(() => _sending = true);
    try {
      final ChatMessage message = await _repository.sendPrivateMessage(
        conversation: _conversation,
        content: text,
        requestId: requestId,
      );
      if (!_checkAccount() || conversationEpoch != _conversationEpoch) {
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
      if (mounted &&
          _checkAccount() &&
          conversationEpoch == _conversationEpoch) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted && conversationEpoch == _conversationEpoch) {
        setState(() => _sending = false);
      }
    }
  }

  void _mediaSent(ChatMessage message) {
    if (!_checkAccount() || !_active) return;
    if (_conversation.isDraft && message.conversationId != null) {
      _conversation = _conversation.withServerIdentity(
        conversationId: message.conversationId!,
        serverUpdatedAt: message.createdAt,
      );
    }
    _loadRequestId += 1;
    final merged = _mergeMessages([message]);
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
      _loading = false;
      _error = null;
    });
    _scrollToEnd();
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
      final previous = byId[item.id];
      byId[item.id] = item.copyWith(
        read: previous?.read == true ? true : item.read ?? previous?.read,
        readAt: previous?.readAt,
      );
    }
    final order = <String, int>{};
    for (final id in byId.keys) {
      order[id] = order.length;
    }
    final List<ChatMessage> merged = byId.values.toList()
      // List.sort is not stable. Preserve accepted order for equal timestamps
      // so a receipt-only update cannot shuffle existing bubbles.
      ..sort((ChatMessage left, ChatMessage right) {
        final byTime = left.createdAt.compareTo(right.createdAt);
        return byTime != 0
            ? byTime
            : order[left.id]!.compareTo(order[right.id]!);
      });
    return merged;
  }

  Set<String> _readRefreshBoundary() {
    // queryChat paginates by creation ID, not state changes. Walk through the
    // oldest unresolved outgoing row already accepted from history.
    // A send-only receipt must not advance the catch-up boundary and skip
    // unseen peer rows between the previous snapshot and that receipt.
    // The repository still caps each flight and resumes via _catchupCursor.
    final unresolved = _messages.where(
      (item) =>
          item.isMine &&
          item.read != true &&
          _historyMessageIds.contains(item.id),
    );
    if (unresolved.isNotEmpty) return {unresolved.first.id};
    return Set<String>.of(_historyMessageIds);
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
            UserAvatarView(
              avatar: _conversation.avatar,
              userId: _conversation.targetUserId,
              size: 34,
              enabled: _conversation.available && !_accountChanged,
              fallback: RuntimeAvatar(
                seed: _conversation.id ?? 'user-${_conversation.targetUserId}',
                size: 34,
              ),
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
                text: '实时消息暂不可用，已保存的消息记录仍可查看。',
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
            child: LayoutBuilder(
              builder: (context, space) => Column(
                children: [
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
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                22,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (BuildContext context, int index) {
                                return _ChatBubble(
                                  message: _messages[index],
                                  mediaVisible: _active && !_accountChanged,
                                );
                              },
                            ),
                          ),
                  ),
                  if (_repository is MediaPrivateMessageRepository &&
                      !_accountChanged)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (space.maxHeight * 0.6).clamp(0.0, 240.0),
                      ),
                      child: SingleChildScrollView(
                        child: PrivateMediaComposer(
                          host: _dependencies!.privateMediaHost,
                          repository:
                              _repository as MediaPrivateMessageRepository,
                          conversation: _conversation,
                          visible: _active && _conversation.available,
                          onSent: _mediaSent,
                        ),
                      ),
                    ),
                ],
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
                    if (_repository is! MediaPrivateMessageRepository)
                      const IconButton(
                        tooltip: '当前环境未接入媒体发送',
                        onPressed: null,
                        icon: Icon(Icons.mic_none_rounded),
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
  const _ChatBubble({required this.message, this.mediaVisible = true});

  final ChatMessage message;
  final bool mediaVisible;

  @override
  Widget build(BuildContext context) {
    final DateTime now = AppDependencyScope.of(context).currentTime();
    final bubble = Container(
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
          if (message.messageType != ChatMessageType.text)
            PrivateMediaBubble(
              key: ValueKey(message.id),
              message: message,
              host: AppDependencyScope.of(context).privateMediaHost,
              visible: mediaVisible,
            )
          else
            Text(
              message.content,
              style: TextStyle(
                color: message.isMine ? Colors.white : SocialColors.textPrimary,
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (message.isMine &&
                  (message.status == ChatMessageStatus.sent ||
                      message.status ==
                          ChatMessageStatus.storedPendingDelivery)) ...<Widget>[
                Text(
                  message.receiptLabel,
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
    );
    final avatar = message.senderAvatar;
    final image = Padding(
      padding: const EdgeInsets.only(left: 5, right: 5, top: 2),
      child: UserAvatarView(
        avatar: avatar,
        userId: message.senderUserId,
        size: 32,
        enabled: mediaVisible,
        fallback: const SizedBox.shrink(),
      ),
    );
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: avatar == null
          ? bubble
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isMine) image,
                Flexible(child: bubble),
                if (message.isMine) image,
              ],
            ),
    );
  }
}
