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

/// Home surface used while only the live read contracts are enabled. It keeps
/// the approved product structure and does not expose create/favorite actions
/// whose backend mutations are intentionally outside M3.2A.
class LiveProductHomePage extends StatefulWidget {
  const LiveProductHomePage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LiveProductHomePage> createState() => _LiveProductHomePageState();
}

class _LiveProductHomePageState extends State<LiveProductHomePage> {
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
        _error = error is ApiException ? error.message : '房间推荐暂时无法加载';
      });
    }
  }

  void _openSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const GlobalSearchPage(),
      ),
    );
  }

  void _openRoom(DiscoveryRoom room) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPage(
          roomId: room.id,
          title: room.title,
          entrySource: RoomEntrySource.home,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF15112E),
            AppColors.background,
            AppColors.background,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('live-home-ready'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _openSearch,
                child: const IgnorePointer(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索房间、用户或房间号',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '此刻适合你的房间',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '点击房间即可查看当前话题、在线人数和固定 8 个麦位。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorPanel(message: _error!, onRetry: _load)
              else if (_rooms.isEmpty)
                _ErrorPanel(message: '当前没有可展示的房间', onRetry: _load)
              else
                for (final DiscoveryRoom room in _rooms) ...<Widget>[
                  _RoomCard(room: room, onTap: () => _openRoom(room)),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Product-safe placeholder for DS-004 while the dynamic service remains
/// intentionally outside M3.2A. The fixed root label remains “发现”.
class LiveDiscoveryHoldingPage extends StatelessWidget {
  const LiveDiscoveryHoldingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: _StatusBanner(
            key: Key('live-discovery-unavailable'),
            icon: Icons.explore_outlined,
            title: '发现内容正在准备',
            description: '动态内容服务尚未开放。你仍可在首页浏览房间，或使用搜索查找房间和用户。',
          ),
        ),
      ),
    );
  }
}

/// Product-safe placeholder for the fixed “消息” root tab. It does not claim
/// that a Tencent IM login or message delivery succeeded.
class LiveMessageHoldingPage extends StatelessWidget {
  const LiveMessageHoldingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: _StatusBanner(
            key: Key('im-vendor-blocked'),
            icon: Icons.forum_outlined,
            title: '消息服务正在准备',
            description: '当前暂不能收发私聊或互动消息。服务开通后，会在这里展示真实会话和通知。',
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible class name retained for older widget tests. The user
/// sees the same product-safe holding state rather than an internal status code.
class LiveBlockedMessagePage extends LiveMessageHoldingPage {
  const LiveBlockedMessagePage({super.key});
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

  bool get _showDeveloperDiagnostics =>
      kDebugMode &&
      (widget.dependencies.environment.deploymentEnvironment ==
              DeploymentEnvironment.local ||
          widget.dependencies.environment.deploymentEnvironment ==
              DeploymentEnvironment.development);

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
        _error = error is ApiException ? error.message : '账号信息加载失败';
      });
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _openDeveloperDiagnostics() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          appBar: AppBar(title: const Text('开发环境接入诊断')),
          body: LiveVendorBoundaryPage(dependencies: widget.dependencies),
        ),
      ),
    );
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
                  description: '你还没有充值订单。',
                )
              else
                for (final LivePaymentOrder order in _overview!.orders)
                  _OrderTile(order: order),
              const SizedBox(height: 18),
              const _StatusBanner(
                key: Key('payment-initiation-blocked'),
                icon: Icons.lock_outline_rounded,
                title: '充值服务暂未开放',
                description: '当前只能查看余额和历史订单，暂不能创建新的充值、退款或提现申请。',
              ),
            ],
            if (_showDeveloperDiagnostics) ...<Widget>[
              const SizedBox(height: 18),
              ListTile(
                key: const Key('open-vendor-diagnostics'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.developer_mode_outlined),
                title: const Text('开发环境接入诊断'),
                subtitle: const Text('仅调试构建可见，不会出现在正式版本'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openDeveloperDiagnostics,
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('live-room-${room.id}'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: room.isSpeaking
                      ? AppColors.primary.withValues(alpha: 0.18)
                      : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  room.isSpeaking
                      ? Icons.graphic_eq_rounded
                      : Icons.headphones_rounded,
                  color: room.isSpeaking
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 13),
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
                    const SizedBox(height: 7),
                    Text(
                      '${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人在线',
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
    return Material(
      key: const Key('live-read-error'),
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(user.nickname, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('用户号 ${user.account}'),
            Text('手机号 ${_maskMobile(user.mobile)}'),
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
            _Metric(label: '礼物币', value: '${wallet.giftCoinBalance}'),
            _Metric(
              label: '现金余额',
              value: wallet.cashBalance.toStringAsFixed(2),
            ),
            _Metric(
              label: '冻结金额',
              value: wallet.frozenBalance.toStringAsFixed(2),
            ),
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
      subtitle: Text('${order.channelName} · ${_statusLabel(order.status)}'),
      trailing: Text('¥${order.amount.toStringAsFixed(2)}'),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'SUCCEEDED' => '支付成功',
  'CONFIRMING' => '确认中',
  'FAILED' => '支付失败',
  'CANCELLED' => '已取消',
  _ => '状态更新中',
};

String _maskMobile(String mobile) {
  if (mobile.contains('*')) {
    return mobile;
  }
  if (mobile.length != 11) {
    return mobile.isEmpty ? '未绑定' : mobile;
  }
  return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
}
