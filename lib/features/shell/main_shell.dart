import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
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
        LiveProductHomePage(dependencies: widget.dependencies),
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (int index) => setState(() => _selectedIndex = index),
        items: _items,
      ),
    );
  }
}
