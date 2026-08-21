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
    return Scaffold(
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
                Text('收益明细', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_income!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('暂无收益记录')),
                  )
                else
                  for (final LedgerEntry entry in _income!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.title),
                      subtitle: Text(
                        '${entry.businessName} · ${_formatDateTime(entry.createdAt)}',
                      ),
                      trailing: Text(
                        '+¥${entry.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({super.key});

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
  String? _error;

  CommerceRepository get _repository =>
      AppDependencyScope.of(context).commerceRepository;

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
        _repository.fetchWithdrawalQuote(),
        _repository.fetchWithdrawalRecords(page: 1, pageSize: 50),
      ]);
      if (mounted) {
        setState(() {
          _wallet = values[0] as WalletSummary;
          _quote = values[1] as WithdrawalQuote;
          _records = (values[2] as CommercePage<WithdrawalRecord>).items;
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

  Future<void> _apply() async {
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0 || _submitting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效提现金额')));
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
    return Scaffold(
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
                  const SizedBox(height: 14),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '提现金额',
                      helperText:
                          '最低 ¥${_quote!.minimumAmount.toStringAsFixed(0)} · 手续费 ${_quote!.feeRateText}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed:
                        _wallet!.realNameVerified &&
                            _wallet!.bankCard != null &&
                            !_submitting
                        ? _apply
                        : null,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('申请提现'),
                  ),
                  const SizedBox(height: 24),
                  Text('提现记录', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_records!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('暂无提现记录')),
                    )
                  else
                    for (final WithdrawalRecord record in _records!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '¥${record.amount.toStringAsFixed(2)} · ${record.statusText}',
                        ),
                        subtitle: Text(
                          '${record.bankName} ${record.maskedCard}\n${_formatDateTime(record.createdAt)}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          '到账 ¥${record.receivedAmount.toStringAsFixed(2)}',
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
