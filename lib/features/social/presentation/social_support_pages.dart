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

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) {
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
    return Scaffold(
      appBar: AppBar(title: Text('举报${widget.targetName}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
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
                  value == null || value.trim().isEmpty ? '请填写举报说明' : null,
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
            FilledButton(
              onPressed: _busy ? null : _submit,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_channel == null) {
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
    final SupportChannel value = await AppDependencyScope.of(
      context,
    ).socialRepository.fetchCustomerService();
    if (mounted) {
      setState(() => _channel = value);
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
    return Scaffold(
      appBar: AppBar(title: const Text('帮助与客服')),
      body: _channel == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _StatusCard(
                  icon: Icons.support_agent_outlined,
                  title: _channel!.name,
                  description: _channel!.description,
                ),
                if (!_channel!.liveConversationAvailable) ...<Widget>[
                  const SizedBox(height: 12),
                  const _InfoBanner(text: '腾讯 IM 接入前不开放伪即时客服会话。'),
                ],
                const SizedBox(height: 18),
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
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '提交中…' : '提交反馈'),
                ),
              ],
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

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
  }

  Future<void> _refresh() async {
    if (!_ticket.progressAvailable || _refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final SupportTicket value = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchSupportTicket(_ticket.id);
      if (mounted) {
        setState(() => _ticket = value);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工单详情与处理进度'),
        actions: <Widget>[
          IconButton(
            onPressed: _ticket.progressAvailable ? _refresh : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StatusCard(
            icon: Icons.receipt_long_outlined,
            title: _ticket.statusText,
            description: _ticket.progressAvailable
                ? '可刷新查看当前处理状态。'
                : '当前反馈接口只确认已提交，不提供处理进度查询。',
          ),
          const SizedBox(height: 18),
          _Detail(label: '工单编号', value: _ticket.id),
          _Detail(label: '主题', value: _ticket.subject),
          _Detail(label: '内容', value: _ticket.content),
          _Detail(label: '提交时间', value: _formatDateTime(_ticket.createdAt)),
        ],
      ),
    );
  }
}
