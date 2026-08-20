import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({super.key});

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
  RoomConfiguration? _existing;
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
    _repositoryInstance = AppDependencyScope.of(
      context,
    ).roomLifecycleRepository;
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
      final RoomConfiguration? existing = await _repository.fetchOwnedRoom();
      if (!mounted) {
        return;
      }
      _existing = existing;
      if (existing != null) {
        _titleController.text = existing.title;
        _topicTitleController.text = existing.topicTitle;
        _topicContentController.text = existing.topicContent;
        _welcomeController.text = existing.welcomeMessage;
        _passwordController.text = existing.password;
        _accessMode = existing.accessMode;
        _showInHall = existing.showInHall;
        _autoLockMic = existing.autoLockMic;
      } else {
        _titleController.text = '我的语音房';
        _topicTitleController.text = '今晚话题';
        _welcomeController.text = '欢迎来到房间，请尊重彼此。';
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error, fallback: '房间配置加载失败，请重试');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: AppBar(title: const Text('创建房间')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _existing == null
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
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 18),
            Text(_error ?? '房间配置加载失败', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final RoomConfiguration? existing = _existing;
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: <Widget>[
                if (existing != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: RoomColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.meeting_room_outlined,
                          color: RoomColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            existing.isOpen
                                ? '当前账号已有个人房 ${existing.roomCode ?? existing.roomId}。保存后直接进入，不重复创建房间。'
                                : '当前个人房已关闭。保存后会重新开放并进入房间。',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
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
                  accessMode: _accessMode,
                  showInHall: _showInHall,
                  autoLockMic: _autoLockMic,
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(_buttonLabel(existing)),
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
    setState(() {
      _saving = true;
      _error = null;
    });
    final RoomConfiguration configuration = RoomConfiguration(
      roomId: _existing?.roomId,
      roomCode: _existing?.roomCode,
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
      availability: RoomAvailability.open,
      coverUrl: _existing?.coverUrl,
    );
    try {
      final RoomLifecycleSaveResult result = await _repository.saveRoom(
        configuration,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              RoomPage(roomId: result.roomId, title: configuration.title),
        ),
      );
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

  static String _buttonLabel(RoomConfiguration? existing) {
    if (existing == null) {
      return '创建并进入房间';
    }
    if (!existing.isOpen) {
      return '重新开放并进入房间';
    }
    return '保存并进入房间';
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RoomColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: RoomColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
