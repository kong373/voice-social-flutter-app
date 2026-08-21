part of 'community_pages.dart';

class ActivityCenterPage extends StatefulWidget {
  const ActivityCenterPage({super.key});

  @override
  State<ActivityCenterPage> createState() => _ActivityCenterPageState();
}

class _ActivityCenterPageState extends State<ActivityCenterPage> {
  List<ThemeActivity>? _activities;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_activities == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final CommunityRepository repository = AppDependencyScope.of(
      context,
    ).communityRepository;
    if (!repository.supportsActivityCatalog) {
      setState(() {
        _activities = const <ThemeActivity>[];
        _error = '当前后端没有确认统一的主题活动目录接口，Live 模式不会生成虚假活动。';
      });
      return;
    }
    try {
      final List<ThemeActivity> value = await repository.fetchActivities();
      if (mounted) {
        setState(() => _activities = value);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Color _statusTint(ThemeActivityStatus status) => switch (status) {
    ThemeActivityStatus.active => AppColors.success,
    ThemeActivityStatus.upcoming => _CommunityPalette.gold,
    ThemeActivityStatus.ended => _CommunityPalette.muted,
  };

  Widget _activityCard(ThemeActivity activity, int index) {
    final Color tint = _statusTint(activity.status);
    final List<Color> coverColors = index.isEven
        ? const <Color>[Color(0xFF6958D9), Color(0xFFE481AB)]
        : const <Color>[Color(0xFF3A8AC8), Color(0xFF62C9C1)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CommunitySection(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 84,
              padding: const EdgeInsets.fromLTRB(15, 13, 13, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: coverColors),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: -8,
                    top: -28,
                    child: Icon(
                      index.isEven
                          ? Icons.nights_stay_rounded
                          : Icons.celebration_rounded,
                      size: 92,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SmallTag(
                        label: activity.status.label,
                        tint: Colors.white,
                      ),
                      const Spacer(),
                      Text(
                        activity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.schedule_rounded, size: 15, color: tint),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          activity.period,
                          style: TextStyle(
                            color: tint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activity.summary,
                    style: const TextStyle(
                      color: _CommunityPalette.ink,
                      fontSize: 12,
                      height: 1.42,
                    ),
                  ),
                  if (activity.rules.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 9),
                    for (final String rule in activity.rules)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: tint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                rule,
                                style: const TextStyle(
                                  color: _CommunityPalette.muted,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (activity.routeTarget != null) ...<Widget>[
                    const SizedBox(height: 9),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              RoomDeepLinkPage(input: activity.routeTarget!),
                        ),
                      ),
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: const Text('进入活动房间'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ThemeActivity>? activities = _activities;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('主题活动中心')),
      body: activities == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && (activities?.isEmpty ?? true)
          ? _StateError(message: _error!, onRetry: _load, retryLabel: '重新检查')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  const _CommunityHero(
                    eyebrow: 'LIVE EVENTS',
                    title: '今天在发生什么',
                    subtitle: '活动连接房间、动态与任务，不额外创造未确认玩法。',
                    icon: Icons.celebration_rounded,
                    colors: <Color>[
                      Color(0xFF4C65CE),
                      Color(0xFF9270E6),
                      Color(0xFFF480A4),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _InfoCard(
                    icon: Icons.verified_outlined,
                    text: '活动只作为普通房间、动态或任务的组织方式，不新增未确认玩法。',
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeading(
                    title: '主题活动',
                    subtitle: '仅展示服务端确认的活动与状态',
                  ),
                  const SizedBox(height: 10),
                  if (activities == null || activities.isEmpty)
                    const _InfoCard(
                      icon: Icons.event_busy_outlined,
                      text: '当前没有可展示的权威活动。',
                    )
                  else
                    for (int index = 0; index < activities.length; index++)
                      _activityCard(activities[index], index),
                ],
              ),
            ),
    );
  }
}
