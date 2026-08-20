part of 'commerce_pages.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<PaymentOrder>? _orders;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orders == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final CommercePage<PaymentOrder> page = await AppDependencyScope.of(
        context,
      ).commerceRepository.fetchOrders(page: 1, pageSize: 50);
      if (mounted) {
        setState(() {
          _orders = page.items;
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
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final PaymentOrder order = _orders![index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '¥${order.amount.toStringAsFixed(2)} · ${order.giftCoinAmount} 礼物币',
                  ),
                  subtitle: Text(
                    '${order.channelName} · ${_formatDateTime(order.createdAt)}\n订单号 ${order.orderNo}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(_orderStatusLabel(order.status)),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          const SizedBox(height: 18),
          _CommerceDetail(
            label: '实付金额',
            value: '¥${_order.amount.toStringAsFixed(2)}',
          ),
          _CommerceDetail(label: '礼物币', value: '${_order.giftCoinAmount}'),
          _CommerceDetail(label: '支付渠道', value: _order.channelName),
          _CommerceDetail(
            label: '创建时间',
            value: _formatDateTime(_order.createdAt),
          ),
          _CommerceDetail(label: '订单号', value: _order.orderNo),
          const SizedBox(height: 8),
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
          const SizedBox(height: 14),
          const _CommerceInfoBanner(text: '补单核验只查询服务端权威订单状态，不会在客户端自行把订单改成成功。'),
        ],
      ),
    );
  }
}
