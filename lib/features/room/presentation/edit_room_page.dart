import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';

class EditRoomPage extends StatefulWidget {
  const EditRoomPage({required this.roomId, super.key});

  final String roomId;

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
  RoomConfiguration? _room;
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
    _repositoryInstance = AppDependencyScope.of(context).roomLifecycleRepository;
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
      _room = room;
      _titleController.text = room.title;
      _topicTitleController.text = room.topicTitle;
      _topicContentController.text = room.topicContent;
      _welcomeController.text = room.welcomeMessage;
      _passwordController.text = room.password;
      _accessMode = room.accessMode;
      _showInHall = room.showInHall;
      _autoLockMic = room.autoLockMic;
      setState(() => _loading = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑与关闭房间'),
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
            Text(
              _error ?? '房间信息不可用',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.tag_rounded, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '房间号 ${room.roomCode ?? room.roomId ?? widget.roomId} · ${room.isOpen ? '当前开放' : '当前关闭'}',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                RoomConfigurationForm(
                  formKey: _formKey,
                  titleController: _titleController,
                  topicTitleController: _topicTitleController,
                  topicContentController: _topicContentController,
                  welcomeController: _welcomeController,
                  passwordController: _passwordController,
                  accessMode: _accessMode,
                  showInHall: _showInHall,
                  autoLockMic: _autoLockMic,
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
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 18),
                Text(
                  '关闭房间',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFFF7A8D),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '关闭后用户不能继续进入，本次房间会话会结束。关闭不是退出房间，也不会删除账号。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: enabled && room.isOpen ? _confirmClose : null,
                  icon: _closing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new_rounded),
                  label: Text(room.isOpen ? '关闭房间' : '房间已关闭'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('保存房间设置'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final RoomConfiguration current = _room!;
    setState(() {
      _saving = true;
      _error = null;
    });
    final RoomConfiguration configuration = current.copyWith(
      title: _titleController.text.trim(),
      topicTitle: _topicTitleController.text.trim(),
      topicContent: _topicContentController.text.trim(),
      welcomeMessage: _welcomeController.text.trim(),
      accessMode: _accessMode,
      password: _accessMode == RoomAccessMode.password
          ? _passwordController.text
          : '',
      showInHall: _showInHall,
      autoLockMic: _autoLockMic,
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
        content: Text(
          '将关闭“${room.title}”，当前成员会结束本次房间会话。此操作不会被当作普通离房。',
        ),
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
      await _repository.closeRoom(widget.roomId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
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
}
