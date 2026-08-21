part of 'social_pages.dart';

class PersonalCenterPage extends StatefulWidget {
  const PersonalCenterPage({
    required this.session,
    required this.onSignOut,
    super.key,
  });

  final AuthSession? session;
  final Future<void> Function() onSignOut;

  @override
  State<PersonalCenterPage> createState() => _PersonalCenterPageState();
}

class _PersonalCenterPageState extends State<PersonalCenterPage> {
  SocialProfile? _profile;
  String? _error;
  bool _signingOut = false;

  SocialRepository get _repository =>
      AppDependencyScope.of(context).socialRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profile == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final SocialProfile value = await _repository.fetchMyProfile();
      if (mounted) {
        setState(() {
          _profile = value;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _open(Widget page, {bool refresh = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
    if (refresh && mounted) {
      await _load();
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await widget.onSignOut();
    if (mounted) {
      setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return SocialSkySurface(
        child: SafeArea(
          child: _error == null
              ? const Center(child: CircularProgressIndicator())
              : _ErrorState(message: _error!, onRetry: _load),
        ),
      );
    }
    final SocialProfile profile = _profile!;
    final AppDependencyScope scope = context
        .dependOnInheritedWidgetOfExactType<AppDependencyScope>()!;
    final int currentVersion =
        int.tryParse(scope.dependencies.environment.clientInnerVersion) ?? 1;
    final int platformType =
        scope.dependencies.environment.clientType.toLowerCase().contains('ios')
        ? 2
        : 1;
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 34),
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Spacer(),
                  _OxygenTopButton(
                    icon: Icons.settings_outlined,
                    tooltip: '账号与安全',
                    onTap: () => _open(
                      AccountComplianceHubPage(
                        account: widget.session?.mobile ?? profile.account,
                        currentVersion: currentVersion,
                        platformType: platformType,
                      ),
                    ),
                  ),
                ],
              ),
              Transform.translate(
                offset: const Offset(0, -6),
                child: _ProfileHeader(profile: profile),
              ),
              const SizedBox(height: 8),
              _Metrics(profile: profile),
              const SizedBox(height: 14),
              _MineDecorationBanner(onTap: () => _open(const DecorationPage())),
              _OxygenPanel(
                radius: 0,
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    _OxygenFeatureShortcut(
                      icon: Icons.account_balance_wallet_rounded,
                      label: '钱包、订单与收益',
                      colors: const <Color>[
                        Color(0xFFFFD85F),
                        Color(0xFFFFA83F),
                      ],
                      onTap: () => _open(
                        CommerceHubPage(account: widget.session?.mobile ?? ''),
                      ),
                    ),
                    _OxygenFeatureShortcut(
                      icon: Icons.style_rounded,
                      label: '装扮',
                      colors: const <Color>[
                        Color(0xFFFFA7D0),
                        Color(0xFFF16BC6),
                      ],
                      onTap: () => _open(const DecorationPage()),
                    ),
                    _OxygenFeatureShortcut(
                      icon: Icons.person_outline_rounded,
                      label: '资料',
                      colors: const <Color>[
                        Color(0xFFA9B8FF),
                        Color(0xFF6879E7),
                      ],
                      onTap: () => _open(
                        EditProfilePage(initialProfile: profile),
                        refresh: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _OxygenPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _OxygenSectionLabel(
                      title: '最近进房',
                      trailing: InkWell(
                        onTap: () => _open(const SavedRoomsPage()),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '全部',
                              style: TextStyle(
                                color: SocialColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: SocialColors.textTertiary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _RecentRoomTile(
                            title: profile.user.roomId == null
                                ? '收藏的房间'
                                : '正在收听',
                            subtitle: profile.user.roomId == null
                                ? '去看看已保存的房间'
                                : 'ID ${profile.user.roomId}',
                            seed: profile.user.roomId ?? profile.account,
                            onTap: () => profile.user.roomId == null
                                ? _open(const SavedRoomsPage())
                                : _open(
                                    RoomDeepLinkPage(
                                      input: profile.user.roomId!,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _RecentRoomTile(
                            title: '我的收藏',
                            subtitle: '继续上次的听房时光',
                            seed: 'saved-${profile.account}',
                            onTap: () => _open(const SavedRoomsPage()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _OxygenPanel(
                padding: const EdgeInsets.fromLTRB(9, 12, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: _OxygenSectionLabel(title: '常用工具'),
                    ),
                    const SizedBox(height: 4),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 0,
                      crossAxisSpacing: 0,
                      childAspectRatio: 0.9,
                      children: <Widget>[
                        _OxygenToolShortcut(
                          icon: Icons.edit_outlined,
                          label: '编辑个人资料',
                          onTap: () => _open(
                            EditProfilePage(initialProfile: profile),
                            refresh: true,
                          ),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.people_outline_rounded,
                          label: '关注、粉丝与好友',
                          onTap: () => _open(const RelationsPage()),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.person_add_alt_1_rounded,
                          label: '好友请求',
                          onTap: () => _open(const FriendRequestsPage()),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.visibility_outlined,
                          label: '访客记录',
                          onTap: () => _open(const VisitorRecordsPage()),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.lock_outline_rounded,
                          label: '隐私与黑名单',
                          onTap: () => _open(const PrivacyBlacklistPage()),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.support_agent_outlined,
                          label: '帮助与客服',
                          onTap: () => _open(const HelpCenterPage()),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.security_outlined,
                          label: '账号安全',
                          onTap: () => _open(
                            AccountComplianceHubPage(
                              account:
                                  widget.session?.mobile ?? profile.account,
                              currentVersion: currentVersion,
                              platformType: platformType,
                            ),
                          ),
                        ),
                        _OxygenToolShortcut(
                          icon: Icons.logout_rounded,
                          label: _signingOut ? '退出中' : '退出登录',
                          onTap: _signingOut ? () {} : _signOut,
                        ),
                      ],
                    ),
                    if (!_repository.supportsFriendRequestWorkflow)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 2, 6, 0),
                        child: Text(
                          '好友请求协议未接入，页面保持只读说明。',
                          style: TextStyle(
                            color: SocialColors.textTertiary,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({required this.initialProfile, super.key});

  final SocialProfile initialProfile;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _signatureController;
  late final TextEditingController _birthdayController;
  late final TextEditingController _cityController;
  late int _sex;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialProfile.user.name,
    );
    _signatureController = TextEditingController(
      text: widget.initialProfile.user.signature,
    );
    _birthdayController = TextEditingController(
      text: widget.initialProfile.birthday,
    );
    _cityController = TextEditingController(text: widget.initialProfile.city);
    _sex = widget.initialProfile.sex == 1 ? 1 : 2;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _signatureController.dispose();
    _birthdayController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDependencyScope.of(context).socialRepository.updateMyProfile(
        nickname: _nameController.text,
        signature: _signatureController.text,
        sex: _sex,
        birthday: _birthdayController.text,
        city: _cityController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
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
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('编辑个人资料')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: <Widget>[
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: RuntimeAvatar(
                      seed: '${widget.initialProfile.user.userId}',
                      size: 76,
                    ),
                  ),
                  const Positioned(
                    right: -3,
                    bottom: 2,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: SocialColors.primary,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _InfoBanner(text: '头像和封面上传需要对象存储适配器。本阶段先完成可直接联调的文字资料。'),
            const SizedBox(height: 12),
            _OxygenPanel(
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _nameController,
                    maxLength: 64,
                    decoration: const InputDecoration(labelText: '昵称'),
                    validator: (String? value) =>
                        value == null || value.trim().isEmpty ? '请输入昵称' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _signatureController,
                    maxLength: 150,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '个性签名'),
                  ),
                  const SizedBox(height: 8),
                  _OxygenInlineTabs<int>(
                    items: const <int, String>{1: '男', 2: '女'},
                    value: _sex,
                    onChanged: (int value) => setState(() => _sex = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _birthdayController,
                    decoration: const InputDecoration(
                      labelText: '生日',
                      hintText: 'YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: '所在地'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '保存中…' : '保存资料'),
            ),
          ],
        ),
      ),
    );
  }
}

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({required this.userId, super.key});

  final int userId;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  SocialProfile? _profile;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profile == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final SocialProfile value = await AppDependencyScope.of(
        context,
      ).socialRepository.fetchPublicProfile(widget.userId);
      if (mounted) {
        setState(() {
          _profile = value;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _follow() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDependencyScope.of(context).socialRepository.setFollowing(
        userId: widget.userId,
        following: !_profile!.user.isFollowing,
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

  Future<void> _block() async {
    final bool next = !_profile!.user.isBlocked;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(next ? '加入黑名单？' : '移出黑名单？'),
        content: Text(next ? '加入黑名单后将取消现有关注或好友关系。' : '移出后不会自动恢复之前的关注关系。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await AppDependencyScope.of(
      context,
    ).socialRepository.setBlocked(userId: widget.userId, blocked: next);
    if (mounted) {
      await _load();
    }
  }

  void _openChat(SocialProfile profile) {
    final dependencies = AppDependencyScope.of(context);
    if (!dependencies.messageRepository.supportsPrivateHistory &&
        !dependencies.messageRepository.supportsPrivateSend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('私聊服务尚未配置，当前不能发起会话')));
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PrivateChatPage(
          conversation: ConversationSummary(
            id: 'conversation-${profile.user.userId}',
            kind: ConversationKind.privateChat,
            title: profile.user.name,
            lastMessage: '',
            updatedAt: DateTime.now(),
            unreadCount: 0,
            targetUserId: profile.user.userId,
            available: !profile.user.isBlocked,
            unavailableReason: profile.user.isBlocked ? '该用户已在黑名单中' : '',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SocialProfile? profile = _profile;
    return RoomPageScaffold(
      appBar: AppBar(
        title: const Text('个人主页'),
        actions: <Widget>[
          IconButton(
            tooltip: '举报用户',
            onPressed: profile == null
                ? null
                : () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => ReportPage(
                        targetType: ReportTargetType.user,
                        targetId: '${profile.user.userId}',
                        targetName: profile.user.name,
                      ),
                    ),
                  ),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: profile == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
              children: <Widget>[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: <Color>[
                          Color(0xFF75E7FF),
                          Color(0xFFC984FF),
                          Color(0xFFFFC875),
                        ],
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x786E68FF),
                          blurRadius: 28,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: RuntimeAvatar(
                      seed: '${profile.user.userId}',
                      size: 88,
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  profile.user.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'ID ${profile.account}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RoomColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  profile.user.signature.isEmpty
                      ? '愿每一次相遇都轻松一点。'
                      : profile.user.signature,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE9E4FA),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                RoomGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 13,
                  ),
                  radius: 18,
                  child: Row(
                    children: <Widget>[
                      _DarkMetric(value: profile.followingCount, label: '关注'),
                      _DarkMetric(value: profile.followerCount, label: '粉丝'),
                      _DarkMetric(value: profile.friendCount, label: '好友'),
                      _DarkMetric(value: profile.postCount, label: '动态'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy || profile.user.isBlocked
                            ? null
                            : _follow,
                        child: Text(profile.user.isFollowing ? '取消关注' : '关注'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: profile.user.isBlocked
                            ? null
                            : () => _openChat(profile),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x557F8AD6)),
                        ),
                        child: const Text('私聊'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 48,
                      child: OutlinedButton(
                        onPressed: _block,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x557F8AD6)),
                        ),
                        child: Icon(
                          profile.user.isBlocked
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
                if (profile.user.roomId != null) ...<Widget>[
                  const SizedBox(height: 16),
                  RoomGlassCard(
                    padding: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            RoomDeepLinkPage(input: profile.user.roomId!),
                      ),
                    ),
                    child: const ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(0x302EDCFB),
                        child: Icon(
                          Icons.headphones_rounded,
                          color: RoomColors.accent,
                        ),
                      ),
                      title: Text('正在收听'),
                      subtitle: Text('点击进入语音房'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const _ProfileStageShelves(),
              ],
            ),
    );
  }
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: RoomColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStageShelves extends StatelessWidget {
  const _ProfileStageShelves();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '主页陈列',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: <Widget>[
            Expanded(
              child: _StageSlot(
                icon: Icons.mic_external_on_rounded,
                title: '声音主页',
                subtitle: '公开声音和房间状态',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _StageSlot(
                icon: Icons.auto_awesome_rounded,
                title: '装扮展示',
                subtitle: '已穿戴的资料卡装扮',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StageSlot extends StatelessWidget {
  const _StageSlot({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x4D7F6DD6), Color(0x1611122B)],
        ),
        border: Border.all(color: const Color(0x337F8AD6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: RoomColors.accent, size: 23),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RoomColors.textSecondary,
              fontSize: 9,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
