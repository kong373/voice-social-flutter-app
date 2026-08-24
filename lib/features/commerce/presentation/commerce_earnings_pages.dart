part of 'commerce_pages.dart';

class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
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
    try {
      final CommerceRepository repository = AppDependencyScope.of(
        context,
      ).commerceRepository;
      final List<Object> values = await Future.wait<Object>(<Future<Object>>[
        repository.fetchWalletSummary(),
        repository.fetchLedger(
          currency: LedgerCurrency.cashCny,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 50,
        ),
      ]);
      if (mounted) {
        setState(() {
          _wallet = values[0] as WalletSummary;
          _income = (values[1] as CommercePage<LedgerEntry>).items;
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
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('主播收益')),
      body: _wallet == null || _income == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _load)
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  Text(
                                    '${entry.businessName} · ${_formatDateTime(entry.createdAt)}',
                                    maxLines: 2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '+¥${entry.amount.toStringAsFixed(2)}',
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
  bool _loading = true;
  bool _submitting = false;
  bool _quoteLoading = false;
  double? _quotedAmount;
  String? _quoteError;
  String? _error;

  CommerceRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).commerceRepository;

  // The current first-party live contract deliberately has no payout-account
  // list/selection endpoint.  A masked default card is display-only and must
  // never be treated as the withdrawal request's payoutAccountId.
  bool get _canApplyWithdrawal => _repository.supportsWithdrawalApplication;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wallet == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> values = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchWalletSummary(),
        _repository.fetchWithdrawalRecords(page: 1, pageSize: 50),
      ]);
      if (mounted) {
        setState(() {
          _wallet = values[0] as WalletSummary;
          _records = (values[1] as CommercePage<WithdrawalRecord>).items;
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

  Future<void> _loadQuote() async {
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效提现金额后再计算报价')));
      return;
    }
    if (_quoteLoading) {
      return;
    }
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final WithdrawalQuote quote = await _repository.fetchWithdrawalQuote(
        amount: amount,
      );
      if (mounted) {
        setState(() {
          _quote = quote;
          _quotedAmount = amount;
          _quoteLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _quoteLoading = false;
          _quoteError = _messageFor(error);
          _quote = null;
          _quotedAmount = null;
        });
      }
    }
  }

  double? get _enteredAmount => double.tryParse(_amountController.text.trim());

  bool get _hasCurrentQuote {
    final double? entered = _enteredAmount;
    return entered != null &&
        _quote != null &&
        _quotedAmount != null &&
        (entered - _quotedAmount!).abs() < 0.005;
  }

  Future<void> _apply() async {
    if (!_canApplyWithdrawal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前后端未提供收款账户选择契约，提现申请暂不可用。')),
      );
      return;
    }
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || _submitting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效提现金额')));
      return;
    }
    if (!_hasCurrentQuote) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先计算当前提现金额的服务端报价')));
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认申请提现？'),
        content: Text(
          '提现金额：¥${amount.toStringAsFixed(2)}\n手续费：¥${_quote!.feeFor(amount).toStringAsFixed(2)}\n预计到账：¥${_quote!.receivedFor(amount).toStringAsFixed(2)}',
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
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repository.applyWithdrawal(amount: amount);
      _amountController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提现申请已提交')));
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
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('结算与提现')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _CommerceStatusCard(
                    icon: Icons.account_balance_outlined,
                    title: '可提现 ¥${_wallet!.cashBalance.toStringAsFixed(2)}',
                    description: _wallet!.bankCard == null
                        ? '尚未绑定银行卡'
                        : '${_wallet!.bankCard!.bankName} ${_wallet!.bankCard!.maskedNumber}',
                  ),
                  const SizedBox(height: 14),
                  if (!_wallet!.realNameVerified || _wallet!.bankCard == null)
                    const _CommerceInfoBanner(
                      text: '提交提现前必须完成实名认证并绑定银行卡。缺少条件时客户端会阻止提交。',
                    ),
                  if (!_canApplyWithdrawal) ...<Widget>[
                    const SizedBox(height: 10),
                    const _CommerceInfoBanner(
                      text:
                          '当前第一方后端尚未提供 payoutAccountId 的账户列表与选择接口。银行卡摘要仅供展示，提现申请已安全禁用；报价和历史记录仍可查看。',
                    ),
                  ],
                  const SizedBox(height: 14),
                  _CommercePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _CommerceSectionTitle(title: '提现申请'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
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
                                ? '输入金额后计算服务端报价'
                                : '最低 ¥${_quote!.minimumAmount.toStringAsFixed(0)} · 手续费 ${_quote!.feeRateText}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _quoteLoading ? null : _loadQuote,
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
                                _canApplyWithdrawal &&
                                    _wallet!.realNameVerified &&
                                    _wallet!.bankCard != null &&
                                    !_submitting
                                ? _apply
                                : null,
                            child: _submitting
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}
