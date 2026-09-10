import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/media/media_identity.dart';
import '../../../core/media/media_models.dart';
import '../../media/app_image_media_host.dart';
import '../../media/media_labels.dart';
import '../domain/room_image_models.dart';
import 'room_cover_artwork.dart';

/// Upload journals remain app-owned; this editor owns only the current room
/// lease scope and temporary bytes. Closing it never revokes an unknown asset.
class RoomImageEditorBinding extends ChangeNotifier {
  RoomImageEditorBinding({
    required this.host,
    required String roomId,
    required bool Function() isCurrent,
    Listenable? roomChanges,
  }) {
    changes = Listenable.merge([host.changes, roomChanges]);
    scope = MediaIdentityScope(
      currentUserId: host.userId,
      identityGeneration: host.generation,
      changes: changes,
      contextIsCurrent: isCurrent,
    );
    cover = host.draft('room:$roomId:cover', MediaPurpose.roomCover);
    background = host.draft(
      'room:$roomId:background',
      MediaPurpose.roomBackground,
    );
    changes.addListener(_changed);
    host.addListener(_hostChanged);
  }
  final AppImageMediaHost host;
  late final Listenable changes;
  late final MediaIdentityScope scope;
  late final ImageDraft cover;
  late final ImageDraft background;
  bool _disposed = false;
  bool get current => !_disposed && scope.isCurrent;
  bool get busy => [
    cover,
    background,
  ].any((d) => d.picking || d.images.any((i) => i.flight != null));
  bool get canSave {
    if (!current || busy) return false;
    try {
      change(cover);
      change(background);
      return true;
    } catch (_) {
      return false;
    }
  }

  RoomImageChange change(ImageDraft draft) {
    scope.check();
    if (draft.fields['clear'] == 'true') return const RoomImageChange.clear();
    if (draft.images.isEmpty) return const RoomImageChange.unchanged();
    return RoomImageChange.replace(draft.ready.single);
  }

  MediaReference? preview(ImageDraft draft, MediaReference? original) {
    if (!current || draft.fields['clear'] == 'true') return null;
    return draft.images.isEmpty ? original : draft.images.single.status?.ready;
  }

  void _hostChanged() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    if (!current) {
      host.detachRoomDraft(cover);
      host.detachRoomDraft(background);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> pick(ImageDraft draft) async {
    scope.check();
    await host.pick(draft, identity: scope);
    scope.check();
    if (draft.images.isNotEmpty) draft.fields.remove('clear');
    notifyListeners();
  }

  Future<void> upload(
    ImageDraft draft,
    ImageUpload image, {
    bool recover = false,
  }) async {
    scope.check();
    try {
      await host.upload(draft, image, recover: recover, identity: scope);
      scope.check();
    } catch (_) {
      // A lost response never permits another PUT; retain metadata only.
      host.detachRoomDraft(draft);
      rethrow;
    }
  }

  void removeSelection(ImageDraft draft) {
    scope.check();
    for (final image in draft.images.toList()) host.remove(draft, image);
    draft.fields.remove('clear');
    notifyListeners();
  }

  void clear(ImageDraft draft) {
    removeSelection(draft);
    draft.fields['clear'] = 'true';
    notifyListeners();
  }

  void reset() {
    removeSelection(cover);
    removeSelection(background);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    changes.removeListener(_changed);
    host.removeListener(_hostChanged);
    scope.dispose();
    host.detachRoomDraft(cover);
    host.detachRoomDraft(background);
    super.dispose();
  }
}

class RoomImageEditor extends StatelessWidget {
  const RoomImageEditor({
    required this.binding,
    required this.cover,
    required this.background,
    required this.enabled,
    super.key,
  });
  final RoomImageEditorBinding binding;
  final MediaReference? cover;
  final MediaReference? background;
  final bool enabled;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted && binding.current)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(imageError(error))));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: binding,
    builder: (context, _) {
      if (!binding.current) return const Text('房间或账号已变化，图片已清理');
      if (!binding.host.enabled) return const Text('演示环境不上传房间图片');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('房间封面与背景', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('每张不超过10MB，支持JPEG、PNG、WebP。上传完成后才可保存。'),
          _slot(context, binding.cover, cover, '封面'),
          _slot(context, binding.background, background, '背景'),
        ],
      );
    },
  );

  Widget _slot(
    BuildContext context,
    ImageDraft draft,
    MediaReference? original,
    String label,
  ) {
    final available = enabled && !binding.busy;
    final media = binding.preview(draft, original);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          SizedBox(
            height: 110,
            child: RoomMediaImage(
              media: media,
              host: binding.host,
              contextChanges: binding,
              contextIsCurrent: () => binding.current,
              placeholder: Center(
                child: Text(
                  draft.fields['clear'] == 'true'
                      ? '保存后清除$label'
                      : media == null
                      ? '尚未设置$label'
                      : '读取$label…',
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: ValueKey('room-${draft.purpose.wire}-pick'),
                onPressed: available && draft.images.isEmpty
                    ? () => _run(context, () => binding.pick(draft))
                    : null,
                child: Text('选择$label'),
              ),
              if (original != null)
                TextButton(
                  onPressed: available ? () => binding.clear(draft) : null,
                  child: Text('清除$label'),
                ),
              if (draft.images.isNotEmpty || draft.fields['clear'] == 'true')
                TextButton(
                  onPressed: available
                      ? () => binding.removeSelection(draft)
                      : null,
                  child: Text('保留原$label'),
                ),
            ],
          ),
          for (final image in draft.images) ...[
            Text(
              mediaStateLabel(image.status?.state, attempted: image.attempted),
            ),
            if (image.error != null) Text(image.error!),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: available
                      ? () => _run(
                          context,
                          () => binding.upload(
                            draft,
                            image,
                            recover: image.attempted,
                          ),
                        )
                      : null,
                  child: Text(image.attempted ? '检查${label}上传状态' : '上传$label'),
                ),
                if (image.status?.state == MediaAssetState.uploading ||
                    image.status?.state == MediaAssetState.quarantined ||
                    (image.status?.state == MediaAssetState.allocated &&
                        !image.putAttempted &&
                        image.source != null))
                  TextButton(
                    onPressed: available
                        ? () =>
                              _run(context, () => binding.upload(draft, image))
                        : null,
                    child: Text('继续检查$label'),
                  ),
              ],
            ),
          ],
          for (final image in draft.retainedUploads)
            TextButton(
              onPressed: available
                  ? () => _run(
                      context,
                      () => binding.upload(draft, image, recover: true),
                    )
                  : null,
              child: Text('检查已取消的${label}上传（不会重新上传）'),
            ),
        ],
      ),
    );
  }
}
