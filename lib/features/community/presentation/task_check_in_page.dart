part of 'community_pages.dart';

class TaskCheckInPage extends StatefulWidget {
  const TaskCheckInPage({super.key});

  @override
  State<TaskCheckInPage> createState() => _TaskCheckInPageState();
}

class _TaskCheckInPageState extends State<TaskCheckInPage> {
  TaskCenterSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  String? _busyId;

  CommunityRepository get _repository =>
      AppDependencyScope.of(context).communityRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TaskCenterSnapshot value = await _repository.fetchTaskCenter();
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _sign() async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = 'sign');
    try {
      final TaskCenterSnapshot value = await _repository.completeDailyCheckIn();
      if (mounted) {
        setState(() => _snapshot = value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _claim(TaskItem task) async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = task.id);
    try {
      final TaskCenterSnapshot value = await _repository.claimTask(task.id);
      if (mounted) {
        setState(() => _snapshot = value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TaskCenterSnapshot? snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('任务与签到')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : snapshot == null
          ? const Center(child: Text('任务中心不可用'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '连续签到 ${snapshot.continuousDays} 天',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  snapshot.signedToday
                                      ? '今天已经签到'
                                      : '完成今日签到后领取服务端奖励',
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: snapshot.signedToday || _busyId != null
                                ? null
                                : _sign,
                            child: Text(snapshot.signedToday ? '已签到' : '签到'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final CheckInDay day in snapshot.checkInDays)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Container(
                              width: 92,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: day.today
                                    ? AppColors.primary.withValues(alpha: 0.18)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: day.today
                                      ? AppColors.primary
                                      : AppColors.divider,
                                ),
                              ),
                              child: Column(
                                children: <Widget>[
                                  Text('第 ${day.day} 天'),
                                  const SizedBox(height: 6),
                                  Icon(
                                    day.completed
                                        ? Icons.check_circle_rounded
                                        : Icons.card_giftcard_rounded,
                                    color: day.completed
                                        ? AppColors.success
                                        : AppColors.accent,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    day.reward,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('平台任务', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (snapshot.tasks.isEmpty)
                    const _InfoCard(
                      icon: Icons.task_alt_outlined,
                      text: '当前没有可执行任务。',
                    )
                  else
                    for (final TaskItem task in snapshot.tasks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            title: Text(task.title),
                            subtitle: Text(
                              <String>[
                                if (task.description.isNotEmpty)
                                  task.description,
                                '${task.progress}/${task.target} · ${task.reward}',
                              ].join('\n'),
                            ),
                            trailing: switch (task.state) {
                              TaskState.claimable => FilledButton.tonal(
                                onPressed: _busyId == null
                                    ? () => _claim(task)
                                    : null,
                                child: Text(_busyId == task.id ? '领取中…' : '领取'),
                              ),
                              TaskState.claimed => const _SmallTag(
                                label: '已领取',
                              ),
                              TaskState.expired => const _SmallTag(
                                label: '已过期',
                              ),
                              TaskState.inProgress => const _SmallTag(
                                label: '进行中',
                              ),
                            },
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
