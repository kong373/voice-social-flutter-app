part of 'community_pages.dart';

class CommunityHubPage extends StatelessWidget {
  const CommunityHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    const List<_CommunityEntry> entries = <_CommunityEntry>[
      _CommunityEntry(
        icon: Icons.account_balance_outlined,
        title: '公会主页',
        subtitle: '查看当前公会、推荐公会和有效房间',
        page: GuildHomePage(),
        tint: Color(0xFF7764F4),
      ),
      _CommunityEntry(
        icon: Icons.group_add_outlined,
        title: '公会加入与成员管理',
        subtitle: '申请加入、签到、成员治理与申请审核',
        page: GuildMembersEntryPage(),
        tint: Color(0xFF49BCE7),
      ),
      _CommunityEntry(
        icon: Icons.link_rounded,
        title: '邀请与渠道归属',
        subtitle: '查看服务端确认的邀请归属，不允许客户端改写',
        page: InviteAttributionPage(),
        tint: Color(0xFFF0A03D),
      ),
      _CommunityEntry(
        icon: Icons.favorite_border_rounded,
        title: 'CP 关系',
        subtitle: '发起邀请、接受或拒绝，关系以服务端状态为准',
        page: CpRelationPage(),
        tint: Color(0xFFFF72A7),
      ),
      _CommunityEntry(
        icon: Icons.shield_outlined,
        title: '守护与粉团',
        subtitle: '查看守护档位、粉团关系和粉团任务',
        page: GuardianFanPage(),
        tint: Color(0xFF6D81EE),
      ),
      _CommunityEntry(
        icon: Icons.task_alt_rounded,
        title: '任务与签到',
        subtitle: '每日签到、平台任务和奖励领取',
        page: TaskCheckInPage(),
        tint: Color(0xFF39B98E),
      ),
      _CommunityEntry(
        icon: Icons.celebration_outlined,
        title: '主题活动中心',
        subtitle: '仅展示服务端确认的活动，不生成虚假活动入口',
        page: ActivityCenterPage(),
        tint: Color(0xFFE86C8B),
      ),
    ];
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('社交经营与活动')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          const _CommunityHero(
            eyebrow: 'SOCIAL STATION',
            title: '一起经营真实关系',
            subtitle: '公会、陪伴与活动都从这里开始，每一步都由双方和服务端确认。',
            icon: Icons.bubble_chart_rounded,
          ),
          const SizedBox(height: 20),
          const _SectionHeading(title: '常用入口', subtitle: '选择你现在想处理的关系或活动'),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 132,
            ),
            itemBuilder: (BuildContext context, int index) {
              final _CommunityEntry entry = entries[index];
              return _CommunitySection(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => entry.page,
                  ),
                ),
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CommunityGlyph(icon: entry.icon, tint: entry.tint),
                    const Spacer(),
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _CommunityPalette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _CommunityPalette.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
