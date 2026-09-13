part of 'commerce_pages.dart';

class RechargeCatalogPage extends StatefulWidget {
  const RechargeCatalogPage({super.key});

  @override
  State<RechargeCatalogPage> createState() => _RechargeCatalogPageState();
}

class _RechargeCatalogPageState extends State<RechargeCatalogPage>
    with CommerceIdentityFence<RechargeCatalogPage> {
  @override
  CommerceRepository get commerceIdentityRepository =>
      AppDependencyScope.of(context).commerceRepository;
  @override
  void clearCommerceIdentity() {
    _wallet = null;
    _products = null;
    _selected = null;
    _compliance = null;
    _loading = false;
    _error = '请登录后充值';
  }

  @override
  Future<void> reloadCommerceIdentity() => _load();

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

  bool get _paymentAvailable => AppDependencyScope.of(
    context,
  ).commerceCatalogRepository.supportsPaymentChannelInvocation;

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
    final ticket = beginCommerceRead();
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchRechargeProducts(platform: _platform),
        dependencies.commerceRepository.fetchWalletSummary(),
        dependencies.accountComplianceRepository.fetchSnapshot(
          account: account,
          expectedUserId: dependencies.sessionManager.session?.userId,
          currentVersion: currentVersion,
          platformType: platformType,
        ),
      ]);
      if (!acceptsCommerceRead(ticket)) {
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
      if (acceptsCommerceRead(ticket)) {
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
    final ticket = beginCommerceRead();
    final RechargeEligibility eligibility = await _repository
        .checkRechargeEligibility(
          youthModeEnabled: compliance.youthModeEnabled,
        );
    if (!mounted || !acceptsCommerceRead(ticket)) {
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
    if (mounted && acceptsCommerceRead(ticket)) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
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
                  _CommercePanel(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: <Widget>[
                        const _CommerceAssetOrb(
                          icon: Icons.diamond_rounded,
                          size: 48,
                          colors: <Color>[Color(0xFFFFE88B), Color(0xFFFFB1DA)],
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '当前礼物币余额',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: SocialColors.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _wallet?.giftCoinText ?? '以服务端为准',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(color: SocialColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        _CommercePill(
                          label: _platform == ClientStorePlatform.ios
                              ? 'iOS'
                              : 'Android',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_compliance?.youthModeEnabled == true)
                    const _CommerceInfoBanner(
                      text: '青少年模式已开启，请先使用自己设置的 4 位密码解锁后再操作 App。',
                    ),
                  const SizedBox(height: 18),
                  const _CommerceSectionTitle(title: '选择充值档位'),
                  const SizedBox(height: 10),
                  if (_products == null || _products!.isEmpty)
                    const _CommerceInfoBanner(text: '当前没有可用充值商品，请稍后刷新。')
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _products!.map((RechargeProduct product) {
                          final bool selected = _selected?.id == product.id;
                          // Keep two columns, but allow scaled text to determine
                          // card height instead of clipping a fixed grid extent.
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: (constraints.maxWidth - 10) / 2,
                              maxWidth: (constraints.maxWidth - 10) / 2,
                              minHeight: 138,
                            ),
                            child: _CommercePanel(
                              selected: selected,
                              onTap: product.enabled
                                  ? () => setState(() => _selected = product)
                                  : null,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      const _CommerceAssetOrb(
                                        icon: Icons.diamond_rounded,
                                        size: 32,
                                      ),
                                      const Spacer(),
                                      if (product.recommended)
                                        const _CommercePill(label: '推荐'),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    '${product.totalGiftCoins} 礼物币',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Expanded(
                                        child: FittedBox(
                                          alignment: Alignment.centerLeft,
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            product.storeDisplayPrice ??
                                                '¥${product.priceCny.toStringAsFixed(product.priceCny % 1 == 0 ? 0 : 2)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(fontSize: 18),
                                          ),
                                        ),
                                      ),
                                      if (product.bonusGiftCoins >
                                          0) ...<Widget>[
                                        const SizedBox(width: 6),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 1,
                                          ),
                                          child: Text(
                                            '+${product.bonusGiftCoins}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors.secondary,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (_paymentAvailable)
                    FilledButton(
                      onPressed:
                          _selected == null ||
                              _compliance?.youthModeEnabled == true
                          ? null
                          : _continue,
                      child: const Text('选择支付方式'),
                    )
                  else
                    const _CommerceInfoBanner(
                      text: '当前充值暂不可用，可以查看商品和礼物币档位。请稍后再试。',
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

typedef _PaymentIdentity = (int?, int);

/// Binds a payment page to the existing account identity generation.
///
/// Access-token rotation creates a new AuthSession object but keeps the same
/// `(userId, identityGeneration)` tuple, so a normal refresh does not discard
/// an in-flight page. Logout/account changes increment the existing
/// generation and invalidate this fence.
class _PaymentAuthIdentityFence {
  _PaymentAuthIdentityFence(this._dependencies, this._onInvalidated)
    : _identity = _currentIdentity(_dependencies) {
    _dependencies.sessionManager.addListener(_changed);
    _dependencies.authController.addListener(_changed);
    if (_dependencies.authController.signingOut) {
      _invalidate();
    }
  }

  final AppDependencies _dependencies;
  final VoidCallback _onInvalidated;
  final _PaymentIdentity _identity;
  bool _invalidated = false;

  bool get isCurrent =>
      !_invalidated &&
      !_dependencies.authController.signingOut &&
      _identity == _currentIdentity(_dependencies);

  static _PaymentIdentity _currentIdentity(AppDependencies dependencies) => (
    dependencies.sessionManager.session?.userId,
    dependencies.sessionManager.identityGeneration,
  );

  void _changed() {
    if (!_invalidated && !isCurrent) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (_invalidated) {
      return;
    }
    _invalidated = true;
    _onInvalidated();
  }

  void dispose() {
    _dependencies.sessionManager.removeListener(_changed);
    _dependencies.authController.removeListener(_changed);
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
  bool _identityLost = false;
  _PaymentAuthIdentityFence? _identityFence;

  CommerceCatalogRepository get _repository =>
      AppDependencyScope.of(context).commerceCatalogRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _identityFence ??= _PaymentAuthIdentityFence(
      AppDependencyScope.of(context),
      _handleIdentityInvalidated,
    );
    if (_repository.supportsPaymentChannelInvocation) {
      _channel ??= _repository.availableChannels(widget.platform).firstOrNull;
    }
  }

  void _handleIdentityInvalidated() {
    if (!mounted) {
      return;
    }
    setState(() {
      _identityLost = true;
      _submitting = false;
    });
  }

  bool _acceptsIdentity(_PaymentAuthIdentityFence fence) =>
      mounted &&
      !_identityLost &&
      identical(fence, _identityFence) &&
      fence.isCurrent;

  Future<void> _submit() async {
    final PaymentChannelType? channel = _channel;
    final _PaymentAuthIdentityFence? identityFence = _identityFence;
    if (!_repository.supportsPaymentChannelInvocation ||
        channel == null ||
        _submitting ||
        identityFence == null ||
        !_acceptsIdentity(identityFence)) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认充值信息'),
        content: Text(
          '充值 ${widget.product.totalGiftCoins} 礼物币，实付 ${widget.product.storeDisplayPrice ?? '¥${widget.product.priceCny.toStringAsFixed(2)}'}，支付方式为 ${channel.label}。',
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
    if (confirmed != true || !mounted || !_acceptsIdentity(identityFence)) {
      return;
    }
    setState(() => _submitting = true);
    RechargeOrder? createdOrder;
    try {
      if (!mounted || !_acceptsIdentity(identityFence)) {
        return;
      }
      final String account =
          AppDependencyScope.of(context).sessionManager.session?.mobile ?? '';
      RechargeOrder order = await _repository.createRechargeOrder(
        account: account,
        product: widget.product,
        channel: channel,
        platform: widget.platform,
        youthModeEnabled: widget.youthModeEnabled,
      );
      if (!mounted || !_acceptsIdentity(identityFence)) {
        return;
      }
      createdOrder = order;
      if (_repository.supportsPaymentChannelInvocation) {
        if (!_acceptsIdentity(identityFence)) {
          return;
        }
        order = await _repository.invokePayment(order);
      }
      if (!mounted || !_acceptsIdentity(identityFence)) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PaymentResultPage(order: order),
        ),
      );
      if (mounted && _acceptsIdentity(identityFence)) {
        Navigator.of(context).pop<void>();
      }
    } catch (error) {
      if (mounted && _acceptsIdentity(identityFence)) {
        final RechargeOrder? pendingOrder = createdOrder;
        if (channel == PaymentChannelType.appleIap && pendingOrder != null) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PaymentResultPage(
                order: pendingOrder.copyWith(
                  state: RechargeOrderState.confirming,
                  message: 'Apple 购买结果尚未确认，请刷新订单，不要重复购买',
                ),
              ),
            ),
          );
          if (mounted && _acceptsIdentity(identityFence)) {
            Navigator.of(context).pop<void>();
          }
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (_acceptsIdentity(identityFence)) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _identityFence?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_identityLost) {
      return _CommerceScaffold(
        appBar: AppBar(title: const Text('支付方式与提交')),
        body: const Center(child: Text('登录身份已失效，请重新登录')),
      );
    }
    final bool paymentAvailable = _repository.supportsPaymentChannelInvocation;
    final List<PaymentChannelType> channels = paymentAvailable
        ? _repository.availableChannels(widget.platform)
        : const <PaymentChannelType>[];
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('支付方式与提交')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _CommercePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    _CommerceAssetOrb(
                      icon: Icons.receipt_long_rounded,
                      size: 38,
                    ),
                    SizedBox(width: 10),
                    Expanded(child: _CommerceSectionTitle(title: '订单确认')),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 6),
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
                  value:
                      widget.product.storeDisplayPrice ??
                      '¥${widget.product.priceCny.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),
          if (paymentAvailable) ...<Widget>[
            const SizedBox(height: 20),
            const _CommerceSectionTitle(title: '选择支付方式'),
            const SizedBox(height: 10),
            for (final PaymentChannelType channel in channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CommercePanel(
                  selected: _channel == channel,
                  padding: EdgeInsets.zero,
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
                    secondary: _CommerceAssetOrb(
                      icon: channel == PaymentChannelType.wechat
                          ? Icons.chat_bubble_rounded
                          : channel == PaymentChannelType.alipay
                          ? Icons.account_balance_wallet_rounded
                          : Icons.apple_rounded,
                      size: 40,
                    ),
                    title: Text(channel.label),
                    subtitle: Text(
                      channel == PaymentChannelType.appleIap
                          ? '由 Apple IAP 完成购买与收据校验'
                          : '支付结果需等待服务端订单确认',
                    ),
                  ),
                ),
              ),
          ] else
            const _CommerceInfoBanner(text: '当前支付暂不可用，可以查看订单摘要。请稍后再试。'),
          if (paymentAvailable) ...<Widget>[
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
          ],
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
  bool _identityLost = false;
  _PaymentAuthIdentityFence? _identityFence;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _identityFence ??= _PaymentAuthIdentityFence(
      AppDependencyScope.of(context),
      _handleIdentityInvalidated,
    );
  }

  void _handleIdentityInvalidated() {
    if (!mounted) {
      return;
    }
    setState(() {
      _identityLost = true;
      _refreshing = false;
      _error = null;
    });
  }

  bool _acceptsIdentity(_PaymentAuthIdentityFence fence) =>
      mounted &&
      !_identityLost &&
      identical(fence, _identityFence) &&
      fence.isCurrent;

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
    final _PaymentAuthIdentityFence? identityFence = _identityFence;
    if (_refreshing ||
        identityFence == null ||
        !_acceptsIdentity(identityFence)) {
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      if (!_acceptsIdentity(identityFence)) {
        return;
      }
      final RechargeOrder value = await AppDependencyScope.of(
        context,
      ).commerceCatalogRepository.queryRechargeOrder(_order);
      if (_acceptsIdentity(identityFence)) {
        setState(() => _order = value);
      }
    } catch (error) {
      if (_acceptsIdentity(identityFence)) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (_acceptsIdentity(identityFence)) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  void dispose() {
    _identityFence?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_identityLost) {
      return _CommerceScaffold(
        appBar: AppBar(title: const Text('支付返回与结果')),
        body: const Center(child: Text('登录身份已失效，请重新登录')),
      );
    }
    final bool success = _order.state == RechargeOrderState.succeeded;
    final bool terminal =
        success ||
        _order.state == RechargeOrderState.failed ||
        _order.state == RechargeOrderState.canceled;
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('支付返回与结果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 28),
        children: <Widget>[
          _CommercePanel(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
            child: Column(
              children: <Widget>[
                _CommerceAssetOrb(
                  icon: success
                      ? Icons.check_rounded
                      : terminal
                      ? Icons.close_rounded
                      : Icons.hourglass_top_rounded,
                  size: 70,
                  colors: success
                      ? const <Color>[Color(0xFFD7FFF0), Color(0xFFDDF7FF)]
                      : terminal
                      ? const <Color>[Color(0xFFFFE4EA), Color(0xFFFFF1DE)]
                      : const <Color>[Color(0xFFFFF1C9), Color(0xFFF1E7FF)],
                ),
                const SizedBox(height: 15),
                Text(
                  _order.state.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _order.message.isEmpty ? '订单结果以服务端状态为准' : _order.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CommercePanel(
            padding: const EdgeInsets.all(16),
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
                  value:
                      _order.product.storeDisplayPrice ??
                      '¥${_order.product.priceCny.toStringAsFixed(2)}',
                ),
              ],
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
  const GiftCatalogPage({this.initialGifts, super.key});

  /// Explicit deterministic data for the QA page catalog. Ordinary app routes
  /// leave this null and always load the backend-owned gift categories.
  final List<GiftCatalogItem>? initialGifts;

  @override
  State<GiftCatalogPage> createState() => _GiftCatalogPageState();
}

class _GiftCatalogPageState extends State<GiftCatalogPage>
    with CommerceIdentityFence<GiftCatalogPage> {
  @override
  CommerceRepository get commerceIdentityRepository =>
      AppDependencyScope.of(context).commerceRepository;
  @override
  void clearCommerceIdentity() {
    _wallet = null;
    _gifts = null;
    _loading = false;
    _error = '请登录后查看礼物';
  }

  @override
  Future<void> reloadCommerceIdentity() => _load();

  List<GiftCatalogItem>? _gifts;
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
    final ticket = beginCommerceRead();
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        if (widget.initialGifts == null)
          dependencies.commerceCatalogRepository.fetchGiftCatalog()
        else
          Future<List<GiftCatalogItem>>.value(widget.initialGifts),
        dependencies.commerceRepository.fetchWalletSummary(),
      ]);
      if (acceptsCommerceRead(ticket)) {
        setState(() {
          _gifts = result[0] as List<GiftCatalogItem>;
          _wallet = result[1] as WalletSummary;
          _loading = false;
        });
      }
    } catch (error) {
      if (acceptsCommerceRead(ticket)) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<GiftCatalogItem> gifts = _gifts ?? const <GiftCatalogItem>[];
    final List<GiftCatalogItem> visible = filterGiftCatalogItems(
      gifts: gifts,
      category: _category,
    );
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('礼物图鉴')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  _GiftBalanceBanner(balance: _wallet?.giftCoinText),
                  const SizedBox(height: 12),
                  _CommercePanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: <Widget>[
                        for (final String asset in const <String>[
                          'assets/runtime/avatar-rose.png',
                          'assets/runtime/avatar-night.png',
                          'assets/runtime/avatar-copper.png',
                        ]) ...<Widget>[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFECE8FF),
                            backgroundImage: AssetImage(asset),
                          ),
                          const SizedBox(width: 5),
                        ],
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '进入房间后选择麦上用户送礼',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: SocialColors.textSecondary),
                          ),
                        ),
                        const _CommercePill(label: '房间内送出'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final GiftCatalogItem gift = visible[index];
                        final String asset =
                            builtInGiftCatalogAsset(gift.assetUrl) ??
                            switch (_giftAssetIndex(gift.id)) {
                              0 => 'assets/runtime/gift-blossom.png',
                              1 => 'assets/runtime/gift-whale.png',
                              2 => 'assets/runtime/gift-ticket.png',
                              _ => 'assets/runtime/gift-celebration-banner.png',
                            };
                        return _CommercePanel(
                          padding: const EdgeInsets.fromLTRB(5, 9, 5, 7),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Expanded(
                                child: Image.asset(asset, fit: BoxFit.contain),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gift.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const Icon(
                                    Icons.circle,
                                    size: 7,
                                    color: Color(0xFFFFC84E),
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      '${gift.price}',
                                      maxLines: 1,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 14),
                  const _CommerceInfoBanner(
                    text: '这里只展示普通礼物。实际赠送必须在语音房内选择麦上用户，礼物面板会保留当前房间上下文。',
                  ),
                ],
              ),
            ),
    );
  }
}

/// Applies the backend-owned category to the catalog tab. The grid remains a
/// four-column layout; the popular tab must not show arbitrary first records.
List<GiftCatalogItem> filterGiftCatalogItems({
  required List<GiftCatalogItem> gifts,
  required GiftCatalogCategory category,
}) => gifts
    .where((GiftCatalogItem item) => item.category == category)
    .toList(growable: false);

int _giftAssetIndex(String giftId) => giftId.codeUnits.fold<int>(
  0,
  (int value, int codeUnit) => (value + codeUnit) % 4,
);

class DecorationPage extends StatefulWidget {
  const DecorationPage({this.repository, super.key});

  @visibleForTesting
  final CommerceCatalogRepository? repository;

  @override
  State<DecorationPage> createState() => _DecorationPageState();
}

class _DecorationPageState extends State<DecorationPage> {
  List<DecorationItem>? _decorations;
  DecorationKind? _filter;
  String? _busyId;
  bool _loading = true;
  String? _error;
  AppDependencies? _dependencies;
  (int?, int)? _identity;
  int _readEpoch = 0;
  int _operationEpoch = 0;
  DialogRoute<bool>? _dialog;
  final Map<String, DecorationItem> _unknownPurchases = {};

  CommerceCatalogRepository get _repository =>
      widget.repository ?? _dependencies!.commerceCatalogRepository;

  (int?, int) get _currentIdentity => (
    _dependencies!.sessionManager.session?.userId,
    _dependencies!.sessionManager.identityGeneration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependencyScope.of(context);
    if (!identical(_dependencies, dependencies)) {
      _dependencies?.sessionManager.removeListener(_identityChanged);
      _dependencies = dependencies;
      _identity = _currentIdentity;
      dependencies.sessionManager.addListener(_identityChanged);
      _clearIdentity();
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant DecorationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _clearIdentity();
      _load();
    }
  }

  void _closeDialog() {
    final route = _dialog;
    _dialog = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive)
        navigator.removeRoute(route);
    });
  }

  void _clearIdentity() {
    _readEpoch++;
    _operationEpoch++;
    _decorations = null;
    _busyId = null;
    _unknownPurchases.clear();
    _error = null;
    _closeDialog();
  }

  void _identityChanged() {
    if (!mounted || _identity == _currentIdentity) return;
    _identity = _currentIdentity;
    setState(_clearIdentity);
    _load();
  }

  @override
  void dispose() {
    _readEpoch++;
    _operationEpoch++;
    _dependencies?.sessionManager.removeListener(_identityChanged);
    _closeDialog();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = _currentIdentity;
    final epoch = ++_readEpoch;
    final repository = _repository;
    bool accepts() =>
        mounted &&
        epoch == _readEpoch &&
        identity == _currentIdentity &&
        identical(repository, _repository);
    if (_dependencies!.environment.isLive &&
        (identity.$1 == null || identity.$1! <= 0)) {
      setState(() {
        _loading = false;
        _error = '请登录后查看装扮';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<DecorationItem> result = await repository.fetchDecorations();
      if (!accepts()) return;
      setState(() {
        final returnedIds = result.map((item) => item.id).toSet();
        _decorations = [
          ...result,
          for (final intent in _unknownPurchases.values)
            if (!returnedIds.contains(intent.id))
              intent.copyWith(owned: false, equipped: false, forSale: false),
        ];
        _loading = false;
      });
    } catch (error) {
      if (accepts()) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<bool> _confirm(
    String title,
    Widget content, {
    required bool Function() isCurrent,
    bool preview = false,
  }) async {
    final route = DialogRoute<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(preview ? '关闭' : '取消'),
          ),
          if (!preview)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(isCurrent()),
              child: const Text('确认'),
            ),
        ],
      ),
    );
    _dialog = route;
    final result = await Navigator.of(context).push<bool>(route);
    if (identical(_dialog, route)) _dialog = null;
    return result == true && isCurrent();
  }

  Future<void> _previewDecoration(DecorationItem item) async {
    if (_dialog != null) return;
    final identity = _currentIdentity;
    final epoch = _operationEpoch;
    await _confirm(
      '${item.name} · 仅预览',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecorationPreview(
            item: item,
            size: 180,
            allowMockAssetPaths: !_dependencies!.environment.isLive,
          ),
          const SizedBox(height: 12),
          const Text('仅查看商品素材，不试用、不穿戴、不扣币。'),
        ],
      ),
      preview: true,
      isCurrent: () =>
          mounted && epoch == _operationEpoch && identity == _currentIdentity,
    );
  }

  Future<void> _operateDecoration(
    DecorationItem selected, {
    bool purchase = false,
  }) async {
    if (_busyId != null || _dialog != null) return;
    final item = _unknownPurchases[selected.id] ?? selected;
    final buying =
        purchase || !item.owned || _unknownPurchases.containsKey(item.id);
    if (buying && !item.canPurchase) return;
    final renewing = item.owned || item.expiresAt != null;
    final retrying = _unknownPurchases.containsKey(item.id);
    final identity = _currentIdentity;
    final epoch = ++_operationEpoch;
    final repository = _repository;
    bool accepts() =>
        mounted &&
        epoch == _operationEpoch &&
        identity == _currentIdentity &&
        identical(repository, _repository);
    setState(() => _busyId = item.id);
    try {
      if (buying) {
        final confirmed = await _confirm(
          '${retrying ? '重试原' : ''}${renewing ? '续购' : '购买'}${item.name}？',
          Text(
            '${renewing ? '续购' : '购买'} ${item.durationDays} 天，将扣除 ${item.priceGiftCoins} 礼物币。${renewing ? '从原到期时间或服务端当前时间中较晚者延长，保留有效穿戴；已过期不自动穿戴。' : ''}${retrying ? '沿用原请求，不另建购买。' : ''}最终到期与余额以服务端记录为准。',
          ),
          isCurrent: accepts,
        );
        if (!confirmed || !accepts()) return;
        _unknownPurchases[item.id] = item;
        await repository.purchaseDecoration(item.id);
        if (!accepts()) return;
        _unknownPurchases.remove(item.id);
      } else {
        await repository.setDecorationEquipped(
          decorationId: item.id,
          equipped: !item.equipped,
        );
      }
      if (accepts()) {
        await _load();
      }
    } catch (error) {
      if (mounted && accepts()) {
        if (buying && !shouldRetainDecorationPurchaseRequest(error))
          _unknownPurchases.remove(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              buying && _unknownPurchases.containsKey(item.id)
                  ? '购买结果尚未确认，请重试原操作。${_messageFor(error)}'
                  : _messageFor(error),
            ),
          ),
        );
      }
    } finally {
      if (accepts()) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DecorationItem> decorations =
        _decorations ?? const <DecorationItem>[];
    final List<DecorationItem> visible = decorations
        .where((DecorationItem item) => _filter == null || item.kind == _filter)
        .toList(growable: false);
    final int ownedCount = decorations
        .where((DecorationItem item) => item.owned)
        .length;
    final int equippedCount = decorations
        .where((DecorationItem item) => item.equipped)
        .length;
    return _CommerceScaffold(
      appBar: AppBar(
        title: const Text(
          '装扮中心',
          style: TextStyle(
            color: SocialColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CommerceErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  _CommercePanel(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: <Widget>[
                        const _CommerceAssetOrb(
                          icon: Icons.auto_awesome_rounded,
                          asset: 'assets/runtime/avatar-rose.png',
                          size: 58,
                          colors: <Color>[Color(0xFFDFF8FF), Color(0xFFFFE1F3)],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                '个性装扮',
                                style: TextStyle(
                                  color: SocialColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '头像框、进场效果与声波样式',
                                style: TextStyle(
                                  color: SocialColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              '已拥有 $ownedCount',
                              style: const TextStyle(
                                color: SocialColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '穿戴中 $equippedCount',
                              style: const TextStyle(
                                color: SocialColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        SocialPill(
                          label: '全部',
                          active: _filter == null,
                          onTap: () => setState(() => _filter = null),
                        ),
                        for (final DecorationKind kind
                            in DecorationKind.values) ...<Widget>[
                          const SizedBox(width: 8),
                          SocialPill(
                            label: kind.label,
                            active: _filter == kind,
                            onTap: () => setState(() => _filter = kind),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    const _CommercePanel(
                      child: Center(child: Text('当前分类没有可用装扮')),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent:
                            250 +
                            9 * MediaQuery.textScalerOf(context).scale(14),
                      ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final DecorationItem item = visible[index];
                        return _CommercePanel(
                          selected: item.equipped,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            children: <Widget>[
                              DecorationPreview(
                                item: item,
                                size: 72,
                                allowMockAssetPaths:
                                    !_dependencies!.environment.isLive,
                              ),
                              TextButton(
                                key: Key('decoration-preview-${item.id}'),
                                onPressed: () => _previewDecoration(item),
                                child: const Text('预览'),
                              ),
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _unknownPurchases.containsKey(item.id)
                                    ? '购买结果待确认'
                                    : item.owned
                                    ? item.equipped
                                          ? '当前穿戴'
                                          : '已拥有'
                                    : item.expiresAt != null
                                    ? '已到期'
                                    : '未拥有',
                                maxLines: 1,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (item.permanent)
                                Text(
                                  '历史永久',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (item.canPurchase)
                                Text(
                                  '${item.durationDays} 天 · ${item.priceGiftCoins} 礼物币',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              if (item.expiresAt != null)
                                Text(
                                  '到期 ${item.expiresAt!.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              const Spacer(),
                              if (item.canPurchase &&
                                  item.owned &&
                                  !_unknownPurchases.containsKey(item.id))
                                SizedBox(
                                  width: double.infinity,
                                  height: 38,
                                  child: OutlinedButton(
                                    key: Key('decoration-renew-${item.id}'),
                                    onPressed: _busyId == null
                                        ? () => _operateDecoration(
                                            item,
                                            purchase: true,
                                          )
                                        : null,
                                    child: const Text('续购'),
                                  ),
                                ),
                              if (item.canPurchase && item.owned)
                                const SizedBox(height: 4),
                              if (item.canPurchase ||
                                  item.owned ||
                                  _unknownPurchases.containsKey(item.id))
                                SizedBox(
                                  width: double.infinity,
                                  height: 38,
                                  child: FilledButton(
                                    key: Key('decoration-action-${item.id}'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(52, 38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: _busyId == null
                                        ? () => _operateDecoration(item)
                                        : null,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _busyId == item.id
                                            ? '处理中…'
                                            : _unknownPurchases.containsKey(
                                                item.id,
                                              )
                                            ? '重试原购买'
                                            : item.owned
                                            ? item.equipped
                                                  ? '卸下'
                                                  : '穿戴'
                                            : item.expiresAt != null
                                            ? '续购'
                                            : '购买',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 4),
                  const _CommerceInfoBanner(
                    text: '同类型仅穿戴一个。仅预览，不提供试用；续购保留有效穿戴，已过期不自动穿戴，结果以服务端记录为准。',
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
