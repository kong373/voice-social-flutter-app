import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';

class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({
    this.repositoryOverride,
    this.communityRepositoryOverride,
    super.key,
  });

  final RoomLifecycleRepository? repositoryOverride;
  final CommunityRepository? communityRepositoryOverride;

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _topicTitleController = TextEditingController();
  final TextEditingController _topicContentController = TextEditingController();
  final TextEditingController _welcomeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  RoomLifecycleRepository? _repositoryInstance;
  RoomLifecycleRepository get _repository => _repositoryInstance!;
  RoomLifecycleCapabilities get _capabilities => _repository.capabilities;
  late AppDependencies _dependencies;
  late int _identity;
  List<OwnedRoomSummary> _rooms = const [];
  bool _canCreate = false;
  bool _creating = false;
  bool _loadFailed = false;
  RoomAccessMode _accessMode = RoomAccessMode.publicRoom;
  bool _showInHall = true;
  bool _autoLockMic = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _dependencies = AppDependencyScope.of(context);
    _identity = _dependencies.sessionManager.identityGeneration;
    _dependencies.sessionManager.addListener(_identityChanged);
    _repositoryInstance =
        widget.repositoryOverride ?? _dependencies.roomLifecycleRepository;
    _load();
  }

  @override
  void dispose() {
    _dependencies.sessionManager.removeListener(_identityChanged);
    _titleController.dispose();
    _topicTitleController.dispose();
    _topicContentController.dispose();
    _welcomeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isCurrent =>
      mounted && _identity == _dependencies.sessionManager.identityGeneration;

  void _identityChanged() {
    if (_isCurrent || !mounted) return;
    setState(() {
      _rooms = const [];
      _canCreate = false;
      _creating = false;
      _loading = false;
      _loadFailed = true;
      _error = '账号已变化，请返回后重新打开';
    });
  }

  Future<void> _load() async {
    if (!_isCurrent) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final repository = _repository;
      if (repository is! OwnedRoomSelectionRepository) {
        throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '当前服务不支持名下房间列表',
        );
      }
      final (rooms, home) = await (
        (repository as OwnedRoomSelectionRepository).fetchOwnedRooms(),
        (widget.communityRepositoryOverride ??
                _dependencies.communityRepository)
            .fetchGuildHome(),
      ).wait;
      if (!_isCurrent) return;
      final guild = home.currentGuild;
      _rooms = rooms;
      _canCreate =
          home.currentGuildAuthority == GuildCurrentAuthority.authoritative &&
          guild != null &&
          guild.joined &&
          guild.status == GuildStatus.active &&
          guild.role == GuildRole.owner;
      setState(() => _loading = false);
    } catch (error) {
      if (!_isCurrent) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = _messageFor(error, fallback: '名下房间加载失败，请重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(title: _creating ? '创建房间' : '名下房间'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _buildFailure()
          : _creating
          ? _buildForm()
          : _buildSelection(),
    );
  }

  Widget _buildFailure() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 18),
            Text(_error ?? '房间配置加载失败', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_isCurrent)
              FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildSelection() => SafeArea(
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const RoomOxygenNotice(
            icon: Icons.meeting_room_outlined,
            message: '选择已有房间进入或管理。关闭房间仍计入公会可建房数量；新建上限以服务端为准。',
          ),
          const SizedBox(height: 16),
          if (_rooms.isEmpty) const Text('暂无名下房间'),
          for (final room in _rooms)
            Card(
              key: ValueKey('owned-room-${room.roomId}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text('房间号 ${room.roomCode}'),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          room.availability == RoomAvailability.closed
                              ? '已关闭'
                              : '已开放',
                        ),
                        Text(switch (room.accessMode) {
                          RoomAccessMode.password => '密码房',
                          RoomAccessMode.approval => '历史审批房',
                          RoomAccessMode.publicRoom => '公开房',
                        }),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => _openRoom(room, edit: false),
                          child: const Text('进入房间'),
                        ),
                        TextButton(
                          onPressed: () => _openRoom(room, edit: true),
                          child: const Text('管理房间'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_canCreate)
            FilledButton.icon(
              onPressed: _startCreating,
              icon: const Icon(Icons.add),
              label: const Text('创建新房间'),
            )
          else
            const Text('仅当前有效公会的会长可创建新房间'),
        ],
      ),
    ),
  );

  void _startCreating() {
    if (!_isCurrent || !_canCreate) return;
    _titleController.text = '我的语音房';
    _topicTitleController.text = '今晚话题';
    _welcomeController.text = '欢迎来到房间，请尊重彼此。';
    setState(() {
      _creating = true;
      _error = null;
    });
  }

  Future<void> _openRoom(OwnedRoomSummary room, {required bool edit}) async {
    if (!_isCurrent) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppDependencyScope(
          dependencies: _dependencies,
          child: edit
              ? EditRoomPage(
                  roomId: room.roomId,
                  repositoryOverride: _repository,
                )
              : RoomPage(roomId: room.roomId, title: room.title),
        ),
      ),
    );
    if (_isCurrent) await _load();
  }

  Widget _buildForm() {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                const RoomOxygenNotice(
                  icon: Icons.meeting_room_outlined,
                  title: '创建 1+8 九麦房',
                  message: '本次将创建一个新房间，可建数量由后台配置。',
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _creating = false),
                  child: const Text('返回名下房间'),
                ),
                if (_error != null) ...<Widget>[
                  _InlineError(message: _error!),
                  const SizedBox(height: 18),
                ],
                RoomConfigurationForm(
                  formKey: _formKey,
                  titleController: _titleController,
                  topicTitleController: _topicTitleController,
                  topicContentController: _topicContentController,
                  welcomeController: _welcomeController,
                  passwordController: _passwordController,
                  allowExistingPassword: false,
                  accessMode: _accessMode,
                  showInHall: _showInHall,
                  autoLockMic: _autoLockMic,
                  supportsApprovalAccessMode:
                      _capabilities.supportsApprovalAccessMode,
                  supportsTopicTitle: _capabilities.supportsTopicTitle,
                  supportsAutoLockMic: _capabilities.supportsAutoLockMic,
                  enabled: !_saving,
                  onAccessModeChanged: (RoomAccessMode value) {
                    setState(() => _accessMode = value);
                  },
                  onShowInHallChanged: (bool value) {
                    setState(() => _showInHall = value);
                  },
                  onAutoLockMicChanged: (bool value) {
                    setState(() => _autoLockMic = value);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _accessMode == RoomAccessMode.approval
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: const Text('创建并进入房间'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_isCurrent || !_canCreate || _saving) return;
    if (_accessMode == RoomAccessMode.approval) {
      setState(() {
        _error = '请选择公开房或密码房后保存';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final RoomConfiguration configuration = RoomConfiguration(
      title: _titleController.text.trim(),
      topicTitle: _capabilities.supportsTopicTitle
          ? _topicTitleController.text.trim()
          : '',
      topicContent: _topicContentController.text.trim(),
      welcomeMessage: _welcomeController.text.trim(),
      accessMode: _accessMode,
      password: _accessMode == RoomAccessMode.password
          ? _passwordController.text
          : '',
      showInHall: _showInHall,
      autoLockMic: _capabilities.supportsAutoLockMic ? _autoLockMic : false,
      availability: RoomAvailability.open,
    );
    try {
      final RoomLifecycleSaveResult result = await _repository.saveRoom(
        configuration,
      );
      if (!mounted || !_isCurrent) return;
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => AppDependencyScope(
            dependencies: _dependencies,
            child: RoomPage(roomId: result.roomId, title: configuration.title),
          ),
        ),
      );
    } catch (error) {
      if (!_isCurrent) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error, fallback: '房间保存失败，请重试');
      });
    }
  }

  static String _messageFor(Object error, {required String fallback}) {
    return error is ApiException ? error.message : fallback;
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return RoomOxygenNotice(
      icon: Icons.error_outline_rounded,
      message: message,
      accent: RoomColors.warning,
    );
  }
}
