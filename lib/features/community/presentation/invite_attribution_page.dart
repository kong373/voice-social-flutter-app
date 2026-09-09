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
