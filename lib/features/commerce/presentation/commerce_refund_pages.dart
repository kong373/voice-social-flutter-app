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
    if (_repository.refundScope == RefundScope.order &&
        !_repository.supportsRefundHistory) {
      return;
    }
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
    if (_repository.refundScope == RefundScope.order &&
        !_repository.supportsRefundHistory) {
      return _CommerceScaffold(
        appBar: AppBar(title: const Text('订单退款')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const _CommerceInfoBanner(
              text: '当前退款接口严格绑定充值订单，不能从账户退款表单发起。请先选择一笔充值订单。',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushReplacement<void, void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => const OrdersPage(),
                    ),
                  ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('选择充值订单'),
            ),
          ],
        ),
      );
    }
    return _CommerceScaffold(
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
                  _repository.refundScope == RefundScope.order
                  ? const OrdersPage()
                  : RefundApplicationPage(account: widget.account),
            ),
          );
          if (mounted) {
            await _load();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _repository.refundScope == RefundScope.order ? '选择充值订单' : '申请退款',
        ),
      ),
      body: _applications == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: <Widget>[
                _CommerceInfoBanner(
                  text: _repository.refundScope == RefundScope.order
                      ? '退款申请严格绑定具体充值订单；这里展示当前账号的完整退款历史，新申请请先选择充值订单。'
                      : '当前后端是账户级历史退款流程，不是按单个充值订单发起的标准退款。页面不会把两种业务混为一谈。',
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
                    child: Center(child: Text('暂无退款申请记录')),
                  )
                else
                  for (final RefundApplication application in _applications!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _CommercePanel(
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => RefundResultPage(
                              application: application,
                              repository: _repository,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: <Widget>[
                            _CommerceAssetOrb(
                              icon: _refundIcon(application.status),
                              size: 42,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '¥${application.amount.toStringAsFixed(2)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ),
                                      _CommercePill(
                                        label: application.statusText,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '申请编号 ${application.id}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    _formatDateTime(application.createdAt),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class RefundApplicationPage extends StatefulWidget {
  const RefundApplicationPage({
    this.account,
    this.order,
    this.repository,
    super.key,
  }) : assert((account == null) != (order == null));

  final String? account;
  final PaymentOrder? order;
  @visibleForTesting
  final CommerceRepository? repository;

  bool get isOrderScope => order != null;

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

  CommerceRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).commerceRepository;

  String get _subject => widget.order?.orderNo ?? widget.account ?? '';

  double get _requestedAmount =>
      widget.order?.amount ??
      (double.tryParse(_amountController.text.trim()) ?? 0);

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
      final RefundEligibility eligibility = await _repository
          .checkRefundEligibility(_subject);
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
    final double amount = _requestedAmount;
    // Lock before opening the confirmation dialog. This makes the write
    // boundary single-flight even when a tap/semantics event is delivered
    // twice before the dialog finishes.
    setState(() => _submitting = true);
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('确认提交退款申请？'),
          content: Text(
            '${widget.isOrderScope ? '充值订单' : '申请账号'}：$_subject\n申请金额：¥${amount.toStringAsFixed(2)}\n提交后将进入人工审核。',
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
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
      }
      rethrow;
    }
    if (confirmed != true || !mounted) {
      if (mounted) {
        setState(() => _submitting = false);
      }
      return;
    }
    try {
      final RefundApplication application = await _repository.submitRefund(
        RefundRequest(
          account: _subject,
          realName: widget.isOrderScope ? '' : _nameController.text.trim(),
          age: widget.isOrderScope ? 0 : int.parse(_ageController.text.trim()),
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
            builder: (BuildContext context) => RefundResultPage(
              application: application,
              repository: _repository,
            ),
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

  Widget _buildOrderForm() {
    final PaymentOrder order = widget.order!;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _CommerceInfoBanner(text: _eligibility!.message),
          const SizedBox(height: 14),
          _CommercePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _CommerceSectionTitle(title: '充值订单退款'),
                const SizedBox(height: 12),
                _CommerceDetail(label: '订单号', value: order.orderNo),
                _CommerceDetail(
                  label: '退款金额',
                  value: '¥${order.amount.toStringAsFixed(2)}',
                ),
                _CommerceDetail(label: '支付渠道', value: order.channelName),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CommercePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _CommerceSectionTitle(title: '退款原因'),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _CommerceInfoBanner(
            text: '订单退款由服务端校验订单状态并处理。客户端不会提交姓名、年龄、收款账户或监护人资料。',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _eligibility!.allowed && !_submitting ? _submit : null,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('提交订单退款申请'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('退款申请')),
      body: _eligibility == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _check)
          : widget.isOrderScope
          ? _buildOrderForm()
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _CommerceInfoBanner(text: _eligibility!.message),
                  const SizedBox(height: 14),
                  _CommercePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _CommerceSectionTitle(title: '退款资料'),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: _subject,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: '申请账号'),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '账号使用人姓名',
                          ),
                          validator: (String? value) =>
                              value == null || value.trim().isEmpty
                              ? '请输入姓名'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: TextFormField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: '年龄',
                                ),
                                validator: (String? value) {
                                  final int? age = int.tryParse(value ?? '');
                                  return age == null || age < 1 || age > 120
                                      ? '请输入有效年龄'
                                      : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: '申请退款金额',
                                ),
                                validator: (String? value) {
                                  final double? amount = double.tryParse(
                                    value ?? '',
                                  );
                                  return amount == null || amount <= 0
                                      ? '请输入有效金额'
                                      : null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CommercePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _CommerceSectionTitle(title: '退款说明'),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CommercePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _CommerceSectionTitle(title: '收款与监护信息'),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _receivingAccountController,
                          decoration: const InputDecoration(
                            labelText: '退款收款账号',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: '监护人手机号（可选）',
                          ),
                        ),
                      ],
                    ),
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
  const RefundResultPage({
    required this.application,
    this.repository,
    super.key,
  });

  final RefundApplication application;
  @visibleForTesting
  final CommerceRepository? repository;

  @override
  State<RefundResultPage> createState() => _RefundResultPageState();
}

class _RefundResultPageState extends State<RefundResultPage> {
  late RefundApplication _application;
  bool _refreshing = false;
  String? _refreshError;

  CommerceRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).commerceRepository;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    // A submitted/approved result is only a snapshot supplied by the
    // previous screen. Resolve it against the authenticated backend as soon
    // as this page is mounted so a stale snapshot cannot look terminal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _refundStatusNeedsRefresh(_application.status)) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final RefundApplication updated = await _repository.fetchRefundResult(
        _application.id,
        expectedOrderNo: _application.account,
      );
      if (mounted) {
        setState(() {
          _application = updated;
          _refreshError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        final String message = _messageFor(error);
        setState(() => _refreshError = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _resubmit() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final RefundApplication updated = await _repository.resubmitRefund(
        _application.id,
        expectedOrderNo: _application.account,
      );
      if (mounted) {
        setState(() {
          _application = updated;
          _refreshError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        final String message = _messageFor(error);
        setState(() => _refreshError = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOrderScope = _repository.refundScope == RefundScope.order;
    return _CommerceScaffold(
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
            description: _descriptionForApplication,
          ),
          if (_refreshError != null) ...<Widget>[
            const SizedBox(height: 10),
            _CommerceInfoBanner(
              text: '状态查询失败：$_refreshError。当前状态未改变，可点击右上角刷新重试。',
            ),
          ],
          const SizedBox(height: 14),
          _CommercePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                _CommerceDetail(label: '申请编号', value: _application.id),
                _CommerceDetail(
                  label: isOrderScope ? '充值订单号' : '申请账号',
                  value: _application.account,
                ),
                _CommerceDetail(
                  label: '申请金额',
                  value: '¥${_application.amount.toStringAsFixed(2)}',
                ),
                _CommerceDetail(
                  label: '提交时间',
                  value: _formatDateTime(_application.createdAt),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_application.status == RefundStatus.rejected)
            FilledButton(
              onPressed: _refreshing ? null : _resubmit,
              child: const Text('重新提交申请'),
            ),
        ],
      ),
    );
  }

  String get _descriptionForApplication {
    return switch (_application.status) {
      RefundStatus.reviewing ||
      RefundStatus.resubmitted => '退款申请正在服务端处理中，审核和结果以权威退款接口为准。客户端不会自行入账。',
      RefundStatus.approved => '服务端已审批通过，退款是否最终完成仍以服务端后续状态为准。客户端不会自行入账。',
      RefundStatus.completed => '服务端已确认退款完成。客户端不会自行修改余额，余额以服务端账本为准。',
      RefundStatus.rejected =>
        _application.rejectedReason.isEmpty
            ? '服务端已拒绝本次退款申请，可修正资料后重新提交。'
            : '服务端拒绝原因：${_application.rejectedReason}。可修正资料后重新提交。',
      RefundStatus.unavailable => '服务端当前无法提供可继续处理的退款结果，请稍后刷新查询。',
    };
  }
}

bool _refundStatusNeedsRefresh(RefundStatus status) =>
    status == RefundStatus.reviewing ||
    status == RefundStatus.resubmitted ||
    status == RefundStatus.approved;
