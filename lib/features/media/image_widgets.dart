import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/app_dependency_scope.dart';
import '../../core/media/media_files.dart';
import '../../core/media/media_identity.dart';
import '../../core/media/media_models.dart';
import 'app_image_media_host.dart';

AppImageMediaHost? imageHostOf(BuildContext context) => context
    .dependOnInheritedWidgetOfExactType<AppDependencyScope>()
    ?.dependencies
    .imageMediaHost;

/// A page may detach this binding, never dispose its app-owned draft.
class ImagePageBinding extends ChangeNotifier {
  ImagePageBinding(this.host, String key, MediaPurpose purpose)
    : identity = host.identity,
      draft = host.draft(key, purpose) {
    host.addListener(_changed);
  }
  final AppImageMediaHost host;
  final (int, int) identity;
  final ImageDraft draft;
  bool get current => host.identity == identity;
  void _changed() => notifyListeners();
  @override
  void dispose() {
    host.removeListener(_changed);
    super.dispose();
  }
}

class ImageAttachmentEditor extends StatelessWidget {
  const ImageAttachmentEditor({required this.binding, super.key});
  final ImagePageBinding binding;
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted && binding.current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(imageError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: binding,
    builder: (context, _) {
      if (!binding.current) return const Text('账号已变化，请重新打开页面');
      final draft = binding.draft;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('media-pick-images'),
            onPressed:
                draft.locked ||
                    draft.picking ||
                    draft.images.length >= draft.purpose.maximumCount
                ? null
                : () => _run(context, () => binding.host.pick(draft)),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              '选择图片 ${draft.images.length}/${draft.purpose.maximumCount}',
            ),
          ),
          const Text('每张不超过10MB。仅服务端确认就绪的图片会随内容提交。'),
          if (draft.locked) const Text('提交结果待确认，已保留原内容与请求；请再次点提交恢复，不会换内容重发。'),
          for (final image in draft.images)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '图片 ${draft.images.indexOf(image) + 1} · ${image.status?.state.wire ?? (image.attempted ? '结果未知' : '待上传')}',
                  ),
                  if (image.error != null) Text(image.error!),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: draft.locked || image.flight != null
                            ? null
                            : () => _run(
                                context,
                                () => binding.host.upload(
                                  draft,
                                  image,
                                  recover: image.attempted,
                                ),
                              ),
                        child: Text(
                          image.flight != null
                              ? '处理中…'
                              : image.attempted
                              ? '查询原资产'
                              : '上传图片',
                        ),
                      ),
                      if (image.status?.state == MediaAssetState.quarantined ||
                          image.status?.state == MediaAssetState.uploading ||
                          (image.status?.state == MediaAssetState.allocated &&
                              !image.putAttempted &&
                              image.source != null))
                        TextButton(
                          onPressed: draft.locked || image.flight != null
                              ? null
                              : () => _run(
                                  context,
                                  () => binding.host.upload(draft, image),
                                ),
                          child: const Text('重新检查就绪'),
                        ),
                      TextButton(
                        onPressed: draft.locked || image.flight != null
                            ? null
                            : () => _run(
                                context,
                                () async => binding.host.remove(draft, image),
                              ),
                        child: const Text('移除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          for (final image in draft.retainedUploads)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('已移除图片 · ${image.status?.state.wire ?? '结果未知'}'),
              subtitle: const Text('本机副本已清理，原请求仍保留；仅查询，不会随内容提交。'),
              trailing: TextButton(
                onPressed: image.flight != null
                    ? null
                    : () => _run(
                        context,
                        () => binding.host.upload(draft, image, recover: true),
                      ),
                child: const Text('查询原资产'),
              ),
            ),
        ],
      );
    },
  );
}

class ControlledImages extends StatelessWidget {
  const ControlledImages({required this.media, this.host, super.key});
  final List<MediaReference> media;
  final AppImageMediaHost? host;
  @override
  Widget build(BuildContext context) {
    final owner = host ?? imageHostOf(context);
    if (owner == null || !owner.enabled) return const Text('当前环境不能读取受控图片');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final image in media)
          _ControlledImage(
            key: ValueKey((image.assetId, image.version)),
            host: owner,
            media: image,
          ),
      ],
    );
  }
}

class _ControlledImage extends StatefulWidget {
  const _ControlledImage({required this.host, required this.media, super.key});
  final AppImageMediaHost host;
  final MediaReference media;
  @override
  State<_ControlledImage> createState() => _ControlledImageState();
}

class _ControlledImageState extends State<_ControlledImage> {
  MediaIdentityScope? _bound;
  MediaTemporaryFile? _file;
  FileImage? _provider;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    try {
      _bound = widget.host.scope;
    } catch (error) {
      _error = imageError(error);
    }
    widget.host.addListener(_changed);
  }

  void _clear() {
    final provider = _provider;
    _provider = null;
    if (provider != null) unawaited(provider.evict());
    final file = _file;
    _file = null;
    if (file != null) unawaited(file.dispose().catchError((Object _) {}));
  }

  void _changed() {
    if (_bound?.isCurrent != true && mounted) {
      _clear();
      setState(() {
        _busy = false;
        _error = '账号已变化，图片已清理，请重新打开内容';
      });
    }
  }

  Future<void> _load() async {
    final bound = _bound;
    if (_busy || bound == null || !bound.isCurrent) return;
    _clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.host.download(widget.media, bound);
      if (!mounted || !bound.isCurrent) {
        await file.dispose();
        return;
      }
      setState(() {
        _file = file;
        _provider = FileImage(File(file.path));
      });
    } catch (error) {
      if (mounted && bound.isCurrent)
        setState(() {
          _clear();
          _error = imageError(error);
        });
    } finally {
      if (mounted && bound.isCurrent) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.host.removeListener(_changed);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_provider != null && _bound?.isCurrent == true)
        Image(
          image: _provider!,
          fit: BoxFit.contain,
          height: 200,
          errorBuilder: (_, _, _) => const Text('图片内容无效，无法预览'),
        ),
      if (_error != null) Text(_error!),
      TextButton.icon(
        onPressed: _busy || _bound?.isCurrent != true ? null : _load,
        icon: const Icon(Icons.image_outlined),
        label: Text(
          _busy
              ? '读取图片…'
              : _error != null
              ? '重试读取图片'
              : '查看图片',
        ),
      ),
    ],
  );
}
