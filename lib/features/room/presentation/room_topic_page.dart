import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';

class RoomTopicPage extends StatefulWidget {
  const RoomTopicPage({
    required this.roomId,
    required this.canEdit,
    super.key,
  });

  final String roomId;
  final bool canEdit;

  @override
  State<RoomTopicPage> createState() => _RoomTopicPageState();
}

class _RoomTopicPageState extends State<RoomTopicPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(context).roomOperationsRepository;
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final RoomTopic topic = await _repository.fetchTopic(widget.roomId);
      if (!mounted) {
        return;
      }
      _titleController.text = topic.title;
      _contentController.text = topic.content;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _save() async {
    if (_submitting || !widget.canEdit || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final RoomTopic requested = RoomTopic(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
    );
    try {
      await _repository.updateTopic(roomId: widget.roomId, topic: requested);
      final RoomTopic authoritative = await _repository.fetchTopic(widget.roomId);
      if (authoritative.title != requested.title ||
          authoritative.content != requested.content) {
        throw const ApiException(
          kind: ApiFailureKind.business,
          message: '房间公告已被其他操作更新，请重新确认',
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.canEdit ? '编辑房间公告' : '房间公告')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _titleController.text.isEmpty
              ? _TopicError(message: _error!, onRetry: _load)
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: <Widget>[
                      TextFormField(
                        controller: _titleController,
                        enabled: widget.canEdit && !_submitting,
                        maxLength: 64,
                        decoration: const InputDecoration(labelText: '公告标题'),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return '请输入公告标题';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contentController,
                        enabled: widget.canEdit && !_submitting,
                        maxLength: 500,
                        minLines: 6,
                        maxLines: 12,
                        decoration: const InputDecoration(
                          labelText: '公告内容',
                          alignLabelWithHint: true,
                        ),
                        validator: (String? value) {
                          if ((value ?? '').trim().isEmpty) {
                            return '请输入公告内容';
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (widget.canEdit)
                        FilledButton.icon(
                          onPressed: _submitting ? null : _save,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_submitting ? '正在保存' : '保存公告'),
                        )
                      else
                        Text(
                          '只有房主可以修改公告。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
    );
  }

  static String _messageFor(Object error) {
    return error is ApiException ? error.message : '公告加载或保存失败，请重试';
  }
}

class _TopicError extends StatelessWidget {
  const _TopicError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.info_outline_rounded, size: 44),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
