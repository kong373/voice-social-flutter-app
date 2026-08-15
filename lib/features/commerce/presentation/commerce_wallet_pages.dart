part of 'commerce_pages.dart';

class CommerceHubPage extends StatefulWidget {
  const CommerceHubPage({required this.account, super.key});

  final String account;

  @override
  State<CommerceHubPage> createState() => _CommerceHubPageState();
}

class _CommerceHubPageState extends State<CommerceHubPage> {
  WalletSummary? _wallet;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wallet == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final WalletSummary wallet =
          await AppDependencyScope.of(context).commerceRepository.fetchWalletSummary();
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('钱包与商业化'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _wallet == null ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _wallet == null
          ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : _CommerceErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                _WalletSummaryCard(wallet: _wallet!),
                const SizedBox(height: 18),
                _CommerceEntry(
                  icon: Icons.receipt_long_outlined,
                  title: '钱包与流水',
                  subtitle: '查看礼物币、现金收益和收支明细',
                  onTap: () => _open(const WalletPage()),
                ),
                _CommerceEntry(
                  icon: Icons.shopping_bag_outlined,
                  title: '充值订单',
                  subtitle: '查询订单并以服务端结果为准进行补单核验',
                  onTap: () => _open(const OrdersPage()),
                ),
                _CommerceEntry(
                  icon: Icons.assignment_return_outlined,
                  title: '退款申请',
                  subtitle: '当前后端为账户级历史退款流程，不冒充逐订单退款',
                  onTap: () => _open(RefundListPage(account: widget.account)),
                ),
                _CommerceEntry(
                  icon: Icons.trending_up_rounded,
                  title: '主播收益',
                  subtitle: '累计收益、昨日收益和收入明细',
                  onTap: () => _open(const EarningsPage()),
                ),
                _CommerceEntry(
                  icon: Icons.account_balance_outlined,
                  title: '结算与提现',
                  subtitle: '手续费、银行卡、提现申请和处理记录',
                  onTap: () => _open(const WithdrawalPage()),
                ),
                const SizedBox(height: 18),
                const _CommerceInfoBanner(
                  text: '微信支付、支付宝和 Apple IAP 尚在申请。本阶段不调起第三方支付，也不会伪造支付成功；订单查询、退款、收益和提现业务可独立开发。',
                ),
              ],
            ),
    );
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  LedgerDirection _direction = LedgerDirection.income;
  WalletSummary? _wallet;
  List<LedgerEntry>? _entries;
  bool _loading = true;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchWalletSummary(),
        _repository.fetchLedger(
          direction: _direction,
          page: 1,
          pageSize: 50,
        ),
      ]);
      final WalletSummary wallet = results[0] as WalletSummary;
      final CommercePage<LedgerEntry> page =
          results[1] as CommercePage<LedgerEntry>;
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _entries = page.items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('钱包与流水')),
      body: Column(
        children: <Widget>[
          if (_wallet != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _WalletSummaryCard(wallet: _wallet!),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<LedgerDirection>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<LedgerDirection>>[
                ButtonSegment<LedgerDirection>(
                  value: LedgerDirection.income,
                  label: Text('收入'),
                ),
                ButtonSegment<LedgerDirection>(
                  value: LedgerDirection.expense,
                  label: Text('支出'),
                ),
              ],
              selected: <LedgerDirection>{_direction},
              onSelectionChanged: (Set<LedgerDirection> value) {
                setState(() => _direction = value.first);
                _load();
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildLedger()),
        ],
      ),
    );
  }

  Widget _buildLedger() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CommerceErrorState(message: _error!, onRetry: _load);
    }
    final List<LedgerEntry> entries = _entries ?? const <LedgerEntry>[];
    if (entries.isEmpty) {
      return Center(
        child: Text(_direction == LedgerDirection.income ? '暂无收入记录' : '暂无支出记录'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final LedgerEntry entry = entries[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: entry.direction == LedgerDirection.income
                  ? AppColors.success.withValues(alpha: 0.16)
                  : AppColors.warning.withValues(alpha: 0.16),
              child: Icon(
                entry.direction == LedgerDirection.income
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
              ),
            ),
            title: Text(entry.title),
            subtitle: Text(
              <String>[
                if (entry.relatedUserName.isNotEmpty) entry.relatedUserName,
                if (entry.businessName.isNotEmpty) entry.businessName,
                _formatDateTime(entry.createdAt),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              '${entry.direction == LedgerDirection.income ? '+' : '-'}¥${entry.amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: entry.direction == LedgerDirection.income
                    ? AppColors.success
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      ),
    );
  }
}
