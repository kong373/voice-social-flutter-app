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

  Widget _guardianLevelCard(GuardianLevel level) {
    return _CommunitySection(
      tint: const Color(0xFFF9F6FF),
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _CommunityGlyph(
                icon: Icons.shield_rounded,
                tint: _CommunityPalette.violet,
                size: 38,
              ),
              const Spacer(),
              _SmallTag(
                label: '${level.durationDays} 天',
                tint: _CommunityPalette.violet,
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            level.name,
            style: const TextStyle(
              color: _CommunityPalette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${level.price} 礼物币',
            style: const TextStyle(
              color: _CommunityPalette.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _busy ? null : () => _guard(level),
              child: const Text('开通'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fansTaskCard(FansTask task) {
    final double progress = task.target == 0 ? 0 : task.progress / task.target;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommunitySection(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        child: Row(
          children: <Widget>[
            _CommunityGlyph(
              icon: task.claimed
                  ? Icons.check_rounded
                  : Icons.auto_awesome_rounded,
              tint: task.claimed ? AppColors.success : _CommunityPalette.gold,
              size: 38,
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
                  const SizedBox(height: 5),
                  _ProgressLine(value: progress),
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
            if (task.claimed) ...<Widget>[
              const SizedBox(width: 8),
              const _SmallTag(label: '已完成', tint: AppColors.success),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GuardianFanSnapshot? snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('守护与粉团')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          if (!_loading && _error == null && snapshot != null) ...<Widget>[
            _CommunityHero(
              eyebrow: 'GUARDIAN SPACE · ${snapshot.anchorUserId}',
              title: snapshot.anchorName,
              subtitle: snapshot.currentGuardianLevel == null
                  ? '当前未开通守护 · 先从陪伴开始'
                  : '当前守护：${snapshot.currentGuardianLevel!.name}',
              icon: Icons.shield_rounded,
              colors: const <Color>[
                Color(0xFF3A2E76),
                Color(0xFF6953C6),
                Color(0xFFE17EA8),
              ],
              trailing: const _LetterAvatar(
                label: '晚星',
                prominent: true,
                imagePath: 'assets/runtime/avatar-rose.png',
                size: 66,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _CommunitySection(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _anchorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '主播用户 ID',
                      prefixIcon: Icon(Icons.person_search_outlined),
                      fillColor: Color(0xFFF7F5FF),
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
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _StateError(message: _error!, onRetry: _load)
          else if (snapshot != null) ...<Widget>[
            const _SectionHeading(title: '守护档位', subtitle: '开通前会再次确认消耗与时长'),
            const SizedBox(height: 10),
            if (snapshot.guardianLevels.isEmpty)
              const _InfoCard(icon: Icons.shield_outlined, text: '当前没有可用守护档位。')
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.guardianLevels.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  mainAxisExtent: 188,
                ),
                itemBuilder: (BuildContext context, int index) =>
                    _guardianLevelCard(snapshot.guardianLevels[index]),
              ),
            const SizedBox(height: 20),
            _CommunitySection(
              tint: const Color(0xFFF8F5FF),
              child: Row(
                children: <Widget>[
                  const _CommunityGlyph(
                    icon: Icons.auto_awesome_rounded,
                    tint: _CommunityPalette.gold,
                    size: 46,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          snapshot.fansTeamName,
                          style: const TextStyle(
                            color: _CommunityPalette.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          snapshot.joinedFansTeam
                              ? '粉团等级 ${snapshot.fansLevel} · 亲密值 ${snapshot.intimacy}'
                              : '尚未加入粉团',
                          style: const TextStyle(
                            color: _CommunityPalette.muted,
                            fontSize: 11,
                          ),
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
            ),
            const SizedBox(height: 18),
            const _SectionHeading(title: '粉团任务', subtitle: '完成互动累积亲密值'),
            const SizedBox(height: 10),
            if (snapshot.tasks.isEmpty)
              const _InfoCard(icon: Icons.task_alt_outlined, text: '当前没有粉团任务。')
            else
              for (final FansTask task in snapshot.tasks) _fansTaskCard(task),
          ],
        ],
      ),
    );
  }
}
