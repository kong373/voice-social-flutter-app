import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

/// Fail-closed Discover surface used until the dynamic read contract is added.
///
/// The root navigation remains stable (`首页 / 发现 / 消息 / 我的`) while this
/// page keeps the current context and presents a recoverable, product-facing
/// unavailable state instead of replacing Discover with an internal QA tool.
class LiveDiscoverPage extends StatelessWidget {
  const LiveDiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        key: const Key('live-discover-page'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: <Widget>[
          Text('发现', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.dynamic_feed_outlined,
                    size: 46,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '动态内容暂时无法加载',
                    key: Key('live-discover-unavailable'),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '首页房间、搜索和个人账户仍可正常使用。动态服务恢复后可在这里继续浏览。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
