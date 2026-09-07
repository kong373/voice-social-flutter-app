part of 'community_pages.dart';

class InviteAttributionPage extends StatefulWidget {
  const InviteAttributionPage({super.key});

  @override
  State<InviteAttributionPage> createState() => _InviteAttributionPageState();
}

class _InviteAttributionPageState extends State<InviteAttributionPage> {
  InviteAttribution? _data;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final InviteAttribution value = await AppDependencyScope.of(
        context,
      ).communityRepository.fetchInviteAttribution();
      if (mounted) {
        setState(() => _data = value);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final InviteAttribution? data = _data;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('邀请与渠道归属')),
      body: _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                _CommunityHero(
                  eyebrow: 'INVITATION RECORD',
                  title: data.available ? '邀请关系已确认' : '暂未形成邀请归属',
                  subtitle: data.available
                      ? '邀请码 ${data.inviteCode}  ·  ${data.invitedUsers == null ? '邀请人数未知' : '已邀请 ${data.invitedUsers} 人'}'
                      : data.message,
                  icon: Icons.mark_email_read_rounded,
                  colors: const <Color>[
                    Color(0xFF4F83D5),
                    Color(0xFF73C5DF),
                    Color(0xFF9D81F0),
                  ],
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  icon: data.available
                      ? Icons.verified_outlined
                      : Icons.link_off_rounded,
                  text: data.available
                      ? '以下归属来自服务端权威记录，客户端不能修改。'
                      : data.message,
                ),
                const SizedBox(height: 16),
                if (data.available)
                  _CommunitySection(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              _CommunityGlyph(
                                icon: Icons.link_rounded,
                                tint: _CommunityPalette.violet,
                                size: 38,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '邀请归属凭证',
                                  style: TextStyle(
                                    color: _CommunityPalette.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              _SmallTag(
                                label: '服务端确认',
                                tint: AppColors.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(color: _CommunityPalette.line),
                          _KeyValue(label: '邀请码', value: data.inviteCode),
                          _KeyValue(label: '渠道归属', value: data.channelName),
                          _KeyValue(label: '绑定时间', value: data.boundAt),
                          _KeyValue(
                            label: '已邀请用户',
                            value: data.invitedUsers == null
                                ? '未知（服务端未提供统计）'
                                : '${data.invitedUsers} 人',
                          ),
                          if (data.message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                data.message,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const _InfoCard(
                  icon: Icons.lock_outline_rounded,
                  text: '本页不提供改绑、抢绑或客户端本地生成归属。历史收益归属也不会被客户端重算。',
                ),
              ],
            ),
    );
  }
}

class CpRelationPage extends StatefulWidget {
  const CpRelationPage({super.key});

  @override
  State<CpRelationPage> createState() => _CpRelationPageState();
}

class _CpRelationPageState extends State<CpRelationPage> {
  final TextEditingController _userIdController = TextEditingController();
  final List<CpRelation> _relations = <CpRelation>[];
  final List<CpInvitation> _invitations = <CpInvitation>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  CommunityRepository get _repository =>
      AppDependencyScope.of(context).communityRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _relations.isEmpty) {
      _load();
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchCpRelations(),
        _repository.fetchPendingCpInvitations(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _relations
          ..clear()
          ..addAll(result[0] as List<CpRelation>);
        _invitations
          ..clear()
          ..addAll(result[1] as List<CpInvitation>);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _request() async {
    final int? userId = int.tryParse(_userIdController.text.trim());
    if (userId == null || _busy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效用户 ID')));
      return;
    }
    setState(() => _busy = true);
    try {
      final CpEligibility eligibility = await _repository.checkCpEligibility(
        userId,
      );
      if (!eligibility.allowed) {
        throw ApiException(
          kind: ApiFailureKind.business,
          message: eligibility.message,
        );
      }
      await _repository.requestCp(userId);
      if (mounted) {
        _userIdController.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('CP 邀请已发送，等待对方确认')));
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

  Future<void> _resolve(CpInvitation invitation, bool accepted) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.resolveCpInvitation(
        invitationId: invitation.invitationId,
        accepted: accepted,
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

  Future<void> _end(CpRelation relation) async {
    if (_busy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('解除 CP 关系？'),
        content: const Text('解除后双方关系会立即结束，是否继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认解除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.endCpRelation(relation.relationId);
      if (mounted) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('CP 关系已解除')));
        }
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

  Widget _relationCard(CpRelation relation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _CommunitySection(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                PublicProfilePage(userId: relation.userId),
          ),
        ),
        tint: const Color(0xFFFFF8FB),
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: <Widget>[
            const _LetterAvatar(
              label: '我',
              prominent: true,
              imagePath: 'assets/runtime/avatar-silver.png',
              size: 50,
            ),
            Transform.translate(
              offset: const Offset(-8, 0),
              child: _LetterAvatar(
                label: relation.nickname,
                prominent: true,
                imagePath: 'assets/runtime/avatar-rose.png',
                size: 50,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          relation.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _CommunityPalette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFFF6C9D),
                        size: 15,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    relation.days == null ? '相伴天数未知' : '已相伴 ${relation.days} 天',
                    style: const TextStyle(
                      color: Color(0xFFE25D8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    relation.boundAt.isEmpty
                        ? '建立时间未知'
                        : '建立于 ${relation.boundAt}',
                    style: const TextStyle(
                      color: _CommunityPalette.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '关系操作',
              onSelected: (String value) {
                if (value == 'end') {
                  _end(relation);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'end',
                      child: Text('解除 CP 关系'),
                    ),
                  ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _invitationCard(CpInvitation invitation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _CommunitySection(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: <Widget>[
            _LetterAvatar(label: invitation.nickname),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    invitation.nickname,
                    style: const TextStyle(
                      color: _CommunityPalette.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    invitation.createdAt,
                    style: const TextStyle(
                      color: _CommunityPalette.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _resolve(invitation, false),
              child: const Text('拒绝'),
            ),
            FilledButton.tonal(
              onPressed: _busy ? null : () => _resolve(invitation, true),
              child: const Text('接受'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('CP 关系')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  const _CommunityHero(
                    eyebrow: 'CP CONNECTION',
                    title: '把心意交给彼此确认',
                    subtitle: '发出邀请后，只有对方接受才会建立关系。',
                    icon: Icons.favorite_rounded,
                    colors: <Color>[
                      Color(0xFFB061CE),
                      Color(0xFFF276A7),
                      Color(0xFFFFB16C),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _InfoCard(
                    icon: Icons.favorite_outline_rounded,
                    text: 'CP 关系由双方主动确认。这里不会提供随机配对或自动建立关系。',
                  ),
                  const SizedBox(height: 10),
                  _CommunitySection(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _userIdController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '对方用户 ID',
                              prefixIcon: Icon(Icons.person_search_outlined),
                              fillColor: Color(0xFFF7F5FF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _busy ? null : _request,
                          child: const Text('邀请'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeading(
                    title: '当前关系',
                    subtitle: '由双方共同确认的陪伴关系',
                  ),
                  const SizedBox(height: 10),
                  if (_relations.isEmpty)
                    const _InfoCard(
                      icon: Icons.favorite_border_rounded,
                      text: '当前没有已建立的 CP 关系。',
                    )
                  else
                    for (final CpRelation relation in _relations)
                      _relationCard(relation),
                  const SizedBox(height: 20),
                  _SectionHeading(
                    title: '待处理邀请',
                    subtitle: '${_invitations.length} 条邀请等待你的决定',
                  ),
                  const SizedBox(height: 10),
                  if (_invitations.isEmpty)
                    const _InfoCard(
                      icon: Icons.mark_email_read_outlined,
                      text: '当前没有待处理邀请。',
                    )
                  else
                    for (final CpInvitation invitation in _invitations)
                      _invitationCard(invitation),
                ],
              ),
            ),
    );
  }
}
