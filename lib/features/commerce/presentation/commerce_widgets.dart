part of 'commerce_pages.dart';

class _CommerceScaffold extends StatelessWidget {
  const _CommerceScaffold({
    required this.body,
    this.appBar,
    this.floatingActionButton,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const IgnorePointer(
            child: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 230,
                height: 210,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.05,
                      colors: <Color>[
                        Color(0x6678E5FF),
                        Color(0x249A82FF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

class _CommercePanel extends StatelessWidget {
  const _CommercePanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFF1EEFF).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: radius,
        border: Border.all(
          color: selected ? const Color(0xFF7866F2) : const Color(0x147866F2),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C2D1A70),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CommerceSectionTitle extends StatelessWidget {
  const _CommerceSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF55CFFF), Color(0xFF8B63F6)],
            ),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _CommerceAssetOrb extends StatelessWidget {
  const _CommerceAssetOrb({
    required this.icon,
    this.size = 44,
    this.asset,
    this.colors = const <Color>[Color(0xFFE4F9FF), Color(0xFFF4E9FF)],
  });

  final IconData icon;
  final double size;
  final String? asset;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x207866F2), blurRadius: 12),
        ],
      ),
      child: asset == null
          ? Icon(icon, color: const Color(0xFF6D59DF), size: size * 0.5)
          : Image.asset(asset!, fit: BoxFit.contain),
    );
  }
}

class _GiftBalanceBanner extends StatelessWidget {
  const _GiftBalanceBanner({required this.balance});

  final int? balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF6456D9), Color(0xFFE34EC4)],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x356A43CE), blurRadius: 18),
        ],
      ),
      child: Row(
        children: <Widget>[
          const _CommerceAssetOrb(
            icon: Icons.redeem_rounded,
            asset: 'assets/runtime/gift-blossom.png',
            size: 46,
            colors: <Color>[Color(0x33FFFFFF), Color(0x22FFFFFF)],
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '普通礼物图鉴',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '送礼时将在房间底部连续展开',
                  style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            balance == null ? '余额 —' : '余额 $balance',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSummaryCard extends StatelessWidget {
  const _WalletSummaryCard({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    final String? fontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.room(fontFamily: fontFamily),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF27306D),
              Color(0xFF4A3184),
              Color(0xFF7A4BA2),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x382A1C72),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const _CommerceAssetOrb(
                  icon: Icons.diamond_rounded,
                  size: 38,
                  colors: <Color>[Color(0xFFFFE89D), Color(0xFFFF9ED3)],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '礼物币账户',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '用于礼物与装扮消费',
                        style: const TextStyle(
                          color: Color(0xCFFFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '安全账户',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  wallet.giftCoinBalance == null
                      ? '读取中'
                      : '${wallet.giftCoinBalance}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    '礼物币',
                    style: TextStyle(color: Color(0xD9FFFFFF)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  _SummaryMetric(
                    label: '可提现',
                    value: '¥${wallet.cashBalance.toStringAsFixed(2)}',
                    onDark: true,
                  ),
                  _SummaryMetric(
                    label: '冻结',
                    value: '¥${wallet.frozenBalance.toStringAsFixed(2)}',
                    onDark: true,
                  ),
                  _SummaryMetric(
                    label: '累计收益',
                    value: '¥${wallet.totalEarnings.toStringAsFixed(2)}',
                    onDark: true,
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

class _EarningsSummary extends StatelessWidget {
  const _EarningsSummary({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    return _CommercePanel(
      padding: const EdgeInsets.all(18),
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
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.onDark = false,
  });

  final String label;
  final String value;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: onDark ? const Color(0xCFFFFFFF) : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: onDark ? Colors.white : null,
              fontSize: onDark ? 13 : null,
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommercePanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            _CommerceAssetOrb(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _CommerceShortcut extends StatelessWidget {
  const _CommerceShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    this.asset,
  });

  final IconData icon;
  final String label;
  final String? asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _CommercePanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(
          children: <Widget>[
            _CommerceAssetOrb(icon: icon, asset: asset, size: 46),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
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
    return _CommercePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          _CommerceAssetOrb(icon: icon, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xDDEDFBFF), Color(0xDDF3ECFF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x247866F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFF6E5ADE),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
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
  RefundStatus.reviewing ||
  RefundStatus.resubmitted => Icons.hourglass_top_rounded,
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
