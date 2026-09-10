part of 'commerce_pages.dart';

class PayoutAccountBindingPage extends StatefulWidget {
  const PayoutAccountBindingPage({required this.repository, super.key});
  final CommerceRepository repository;
  @override
  State<PayoutAccountBindingPage> createState() =>
      _PayoutAccountBindingPageState();
}

class _PayoutAccountBindingPageState extends State<PayoutAccountBindingPage> {
  final _form = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _holder = TextEditingController();
  final _bank = TextEditingController();
  late final PayoutBindingSession _session;
  String _type = 'ALIPAY';
  bool _busy = false;
  bool _identityLost = false;
  bool _closed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _session = PayoutBindingSession(widget.repository);
    widget.repository.withdrawalIdentityChanges?.addListener(_identityChanged);
  }

  void _identityChanged() {
    if (_session.identity == widget.repository.withdrawalIdentity) return;
    _session.dispose();
    _account.clear();
    _holder.clear();
    _bank.clear();
    if (mounted)
      setState(() {
        _identityLost = true;
        _busy = false;
        _error = '登录身份已变更，请关闭后重新进入';
      });
  }

  void _close() {
    _closed = true;
    _session.dispose();
    _account.clear();
    _holder.clear();
    _bank.clear();
  }

  @override
  void dispose() {
    widget.repository.withdrawalIdentityChanges?.removeListener(
      _identityChanged,
    );
    _close();
    _account.dispose();
    _holder.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_closed ||
        _busy ||
        _identityLost ||
        (!_session.hasPending && !(_form.currentState?.validate() ?? false)))
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.submit(
        PayoutAccountInput(
          accountType: _type,
          accountNumber: _account.text.trim(),
          holderName: _holder.text.trim(),
          bankName: _type == 'BANK_CARD' ? _bank.text.trim() : '',
        ),
      );
      if (!mounted ||
          _closed ||
          _session.identity != widget.repository.withdrawalIdentity)
        return;
      _account.clear();
      _holder.clear();
      _bank.clear();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted ||
          _closed ||
          _session.identity != widget.repository.withdrawalIdentity)
        return;
      setState(() {
        _error = _session.hasPending
            ? '结果尚未确认，请重试原绑定；原资料已锁定。关闭此页会清除本次恢复资料。'
            : switch (error is ApiException ? error.code : null) {
                40379 => '持有人姓名与本人实名认证资料不一致，请核对',
                40924 => '请补充实名认证资料后绑定收款账户',
                40371 => '请先完成本人实名认证',
                40375 => '当前身份没有收益收款权限',
                40079 => '收款资料格式有误，请核对',
                50379 => '收款账户绑定暂不可用',
                40903 => '请求内容冲突，请关闭后重新进入',
                _ => '暂时无法绑定，请核对登录状态及填写资料后重试',
              };
      });
    } finally {
      if (mounted && !_closed && !_identityLost) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _session.hasPending || _identityLost;
    return PopScope<bool>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('绑定本人收款账户')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('仅可绑定实名认证本人账户。填写后即可使用；资料由用户填写，不代表银行或支付宝已核验。提现仍由财务人工打款。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              ),
            if (!_identityLost)
              Form(
                key: _form,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: '收款类型'),
                      items: const [
                        DropdownMenuItem(value: 'ALIPAY', child: Text('支付宝')),
                        DropdownMenuItem(
                          value: 'BANK_CARD',
                          child: Text('银行卡'),
                        ),
                      ],
                      onChanged: locked
                          ? null
                          : (value) {
                              if (value != null)
                                setState(() {
                                  _type = value;
                                  _account.clear();
                                  _bank.clear();
                                });
                            },
                    ),
                    TextFormField(
                      controller: _holder,
                      enabled: !locked,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '本人真实姓名'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请填写本人真实姓名'
                          : null,
                    ),
                    TextFormField(
                      controller: _account,
                      enabled: !locked,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: _type == 'BANK_CARD'
                          ? TextInputType.number
                          : TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: _type == 'BANK_CARD'
                            ? '银行卡号'
                            : '支付宝账号（手机号或邮箱）',
                      ),
                      validator: (value) =>
                          PayoutAccountInput(
                            accountType: _type,
                            accountNumber: value?.trim() ?? '',
                            holderName: '姓名',
                            bankName: _type == 'BANK_CARD' ? '银行' : '',
                          ).valid
                          ? null
                          : '请填写有效收款账号',
                    ),
                    if (_type == 'BANK_CARD')
                      TextFormField(
                        controller: _bank,
                        enabled: !locked,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(labelText: '开户银行'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请填写开户银行'
                            : null,
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? '正在确认…'
                            : _session.hasPending
                            ? '重试原绑定'
                            : '确认绑定',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EarningsPage extends StatefulWidget {
  const EarningsPage({this.repository, super.key});
  @visibleForTesting
  final CommerceRepository? repository;

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage>
    with CommerceIdentityFence<EarningsPage> {
  @override
  CommerceRepository get commerceIdentityRepository =>
      widget.repository ?? AppDependencyScope.of(context).commerceRepository;
  @override
  void clearCommerceIdentity() {
    _wallet = null;
    _income = null;
    _error = '请登录后查看收益';
  }

  @override
  Future<void> reloadCommerceIdentity() => _load();

  WalletSummary? _wallet;
  List<LedgerEntry>? _income;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wallet == null && _income == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _wallet = null;
      _income = null;
      _error = null;
    });
    final ticket = beginCommerceRead();
    try {
      final CommerceRepository repository = commerceIdentityRepository;
      final List<Object> values = await Future.wait<Object>(<Future<Object>>[
        repository.fetchWalletSummary(),
        repository.fetchLedger(
          currency: LedgerCurrency.cashCny,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 50,
        ),
      ]);
      if (acceptsCommerceRead(ticket)) {
        setState(() {
          _wallet = values[0] as WalletSummary;
          _income = (values[1] as CommercePage<LedgerEntry>).items;
          _error = null;
        });
      }
    } catch (error) {
      if (acceptsCommerceRead(ticket)) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('主播收益')),
      body: _wallet == null || _income == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _load)
          : !_wallet!.incomeEligible
          ? const Center(child: Text('当前身份没有现金收益入口'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _EarningsSummary(wallet: _wallet!),
                const SizedBox(height: 18),
                const _CommerceSectionTitle(title: '收益明细'),
                const SizedBox(height: 8),
                if (_income!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('暂无收益记录')),
                  )
                else
                  for (final LedgerEntry entry in _income!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CommercePanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        child: Row(
                          children: <Widget>[
                            const _CommerceAssetOrb(
                              icon: Icons.auto_graph_rounded,
                              size: 40,
                              colors: <Color>[
                                Color(0xFFDFFFF1),
                                Color(0xFFE6F6FF),
                              ],
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: SocialColors.textPrimary,
                                        ),
                                  ),
                                  Text(
                                    '${entry.businessName} · ${_formatDateTime(entry.createdAt)}',
                                    maxLines: 2,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: SocialColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _ledgerAmountText(entry),
                              style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({this.repository, super.key});

  @visibleForTesting
  final CommerceRepository? repository;

  @override
  State<WithdrawalPage> createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  final TextEditingController _amountController = TextEditingController();
  WalletSummary? _wallet;
  WithdrawalQuote? _quote;
  List<WithdrawalRecord>? _records;
  PayoutAccountSelection? _payoutSelection;
  String? _selectedPayoutAccountId;
  bool _loading = true;
  bool _submitting = false;
  bool _confirming = false;
  bool _quoteLoading = false;
  double? _quotedAmount;
  String? _quoteError;
  String? _error;
  String? _payoutAccountsUnavailableMessage;
  CommerceRepository? _observedRepository;
  (String?, int)? _observedIdentity;
  BuildContext? _confirmationContext;

  bool _ownsIdentity((String?, int) identity) =>
      mounted && identity == _repository.withdrawalIdentity;

  void _identityChanged() {
    if (!mounted) return;
    final identity = _repository.withdrawalIdentity;
    if (identity == _observedIdentity) return;
    _observedIdentity = identity;
    final dialog = _confirmationContext;
    if (dialog != null &&
        dialog.mounted &&
        ModalRoute.of(dialog)?.isCurrent == true) {
      Navigator.of(dialog).pop(false);
    }
    setState(() {
      _amountController.clear();
      _wallet = null;
      _records = null;
      _quote = null;
      _quotedAmount = null;
      _payoutSelection = null;
      _selectedPayoutAccountId = null;
      _submitting = false;
      _confirming = false;
      _quoteLoading = false;
      _quoteError = null;
      _error = null;
      _payoutAccountsUnavailableMessage = null;
      _loading = _repository.withdrawalIdentity.$1 != null;
      if (!_loading) _error = '请登录后查看提现';
    });
    if (_loading) _load();
  }

  CommerceRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).commerceRepository;

  PayoutAccount? get _selectedPayoutAccount {
    final String? selectedId = _selectedPayoutAccountId;
    if (selectedId == null) {
      return null;
    }
    for (final PayoutAccount account
        in _payoutSelection?.accounts ?? const <PayoutAccount>[]) {
      if (account.payoutAccountId == selectedId && account.selectable) {
        return account;
      }
    }
    return null;
  }

  bool get _canApplyWithdrawal =>
      _repository.pendingWithdrawal != null ||
      (_wallet?.canWithdraw == true &&
          _repository.supportsWithdrawalApplication &&
          _selectedPayoutAccount != null);

  String get _withdrawalBlockerMessage {
    if (_wallet?.canWithdraw != true) return '当前身份不支持新提现申请；历史记录和原未决申请仍可恢复。';
    final String? unavailable = _payoutAccountsUnavailableMessage;
    if (unavailable != null) {
      return '$unavailable；提现申请已安全禁用，报价和历史记录仍可查看。';
    }
    if (!_repository.supportsWithdrawalApplication) {
      return '当前第一方实现未启用基于 payoutAccountId 的提现申请；报价和历史记录仍可查看。';
    }
    return '当前没有可用的收款账户。提现申请已安全禁用；报价和历史记录仍可查看。';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!identical(_observedRepository, _repository)) {
      _observedRepository?.withdrawalIdentityChanges?.removeListener(
        _identityChanged,
      );
      _observedRepository = _repository;
      _observedIdentity = _repository.withdrawalIdentity;
      _observedRepository?.withdrawalIdentityChanges?.addListener(
        _identityChanged,
      );
    }
    if (_wallet == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _observedRepository?.withdrawalIdentityChanges?.removeListener(
      _identityChanged,
    );
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = _repository.withdrawalIdentity;
    setState(() {
      _loading = true;
      _error = null;
      _payoutAccountsUnavailableMessage = null;
    });
    try {
      final List<Object> values = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchWalletSummary(),
        _repository.fetchWithdrawalRecords(page: 1, pageSize: 50),
      ]);
      if (!_ownsIdentity(identity)) return;
      PayoutAccountSelection? payoutSelection;
      try {
        if ((values[0] as WalletSummary).canWithdraw &&
            _repository.pendingWithdrawal == null) {
          payoutSelection = await _repository.fetchPayoutAccounts();
        }
      } on ApiException catch (error) {
        if (error.kind != ApiFailureKind.configuration &&
            error.kind != ApiFailureKind.forbidden) {
          rethrow;
        }
        // Explicitly unsupported and domain-level authorization outcomes may
        // keep quote/history usable. Retryable transport/server failures and
        // malformed authority responses must remain visible to the user.
        payoutSelection = null;
        _payoutAccountsUnavailableMessage = error.message;
      }
      if (_ownsIdentity(identity)) {
        setState(() {
          _wallet = values[0] as WalletSummary;
          _records = (values[1] as CommercePage<WithdrawalRecord>).items;
          _payoutSelection = payoutSelection;
          _selectedPayoutAccountId = payoutSelection?.selectedPayoutAccountId;
          final pending = _repository.pendingWithdrawal;
          if (pending != null) {
            _amountController.text = pending.amount.toStringAsFixed(0);
            _quote = pending.quote;
            _quotedAmount = pending.amount;
          }
          _loading = false;
        });
      }
    } catch (error) {
      if (_ownsIdentity(identity)) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _loadQuote() async {
    final identity = _repository.withdrawalIdentity;
    if (_submitting ||
        _repository.pendingWithdrawal != null ||
        _wallet?.canWithdraw != true)
      return;
    final double? amount = _enteredAmount;
    if (!_isLegalAmount(amount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WithdrawalAmountPolicy.message)),
      );
      return;
    }
    final double legalAmount = amount!;
    if (_quoteLoading) {
      return;
    }
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final WithdrawalQuote quote = await _repository.fetchWithdrawalQuote(
        amount: legalAmount,
      );
      if (_ownsIdentity(identity)) {
        setState(() {
          _quote = quote;
          _quotedAmount = legalAmount;
          _quoteLoading = false;
        });
      }
    } catch (error) {
      if (_ownsIdentity(identity)) {
        setState(() {
          _quoteLoading = false;
          _quoteError = _messageFor(error);
          _quote = null;
          _quotedAmount = null;
        });
      }
    }
  }

  bool _isLegalAmount(double? amount) {
    return WithdrawalAmountPolicy.isValid(amount);
  }

  double? get _enteredAmount =>
      WithdrawalAmountPolicy.parseInput(_amountController.text);

  bool get _hasCurrentQuote {
    final double? entered = _enteredAmount;
    return _isLegalAmount(entered) &&
        _quote != null &&
        _quotedAmount != null &&
        entered == _quotedAmount &&
        entered == _quote!.quotedAmount;
  }

  Future<void> _apply() async {
    final identity = _repository.withdrawalIdentity;
    if (!_canApplyWithdrawal) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择当前权威列表中的有效收款账户后再提交提现。')));
      return;
    }
    final double? amount = _enteredAmount;
    if (!_isLegalAmount(amount) || _submitting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WithdrawalAmountPolicy.message)),
      );
      return;
    }
    final double legalAmount = amount!;
    if (_repository.pendingWithdrawal == null &&
        (legalAmount > _wallet!.cashBalance ||
            (_quote != null && legalAmount < _quote!.minimumAmount))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('可提现余额不足或未达到服务端最低提现金额')));
      return;
    }
    if (!_hasCurrentQuote) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先计算当前提现金额的服务端报价')));
      return;
    }
    final WithdrawalQuote confirmedQuote =
        _repository.pendingWithdrawal?.quote ?? _quote!;
    final String confirmedAccountId =
        _repository.pendingWithdrawal?.payoutAccountId ??
        _selectedPayoutAccount!.payoutAccountId;
    setState(() {
      _submitting = true;
      _confirming = true;
    });
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        _confirmationContext = context;
        return AlertDialog(
          title: const Text('确认申请提现？'),
          content: Text(
            '提现金额：¥${legalAmount.toStringAsFixed(2)}\n手续费（${confirmedQuote.feeRateText}）：¥${confirmedQuote.feeFor(legalAmount).toStringAsFixed(2)}\n预计到账：¥${confirmedQuote.receivedFor(legalAmount).toStringAsFixed(2)}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认提现'),
            ),
          ],
        );
      },
    );
    _confirmationContext = null;
    if (!_ownsIdentity(identity)) return;
    if (confirmed != true || !mounted) {
      if (mounted)
        setState(() {
          _submitting = false;
          _confirming = false;
        });
      return;
    }
    setState(() => _confirming = false);
    try {
      await _repository.applyWithdrawal(
        amount: legalAmount,
        confirmedQuote: confirmedQuote,
        payoutAccountId: confirmedAccountId,
      );
      if (!_ownsIdentity(identity)) return;
      _amountController.clear();
      _quote = null;
      _quotedAmount = null;
      await _load();
      if (mounted && _ownsIdentity(identity)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提现申请已提交')));
      }
    } catch (error) {
      if (mounted && _ownsIdentity(identity)) {
        if (error is ApiException &&
            error.kind == ApiFailureKind.conflict &&
            _repository.pendingWithdrawal == null) {
          setState(() {
            _quote = null;
            _quotedAmount = null;
          });
        }
        final pending = _repository.pendingWithdrawal;
        if (pending != null) {
          setState(() {
            _amountController.text = pending.amount.toStringAsFixed(0);
            _quote = pending.quote;
            _quotedAmount = pending.amount;
          });
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (_ownsIdentity(identity)) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openBinding() async {
    final identity = _repository.withdrawalIdentity;
    if (_submitting ||
        _wallet?.canWithdraw != true ||
        _payoutSelection?.canBind != true)
      return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PayoutAccountBindingPage(repository: _repository),
      ),
    );
    if (_ownsIdentity(identity)) await _load();
  }

  Widget _buildPayoutAccountPicker() {
    if (_repository.pendingWithdrawal != null) {
      return const _CommerceInfoBanner(
        text: '上一笔提现结果尚未确定，金额、报价和原收款账户已锁定；请重试原申请。',
      );
    }
    final PayoutAccountSelection selection = _payoutSelection!;
    final List<PayoutAccount> selectable = selection.selectableAccounts;
    return _CommercePanel(
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('收款账户', style: TextStyle(fontWeight: FontWeight.w800)),
          if (selection.canBind &&
              _wallet?.canWithdraw == true &&
              _repository is PayoutAccountBindingRepository)
            TextButton(
              onPressed: _submitting ? null : _openBinding,
              child: const Text('新增 / 更换收款账户'),
            ),
          if (selection.bindingBlockReason == 'REAL_NAME_RESUBMISSION_REQUIRED')
            const Text('请补充实名认证资料后绑定收款账户'),
          if (selection.bindingBlockReason == 'REAL_NAME_REQUIRED')
            const Text('请先完成本人实名认证后绑定收款账户'),
          if (selection.bindingBlockReason == 'CONFIGURATION_UNAVAILABLE')
            const Text('收款账户绑定暂不可用'),
          if (selectable.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _CommerceInfoBanner(text: '暂无可用于提现的收款账户。'),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedPayoutAccountId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final PayoutAccount account in selectable)
                  DropdownMenuItem<String>(
                    value: account.payoutAccountId,
                    child: Text(
                      '${account.accountMasked} · ${account.holderNameMasked} · ${account.status == PayoutAccountStatus.bound ? '已绑定 / 用户填写' : '已验证'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting || _repository.pendingWithdrawal != null
                  ? null
                  : (String? value) {
                      if (value == null || _payoutSelection == null) {
                        return;
                      }
                      setState(() {
                        _payoutSelection = _payoutSelection!.select(value);
                        _selectedPayoutAccountId = value;
                      });
                    },
            ),
          if (selection.accounts.any((PayoutAccount item) => !item.selectable))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '另有 ${selection.accounts.where((PayoutAccount item) => !item.selectable).length} 个账户待审核或不可用',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('结算与提现')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _CommerceStatusCard(
                      icon: Icons.account_balance_outlined,
                      title:
                          '${_wallet!.canWithdraw ? '可提现' : '历史现金余额'} ¥${_wallet!.cashBalance.toStringAsFixed(2)}',
                      description: _wallet!.bankCard == null
                          ? '尚未绑定银行卡'
                          : '${_wallet!.bankCard!.accountType} ${_wallet!.bankCard!.maskedAccount}',
                    ),
                    const SizedBox(height: 14),
                    if (!_wallet!.realNameVerified || _wallet!.bankCard == null)
                      const _CommerceInfoBanner(
                        text: '提交提现前必须完成实名认证并绑定银行卡。缺少条件时客户端会阻止提交。',
                      ),
                    if (!_wallet!.canWithdraw ||
                        !_repository.supportsWithdrawalApplication ||
                        _payoutSelection == null ||
                        _payoutSelection!
                            .selectableAccounts
                            .isEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      _CommerceInfoBanner(text: _withdrawalBlockerMessage),
                    ],
                    if (_wallet!.canWithdraw &&
                        _payoutSelection != null &&
                        _repository.supportsPayoutAccountSelection &&
                        _repository.supportsWithdrawalApplication) ...<Widget>[
                      const SizedBox(height: 10),
                      _buildPayoutAccountPicker(),
                    ],
                    const SizedBox(height: 14),
                    if (_wallet!.canWithdraw ||
                        _repository.pendingWithdrawal != null)
                      _CommercePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _CommerceSectionTitle(title: '提现申请'),
                            const _CommerceInfoBanner(
                              text:
                                  '财务人工审核处理，不自动打款。最低提现 100 元，仅支持整元，余额零头保留。按北京时间自然日每天可提交一次；驳回后次日重新申请。',
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              enabled:
                                  !_submitting &&
                                  _repository.pendingWithdrawal == null,
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) {
                                if (_quote != null || _quoteError != null) {
                                  setState(() {
                                    _quote = null;
                                    _quotedAmount = null;
                                    _quoteError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: '提现金额',
                                helperText: _quote == null
                                    ? '输入整元金额后计算手续费和预计到账金额'
                                    : '最低 ¥${(_quote!.minimumAmount < 100 ? 100 : _quote!.minimumAmount).toStringAsFixed(0)} · 手续费 ${_quote!.feeRateText}',
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _quoteLoading ||
                                      _submitting ||
                                      _repository.pendingWithdrawal != null
                                  ? null
                                  : _loadQuote,
                              icon: _quoteLoading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.calculate_outlined),
                              label: const Text('计算到账金额'),
                            ),
                            if (_quoteError != null) ...<Widget>[
                              const SizedBox(height: 8),
                              _CommerceInfoBanner(text: _quoteError!),
                            ],
                            if (_hasCurrentQuote) ...<Widget>[
                              const SizedBox(height: 8),
                              _CommerceInfoBanner(
                                text:
                                    '服务端报价：手续费 ¥${_quote!.feeFor(_quotedAmount!).toStringAsFixed(2)} · 预计到账 ¥${_quote!.receivedFor(_quotedAmount!).toStringAsFixed(2)}',
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed:
                                    (_repository.pendingWithdrawal != null ||
                                            (_canApplyWithdrawal &&
                                                _wallet!.realNameVerified &&
                                                _wallet!.bankCard != null &&
                                                _wallet!.cashBalance >=
                                                    WithdrawalAmountPolicy
                                                        .minimum)) &&
                                        !_submitting
                                    ? _apply
                                    : null,
                                child: _submitting && !_confirming
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('申请提现'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    const _CommerceSectionTitle(title: '提现记录'),
                    const SizedBox(height: 8),
                    if (_records!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: Text('暂无提现记录')),
                      )
                    else
                      for (final WithdrawalRecord record in _records!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CommercePanel(
                            padding: const EdgeInsets.all(13),
                            child: Row(
                              children: <Widget>[
                                const _CommerceAssetOrb(
                                  icon: Icons.account_balance_rounded,
                                  size: 40,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        '¥${record.amount.toStringAsFixed(2)} · ${record.statusText}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      Text(
                                        '持卡人 ${record.holderNameMasked} ${record.maskedCard}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      Text(
                                        _formatDateTime(record.createdAt),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '到账\n¥${record.receivedAmount.toStringAsFixed(2)}',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
    );
  }
}
