import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/shell/live_vendor_boundary_page.dart';

class LiveHomePage extends StatefulWidget {
  const LiveHomePage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  List<DiscoveryRoom> _rooms = const <DiscoveryRoom>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final List<DiscoveryRoom> rooms = await widget
          .dependencies
          .discoveryRepository
          .fetchHomeRooms();
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
        _error = error is ApiException ? error.message : '房间列表暂时无法加载';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('live-home-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '此刻适合你的房间',
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
              '看看大家正在聊什么，找到喜欢的房间后可以先听一会儿。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ProductStatePanel(
                icon: Icons.cloud_off_outlined,
                title: '房间列表加载失败',
                description: _error!,
                actionLabel: '重新加载',
                onAction: _load,
              )
            else if (_rooms.isEmpty)
              _ProductStatePanel(
                icon: Icons.headphones_outlined,
                title: '暂时没有正在开放的房间',
                description: '稍后再来看看，或下拉刷新房间列表。',
                actionLabel: '刷新',
                onAction: _load,
              )
            else ...<Widget>[
              Text('正在发生', style: Theme.of(context).textTheme.titleLarge),
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

class LiveMessagesUnavailablePage extends StatelessWidget {
  const LiveMessagesUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        key: const Key('live-messages-page'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: <Widget>[
          Text('消息', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          const _ProductStatePanel(
            key: Key('im-vendor-blocked'),
            icon: Icons.forum_outlined,
            title: '消息服务暂时不可用',
            description: '好友、通知和私聊内容不会被伪造。服务恢复后可在这里继续查看。',
          ),
        ],
      ),
    );
  }
}

class LiveAccountPage extends StatefulWidget {
  const LiveAccountPage({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  State<LiveAccountPage> createState() => _LiveAccountPageState();
}

class _LiveAccountPageState extends State<LiveAccountPage> {
  LiveReadOnlyOverview? _overview;
  String? _error;
  bool _loading = true;
  bool _signingOut = false;

  bool get _showDeveloperReadiness =>
      kDebugMode &&
      widget
          .dependencies
          .environment
          .deploymentEnvironment
          .allowsDevelopmentTools;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final LiveReadOnlyOverview overview = await widget
          .dependencies
          .liveReadOnlyRepository
          .fetchOverview();
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
        _error = error is ApiException ? error.message : '账号信息暂时无法加载';
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
    final LiveReadOnlyOverview? overview = _overview;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('live-account-page'),
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
              _ProductStatePanel(
                icon: Icons.cloud_off_outlined,
                title: '账号信息加载失败',
                description: _error!,
                actionLabel: '重新加载',
                onAction: _load,
              )
            else if (overview != null) ...<Widget>[
              _AccountCard(user: overview.user),
              const SizedBox(height: 12),
              _WalletCard(wallet: overview.wallet),
              const SizedBox(height: 18),
              Text('最近订单', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (overview.orders.isEmpty)
                const _ProductStatePanel(
                  icon: Icons.receipt_long_outlined,
                  title: '暂无订单',
                  description: '完成充值后，订单记录会显示在这里。',
                )
              else
                for (final LivePaymentOrder order in overview.orders)
                  _OrderTile(order: order),
              const SizedBox(height: 18),
              const _ProductStatePanel(
                key: Key('payment-initiation-blocked'),
                icon: Icons.lock_outline_rounded,
                title: '充值服务暂时不可用',
                description: '当前可以查看余额与历史订单，暂时不能创建新的支付订单。',
              ),
              if (_showDeveloperReadiness) ...<Widget>[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const Key('developer-vendor-readiness'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => LiveVendorBoundaryPage(
                        dependencies: widget.dependencies,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.developer_mode_outlined),
                  label: const Text('开发接入状态'),
                ),
              ],
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
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                child: Icon(
                  room.isSpeaking
                      ? Icons.graphic_eq_rounded
                      : Icons.headphones_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人在线',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (room.isLocked)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.lock_outline_rounded, size: 18),
                ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              child: Text(
                user.nickname.isEmpty
                    ? '?'
                    : String.fromCharCode(user.nickname.runes.first),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.nickname,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('账号 ${user.account}'),
                  if (user.mobile.isNotEmpty) Text(user.mobile),
                ],
              ),
            ),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('钱包', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _BalanceValue(
                    label: '礼物币',
                    value: '${wallet.giftCoinBalance}',
                  ),
                ),
                Expanded(
                  child: _BalanceValue(
                    label: '现金余额',
                    value: '¥${wallet.cashBalance.toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceValue extends StatelessWidget {
  const _BalanceValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final LivePaymentOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(order.orderNo),
        subtitle: Text('${order.channelName} · ${_statusLabel(order.status)}'),
        trailing: Text('¥${order.amount.toStringAsFixed(2)}'),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'SUCCEEDED' => '已完成',
    'CONFIRMING' => '确认中',
    'FAILED' => '失败',
    'CANCELLED' => '已取消',
    _ => '处理中',
  };
}

class _ProductStatePanel extends StatelessWidget {
  const _ProductStatePanel({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 42, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
