import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance =
        widget.repositoryOverride ??
        AppDependencyScope.of(context).roomLifecycleRepository;
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _topicTitleController.dispose();
    _topicContentController.dispose();
    _welcomeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final RoomConfiguration room = await _repository.fetchRoom(widget.roomId);
      if (!mounted) {
        return;
      }
      setState(() {
        _applyAuthoritativeRoom(room);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
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
        title: '编辑与关闭房间',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新权威状态',
            onPressed: _loading || _saving || _closing ? null : _load,
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
            FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final RoomConfiguration room = _room!;
    final bool enabled =
        !_saving && !_closing && (room.isOpen || _capabilities.supportsReopen);
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
                  enabled: enabled,
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
                const SizedBox(height: 18),
                if (!room.isOpen && !_capabilities.supportsReopen)
                  const RoomOxygenNotice(
                    icon: Icons.info_outline_rounded,
                    message: '当前 development 后端尚未提供重新开放接口，已关闭房间仅可查看。',
                  ),
                if (!room.isOpen && !_capabilities.supportsReopen)
                  const SizedBox(height: 18),
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
                onPressed: enabled ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_conflictReview != null ? '重新确认后提交' : '保存房间设置'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final RoomConfiguration current = _room!;
    if (!current.isOpen && !_capabilities.supportsReopen) {
      setState(() {
        _error = '当前 development 后端尚未提供重新开放房间接口。';
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
    final RoomConfiguration configuration = current.copyWith(
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
    try {
      await _repository.saveRoom(configuration);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_isVersionConflict(error)) {
        await _recoverFromConflict(draft: configuration);
        return;
      }
      setState(() {
        _saving = false;
        _error = _messageFor(error, fallback: '房间保存失败，请重试');
      });
    }
  }

  Future<void> _confirmClose() async {
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
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      await _repository.closeRoom(widget.roomId, expectedVersion: room.version);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
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
    try {
      final RoomConfiguration authoritative = await _repository.fetchRoom(
        widget.roomId,
      );
      if (!mounted) {
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
      if (!mounted) {
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
      error is ApiException &&
      (error.code == 40945 || error.kind == ApiFailureKind.conflict);
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
