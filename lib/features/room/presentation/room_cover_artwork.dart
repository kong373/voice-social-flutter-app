import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/design_system/runtime_surfaces.dart';
import '../../../core/media/media_files.dart';
import '../../../core/media/media_identity.dart';
import '../../../core/media/media_models.dart';
import '../../media/app_image_media_host.dart';
import '../../media/image_widgets.dart' show imageHostOf;
import '../domain/room_image_models.dart';

class RoomCoverArtwork extends StatelessWidget {
  const RoomCoverArtwork({
    required this.roomId,
    required this.media,
    required this.seed,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.child,
    super.key,
  });
  final String roomId;
  final MediaReference? media;
  final String seed;
  final double height;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) => media == null
      ? OriginalRoomArtwork(
          seed: seed,
          height: height,
          borderRadius: borderRadius,
          child: child,
        )
      : ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RoomMediaImage(
                  key: ValueKey(('cover', roomId)),
                  media: media,
                  placeholder: OriginalRoomArtwork(
                    seed: seed,
                    height: height,
                    borderRadius: borderRadius,
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x08000000), Color(0xA6000018)],
                      ),
                    ),
                  ),
                ),
                if (child != null) child!,
              ],
            ),
          ),
        );
}

/// No URL, shared image cache or unbounded byte buffer. Each view owns its
/// authenticated download scope and evicts its decoded image on invalidation.
class RoomMediaImage extends StatefulWidget {
  const RoomMediaImage({
    required this.media,
    this.host,
    this.placeholder,
    this.contextChanges,
    this.contextIsCurrent,
    this.fit = BoxFit.cover,
    super.key,
  });
  final MediaReference? media;
  final AppImageMediaHost? host;
  final Widget? placeholder;
  final Listenable? contextChanges;
  final bool Function()? contextIsCurrent;
  final BoxFit fit;
  @override
  State<RoomMediaImage> createState() => _RoomMediaImageState();
}

class _RoomMediaImageState extends State<RoomMediaImage> {
  AppImageMediaHost? _host;
  MediaIdentityScope? _scope;
  Listenable? _changes;
  MediaTemporaryFile? _file;
  FileImage? _provider;
  int _epoch = 0;
  bool _busy = false;
  bool _invalidated = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = widget.host ?? imageHostOf(context);
    if (identical(_host, host)) return;
    _host = host;
    _start();
  }

  @override
  void didUpdateWidget(covariant RoomMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameRoomMedia(oldWidget.media, widget.media) ||
        oldWidget.contextChanges != widget.contextChanges ||
        oldWidget.host != widget.host) {
      _host = widget.host ?? imageHostOf(context);
      if (!_invalidated) _start();
    } else if (widget.contextIsCurrent?.call() == false) {
      _changed();
    }
  }

  void _clear() {
    final provider = _provider;
    _provider = null;
    if (provider != null) unawaited(provider.evict());
    final file = _file;
    _file = null;
    if (file != null) unawaited(file.dispose().catchError((Object _) {}));
  }

  void _stop() {
    _epoch++;
    _changes?.removeListener(_changed);
    _changes = null;
    _scope?.dispose();
    _scope = null;
    _clear();
  }

  void _start() {
    _stop();
    _error = null;
    _busy = false;
    final host = _host;
    if (host == null || !host.enabled || widget.media == null) return;
    try {
      final media = widget.media!;
      parseRoomMedia(media.toJson(), media.purpose);
      _changes = Listenable.merge([host.changes, widget.contextChanges]);
      _scope = MediaIdentityScope(
        currentUserId: host.userId,
        identityGeneration: host.generation,
        changes: _changes!,
        contextIsCurrent: () => widget.contextIsCurrent?.call() ?? true,
      );
      _changes!.addListener(_changed);
      unawaited(_load());
    } catch (_) {
      _error = '房间图片暂不可用';
    }
  }

  void _changed() {
    if (!mounted || _scope?.isCurrent == true) return;
    _invalidated = true;
    _stop();
    setState(() {
      _busy = false;
      _error = '房间或账号已变化，图片已清理';
    });
  }

  Future<void> _load() async {
    final scope = _scope;
    final host = _host;
    final media = widget.media;
    if (_busy ||
        scope == null ||
        !scope.isCurrent ||
        host == null ||
        media == null)
      return;
    final epoch = _epoch;
    _clear();
    _busy = true;
    _error = null;
    try {
      final file = await host.download(media, scope);
      if (!mounted || epoch != _epoch || !scope.isCurrent) {
        await file.dispose();
        return;
      }
      setState(() {
        _file = file;
        _provider = _RoomFileImage(File(file.path));
      });
    } catch (_) {
      if (mounted && epoch == _epoch && scope.isCurrent) {
        _clear();
        setState(() => _error = '房间图片读取失败');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.placeholder ?? const ColoredBox(color: Color(0xFF211A35)),
      if (_provider != null && _scope?.isCurrent == true)
        Image(
          image: _provider!,
          fit: widget.fit,
          errorBuilder: (_, _, _) => const Center(child: Text('房间图片无法显示')),
        ),
      if (_error != null)
        Align(
          alignment: Alignment.bottomRight,
          child: TextButton(
            onPressed: _invalidated || _busy
                ? null
                : () {
                    setState(() {});
                    _load();
                  },
            child: Text(_invalidated ? '图片已清理' : '重试图片'),
          ),
        ),
    ],
  );
}

/// Image.errorBuilder loses its listener when the widget is removed. Observe
/// this stream's first outcome even after eviction/unlink, so a pending file
/// read cannot report a late error globally. This owns no file lifetime and
/// never updates UI; every received image clone and the listener are released.
class _RoomFileImage extends FileImage {
  const _RoomFileImage(super.file);

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    final completer = super.loadImage(key, decode);
    late final ImageStreamListener pending;
    pending = ImageStreamListener((image, _) {
      image.dispose();
      completer.removeListener(pending);
    }, onError: (_, _) => completer.removeListener(pending));
    completer.addListener(pending);
    return completer;
  }
}
