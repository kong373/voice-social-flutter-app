part of 'commerce_pages.dart';

class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2A2255), Color(0xFF171A34)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('礼物币余额', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            wallet.giftCoinBalance == null ? '读取中' : '${wallet.giftCoinBalance}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _SummaryMetric(label: '可提现', value: '¥${wallet.cashBalance.toStringAsFixed(2)}'),
              _SummaryMetric(label: '冻结', value: '¥${wallet.frozenBalance.toStringAsFixed(2)}'),
              _SummaryMetric(label: '累计收益', value: '¥${wallet.totalEarnings.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '礼物币余额、主播现金收益和可提现余额是不同账户口径，不会混合展示。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _EarningsSummary extends StatelessWidget {
  const _EarningsSummary({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('累计收益', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(
            '¥${wallet.totalEarnings.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _SummaryMetric(
                label: '昨日收益',
                value: '¥${wallet.yesterdayEarnings.toStringAsFixed(2)}',
              ),
              _SummaryMetric(
                label: '已提现',
                value: '¥${wallet.totalWithdrawn.toStringAsFixed(2)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CommerceEntry extends StatelessWidget {
  const _CommerceEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _CommerceStatusCard extends StatelessWidget {
  const _CommerceStatusCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 36, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommerceDetail extends StatelessWidget {
  const _CommerceDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value.isEmpty ? '暂无' : value)),
        ],
      ),
    );
  }
}

class _CommerceInfoBanner extends StatelessWidget {
  const _CommerceInfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _CommerceErrorState extends StatelessWidget {
  const _CommerceErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _orderStatusLabel(PaymentOrderStatus status) => switch (status) {
      PaymentOrderStatus.pending => '待支付',
      PaymentOrderStatus.confirming => '服务端确认中',
      PaymentOrderStatus.succeeded => '支付成功',
      PaymentOrderStatus.failed => '支付失败',
      PaymentOrderStatus.canceled => '已取消',
      PaymentOrderStatus.unknown => '状态待核验',
    };

IconData _refundIcon(RefundStatus status) => switch (status) {
      RefundStatus.approved => Icons.check_circle_rounded,
      RefundStatus.rejected => Icons.cancel_rounded,
      RefundStatus.reviewing || RefundStatus.resubmitted => Icons.hourglass_top_rounded,
      RefundStatus.unavailable => Icons.block_rounded,
    };

String _formatDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';
