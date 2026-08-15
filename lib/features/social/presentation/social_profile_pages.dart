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
      return SafeArea(
        child: _error == null
            ? const Center(child: CircularProgressIndicator())
            : _ErrorState(message: _error!, onRetry: _load),
      );
    }
    final SocialProfile profile = _profile!;
    final AppDependencyScope scope =
        context.dependOnInheritedWidgetOfExactType<AppDependencyScope>()!;
    final int currentVersion =
        int.tryParse(scope.dependencies.environment.clientInnerVersion) ?? 1;
    final int platformType = scope.dependencies.environment.clientType
            .toLowerCase()
            .contains('ios')
        ? 2
        : 1;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
          children: <Widget>[
            _ProfileHeader(profile: profile),
            const SizedBox(height: 16),
            _Metrics(profile: profile),
            const SizedBox(height: 18),
            _Section(
              title: '个人与关系',
              children: <Widget>[
                _Entry(
                  icon: Icons.edit_outlined,
                  title: '编辑个人资料',
                  subtitle: '昵称、签名、生日与所在地',
                  onTap: () => _open(
                    EditProfilePage(initialProfile: profile),
                    refresh: true,
                  ),
                ),
                _Entry(
                  icon: Icons.people_outline_rounded,
                  title: '关注、粉丝与好友',
                  subtitle: '按关系类型查看用户列表',
                  onTap: () => _open(const RelationsPage()),
                ),
                _Entry(
                  icon: Icons.person_add_alt_1_outlined,
                  title: '好友请求',
                  subtitle: _repository.supportsFriendRequestWorkflow
                      ? '处理待确认的好友请求'
                      : '当前后端未提供接受或拒绝协议',
                  onTap: () => _open(const FriendRequestsPage()),
                ),
                _Entry(
                  icon: Icons.visibility_outlined,
                  title: '访客记录',
                  subtitle: '谁看过我与我看过谁',
                  onTap: () => _open(const VisitorRecordsPage()),
                ),
                _Entry(
                  icon: Icons.lock_outline_rounded,
                  title: '隐私与黑名单',
                  subtitle: '关系限制与已屏蔽用户',
                  onTap: () => _open(const PrivacyBlacklistPage()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: '钱包与服务',
              children: <Widget>[
                _Entry(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '钱包、订单与收益',
                  subtitle: '流水、订单、退款、收益与提现',
                  onTap: () => _open(
                    CommerceHubPage(account: widget.session?.mobile ?? ''),
                  ),
                ),
                _Entry(
                  icon: Icons.support_agent_outlined,
                  title: '帮助与客服',
                  subtitle: '提交反馈并查看处理说明',
                  onTap: () => _open(const HelpCenterPage()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: '账号',
              children: <Widget>[
                _Entry(
                  icon: Icons.security_outlined,
                  title: '账号与安全',
                  subtitle: '权限、实名、设备、申诉、注销与青少年模式',
                  onTap: () => _open(AccountComplianceHubPage(
                    account: widget.session?.mobile ?? profile.account,
                    currentVersion: currentVersion,
                    platformType: platformType,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
            ),
          ],
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
    _nameController = TextEditingController(text: widget.initialProfile.user.name);
    _signatureController =
        TextEditingController(text: widget.initialProfile.user.signature);
    _birthdayController = TextEditingController(text: widget.initialProfile.birthday);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
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
      appBar: AppBar(title: const Text('编辑个人资料')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const _InfoBanner(
              text: '头像和封面上传需要对象存储适配器。本阶段先完成可直接联调的文字资料。',
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 1, label: Text('男')),
                ButtonSegment<int>(value: 2, label: Text('女')),
              ],
              selected: <int>{_sex},
              onSelectionChanged: (Set<int> value) =>
                  setState(() => _sex = value.first),
            ),
            const SizedBox(height: 10),
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
      final SocialProfile value = await AppDependencyScope.of(context)
          .socialRepository
          .fetchPublicProfile(widget.userId);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
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
        content: Text(next
            ? '加入黑名单后将取消现有关注或好友关系。'
            : '移出后不会自动恢复之前的关注关系。'),
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
    await AppDependencyScope.of(context).socialRepository.setBlocked(
          userId: widget.userId,
          blocked: next,
        );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SocialProfile? profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('个人主页')),
      body: profile == null
          ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _ProfileHeader(profile: profile),
                const SizedBox(height: 14),
                _Metrics(profile: profile),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: _busy || profile.user.isBlocked ? null : _follow,
                      child: Text(profile.user.isFollowing ? '取消关注' : '关注'),
                    ),
                    OutlinedButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('腾讯 IM 接入后开放私聊')),
                      ),
                      child: const Text('私聊'),
                    ),
                    OutlinedButton(onPressed: _block, child: Text(
                      profile.user.isBlocked ? '移出黑名单' : '加入黑名单',
                    )),
                  ],
                ),
                if (profile.user.roomId != null) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => RoomDeepLinkPage(
                          input: profile.user.roomId!,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.headphones_rounded),
                    label: const Text('进入正在收听的房间'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => ReportPage(
                        targetType: ReportTargetType.user,
                        targetId: '${profile.user.userId}',
                        targetName: profile.user.name,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.report_outlined),
                  label: const Text('举报用户'),
                ),
              ],
            ),
    );
  }
}
