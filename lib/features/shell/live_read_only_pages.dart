import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';

class LiveReadOnlyHomePage extends StatefulWidget {
  const LiveReadOnlyHomePage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LiveReadOnlyHomePage> createState() => _LiveReadOnlyHomePageState();
}

class _LiveReadOnlyHomePageState extends State<LiveReadOnlyHomePage> {
  List<DiscoveryRoom> _rooms = const <DiscoveryRoom>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<DiscoveryRoom> rooms =
          await widget.dependencies.discoveryRepository.fetchHomeRooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '首页快照加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('live-read-only-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '实时后端 · 只读验收',
                    key: const Key('live-home-ready'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '搜索',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const GlobalSearchPage(),
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '登录、首页、搜索与房间快照使用真实接口；RTC、IM 和房间写入在厂商适配器接入前保持关闭。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 18),
            const _StatusBanner(
              icon: Icons.visibility_outlined,
              title: 'HTTP_SNAPSHOT_ONLY',
              description: '进入房间只读取权威快照，不加入 RTC 频道，不建立 IM 连接。',
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorPanel(message: _error!, onRetry: _load)
            else if (_rooms.isEmpty)
              _ErrorPanel(message: '当前没有可展示的房间快照', onRetry: _load)
            else ...<Widget>[
              Text('推荐房间', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final DiscoveryRoom room in _rooms) ...<Widget>[
                _LiveRoomTile(
                  room: room,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => RoomPage(
                        roomId: room.id,
                        title: room.title,
                        entrySource: RoomEntrySource.home,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class LiveVendorReadinessPage extends StatelessWidget {
  const LiveVendorReadinessPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final bool developmentOutbox =
        dependencies.environment.canReadDevelopmentSmsOutbox;
    return SafeArea(
      child: ListView(
        key: const Key('vendor-readiness-page'),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: <Widget>[
          Text(
            '厂商接入准备',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '所有第三方能力都已经被隔离在适配器边界之外。没有配置时返回 VENDOR_BLOCKED，不会降级为假成功。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 18),
          _VendorCard(
            key: const Key('vendor-sms-status'),
            icon: Icons.sms_outlined,
            title: '短信',
            ready: true,
            summary: developmentOutbox
                ? '挑战、限流、消费、开发 Outbox 闭环已完成'
                : '挑战、限流、消费闭环已完成；开发 Outbox 未配置',
            next: '接入供应商发送实现、签名模板、回执与告警配置',
          ),
          const _VendorCard(
            key: Key('vendor-rtc-status'),
            icon: Icons.graphic_eq_rounded,
            title: 'RTC',
            ready: true,
            summary: '房间快照、固定 8 麦、权限与 SnapshotOnly 传输已完成',
            next: '接入 RTC SDK、服务端 Token 签发、续签和质量事件',
          ),
          const _VendorCard(
            key: Key('vendor-im-status'),
            icon: Icons.forum_outlined,
            title: '腾讯 IM',
            ready: true,
            summary: '消息事件码、房间实时网关和降级边界已完成',
            next: '接入 SDKAppID、服务端 UserSig、会话同步和审核链路',
          ),
          const _VendorCard(
            key: Key('vendor-payment-status'),
            icon: Icons.payments_outlined,
            title: '支付',
            ready: true,
            summary: '钱包与订单查询已接通；支付发起始终关闭',
            next: '接入渠道下单、签名验签、幂等回调、对账和退款',
          ),
          const _VendorCard(
            icon: Icons.cloud_upload_outlined,
            title: '对象存储 / 推送',
            ready: true,
            summary: '上传和通知入口未伪造，缺少适配器时保持关闭',
            next: '配置临时凭证、内容审核、回源域名和推送证书',
          ),
        ],
      ),
    );
  }
}

class LiveBlockedMessagePage extends StatelessWidget {
  const LiveBlockedMessagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: _StatusBanner(
            key: Key('im-vendor-blocked'),
            icon: Icons.forum_outlined,
            title: '腾讯 IM · VENDOR_BLOCKED',
            description: '消息入口不会调用旧接口或模拟成功。配置 SDKAppID、服务端 UserSig 和审核链路后再启用。',
          ),
        ),
      ),
    );
  }
}

class LiveReadOnlyAccountPage extends StatefulWidget {
  const LiveReadOnlyAccountPage({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  State<LiveReadOnlyAccountPage> createState() =>
      _LiveReadOnlyAccountPageState();
}

class _LiveReadOnlyAccountPageState extends State<LiveReadOnlyAccountPage> {
  LiveReadOnlyOverview? _overview;
  String? _error;
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final LiveReadOnlyOverview overview =
          await widget.dependencies.liveReadOnlyRepository.fetchOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '账号概览加载失败';
      });
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    await widget.onSignOut();
    if (mounted) {
      setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('live-account-overview'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: <Widget>[
            Text('我的', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorPanel(message: _error!, onRetry: _load)
            else if (_overview != null) ...<Widget>[
              _AccountCard(user: _overview!.user),
              const SizedBox(height: 12),
              _WalletCard(wallet: _overview!.wallet),
              const SizedBox(height: 18),
              Text('最近订单', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (_overview!.orders.isEmpty)
                const _StatusBanner(
                  icon: Icons.receipt_long_outlined,
                  title: '暂无订单',
                  description: '支付渠道尚未接入，本阶段只验证订单查询契约。',
                )
              else
                for (final LivePaymentOrder order in _overview!.orders)
                  _OrderTile(order: order),
              const SizedBox(height: 18),
              const _StatusBanner(
                key: Key('payment-initiation-blocked'),
                icon: Icons.lock_outline_rounded,
                title: '支付发起 · VENDOR_BLOCKED',
                description: '当前页面没有充值、提现或退款写入按钮。渠道适配器、回调验签与对账就绪后再开放。',
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRoomTile extends StatelessWidget {
  const _LiveRoomTile({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('live-room-${room.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const CircleAvatar(child: Icon(Icons.headphones_rounded)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(room.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人 · 只读快照',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({
    required this.icon,
    required this.title,
    required this.ready,
    required this.summary,
    required this.next,
    super.key,
  });

  final IconData icon;
  final String title;
  final bool ready;
  final String summary;
  final String next;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          ready ? '边界就绪' : '未就绪',
                          style: TextStyle(
                            color: ready ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(summary),
                    const SizedBox(height: 6),
                    Text('下一步：$next',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _StatusBanner(
      icon: Icons.cloud_off_outlined,
      title: message,
      description: '下拉刷新或点击重试。',
      key: const Key('live-read-error'),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final LiveCurrentUser user;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('current-user-contract-ready'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(user.nickname, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('用户 ${user.userId} · ${user.account}'),
            Text('手机号 ${_maskMobile(user.mobile)} · ${user.roles}'),
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});

  final LiveWalletSnapshot wallet;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('wallet-contract-ready'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _Metric(label: '钻石', value: '${wallet.giftCoinBalance}'),
            _Metric(label: '现金', value: wallet.cashBalance.toStringAsFixed(2)),
            _Metric(label: '冻结', value: wallet.frozenBalance.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final LivePaymentOrder order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(order.orderNo),
      subtitle: Text('${order.channelName} · ${order.status}'),
      trailing: Text('¥${order.amount.toStringAsFixed(2)}'),
    );
  }
}

String _maskMobile(String mobile) {
  if (mobile.length != 11) {
    return mobile.isEmpty ? '未返回' : mobile;
  }
  return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
}
