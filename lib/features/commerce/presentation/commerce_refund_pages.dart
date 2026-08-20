part of 'commerce_pages.dart';

class RefundListPage extends StatefulWidget {
  const RefundListPage({required this.account, super.key});

  final String account;

  @override
  State<RefundListPage> createState() => _RefundListPageState();
}

class _RefundListPageState extends State<RefundListPage> {
  List<RefundApplication>? _applications;
  String? _error;

  CommerceRepository get _repository =>
      AppDependencyScope.of(context).commerceRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_applications == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final List<RefundApplication> applications = await _repository
          .fetchRefundApplications(widget.account);
      if (mounted) {
        setState(() {
          _applications = applications;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('退款申请列表'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _applications == null ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  RefundApplicationPage(account: widget.account),
            ),
          );
          if (mounted) {
            await _load();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('申请退款'),
      ),
      body: _applications == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: <Widget>[
                const _CommerceInfoBanner(
                  text: '当前后端是账户级历史退款流程，不是按单个充值订单发起的标准退款。页面不会把两种业务混为一谈。',
                ),
                if (!_repository.supportsRefundHistory) ...<Widget>[
                  const SizedBox(height: 10),
                  const _CommerceInfoBanner(
                    text: '当前接口只能查询正在处理的最新申请，不能提供完整历史列表。',
                  ),
                ],
                const SizedBox(height: 14),
                if (_applications!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('暂无正在处理的退款申请')),
                  )
                else
                  for (final RefundApplication application in _applications!)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${application.statusText} · ¥${application.amount.toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          '申请编号 ${application.id}\n${_formatDateTime(application.createdAt)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                RefundResultPage(application: application),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class RefundApplicationPage extends StatefulWidget {
  const RefundApplicationPage({required this.account, super.key});

  final String account;

  @override
  State<RefundApplicationPage> createState() => _RefundApplicationPageState();
}

class _RefundApplicationPageState extends State<RefundApplicationPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _receivingAccountController =
      TextEditingController();
  final TextEditingController _receivingNameController =
      TextEditingController();
  final TextEditingController _guardianNameController = TextEditingController();
  final TextEditingController _guardianPhoneController =
      TextEditingController();
  RefundEligibility? _eligibility;
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eligibility == null && _error == null) {
      _check();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _amountController.dispose();
    _reasonController.dispose();
    _receivingAccountController.dispose();
    _receivingNameController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final RefundEligibility eligibility = await AppDependencyScope.of(
        context,
      ).commerceRepository.checkRefundEligibility(widget.account);
      if (mounted) {
        setState(() {
          _eligibility = eligibility;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() ||
        _submitting ||
        _eligibility?.allowed != true) {
      return;
    }
    final double amount = double.parse(_amountController.text.trim());
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认提交退款申请？'),
        content: Text(
          '申请账号：${widget.account}\n申请金额：¥${amount.toStringAsFixed(2)}\n提交后将进入人工审核。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final RefundApplication application = await AppDependencyScope.of(context)
          .commerceRepository
          .submitRefund(
            RefundRequest(
              account: widget.account,
              realName: _nameController.text.trim(),
              age: int.parse(_ageController.text.trim()),
              amount: amount,
              reason: _reasonController.text.trim(),
              receivingAccount: _receivingAccountController.text.trim(),
              receivingName: _receivingNameController.text.trim(),
              guardianName: _guardianNameController.text.trim(),
              guardianPhone: _guardianPhoneController.text.trim(),
            ),
          );
      if (mounted) {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                RefundResultPage(application: application),
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
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('退款申请')),
      body: _eligibility == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _check)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _CommerceInfoBanner(text: _eligibility!.message),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: widget.account,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: '申请账号'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '账号使用人姓名'),
                    validator: (String? value) =>
                        value == null || value.trim().isEmpty ? '请输入姓名' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(labelText: '年龄'),
                    validator: (String? value) {
                      final int? age = int.tryParse(value ?? '');
                      return age == null || age < 1 || age > 120
                          ? '请输入有效年龄'
                          : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '申请退款金额'),
                    validator: (String? value) {
                      final double? amount = double.tryParse(value ?? '');
                      return amount == null || amount <= 0 ? '请输入有效金额' : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _reasonController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: '退款原因'),
                    validator: (String? value) =>
                        value == null || value.trim().length < 5
                        ? '退款原因至少填写 5 个字'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _receivingAccountController,
                    decoration: const InputDecoration(labelText: '退款收款账号'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _receivingNameController,
                    decoration: const InputDecoration(labelText: '收款人姓名'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _guardianNameController,
                    decoration: const InputDecoration(
                      labelText: '监护人姓名（未成年人场景）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _guardianPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '监护人手机号（可选）'),
                  ),
                  const SizedBox(height: 12),
                  const _CommerceInfoBanner(
                    text: '支付凭证和监护关系图片需要对象存储适配器，本阶段不会上传占位图片或伪造凭证。',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _eligibility!.allowed && !_submitting
                        ? _submit
                        : null,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('提交退款申请'),
                  ),
                ],
              ),
            ),
    );
  }
}

class RefundResultPage extends StatefulWidget {
  const RefundResultPage({required this.application, super.key});

  final RefundApplication application;

  @override
  State<RefundResultPage> createState() => _RefundResultPageState();
}

class _RefundResultPageState extends State<RefundResultPage> {
  late RefundApplication _application;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final RefundApplication updated = await AppDependencyScope.of(
        context,
      ).commerceRepository.fetchRefundResult(_application.id);
      if (mounted) {
        setState(() => _application = updated);
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

  Future<void> _resubmit() async {
    setState(() => _refreshing = true);
    try {
      final RefundApplication updated = await AppDependencyScope.of(
        context,
      ).commerceRepository.resubmitRefund(_application.id);
      if (mounted) {
        setState(() => _application = updated);
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
        title: const Text('退款申请结果'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _CommerceStatusCard(
            icon: _refundIcon(_application.status),
            title: _application.statusText,
            description: _application.rejectedReason.isEmpty
                ? '平台将根据提交资料进行人工审核。'
                : _application.rejectedReason,
          ),
          const SizedBox(height: 18),
          _CommerceDetail(label: '申请编号', value: _application.id),
          _CommerceDetail(label: '申请账号', value: _application.account),
          _CommerceDetail(
            label: '申请金额',
            value: '¥${_application.amount.toStringAsFixed(2)}',
          ),
          _CommerceDetail(
            label: '提交时间',
            value: _formatDateTime(_application.createdAt),
          ),
          if (_application.status == RefundStatus.rejected)
            FilledButton(
              onPressed: _refreshing ? null : _resubmit,
              child: const Text('重新提交申请'),
            ),
        ],
      ),
    );
  }
}
