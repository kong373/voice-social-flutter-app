part of 'social_pages.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({
    required this.targetType,
    required this.targetId,
    required this.targetName,
    super.key,
  });

  final ReportTargetType targetType;
  final String targetId;
  final String targetName;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  int _reasonCode = 1;
  bool _alsoBlock = false;
  bool _busy = false;

  bool get _canSubmitReport {
    if (widget.targetType != ReportTargetType.room) {
      return true;
    }
    if (!AppDependencyScope.of(context).environment.isLive) {
      return true;
    }
    return isCanonicalReportRoomId(widget.targetId);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmitReport || !_formKey.currentState!.validate() || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final String receipt = await AppDependencyScope.of(context)
          .socialRepository
          .submitReport(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reasonCode: _reasonCode,
            description: _descriptionController.text,
            alsoBlock: _alsoBlock,
          );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('举报已提交'),
          content: Text('回执编号：$receipt'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
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

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: Text('举报${widget.targetName}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
          children: <Widget>[
            _OxygenPanel(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: <Widget>[
                  const CircleAvatar(
                    backgroundColor: Color(0xFFFFE9EF),
                    child: Icon(
                      Icons.report_gmailerrorred_rounded,
                      color: SocialColors.error,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '举报对象：${widget.targetName}',
                          style: const TextStyle(
                            color: SocialColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '所有提交都会进入审核，请描述真实情况',
                          style: TextStyle(
                            color: SocialColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!_canSubmitReport) ...<Widget>[
              const SizedBox(height: 12),
              const _InfoBanner(
                text: '当前第一方举报接口只接受数字房间 ID；该房间使用 UUID/public_id，暂不能提交举报。',
              ),
            ],
            const SizedBox(height: 12),
            _OxygenPanel(
              child: Column(
                children: <Widget>[
                  DropdownButtonFormField<int>(
                    initialValue: _reasonCode,
                    decoration: const InputDecoration(labelText: '举报原因'),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(value: 1, child: Text('泄露隐私')),
                      DropdownMenuItem<int>(value: 2, child: Text('人身攻击')),
                      DropdownMenuItem<int>(value: 3, child: Text('淫秽色情')),
                      DropdownMenuItem<int>(value: 4, child: Text('垃圾广告')),
                      DropdownMenuItem<int>(value: 5, child: Text('敏感信息')),
                    ],
                    onChanged: (int? value) {
                      if (value != null) {
                        setState(() => _reasonCode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: '补充说明'),
                    validator: (String? value) =>
                        value == null || value.trim().isEmpty
                        ? '请填写举报说明'
                        : null,
                  ),
                  const _InfoBanner(text: '图片凭证上传需要对象存储适配器。本阶段先提交可审核的文字证据。'),
                  if (widget.targetType == ReportTargetType.user)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _alsoBlock,
                      onChanged: (bool? value) =>
                          setState(() => _alsoBlock = value ?? false),
                      title: const Text('同时加入黑名单'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || !_canSubmitReport ? null : _submit,
              child: Text(_busy ? '提交中…' : '提交举报'),
            ),
          ],
        ),
      ),
    );
  }
}

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  SupportChannel? _channel;
  bool _busy = false;
  bool _initialized = false;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SupportChannel value = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchCustomerService();
      if (mounted) setState(() => _channel = value);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_contentController.text.trim().isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final SupportTicket ticket = await AppDependencyScope.of(context)
          .socialRepository
          .submitFeedback(
            subject: _subjectController.text,
            content: _contentController.text,
          );
      if (mounted) {
        _subjectController.clear();
        _contentController.clear();
        FocusScope.of(context).unfocus();
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                SupportTicketPage(initialTicket: ticket),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('帮助与客服'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    const SupportTicketHistoryPage(),
              ),
            ),
            child: const Text('我的反馈'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: <Widget>[
                _OxygenPanel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: <Color>[
                              Color(0xFFB895FF),
                              Color(0xFF7E6BEF),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.support_agent_rounded,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _channel!.name,
                              style: const TextStyle(
                                color: SocialColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _channel!.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SocialColors.textSecondary,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: SocialColors.textTertiary,
                      ),
                    ],
                  ),
                ),
                if (!_channel!.liveConversationAvailable) ...<Widget>[
                  const SizedBox(height: 12),
                  const _InfoBanner(text: '请提交问题描述，之后可在“我的反馈”查看处理状态。'),
                ],
                const SizedBox(height: 16),
                const _OxygenSectionLabel(title: '提交问题'),
                const SizedBox(height: 8),
                _OxygenPanel(
                  child: Column(
                    children: <Widget>[
                      TextField(
                        controller: _subjectController,
                        decoration: const InputDecoration(labelText: '问题主题'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _contentController,
                        minLines: 5,
                        maxLines: 8,
                        maxLength: 200,
                        decoration: const InputDecoration(labelText: '问题描述'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '提交中…' : '提交反馈'),
                ),
              ],
            ),
    );
  }
}

class SupportTicketHistoryPage extends StatefulWidget {
  const SupportTicketHistoryPage({super.key});

  @override
  State<SupportTicketHistoryPage> createState() =>
      _SupportTicketHistoryPageState();
}

class _SupportTicketHistoryPageState extends State<SupportTicketHistoryPage> {
  final List<SupportTicket> _tickets = <SupportTicket>[];
  bool _initialized = false;
  bool _loading = false;
  bool _hasMore = false;
  bool _retryReset = true;
  bool _refreshPending = false;
  int _page = 0;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load(reset: true);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) {
      if (reset) _refreshPending = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _retryReset = reset;
    });
    try {
      final SocialPage<SupportTicket> result =
          await AppDependencyScope.of(context).socialRepository
              .fetchSupportTickets(page: reset ? 1 : _page + 1, pageSize: 20);
      if (!mounted) return;
      setState(() {
        if (reset) _tickets.clear();
        // A new ticket can shift offset pages while the user is browsing.
        final Set<String> ids = _tickets
            .map((SupportTicket ticket) => ticket.id)
            .toSet();
        _tickets.addAll(
          result.items.where((SupportTicket ticket) => ids.add(ticket.id)),
        );
        _page = result.page;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted && _refreshPending) {
        _refreshPending = false;
        await _load(reset: true);
      }
    }
  }

  Future<void> _open(SupportTicket ticket) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SupportTicketPage(initialTicket: ticket),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('我的反馈'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新反馈列表',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _tickets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _tickets.isEmpty
          ? _ErrorState(message: _error!, onRetry: () => _load(reset: true))
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                children: <Widget>[
                  if (_tickets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('还没有提交过反馈')),
                    ),
                  for (final SupportTicket ticket in _tickets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OxygenPanel(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          key: ValueKey<String>('support-ticket-${ticket.id}'),
                          title: Text(
                            ticket.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                ticket.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ticket.statusText,
                                style: const TextStyle(
                                  color: SocialColors.primary,
                                ),
                              ),
                              Text(
                                _formatDateTime(ticket.createdAt),
                                style: const TextStyle(
                                  color: SocialColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(ticket),
                        ),
                      ),
                    ),
                  if (_error != null) ...<Widget>[
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => _load(reset: _retryReset),
                      child: const Text('重试'),
                    ),
                  ] else if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_hasMore)
                    TextButton(
                      onPressed: () => _load(reset: false),
                      child: const Text('加载更多'),
                    )
                  else if (_tickets.isNotEmpty)
                    const Center(child: Text('已显示全部反馈')),
                ],
              ),
            ),
    );
  }
}

class SupportTicketPage extends StatefulWidget {
  const SupportTicketPage({required this.initialTicket, super.key});

  final SupportTicket initialTicket;

  @override
  State<SupportTicketPage> createState() => _SupportTicketPageState();
}

class _SupportTicketPageState extends State<SupportTicketPage> {
  late SupportTicket _ticket;
  bool _refreshing = false;
  bool _initialized = false;
  bool _detailLoaded = false;
  bool _sending = false;
  final TextEditingController _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!_ticket.progressAvailable || _refreshing || _sending) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final SupportTicket value = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchSupportTicket(_ticket.id);
      if (mounted) {
        setState(() {
          _ticket = value;
          _detailLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _sendReply() async {
    final String message = _replyController.text.trim();
    if (!_detailLoaded ||
        !_ticket.canReply ||
        _sending ||
        _refreshing ||
        message.isEmpty ||
        message.length > 1000)
      return;
    bool refreshAfterConflict = false;
    setState(() => _sending = true);
    try {
      final SupportTicket ticket = await AppDependencyScope.of(context)
          .socialRepository
          .replyToSupportTicket(ticketId: _ticket.id, message: message);
      if (!mounted) return;
      setState(() => _ticket = ticket);
      _replyController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('补充内容已提交')));
    } catch (error) {
      refreshAfterConflict =
          error is ApiException &&
          (error.httpStatus == 409 || error.kind == ApiFailureKind.conflict);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (mounted && refreshAfterConflict) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('工单详情与处理进度'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新工单进度',
            onPressed: _ticket.progressAvailable && !_refreshing && !_sending
                ? _refresh
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: <Widget>[
          _OxygenPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFE9E4FF),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: SocialColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _ticket.statusText,
                        style: const TextStyle(
                          color: SocialColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _ticket.progressAvailable
                            ? '可刷新查看当前处理状态。'
                            : '当前反馈接口只确认已提交，不提供处理进度查询。',
                        style: const TextStyle(
                          color: SocialColors.textSecondary,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _OxygenPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _OxygenSectionLabel(title: '工单信息'),
                const SizedBox(height: 14),
                _Detail(label: '工单编号', value: _ticket.id),
                _Detail(label: '主题', value: _ticket.subject),
                _Detail(label: '内容', value: _ticket.content),
                _Detail(
                  label: '提交时间',
                  value: _formatDateTime(_ticket.createdAt),
                ),
              ],
            ),
          ),
          if (_ticket.events.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _OxygenPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _OxygenSectionLabel(title: '处理记录'),
                  for (final SupportTicketEvent event in _ticket.events)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            event.actorLabel,
                            style: const TextStyle(
                              color: SocialColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            event.message,
                            style: const TextStyle(
                              color: SocialColors.textPrimary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(event.createdAt),
                            style: const TextStyle(
                              color: SocialColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_detailLoaded && _ticket.canReply) ...<Widget>[
            const SizedBox(height: 14),
            _OxygenPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _OxygenSectionLabel(title: '补充反馈'),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey<String>('support-reply-input'),
                    controller: _replyController,
                    enabled: !_sending,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '补充说明',
                      hintText: '请填写需要补充的信息',
                      counterText:
                          '${_replyController.text.trim().length}/1000',
                      errorText: _replyController.text.trim().length > 1000
                          ? '补充说明超过1000字符，请缩短内容'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey<String>('support-reply-submit'),
                    onPressed:
                        !_sending &&
                            !_refreshing &&
                            _replyController.text.trim().isNotEmpty &&
                            _replyController.text.trim().length <= 1000
                        ? _sendReply
                        : null,
                    child: Text(_sending ? '提交中…' : '提交补充'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
