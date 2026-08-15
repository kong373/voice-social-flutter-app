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
  bool _loading = true;
  bool _sending = false;
  String? _error;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _messages.isEmpty) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<ChatMessage> value =
          await _repository.fetchPrivateMessages(widget.conversation);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(value);
        _loading = false;
      });
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
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
    setState(() => _sending = true);
    try {
      final ChatMessage message = await _repository.sendPrivateMessage(
        conversation: widget.conversation,
        content: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(message);
        _controller.clear();
      });
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PublicProfilePage(userId: widget.conversation.targetUserId),
      ),
    );
  }

  void _report() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReportPage(
          targetType: ReportTargetType.user,
          targetId: '${widget.conversation.targetUserId}',
          targetName: widget.conversation.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend = _repository.supportsPrivateSend &&
        widget.conversation.available &&
        !_sending;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.conversation.title),
            Text(
              _repository.supportsPrivateSend ? '私聊会话' : '只读历史',
              style: Theme.of(context).textTheme.bodySmall,
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
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'profile',
                child: Text('查看公开主页'),
              ),
              PopupMenuItem<String>(
                value: 'report',
                child: Text('举报用户'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_repository.supportsPrivateSend)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _MessageInfoCard(
                icon: Icons.lock_outline_rounded,
                text: '腾讯 IM 尚未接入，当前只展示后端已落库的历史内容，不伪造实时收发。',
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
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  10 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Row(
                  children: <Widget>[
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
                          hintText: canSend
                              ? '输入消息…'
                              : '腾讯 IM 接入后开放发送',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: '发送消息',
                      onPressed: canSend ? _send : null,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
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
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 286),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMine
              ? AppColors.primary.withValues(alpha: 0.82)
              : AppColors.surfaceHigh,
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
            Text(message.content),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatMessageTime(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
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
