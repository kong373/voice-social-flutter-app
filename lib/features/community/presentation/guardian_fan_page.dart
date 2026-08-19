part of 'community_pages.dart';

class GuardianFanPage extends StatefulWidget {
  const GuardianFanPage({super.key});

  @override
  State<GuardianFanPage> createState() => _GuardianFanPageState();
}

class _GuardianFanPageState extends State<GuardianFanPage> {
  final TextEditingController _anchorController = TextEditingController(
    text: '20001',
  );
  GuardianFanSnapshot? _snapshot;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  CommunityRepository get _repository =>
      AppDependencyScope.of(context).communityRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _anchorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int? anchorId = int.tryParse(_anchorController.text.trim());
    if (anchorId == null) {
      setState(() {
        _loading = false;
        _error = '请输入有效主播用户 ID';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GuardianFanSnapshot value = await _repository.fetchGuardianFan(
        anchorId,
      );
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

  Future<void> _guard(GuardianLevel level) async {
    final GuardianFanSnapshot snapshot = _snapshot!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('开通${level.name}？'),
        content: Text(
          '将按服务端规则扣除 ${level.price} 礼物币，守护 ${snapshot.anchorName} ${level.durationDays} 天。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认开通'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.becomeGuardian(
        anchorUserId: snapshot.anchorUserId,
        levelId: level.id,
      );
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _joinFans() async {
    if (_busy || _snapshot == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.joinFansTeam(_snapshot!.anchorUserId);
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GuardianFanSnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('守护与粉团')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _anchorController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '主播用户 ID',
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading ? null : _load,
                child: const Text('查询'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _StateError(message: _error!, onRetry: _load)
          else if (snapshot != null) ...<Widget>[
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      snapshot.anchorName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text('主播 ID ${snapshot.anchorUserId}'),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.currentGuardianLevel == null
                          ? '当前未开通守护'
                          : '当前守护：${snapshot.currentGuardianLevel!.name}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('守护档位', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (snapshot.guardianLevels.isEmpty)
              const _InfoCard(icon: Icons.shield_outlined, text: '当前没有可用守护档位。')
            else
              for (final GuardianLevel level in snapshot.guardianLevels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(level.name),
                      subtitle: Text(
                        '${level.durationDays} 天 · ${level.price} 礼物币',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _busy ? null : () => _guard(level),
                        child: const Text('开通'),
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        snapshot.fansTeamName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        snapshot.joinedFansTeam
                            ? '粉团等级 ${snapshot.fansLevel} · 亲密值 ${snapshot.intimacy}'
                            : '尚未加入粉团',
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _busy || snapshot.joinedFansTeam
                      ? null
                      : _joinFans,
                  child: Text(snapshot.joinedFansTeam ? '已加入' : '加入粉团'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.tasks.isEmpty)
              const _InfoCard(icon: Icons.task_alt_outlined, text: '当前没有粉团任务。')
            else
              for (final FansTask task in snapshot.tasks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(task.title),
                  subtitle: Text(
                    '${task.progress}/${task.target} · ${task.reward}',
                  ),
                  trailing: task.claimed
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                        )
                      : null,
                ),
          ],
        ],
      ),
    );
  }
}
