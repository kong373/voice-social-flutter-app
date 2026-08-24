import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_authority_display.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

class RoomTopicPage extends StatefulWidget {
  const RoomTopicPage({
    required this.roomId,
    required this.canEdit,
    this.roomTitle,
    super.key,
  });

  final String roomId;
  final bool canEdit;
  final String? roomTitle;

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
    _repositoryInstance = AppDependencyScope.of(
      context,
    ).roomOperationsRepository;
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
      final RoomTopic authoritative = await _repository.fetchTopic(
        widget.roomId,
      );
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
      Navigator.of(context).pop(authoritative);
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
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(title: widget.canEdit ? '编辑房间公告' : '房间公告'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _titleController.text.isEmpty
          ? _TopicError(message: _error!, onRetry: _load)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: <Widget>[
                  RoomOxygenContextBar(
                    title: roomAuthorityTitle(widget.roomTitle),
                    subtitle: '房间号 ${widget.roomId} · 公告与话题',
                    seed: widget.roomId,
                    status: widget.canEdit ? '可编辑' : '只读',
                    statusColor: widget.canEdit
                        ? RoomColors.accent
                        : RoomColors.textSecondary,
                  ),
                  const SizedBox(height: 18),
                  RoomOxygenSection(
                    title: '房间公告',
                    subtitle: '进房成员会先看到这段说明。',
                    icon: Icons.campaign_outlined,
                    child: Column(
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
                        const SizedBox(height: 10),
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
                      ],
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    RoomOxygenNotice(
                      icon: Icons.error_outline_rounded,
                      message: _error!,
                      accent: RoomColors.warning,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (widget.canEdit)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
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
                      ),
                    )
                  else
                    const RoomOxygenNotice(
                      icon: Icons.lock_outline_rounded,
                      message: '只有房主或房管可以修改公告。',
                      accent: RoomColors.textSecondary,
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
