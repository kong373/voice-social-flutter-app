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
      ),
      _CommunityEntry(
        icon: Icons.group_add_outlined,
        title: '公会加入与成员管理',
        subtitle: '申请加入、签到、成员治理与申请审核',
        page: GuildMembersEntryPage(),
      ),
      _CommunityEntry(
        icon: Icons.link_rounded,
        title: '邀请与渠道归属',
        subtitle: '查看服务端确认的邀请归属，不允许客户端改写',
        page: InviteAttributionPage(),
      ),
      _CommunityEntry(
        icon: Icons.favorite_border_rounded,
        title: 'CP 关系',
        subtitle: '发起邀请、接受或拒绝，关系以服务端状态为准',
        page: CpRelationPage(),
      ),
      _CommunityEntry(
        icon: Icons.shield_outlined,
        title: '守护与粉团',
        subtitle: '查看守护档位、粉团关系和粉团任务',
        page: GuardianFanPage(),
      ),
      _CommunityEntry(
        icon: Icons.task_alt_rounded,
        title: '任务与签到',
        subtitle: '每日签到、平台任务和奖励领取',
        page: TaskCheckInPage(),
      ),
      _CommunityEntry(
        icon: Icons.celebration_outlined,
        title: '主题活动中心',
        subtitle: '仅展示服务端确认的活动，不生成虚假活动入口',
        page: ActivityCenterPage(),
      ),
    ];
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('社交经营与活动')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final _CommunityEntry entry = entries[index];
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              leading: Icon(entry.icon, color: AppColors.accent),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => entry.page,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
