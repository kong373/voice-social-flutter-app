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

  @override
  Widget build(BuildContext context) {
    final List<ThemeActivity>? activities = _activities;
    return Scaffold(
      appBar: AppBar(title: const Text('主题活动中心')),
      body: activities == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && (activities?.isEmpty ?? true)
          ? _StateError(message: _error!, onRetry: _load, retryLabel: '重新检查')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  const _InfoCard(
                    icon: Icons.verified_outlined,
                    text: '活动只作为普通房间、动态或任务的组织方式，不新增未确认玩法。',
                  ),
                  const SizedBox(height: 14),
                  if (activities == null || activities.isEmpty)
                    const _InfoCard(
                      icon: Icons.event_busy_outlined,
                      text: '当前没有可展示的权威活动。',
                    )
                  else
                    for (final ThemeActivity activity in activities)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(17),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        activity.title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    _SmallTag(label: activity.status.label),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activity.period,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                Text(activity.summary),
                                if (activity.rules.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 10),
                                  for (final String rule in activity.rules)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          const Text('• '),
                                          Expanded(child: Text(rule)),
                                        ],
                                      ),
                                    ),
                                ],
                                if (activity.routeTarget != null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (BuildContext context) =>
                                                RoomDeepLinkPage(
                                                  input: activity.routeTarget!,
                                                ),
                                          ),
                                        ),
                                    child: const Text('进入活动房间'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
