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

  Widget _checkInDay(CheckInDay day) {
    final Color tint = day.completed
        ? AppColors.success
        : day.today
        ? _CommunityPalette.violet
        : _CommunityPalette.gold;
    return Container(
      width: 72,
      padding: const EdgeInsets.fromLTRB(7, 9, 7, 8),
      decoration: BoxDecoration(
        color: day.today ? const Color(0xFFF0EDFF) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: day.today
              ? _CommunityPalette.violet.withValues(alpha: 0.42)
              : _CommunityPalette.line,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '第 ${day.day} 天',
            style: const TextStyle(
              color: _CommunityPalette.ink,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          _CommunityGlyph(
            icon: day.completed ? Icons.check_rounded : Icons.redeem_rounded,
            tint: tint,
            size: 34,
          ),
          const SizedBox(height: 6),
          Text(
            day.reward,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _CommunityPalette.muted,
              fontSize: 9,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(TaskItem task) {
    final double progress = task.target == 0 ? 0 : task.progress / task.target;
    final bool isClaimable = task.state == TaskState.claimable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommunitySection(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        tint: isClaimable ? const Color(0xFFF9F7FF) : Colors.white,
        child: Row(
          children: <Widget>[
            _CommunityGlyph(
              icon: switch (task.state) {
                TaskState.claimable => Icons.redeem_rounded,
                TaskState.claimed => Icons.check_rounded,
                TaskState.expired => Icons.schedule_rounded,
                TaskState.inProgress => Icons.bolt_rounded,
              },
              tint: switch (task.state) {
                TaskState.claimable => _CommunityPalette.violet,
                TaskState.claimed => AppColors.success,
                TaskState.expired => _CommunityPalette.muted,
                TaskState.inProgress => _CommunityPalette.gold,
              },
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CommunityPalette.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _CommunityPalette.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _ProgressLine(
                    value: progress,
                    tint: isClaimable
                        ? _CommunityPalette.violet
                        : _CommunityPalette.gold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${task.progress}/${task.target}  ·  ${task.reward}',
                    style: const TextStyle(
                      color: _CommunityPalette.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            switch (task.state) {
              TaskState.claimable => FilledButton.tonal(
                onPressed: _busyId == null ? () => _claim(task) : null,
                child: Text(_busyId == task.id ? '领取中…' : '领取'),
              ),
              TaskState.claimed => const _SmallTag(
                label: '已领取',
                tint: AppColors.success,
              ),
              TaskState.expired => const _SmallTag(
                label: '已过期',
                tint: _CommunityPalette.muted,
              ),
              TaskState.inProgress => const _SmallTag(
                label: '进行中',
                tint: _CommunityPalette.gold,
              ),
            },
          ],
        ),
      ),
    );
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  _CommunityHero(
                    eyebrow: 'DAILY MOMENTUM',
                    title: '连续签到 ${snapshot.continuousDays} 天',
                    subtitle: snapshot.signedToday
                        ? '今天已经签到，明天继续来看看'
                        : '完成今日签到，领取服务端确认的奖励',
                    icon: Icons.local_fire_department_rounded,
                    colors: const <Color>[
                      Color(0xFF6656E8),
                      Color(0xFF9B74EF),
                      Color(0xFFFFA36E),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CommunitySection(
                    padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
                    child: Row(
                      children: <Widget>[
                        const _CommunityGlyph(
                          icon: Icons.calendar_today_rounded,
                          tint: _CommunityPalette.violet,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            snapshot.signedToday ? '今日记录已完成' : '今天也来留下足迹吧',
                            style: const TextStyle(
                              color: _CommunityPalette.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
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
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final CheckInDay day in snapshot.checkInDays)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _checkInDay(day),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeading(
                    title: '平台任务',
                    subtitle: '完成真实互动后领取对应奖励',
                  ),
                  const SizedBox(height: 10),
                  if (snapshot.tasks.isEmpty)
                    const _InfoCard(
                      icon: Icons.task_alt_outlined,
                      text: '当前没有可执行任务。',
                    )
                  else
                    for (final TaskItem task in snapshot.tasks) _taskCard(task),
                ],
              ),
            ),
    );
  }
}
