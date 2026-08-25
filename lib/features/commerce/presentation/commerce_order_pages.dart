part of 'commerce_pages.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({this.initialOrderNo, super.key});

  /// When present, the page is opened from a notification and must resolve
  /// this exact server order before showing its detail page.
  final String? initialOrderNo;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<PaymentOrder>? _orders;
  String? _error;
  bool _initialOrderOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orders == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final String? targetOrderNo = _targetOrderNo;
    final CommerceRepository repository = AppDependencyScope.of(
      context,
    ).commerceRepository;
    try {
      CommercePage<PaymentOrder> page = await repository.fetchOrders(
        page: 1,
        pageSize: 50,
      );
      final List<PaymentOrder> orders = <PaymentOrder>[...page.items];
      PaymentOrder? targetOrder;
      if (targetOrderNo != null) {
        targetOrder = _findOrder(orders, targetOrderNo);
        while (targetOrder == null && page.hasMore) {
          final int nextPage = page.page + 1;
          final CommercePage<PaymentOrder> next = await repository.fetchOrders(
            page: nextPage,
            pageSize: 50,
          );
          if (next.page <= page.page) {
            break;
          }
          page = next;
          orders.addAll(next.items);
          targetOrder = _findOrder(orders, targetOrderNo);
        }
      }
      if (mounted) {
        if (targetOrderNo != null && targetOrder == null) {
          setState(() {
            _orders = null;
            _error = '订单 ${_targetOrderLabel} 不存在或不可访问';
          });
          return;
        }
        setState(() {
          _orders = orders;
          _error = null;
        });
        if (targetOrder != null) {
          _openInitialOrder(targetOrder);
        }
      }
    } catch (error) {
      if (mounted) {
        final String message = _messageFor(error);
        setState(
          () => _error = targetOrderNo == null
              ? message
              : '订单 $_targetOrderLabel 加载失败：$message',
        );
      }
    }
  }

  String? get _targetOrderNo {
    final String? raw = widget.initialOrderNo;
    return raw == null ? null : raw.trim();
  }

  String get _targetOrderLabel {
    final String? targetOrderNo = _targetOrderNo;
    return targetOrderNo == null || targetOrderNo.isEmpty
        ? '（订单号为空）'
        : targetOrderNo;
  }

  static PaymentOrder? _findOrder(
    Iterable<PaymentOrder> orders,
    String orderNo,
  ) {
    for (final PaymentOrder order in orders) {
      if (order.orderNo == orderNo) {
        return order;
      }
    }
    return null;
  }

  void _openInitialOrder(PaymentOrder order) {
    if (_initialOrderOpened || !mounted) {
      return;
    }
    _initialOrderOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => OrderDetailPage(order: order),
        ),
      );
      if (mounted) {
        await _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
      appBar: AppBar(
        title: const Text('订单列表'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _orders == null ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _orders == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _CommerceErrorState(message: _error!, onRetry: _load)
          : _orders!.isEmpty
          ? const Center(child: Text('暂无充值订单'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _orders!.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (BuildContext context, int index) {
                final PaymentOrder order = _orders![index];
                return _CommercePanel(
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            OrderDetailPage(order: order),
                      ),
                    );
                    if (mounted) {
                      await _load();
                    }
                  },
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: <Widget>[
                      const _CommerceAssetOrb(
                        icon: Icons.receipt_long_rounded,
                        size: 44,
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
                                    '¥${order.amount.toStringAsFixed(2)} · ${order.giftCoinAmount} 礼物币',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                _CommercePill(
                                  label: _orderStatusLabel(order.status),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${order.channelName} · ${_formatDateTime(order.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '订单号 ${order.orderNo}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 20),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({required this.order, super.key});

  final PaymentOrder order;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late PaymentOrder _order;
  bool _refreshing = false;
  bool _openingRefund = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _refreshStatus() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final PaymentOrder updated = await AppDependencyScope.of(
        context,
      ).commerceRepository.queryOrderStatus(_order);
      if (mounted) {
        setState(() => _order = updated);
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

  Future<void> _copyOrderNo() async {
    await Clipboard.setData(ClipboardData(text: _order.orderNo));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('订单号已复制')));
    }
  }

  Future<void> _openRefund() async {
    if (_openingRefund) {
      return;
    }
    final CommerceRepository repository = AppDependencyScope.of(
      context,
    ).commerceRepository;
    if (repository.refundScope != RefundScope.order) {
      return;
    }
    setState(() => _openingRefund = true);
    try {
      final RefundEligibility eligibility = await repository
          .checkRefundEligibility(_order.orderNo);
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
          builder: (BuildContext context) =>
              RefundApplicationPage(order: _order),
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
        setState(() => _openingRefund = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CommerceScaffold(
      appBar: AppBar(title: const Text('订单详情与补单')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _CommerceStatusCard(
            icon: _order.status == PaymentOrderStatus.succeeded
                ? Icons.check_circle_rounded
                : Icons.receipt_long_outlined,
            title: _orderStatusLabel(_order.status),
            description: '支付结果始终以服务端订单状态为准。',
          ),
          const SizedBox(height: 14),
          _CommercePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                _CommerceDetail(
                  label: '实付金额',
                  value: '¥${_order.amount.toStringAsFixed(2)}',
                ),
                _CommerceDetail(
                  label: '礼物币',
                  value: '${_order.giftCoinAmount}',
                ),
                _CommerceDetail(label: '支付渠道', value: _order.channelName),
                _CommerceDetail(
                  label: '创建时间',
                  value: _formatDateTime(_order.createdAt),
                ),
                _CommerceDetail(label: '订单号', value: _order.orderNo),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _copyOrderNo,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制订单号'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _refreshing ? null : _refreshStatus,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: const Text('刷新并补单核验'),
          ),
          if (AppDependencyScope.of(context).commerceRepository.refundScope ==
                  RefundScope.order &&
              _order.status == PaymentOrderStatus.succeeded) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openingRefund ? null : _openRefund,
              icon: _openingRefund
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_return_outlined),
              label: const Text('申请退款'),
            ),
            const SizedBox(height: 8),
            const Text(
              '是否可退款以服务端订单校验为准。退款申请只提交订单号和原因，退款金额由服务端根据订单核验。',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          const _CommerceInfoBanner(text: '补单核验只查询服务端权威订单状态，不会在客户端自行把订单改成成功。'),
        ],
      ),
    );
  }
}
