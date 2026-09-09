import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart'
    show RoomReopenRepository, BackendRoomLifecycleRepository;
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

class EditRoomPage extends StatefulWidget {
  const EditRoomPage({
    required this.roomId,
    this.repositoryOverride,
    super.key,
  });

  final String roomId;
  final RoomLifecycleRepository? repositoryOverride;

  @override
  State<EditRoomPage> createState() => _EditRoomPageState();
}

class _EditRoomPageState extends State<EditRoomPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _topicTitleController = TextEditingController();
  final TextEditingController _topicContentController = TextEditingController();
  final TextEditingController _welcomeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  RoomLifecycleRepository? _repositoryInstance;
  RoomLifecycleRepository get _repository => _repositoryInstance!;
  RoomLifecycleCapabilities get _capabilities => _repository.capabilities;
  RoomConfiguration? _room;
  _RoomConflictReview? _conflictReview;
  RoomAccessMode _accessMode = RoomAccessMode.publicRoom;
  bool _showInHall = true;
  bool _autoLockMic = false;
  bool _loading = true;
  bool _saving = false;
  bool _closing = false;
  String? _error;
  int _epoch = 0;
  int? _editGeneration;
  AuthSessionManager? _session;
  int? _identity;
  bool _identityInvalidated = false;
  RoomConfiguration? _pendingSave;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance =
        widget.repositoryOverride ??
        AppDependencyScope.of(context).roomLifecycleRepository;
    _session = context
        .dependOnInheritedWidgetOfExactType<AppDependencyScope>()
        ?.dependencies
        .sessionManager;
    _identity = _session?.identityGeneration;
    _session?.addListener(_onIdentityChanged);
    _load();
  }

  void _onIdentityChanged() {
    if (_session?.identityGeneration == _identity) return;
    _identityInvalidated = true;
    _invalidateEditor();
  }

  void _invalidateEditor() {
    if (!mounted) return;
    _epoch++;
    _passwordController.clear();
    setState(() {
      _room = null;
      _conflictReview = null;
      _pendingSave = null;
      _loading = _saving = _closing = false;
      _error = '账号或房间会话已变化，请退出后重新打开编辑页';
    });
  }

  bool _current(int epoch) {
    if (!mounted || epoch != _epoch) return false;
    final repository = _repository;
    if (_identityInvalidated ||
        _session?.identityGeneration != _identity ||
        (repository is BackendRoomLifecycleRepository &&
            repository.editGeneration != _editGeneration)) {
      _invalidateEditor();
      return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant EditRoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId == widget.roomId &&
        oldWidget.repositoryOverride == widget.repositoryOverride)
      return;
    _epoch++;
    _room = null;
    _pendingSave = null;
    _conflictReview = null;
    _passwordController.clear();
    _repositoryInstance =
        widget.repositoryOverride ??
        AppDependencyScope.of(context).roomLifecycleRepository;
    _load();
  }

  @override
  void dispose() {
    _epoch++;
    _session?.removeListener(_onIdentityChanged);
    _pendingSave = null;
    _passwordController.clear();
    _titleController.dispose();
    _topicTitleController.dispose();
    _topicContentController.dispose();
    _welcomeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_identityInvalidated || _pendingSave != null) return;
    final epoch = ++_epoch;
    final repository = _repository;
    _editGeneration = repository is BackendRoomLifecycleRepository
        ? repository.editGeneration
        : null;
    setState(() {
      _loading = true;
      _room = null;
      _error = null;
    });
    try {
      final RoomConfiguration room = await _repository.fetchRoom(widget.roomId);
      if (!_current(epoch)) {
        return;
      }
      setState(() {
        _applyAuthoritativeRoom(room);
        _loading = false;
      });
    } catch (error) {
      if (!_current(epoch)) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error, fallback: '房间信息加载失败，请重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(
        title: '编辑房间资料',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新权威状态',
            onPressed:
                _loading ||
                    _saving ||
                    _closing ||
                    _pendingSave != null ||
                    _identityInvalidated
                ? null
                : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _room == null
          ? _buildFailure()
          : _buildForm(),
    );
  }

  Widget _buildFailure() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.meeting_room_outlined, size: 48),
            const SizedBox(height: 18),
            Text(_error ?? '房间信息不可用', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (!_identityInvalidated)
              FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final RoomConfiguration room = _room!;
    final bool enabled = !_saving && !_closing;
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                RoomOxygenContextBar(
                  title: room.title,
                  subtitle:
                      '房间号 ${room.roomCode ?? room.roomId ?? widget.roomId} · 设置即时生效',
                  seed: room.roomId ?? room.roomCode ?? widget.roomId,
                  status: room.isOpen ? '开放中' : '已关闭',
                  statusColor: room.isOpen
                      ? RoomColors.success
                      : RoomColors.warning,
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  RoomOxygenNotice(
                    icon: Icons.error_outline_rounded,
                    message: _error!,
                    accent: RoomColors.warning,
                  ),
                ],
                if (_conflictReview != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _RoomConflictCard(
                    review: _conflictReview!,
                    onLoadAuthoritative: _loadAuthoritativeRoom,
                    onRetryClose: _conflictReview!.closeRequiresConfirmation
                        ? _confirmClose
                        : null,
                  ),
                ],
                const SizedBox(height: 18),
                RoomConfigurationForm(
                  formKey: _formKey,
                  titleController: _titleController,
                  topicTitleController: _topicTitleController,
                  topicContentController: _topicContentController,
                  welcomeController: _welcomeController,
                  passwordController: _passwordController,
                  allowExistingPassword: room.passwordConfigured,
                  accessMode: _accessMode,
                  showInHall: _showInHall,
                  autoLockMic: _autoLockMic,
                  supportsApprovalAccessMode:
                      _capabilities.supportsApprovalAccessMode,
                  supportsTopicTitle: _capabilities.supportsTopicTitle,
                  supportsAutoLockMic: _capabilities.supportsAutoLockMic,
                  canControlLifecycle: room.canControlLifecycle,
                  enabled: enabled && _pendingSave == null,
                  onAccessModeChanged: (RoomAccessMode value) {
                    if (value != RoomAccessMode.password)
                      _passwordController.clear();
                    setState(() => _accessMode = value);
                  },
                  onShowInHallChanged: (bool value) {
                    setState(() => _showInHall = value);
                  },
                  onAutoLockMicChanged: (bool value) {
                    setState(() => _autoLockMic = value);
                  },
                ),
                const SizedBox(height: 18),
                if (!room.isOpen)
                  const RoomOxygenNotice(
                    icon: Icons.info_outline_rounded,
                    message: '保存配置后仍保持关闭，仅房主可进入。重新开放使用已保存设置，请先保存需要修改的内容。',
                  ),
                if (!room.isOpen) const SizedBox(height: 18),
                if (room.canControlLifecycle &&
                    !room.isOpen &&
                    _repository is RoomReopenRepository)
                  OutlinedButton.icon(
                    key: const Key('edit-room-reopen-button'),
                    onPressed:
                        enabled && room.accessMode != RoomAccessMode.approval
                        ? _reopen
                        : null,
                    icon: const Icon(Icons.power_settings_new_rounded),
                    label: const Text('重新开放并进入房间'),
                  ),
                if (room.canControlLifecycle)
                  RoomOxygenSection(
                    title: '关闭房间',
                    subtitle: '关闭会结束当前会话，但不会删除账号或房间配置。',
                    icon: Icons.power_settings_new_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const RoomOxygenNotice(
                          icon: Icons.warning_amber_rounded,
                          message: '关闭后用户无法继续进入，当前成员会结束本次房间会话。',
                          accent: RoomColors.error,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('edit-room-close-button'),
                            onPressed: enabled && room.isOpen
                                ? _confirmClose
                                : null,
                            icon: _closing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.power_settings_new_rounded),
                            label: Text(
                              room.isOpen
                                  ? _conflictReview != null
                                        ? '重新确认后关闭'
                                        : '关闭房间'
                                  : '房间已关闭',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('edit-room-save-button'),
                onPressed: enabled && _accessMode != RoomAccessMode.approval
                    ? _save
                    : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _pendingSave != null
                      ? '重试原保存请求'
                      : _conflictReview != null
                      ? '重新确认后提交'
                      : '保存房间设置',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final epoch = _epoch;
    if (!_current(epoch) || _room == null || _saving || _closing) return;
    final RoomConfiguration current = _room!;
    if (_accessMode == RoomAccessMode.approval) {
      setState(() {
        _error = '请选择公开房或密码房后保存';
      });
      return;
    }
    if (_pendingSave == null && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final RoomConfiguration configuration =
        _pendingSave ??
        current.copyWith(
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
          passwordConfigured: current.passwordConfigured,
          showInHall: _showInHall,
          autoLockMic: _capabilities.supportsAutoLockMic ? _autoLockMic : false,
          availability: current.availability,
        );
    _pendingSave = configuration;
    try {
      await _repository.saveRoom(configuration);
      if (!mounted || !_current(epoch)) {
        return;
      }
      setState(() {
        _saving = false;
        _pendingSave = null;
        _passwordController.clear();
      });
      if (ModalRoute.of(context)?.isCurrent == true)
        Navigator.of(context).pop(true);
    } catch (error) {
      if (!_current(epoch)) {
        return;
      }
      if (_isVersionConflict(error)) {
        _pendingSave = null;
        await _recoverFromConflict(draft: configuration);
        return;
      }
      if (error is ApiException &&
          (error.code == 40936 ||
              error.code == 40937 ||
              error.kind == ApiFailureKind.unauthorized ||
              error.kind == ApiFailureKind.forbidden)) {
        _invalidateEditor();
        return;
      }
      setState(() {
        _saving = false;
        if (!_isAmbiguous(error)) _pendingSave = null;
        _error = _pendingSave != null
            ? '保存结果尚未确认，可重试原请求；不会改用新的房间会话'
            : _messageFor(error, fallback: '房间保存失败，请重试');
      });
    }
  }

  Future<void> _reopen() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        _room?.canControlLifecycle != true ||
        _pendingSave != null)
      return;
    final room = _room!;
    if (room.version == null) {
      setState(() => _error = '请刷新房间状态后重试');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (_repository as RoomReopenRepository).reopenRoom(
        widget.roomId,
        expectedVersion: room.version!,
      );
      if (!mounted || !_current(epoch)) return;
      // A new RoomPage performs normal enter and acquires a fresh lease.
      Navigator.of(context).pushReplacement<void, bool>(
        MaterialPageRoute<void>(
          builder: (_) => RoomPage(roomId: widget.roomId, title: room.title),
        ),
        result: true,
      );
    } catch (error) {
      if (!_current(epoch)) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error, fallback: '重新开放失败，请刷新后重试');
      });
    }
  }

  Future<void> _confirmClose() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        _room?.canControlLifecycle != true ||
        _pendingSave != null)
      return;
    final RoomConfiguration room = _room!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认关闭房间？'),
        content: Text('将关闭“${room.title}”，当前成员会结束本次房间会话。此操作不会被当作普通离房。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_current(epoch)) {
      return;
    }
    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      await _repository.closeRoom(widget.roomId, expectedVersion: room.version);
      if (!mounted || !_current(epoch)) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!_current(epoch)) {
        return;
      }
      if (_isVersionConflict(error)) {
        await _recoverFromConflict(
          draft: _currentDraft(),
          closeRequiresConfirmation: true,
        );
        return;
      }
      setState(() {
        _closing = false;
        _error = _messageFor(error, fallback: '关闭房间失败，请刷新后重试');
      });
    }
  }

  static String _messageFor(Object error, {required String fallback}) {
    return error is ApiException ? error.message : fallback;
  }

  Future<void> _recoverFromConflict({
    required RoomConfiguration draft,
    bool closeRequiresConfirmation = false,
  }) async {
    final epoch = _epoch;
    try {
      final RoomConfiguration authoritative = await _repository.fetchRoom(
        widget.roomId,
      );
      if (!_current(epoch)) {
        return;
      }
      setState(() {
        _applyAuthoritativeRoom(authoritative, draft: draft);
        _saving = false;
        _closing = false;
        _error = '内容已更新，请重新确认后提交';
        _conflictReview = _RoomConflictReview(
          authoritative: authoritative,
          draft: draft,
          closeRequiresConfirmation: closeRequiresConfirmation,
        );
      });
    } catch (error) {
      if (!_current(epoch)) {
        return;
      }
      setState(() {
        _saving = false;
        _closing = false;
        _error = _messageFor(error, fallback: '房间刷新失败，请重试');
      });
    }
  }

  RoomConfiguration _currentDraft() {
    final RoomConfiguration base = _room!;
    return base.copyWith(
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
      passwordConfigured: base.passwordConfigured,
      showInHall: _showInHall,
      autoLockMic: _capabilities.supportsAutoLockMic ? _autoLockMic : false,
      availability: base.availability,
    );
  }

  void _applyAuthoritativeRoom(
    RoomConfiguration room, {
    RoomConfiguration? draft,
  }) {
    _room = room;
    if (draft == null) {
      _titleController.text = room.title;
      _topicTitleController.text = room.topicTitle;
      _topicContentController.text = room.topicContent;
      _welcomeController.text = room.welcomeMessage;
      _passwordController.text = room.password;
      _accessMode = room.accessMode;
      _showInHall = room.showInHall;
      _autoLockMic = room.autoLockMic;
      _conflictReview = null;
      return;
    }
    _titleController.text = draft.title;
    _topicTitleController.text = draft.topicTitle;
    _topicContentController.text = draft.topicContent;
    _welcomeController.text = draft.welcomeMessage;
    _passwordController.text = draft.password;
    _accessMode = draft.accessMode;
    _showInHall = draft.showInHall;
    _autoLockMic = draft.autoLockMic;
  }

  void _loadAuthoritativeRoom() {
    if (!_current(_epoch)) return;
    final RoomConfiguration? authoritative = _conflictReview?.authoritative;
    if (authoritative == null) {
      return;
    }
    setState(() {
      _applyAuthoritativeRoom(authoritative);
      _error = null;
    });
  }

  static bool _isVersionConflict(Object error) =>
      error is ApiException && error.code == 40945;

  static bool _isAmbiguous(Object error) =>
      error is! ApiException ||
      error.code == 40901 ||
      error.code == 40902 ||
      {
        ApiFailureKind.network,
        ApiFailureKind.timeout,
        ApiFailureKind.server,
        ApiFailureKind.protocol,
      }.contains(error.kind);
}

class _RoomConflictReview {
  const _RoomConflictReview({
    required this.authoritative,
    required this.draft,
    this.closeRequiresConfirmation = false,
  });

  final RoomConfiguration authoritative;
  final RoomConfiguration draft;
  final bool closeRequiresConfirmation;
}

class _RoomConflictCard extends StatelessWidget {
  const _RoomConflictCard({
    required this.review,
    required this.onLoadAuthoritative,
    this.onRetryClose,
  });

  final _RoomConflictReview review;
  final VoidCallback onLoadAuthoritative;
  final VoidCallback? onRetryClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const RoomOxygenNotice(
          icon: Icons.sync_problem_rounded,
          title: '已同步最新内容',
          message: '内容已更新，请重新确认后提交。当前输入仍保留在表单中。',
          accent: RoomColors.warning,
        ),
        const SizedBox(height: 12),
        RoomOxygenSection(
          title: '最新内容对照',
          subtitle: '需要放弃当前输入时，可直接载入最新内容。',
          icon: Icons.compare_arrows_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RoomConflictField(
                label: '房间名称',
                authoritative: review.authoritative.title,
                draft: review.draft.title,
              ),
              const SizedBox(height: 12),
              _RoomConflictField(
                label: '话题标题',
                authoritative: review.authoritative.topicTitle,
                draft: review.draft.topicTitle,
              ),
              const SizedBox(height: 12),
              _RoomConflictField(
                label: '话题内容',
                authoritative: review.authoritative.topicContent,
                draft: review.draft.topicContent,
              ),
              const SizedBox(height: 12),
              _RoomConflictField(
                label: '欢迎语',
                authoritative: review.authoritative.welcomeMessage,
                draft: review.draft.welcomeMessage,
              ),
              const SizedBox(height: 12),
              Text(
                '最新版本 ${review.authoritative.version ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onLoadAuthoritative,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('载入最新内容'),
                    ),
                    if (onRetryClose != null)
                      FilledButton.tonalIcon(
                        key: const Key('edit-room-close-retry-button'),
                        onPressed: onRetryClose,
                        icon: const Icon(Icons.power_settings_new_rounded),
                        label: const Text('重新确认后关闭'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomConflictField extends StatelessWidget {
  const _RoomConflictField({
    required this.label,
    required this.authoritative,
    required this.draft,
  });

  final String label;
  final String authoritative;
  final String draft;

  @override
  Widget build(BuildContext context) {
    final bool same = authoritative == draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          '服务端：${authoritative.isEmpty ? '未填写' : authoritative}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          same ? '当前输入：与服务端一致' : '当前输入：${draft.isEmpty ? '未填写' : draft}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: same ? RoomColors.success : RoomColors.warning,
          ),
        ),
      ],
    );
  }
}
