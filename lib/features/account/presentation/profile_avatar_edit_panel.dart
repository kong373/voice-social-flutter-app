import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../domain/user_avatar_descriptor.dart';
import '../profile_avatar/profile_avatar_editor.dart';
import 'preset_avatar_view.dart';

/// The personal-avatar editor deliberately has no cover, camera or URL input.
class ProfileAvatarEditPanel extends StatelessWidget {
  const ProfileAvatarEditPanel({
    required this.editor,
    required this.onAvatarChanged,
    super.key,
  });

  final ProfileAvatarEditor editor;
  final ValueChanged<UserAvatarDescriptor?> onAvatarChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: editor,
      builder: (context, _) {
        final hasSelection =
            editor.selectedPresetId != null || editor.hasSelectedImage;
        final loadingCatalog =
            editor.uploadState == ProfileAvatarUploadState.loading &&
            editor.availablePresetIds.isEmpty;
        final saving = editor.busy;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0A36599A),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '头像',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '从相册选择图片，或使用公开预设头像。保存后会更新个人资料中的头像。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('profile-avatar-pick-image'),
                    onPressed: saving ? null : () => _pick(context),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择图片'),
                  ),
                ),
                if (editor.hasSelectedImage) ...<Widget>[
                  const SizedBox(height: 6),
                  const Text('已选择一张图片，点击保存后上传并绑定'),
                ],
                if (editor.availablePresetIds.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Text('公开预设', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  PresetAvatarPicker(
                    selectedId: editor.selectedPresetId,
                    availableIds: editor.availablePresetIds.toSet(),
                    enabled: !saving,
                    onSelected: editor.choosePreset,
                  ),
                ] else if (loadingCatalog) ...<Widget>[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (editor.error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    editor.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (!saving)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _reload(context),
                        child: const Text('重新读取头像设置'),
                      ),
                    ),
                ],
                if (editor.notice != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    editor.notice!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('profile-avatar-save'),
                    onPressed: !saving && hasSelection
                        ? () => _save(context)
                        : null,
                    child: Text(saving ? _savingLabel(editor) : '保存头像'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context) async {
    try {
      await editor.chooseImage();
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _save(BuildContext context) async {
    try {
      final snapshot = await editor.save();
      if (context.mounted) onAvatarChanged(snapshot.avatar);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _reload(BuildContext context) async {
    try {
      await editor.reload();
      final snapshot = editor.current;
      if (context.mounted && snapshot != null) {
        onAvatarChanged(snapshot.avatar);
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    final message = error is ApiException ? error.message : '头像操作未完成，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _savingLabel(ProfileAvatarEditor editor) {
  return switch (editor.uploadState) {
    ProfileAvatarUploadState.loading => '读取中…',
    ProfileAvatarUploadState.uploading => '上传中…',
    ProfileAvatarUploadState.binding => '保存中…',
    ProfileAvatarUploadState.rereading => '确认中…',
    _ => '保存中…',
  };
}
