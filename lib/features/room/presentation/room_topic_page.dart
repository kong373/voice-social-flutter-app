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
    this.repositoryOverride,
    super.key,
  });

  final String roomId;
  final bool canEdit;
  final String? roomTitle;
  final RoomOperationsRepository? repositoryOverride;

  @override
  State<RoomTopicPage> createState() => _RoomTopicPageState();
}

class _RoomTopicPageState extends State<RoomTopicPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  RoomOperationsRepository? _repositoryInstance;
  RoomOperationsRepository get _repository => _repositoryInstance!;
  RoomTopic? _topic;
  _TopicConflictReview? _conflictReview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance =
        widget.repositoryOverride ??
        AppDependencyScope.of(context).roomOperationsRepository;
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
      setState(() {
        _applyAuthoritativeTopic(topic);
        _loading = false;
      });
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
      version: _topic?.version,
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
      if (_isVersionConflict(error)) {
        await _recoverFromConflict(requested);
        return;
      }
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _recoverFromConflict(RoomTopic draft) async {
    try {
      final RoomTopic authoritative = await _repository.fetchTopic(
        widget.roomId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyAuthoritativeTopic(authoritative, draft: draft);
        _submitting = false;
        _error = '内容已更新，请重新确认后提交';
        _conflictReview = _TopicConflictReview(
          authoritative: authoritative,
          draft: draft,
        );
      });
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

  void _applyAuthoritativeTopic(RoomTopic topic, {RoomTopic? draft}) {
    _topic = topic;
    if (draft == null) {
      _titleController.text = topic.title;
      _contentController.text = topic.content;
      _conflictReview = null;
      return;
    }
    _titleController.text = draft.title;
    _contentController.text = draft.content;
  }

  void _loadAuthoritativeTopic() {
    final RoomTopic? authoritative = _conflictReview?.authoritative;
    if (authoritative == null) {
      return;
    }
    setState(() {
      _applyAuthoritativeTopic(authoritative);
      _error = null;
    });
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
                  if (_conflictReview != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _TopicConflictCard(
                      review: _conflictReview!,
                      onLoadAuthoritative: _loadAuthoritativeTopic,
                    ),
                  ],
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
                        key: const Key('room-topic-submit-button'),
                        onPressed: _submitting ? null : _save,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _submitting
                              ? '正在保存'
                              : _conflictReview != null
                              ? '重新确认后提交'
                              : '保存公告',
                        ),
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

  static bool _isVersionConflict(Object error) =>
      error is ApiException &&
      (error.code == 40945 || error.kind == ApiFailureKind.conflict);
}

class _TopicConflictReview {
  const _TopicConflictReview({
    required this.authoritative,
    required this.draft,
  });

  final RoomTopic authoritative;
  final RoomTopic draft;
}

class _TopicConflictCard extends StatelessWidget {
  const _TopicConflictCard({
    required this.review,
    required this.onLoadAuthoritative,
  });

  final _TopicConflictReview review;
  final VoidCallback onLoadAuthoritative;

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
              _ConflictField(
                label: '服务端公告标题',
                authoritative: review.authoritative.title,
                draft: review.draft.title,
              ),
              const SizedBox(height: 12),
              _ConflictField(
                label: '服务端公告内容',
                authoritative: review.authoritative.content,
                draft: review.draft.content,
              ),
              const SizedBox(height: 12),
              Text(
                '最新版本 ${review.authoritative.version ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onLoadAuthoritative,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('载入最新内容'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConflictField extends StatelessWidget {
  const _ConflictField({
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
