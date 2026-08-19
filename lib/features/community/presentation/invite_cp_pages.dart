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
    return Scaffold(
      appBar: AppBar(title: const Text('邀请与渠道归属')),
      body: _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
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
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _KeyValue(label: '邀请码', value: data.inviteCode),
                          _KeyValue(label: '渠道归属', value: data.channelName),
                          _KeyValue(label: '绑定时间', value: data.boundAt),
                          _KeyValue(
                            label: '已邀请用户',
                            value: '${data.invitedUsers} 人',
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
                  icon: Icons.info_outline_rounded,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CP 关系')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _StateError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  const _InfoCard(
                    icon: Icons.favorite_outline_rounded,
                    text: 'CP 关系由双方主动确认。这里不会提供随机配对或自动建立关系。',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _userIdController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '对方用户 ID',
                            prefixIcon: Icon(Icons.person_search_outlined),
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
                  const SizedBox(height: 22),
                  Text('当前关系', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_relations.isEmpty)
                    const _InfoCard(
                      icon: Icons.favorite_border_rounded,
                      text: '当前没有已建立的 CP 关系。',
                    )
                  else
                    for (final CpRelation relation in _relations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            leading: CircleAvatar(
                              child: Text(_initial(relation.nickname)),
                            ),
                            title: Text(relation.nickname),
                            subtitle: Text(
                              '已相伴 ${relation.days} 天${relation.boundAt.isEmpty ? '' : ' · ${relation.boundAt}'}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    PublicProfilePage(userId: relation.userId),
                              ),
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 22),
                  Text('待处理邀请', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_invitations.isEmpty)
                    const _InfoCard(
                      icon: Icons.mark_email_read_outlined,
                      text: '当前没有待处理邀请。',
                    )
                  else
                    for (final CpInvitation invitation in _invitations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            leading: CircleAvatar(
                              child: Text(_initial(invitation.nickname)),
                            ),
                            title: Text(invitation.nickname),
                            subtitle: Text(invitation.createdAt),
                            trailing: Wrap(
                              spacing: 4,
                              children: <Widget>[
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(invitation, false),
                                  child: const Text('拒绝'),
                                ),
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(invitation, true),
                                  child: const Text('接受'),
                                ),
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
