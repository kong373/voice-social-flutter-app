import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/live_read_only_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

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

  List<Widget> get _pages {
    if (widget.dependencies.environment.isLive) {
      return <Widget>[
        const HomePage(),
        const LiveDiscoveryHoldingPage(),
        const LiveMessageHoldingPage(),
        LiveReadOnlyAccountPage(
          dependencies: widget.dependencies,
          onSignOut: widget.onSignOut,
        ),
      ];
    }
    return <Widget>[
      const HomePage(),
      const DiscoveryFeedPage(),
      const MessageCenterPage(),
      PersonalCenterPage(
        session: widget.dependencies.sessionManager.session,
        onSignOut: widget.onSignOut,
      ),
    ];
  }

  static const List<BottomNavigationBarItem> _items = <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: _ActiveNavigationIcon(icon: Icons.home_rounded),
      label: '首页',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.explore_outlined),
      activeIcon: _ActiveNavigationIcon(icon: Icons.explore_rounded),
      label: '发现',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.chat_bubble_outline_rounded),
      activeIcon: _ActiveNavigationIcon(icon: Icons.chat_bubble_rounded),
      label: '消息',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline_rounded),
      activeIcon: _ActiveNavigationIcon(icon: Icons.person_rounded),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFA090D21),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.065)),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 24,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (int index) => setState(() => _selectedIndex = index),
            items: _items,
          ),
        ),
      ),
    );
  }
}

class _ActiveNavigationIcon extends StatelessWidget {
  const _ActiveNavigationIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.primary.withValues(alpha: 0.34),
            AppColors.secondary.withValues(alpha: 0.16),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(icon, size: 21, color: AppColors.primaryBright),
    );
  }
}
