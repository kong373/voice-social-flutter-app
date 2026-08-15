part of 'commerce_pages.dart';

class RechargeCatalogPage extends StatefulWidget {
  const RechargeCatalogPage({super.key});

  @override
  State<RechargeCatalogPage> createState() => _RechargeCatalogPageState();
}

class _RechargeCatalogPageState extends State<RechargeCatalogPage> {
  List<RechargeProduct>? _products;
  RechargeProduct? _selected;
  WalletSummary? _wallet;
  AccountComplianceSnapshot? _compliance;
  bool _loading = true;
  String? _error;

  CommerceCatalogRepository get _repository =>
      AppDependencyScope.of(context).commerceCatalogRepository;

  ClientStorePlatform get _platform =>
      AppDependencyScope.of(
        context,
      ).environment.clientType.toLowerCase().contains('ios')
      ? ClientStorePlatform.ios
      : ClientStorePlatform.android;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _products == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final AppDependencies dependencies = AppDependencyScope.of(context);
    final String account = dependencies.sessionManager.session?.mobile ?? '';
    final int currentVersion =
        int.tryParse(dependencies.environment.clientInnerVersion) ?? 1;
    final int platformType = _platform == ClientStorePlatform.ios ? 2 : 1;
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchRechargeProducts(platform: _platform),
        dependencies.commerceRepository.fetchWalletSummary(),
        dependencies.accountComplianceRepository.fetchSnapshot(
          account: account,
          currentVersion: currentVersion,
          platformType: platformType,
        ),
      ]);
      if (!mounted) {
        return;
      }
      final List<RechargeProduct> products = result[0] as List<RechargeProduct>;
      setState(() {
        _products = products;
        _selected =
            products
                .where(
                  (RechargeProduct item) => item.recommended && item.enabled,
                )
                .firstOrNull ??
            products.where((RechargeProduct item) => item.enabled).firstOrNull;
        _wallet = result[1] as WalletSummary;
        _compliance = result[2] as AccountComplianceSnapshot;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _continue() async {
    final RechargeProduct? product = _selected;
    final AccountComplianceSnapshot? compliance = _compliance;
    if (product == null || compliance == null) {
      return;
    }
    final RechargeEligibility eligibility = await _repository
        .checkRechargeEligibility(
          youthModeEnabled: compliance.youthModeEnabled,
        );
    if (!mounted) {
      return;
    }
    if (!eligibility.allowed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(eligibility.message)));
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PaymentSubmissionPage(
          product: product,
          platform: _platform,
          youthModeEnabled: compliance.youthModeEnabled,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('充值商品目录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: <Widget>[
                          const CircleAvatar(
                            child: Icon(Icons.account_balance_wallet_outlined),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text('当前礼物币余额'),
                                const SizedBox(height: 4),
                                Text(
                                  _wallet?.giftCoinBalance == null
                                      ? '以服务端为准'
                                      : '${_wallet!.giftCoinBalance}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _platform == ClientStorePlatform.ios
                                ? 'iOS'
                                : 'Android',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_compliance?.youthModeEnabled == true)
                    const _CommerceInfoBanner(
                      text: '青少年模式已开启，只限制创建新的充值订单；进房、消息、社交、钱包查询和其他正常功能不受影响。',
                    ),
                  const SizedBox(height: 18),
                  Text('选择充值档位', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_products == null || _products!.isEmpty)
                    const _CommerceInfoBanner(text: '当前没有可用充值商品，请稍后刷新。')
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1,
                          ),
                      itemCount: _products!.length,
                      itemBuilder: (BuildContext context, int index) {
                        final RechargeProduct product = _products![index];
                        final bool selected = _selected?.id == product.id;
                        return Material(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.18)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: product.enabled
                                ? () => setState(() => _selected = product)
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.divider,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '${product.totalGiftCoins} 礼物币',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      if (product.recommended)
                                        const _CommercePill(label: '推荐'),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '¥${product.priceCny.toStringAsFixed(product.priceCny % 1 == 0 ? 0 : 2)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  if (product.bonusGiftCoins > 0)
                                    Text(
                                      '含赠送 ${product.bonusGiftCoins}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        _selected == null ||
                            _compliance?.youthModeEnabled == true
                        ? null
                        : _continue,
                    child: const Text('选择支付方式'),
                  ),
                  const SizedBox(height: 12),
                  const _CommerceInfoBanner(
                    text: '充值得到的是礼物币，不是主播现金收益或可提现余额。支付结果始终以服务端订单状态为准。',
                  ),
                ],
              ),
            ),
    );
  }
}

class PaymentSubmissionPage extends StatefulWidget {
  const PaymentSubmissionPage({
    required this.product,
    required this.platform,
    required this.youthModeEnabled,
    super.key,
  });

  final RechargeProduct product;
  final ClientStorePlatform platform;
  final bool youthModeEnabled;

  @override
  State<PaymentSubmissionPage> createState() => _PaymentSubmissionPageState();
}

class _PaymentSubmissionPageState extends State<PaymentSubmissionPage> {
  PaymentChannelType? _channel;
  bool _submitting = false;

  CommerceCatalogRepository get _repository =>
      AppDependencyScope.of(context).commerceCatalogRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel ??= _repository.availableChannels(widget.platform).firstOrNull;
  }

  Future<void> _submit() async {
    final PaymentChannelType? channel = _channel;
    if (channel == null || _submitting) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认充值信息'),
        content: Text(
          '充值 ${widget.product.totalGiftCoins} 礼物币，实付 ¥${widget.product.priceCny.toStringAsFixed(2)}，支付方式为 ${channel.label}。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
      final String account =
          AppDependencyScope.of(context).sessionManager.session?.mobile ?? '';
      RechargeOrder order = await _repository.createRechargeOrder(
        account: account,
        product: widget.product,
        channel: channel,
        platform: widget.platform,
        youthModeEnabled: widget.youthModeEnabled,
      );
      if (_repository.supportsPaymentChannelInvocation) {
        order = await _repository.invokePayment(order);
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PaymentResultPage(order: order),
        ),
      );
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
    final List<PaymentChannelType> channels = _repository.availableChannels(
      widget.platform,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('支付方式与提交')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  _CommerceKeyValue(
                    label: '充值账号',
                    value:
                        AppDependencyScope.of(
                          context,
                        ).sessionManager.session?.mobile ??
                        '当前账号',
                  ),
                  _CommerceKeyValue(
                    label: '充值商品',
                    value: '${widget.product.totalGiftCoins} 礼物币',
                  ),
                  _CommerceKeyValue(
                    label: '实付金额',
                    value: '¥${widget.product.priceCny.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('选择支付方式', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final PaymentChannelType channel in channels)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: RadioListTile<PaymentChannelType>(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  value: channel,
                  groupValue: _channel,
                  onChanged: _submitting
                      ? null
                      : (PaymentChannelType? value) =>
                            setState(() => _channel = value),
                  title: Text(channel.label),
                  subtitle: Text(
                    channel == PaymentChannelType.appleIap
                        ? '由 Apple IAP 完成购买与收据校验'
                        : '支付结果需等待服务端订单确认',
                  ),
                ),
              ),
            ),
          if (!_repository.supportsPaymentChannelInvocation)
            const _CommerceInfoBanner(
              text: '支付 SDK 尚未接入。Live 模式不会伪造调起或支付成功；正式渠道接入后再开放提交。',
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _channel == null || _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('提交充值订单'),
          ),
          const SizedBox(height: 10),
          Text(
            widget.platform == ClientStorePlatform.ios
                ? 'iOS 只展示 Apple IAP。'
                : 'Android 只展示微信支付与支付宝，不展示其他渠道。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class PaymentResultPage extends StatefulWidget {
  const PaymentResultPage({required this.order, super.key});

  final RechargeOrder order;

  @override
  State<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends State<PaymentResultPage> {
  late RechargeOrder _order;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _order.state != RechargeOrderState.failed &&
          _order.state != RechargeOrderState.canceled) {
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
      _error = null;
    });
    try {
      final RechargeOrder value = await AppDependencyScope.of(
        context,
      ).commerceCatalogRepository.queryRechargeOrder(_order);
      if (mounted) {
        setState(() => _order = value);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool success = _order.state == RechargeOrderState.succeeded;
    final bool terminal =
        success ||
        _order.state == RechargeOrderState.failed ||
        _order.state == RechargeOrderState.canceled;
    return Scaffold(
      appBar: AppBar(title: const Text('支付返回与结果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 28),
        children: <Widget>[
          Icon(
            success
                ? Icons.check_circle_rounded
                : terminal
                ? Icons.error_outline_rounded
                : Icons.hourglass_top_rounded,
            size: 68,
            color: success
                ? AppColors.success
                : terminal
                ? AppColors.error
                : AppColors.warning,
          ),
          const SizedBox(height: 18),
          Text(
            _order.state.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _order.message.isEmpty ? '订单结果以服务端状态为准' : _order.message,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  _CommerceKeyValue(label: '订单号', value: _order.orderNo),
                  _CommerceKeyValue(
                    label: '充值商品',
                    value: '${_order.product.totalGiftCoins} 礼物币',
                  ),
                  _CommerceKeyValue(label: '支付方式', value: _order.channel.label),
                  _CommerceKeyValue(
                    label: '实付金额',
                    value: '¥${_order.product.priceCny.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _CommerceInfoBanner(text: '$_error。保留当前订单信息，可继续刷新服务端状态。'),
          ],
          const SizedBox(height: 18),
          if (!terminal)
            FilledButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_refreshing ? '正在确认…' : '刷新订单状态'),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回钱包'),
          ),
        ],
      ),
    );
  }
}

class GiftCatalogPage extends StatefulWidget {
  const GiftCatalogPage({super.key});

  @override
  State<GiftCatalogPage> createState() => _GiftCatalogPageState();
}

class _GiftCatalogPageState extends State<GiftCatalogPage> {
  List<GiftCatalogItem>? _gifts;
  List<BackpackGiftItem>? _backpack;
  WalletSummary? _wallet;
  GiftCatalogCategory _category = GiftCatalogCategory.popular;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _gifts == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final AppDependencies dependencies = AppDependencyScope.of(context);
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        dependencies.commerceCatalogRepository.fetchGiftCatalog(),
        dependencies.commerceCatalogRepository.fetchBackpackGifts(),
        dependencies.commerceRepository.fetchWalletSummary(),
      ]);
      if (mounted) {
        setState(() {
          _gifts = result[0] as List<GiftCatalogItem>;
          _backpack = result[1] as List<BackpackGiftItem>;
          _wallet = result[2] as WalletSummary;
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
    final List<GiftCatalogItem> visible = (_gifts ?? const <GiftCatalogItem>[])
        .where((GiftCatalogItem item) => item.category == _category)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('礼物目录与赠送面板')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '普通礼物',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        _wallet?.giftCoinBalance == null
                            ? '余额以服务端为准'
                            : '余额 ${_wallet!.giftCoinBalance}',
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<GiftCatalogCategory>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<GiftCatalogCategory>>[
                      for (final GiftCatalogCategory category
                          in GiftCatalogCategory.values)
                        ButtonSegment<GiftCatalogCategory>(
                          value: category,
                          label: Text(category.label),
                        ),
                    ],
                    selected: <GiftCatalogCategory>{_category},
                    onSelectionChanged: (Set<GiftCatalogCategory> values) =>
                        setState(() => _category = values.first),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    const _CommerceInfoBanner(text: '当前分类没有可用普通礼物。')
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.92,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final GiftCatalogItem gift = visible[index];
                        return Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const Icon(Icons.redeem_rounded, size: 30),
                                const SizedBox(height: 8),
                                Text(
                                  gift.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${gift.price}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 20),
                  Text('背包礼物', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_backpack == null || _backpack!.isEmpty)
                    const _CommerceInfoBanner(text: '背包中没有可用礼物。')
                  else
                    for (final BackpackGiftItem item in _backpack!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(item.gift.name),
                        subtitle: Text(
                          item.expiresAt == null
                              ? '长期有效'
                              : '有效期至 ${_formatDateTime(item.expiresAt!)}',
                        ),
                        trailing: Text('×${item.quantity}'),
                      ),
                  const SizedBox(height: 14),
                  const _CommerceInfoBanner(
                    text: '从钱包进入时只浏览礼物和背包。实际赠送必须在语音房内选择麦上用户，礼物面板会保留当前房间上下文。',
                  ),
                ],
              ),
            ),
    );
  }
}

class MembershipBackpackPage extends StatefulWidget {
  const MembershipBackpackPage({super.key});

  @override
  State<MembershipBackpackPage> createState() => _MembershipBackpackPageState();
}

class _MembershipBackpackPageState extends State<MembershipBackpackPage> {
  MembershipSnapshot? _snapshot;
  int _section = 0;
  String? _busyId;
  bool _loading = true;
  String? _error;

  CommerceCatalogRepository get _repository =>
      AppDependencyScope.of(context).commerceCatalogRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _snapshot == null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MembershipSnapshot value = await _repository
          .fetchMembershipSnapshot();
      if (mounted) {
        setState(() {
          _snapshot = value;
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

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _buyMembership(MembershipPlan plan) async {
    if (_busyId != null ||
        !await _confirm(
          '开通${plan.name}？',
          '将扣除 ${plan.priceGiftCoins} 礼物币，有效期 ${plan.durationDays} 天。',
        )) {
      return;
    }
    setState(() => _busyId = plan.id);
    try {
      final MembershipSnapshot value = await _repository.purchaseMembership(
        plan.id,
      );
      if (mounted) {
        setState(() => _snapshot = value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _operateDecoration(DecorationItem item) async {
    if (_busyId != null) {
      return;
    }
    if (!item.owned) {
      final bool confirmed = await _confirm(
        '购买${item.name}？',
        '将扣除 ${item.priceGiftCoins} 礼物币，购买结果以服务端资产记录为准。',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() => _busyId = item.id);
    try {
      if (item.owned) {
        await _repository.setDecorationEquipped(
          decorationId: item.id,
          equipped: !item.equipped,
        );
      } else {
        await _repository.purchaseDecoration(item.id);
      }
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MembershipSnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('会员装扮与背包')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : snapshot == null
          ? const Center(child: Text('会员与背包数据不可用'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            child: Icon(
                              snapshot.active
                                  ? Icons.workspace_premium_rounded
                                  : Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  snapshot.levelName,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  snapshot.expiresAt == null
                                      ? '当前未开通有效会员'
                                      : '有效期至 ${_formatDateTime(snapshot.expiresAt!)}',
                                ),
                              ],
                            ),
                          ),
                          Text('余额 ${snapshot.giftCoinBalance}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(value: 0, label: Text('会员')),
                      ButtonSegment<int>(value: 1, label: Text('装扮')),
                      ButtonSegment<int>(value: 2, label: Text('背包')),
                    ],
                    selected: <int>{_section},
                    onSelectionChanged: (Set<int> value) =>
                        setState(() => _section = value.first),
                  ),
                  const SizedBox(height: 16),
                  if (_section == 0)
                    if (snapshot.plans.isEmpty)
                      const _CommerceInfoBanner(text: '当前没有可购买的权威会员商品。')
                    else
                      for (final MembershipPlan plan in snapshot.plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              title: Text(plan.name),
                              subtitle: Text(
                                '${plan.durationDays} 天 · ${plan.priceGiftCoins} 礼物币\n${plan.benefits.join(' · ')}',
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: _busyId == null
                                    ? () => _buyMembership(plan)
                                    : null,
                                child: Text(_busyId == plan.id ? '处理中…' : '开通'),
                              ),
                            ),
                          ),
                        )
                  else if (_section == 1)
                    if (snapshot.decorations.isEmpty)
                      const _CommerceInfoBanner(text: '当前没有可用装扮。')
                    else
                      for (final DecorationItem item in snapshot.decorations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              leading: const CircleAvatar(
                                child: Icon(Icons.auto_awesome_outlined),
                              ),
                              title: Row(
                                children: <Widget>[
                                  Expanded(child: Text(item.name)),
                                  _CommercePill(label: item.kind.label),
                                ],
                              ),
                              subtitle: Text(
                                item.owned
                                    ? (item.equipped
                                          ? '已拥有 · 当前穿戴'
                                          : '已拥有 · 未穿戴')
                                    : '${item.priceGiftCoins} 礼物币',
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: _busyId == null
                                    ? () => _operateDecoration(item)
                                    : null,
                                child: Text(
                                  _busyId == item.id
                                      ? '处理中…'
                                      : item.owned
                                      ? (item.equipped ? '卸下' : '穿戴')
                                      : '购买',
                                ),
                              ),
                            ),
                          ),
                        )
                  else if (snapshot.backpack.isEmpty)
                    const _CommerceInfoBanner(text: '背包中没有可用礼物或体验卡。')
                  else
                    for (final BackpackGiftItem item in snapshot.backpack)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(item.gift.name),
                        subtitle: Text(
                          item.expiresAt == null
                              ? '长期有效'
                              : '有效期至 ${_formatDateTime(item.expiresAt!)}',
                        ),
                        trailing: Text('×${item.quantity}'),
                      ),
                ],
              ),
            ),
    );
  }
}

class _CommercePill extends StatelessWidget {
  const _CommercePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _CommerceKeyValue extends StatelessWidget {
  const _CommerceKeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

extension _FirstOrNullCommerce<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
