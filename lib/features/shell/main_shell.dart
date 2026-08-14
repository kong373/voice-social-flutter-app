import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  List<Widget> get _pages => <Widget>[
        const HomePage(),
        const _RootPlaceholder(
          title: '发现',
          description: '浏览好友和关注用户发布的动态，参与真实的社交讨论。',
          icon: Icons.explore_rounded,
        ),
        const _RootPlaceholder(
          title: '消息',
          description: '查看私聊、好友互动和系统通知。',
          icon: Icons.chat_bubble_rounded,
        ),
        _AccountRoot(
          session: widget.dependencies.sessionManager.session,
          onSignOut: widget.onSignOut,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (int index) => setState(() => _selectedIndex = index),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: '消息',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _AccountRoot extends StatefulWidget {
  const _AccountRoot({required this.session, required this.onSignOut});

  final AuthSession? session;
  final Future<void> Function() onSignOut;

  @override
  State<_AccountRoot> createState() => _AccountRootState();
}

class _AccountRootState extends State<_AccountRoot> {
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final AuthSession? session = widget.session;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.surfaceHigh,
            child: Icon(Icons.person_rounded, size: 34),
          ),
          const SizedBox(height: 18),
          Text('我的', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            session == null
                ? '会话不可用'
                : '用户 ${session.userId} · ${_maskedMobile(session.mobile)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 28),
          const _AccountEntry(
            icon: Icons.person_outline_rounded,
            title: '个人资料与关系',
            description: '查看和编辑个人资料、关注、好友与隐私设置。',
          ),
          const _AccountEntry(
            icon: Icons.account_balance_wallet_outlined,
            title: '钱包与订单',
            description: '查看礼物币、充值订单、收益与提现。',
          ),
          const _AccountEntry(
            icon: Icons.security_outlined,
            title: '账号与安全',
            description: '管理权限、设备、实名、青少年模式与账号安全。',
          ),
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
    );
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await widget.onSignOut();
    if (mounted) {
      setState(() => _signingOut = false);
    }
  }

  static String _maskedMobile(String mobile) {
    if (mobile.length != 11) {
      return mobile.isEmpty ? '未提供手机号' : mobile;
    }
    return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
  }
}

class _AccountEntry extends StatelessWidget {
  const _AccountEntry({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title),
      subtitle: Text(description),
    );
  }
}

class _RootPlaceholder extends StatelessWidget {
  const _RootPlaceholder({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 34, color: AppColors.primary),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
