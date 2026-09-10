import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../app/app_dependencies.dart';
import '../../../app/app_dependency_scope.dart';
import '../../../core/media/media_identity.dart';
import '../../../core/network/api_client.dart';
import '../domain/user_avatar_descriptor.dart';
import 'preset_avatar_view.dart';

/// Authoritative avatar display only. Null preserves the caller's legacy UI;
/// an uploaded reference is never routed to Image.network or ImageCache.
class UserAvatarView extends StatefulWidget {
  const UserAvatarView({
    required this.avatar,
    required this.userId,
    required this.fallback,
    this.size = 44,
    this.enabled = true,
    super.key,
  });
  final UserAvatarDescriptor? avatar;
  final int userId;
  final Widget fallback;
  final double size;
  final bool enabled;
  @override
  State<UserAvatarView> createState() => _UserAvatarViewState();
}

class _UserAvatarViewState extends State<UserAvatarView> {
  AppDependencies? _dependencies;
  (int?, int)? _viewer;
  MediaIdentityScope? _scope;
  ui.Image? _image;
  int _epoch = 0;
  bool _invalidIdentity = false;
  (int?, int) get _identity => (
    _dependencies!.sessionManager.session?.userId,
    _dependencies!.sessionManager.identityGeneration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindDependencies();
  }

  void _bindDependencies() {
    if (widget.avatar == null && _dependencies == null) return;
    final deps = context
        .dependOnInheritedWidgetOfExactType<AppDependencyScope>()
        ?.dependencies;
    if (identical(deps, _dependencies)) return;
    if (_dependencies != null) {
      _dependencies!.sessionManager.removeListener(_changed);
      _invalidIdentity = true;
    }
    _dependencies = deps;
    if (deps != null) {
      _viewer ??= _identity;
      deps.sessionManager.addListener(_changed);
    }
    _restart();
  }

  void _changed() {
    if (_viewer == _identity) return;
    // This mounted view can never adopt an old descriptor under another
    // account, even after A -> B -> A. A fresh authorized page must recreate it.
    _invalidIdentity = true;
    _clear();
    if (mounted) setState(() {});
  }

  void _clear() {
    _epoch++;
    _scope?.dispose();
    _scope = null;
    _image?.dispose();
    _image = null;
  }

  @override
  void didUpdateWidget(covariant UserAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dependencies == null && widget.avatar != null) {
      _bindDependencies();
      return;
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.enabled != widget.enabled ||
        (
              oldWidget.avatar?.kind,
              oldWidget.avatar?.reference,
              oldWidget.avatar?.version,
            ) !=
            (
              widget.avatar?.kind,
              widget.avatar?.reference,
              widget.avatar?.version,
            ))
      _restart();
  }

  void _restart() {
    _clear();
    final deps = _dependencies;
    final avatar = widget.avatar;
    if (deps == null ||
        _invalidIdentity ||
        !widget.enabled ||
        widget.userId <= 0 ||
        avatar == null ||
        _viewer != _identity ||
        _identity.$1 == null)
      return;
    final scope = MediaIdentityScope(
      currentUserId: () => deps.sessionManager.session?.userId ?? 0,
      identityGeneration: () => deps.sessionManager.identityGeneration,
      changes: deps.sessionManager,
    );
    _scope = scope;
    if (avatar.kind == UserAvatarKind.uploaded)
      unawaited(_load(avatar, scope, _epoch));
  }

  bool _current(MediaIdentityScope scope, int epoch) =>
      mounted &&
      !_invalidIdentity &&
      epoch == _epoch &&
      identical(scope, _scope) &&
      scope.isCurrent &&
      widget.enabled;

  Future<void> _load(
    UserAvatarDescriptor avatar,
    MediaIdentityScope scope,
    int epoch,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final bytes = await _dependencies!.privateMediaHost.api
          .readUserAvatarContent(
            assetId: avatar.reference,
            version: avatar.version!,
            identity: scope,
          );
      if (!_current(scope, epoch)) return;
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      if (!_current(scope, epoch)) return;
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!mounted || !_current(scope, epoch)) return;
      // Bound decoded display pixels as well as encoded bytes. Never upscale.
      final limit =
          (widget.size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1))
              .ceil()
              .clamp(1, 512);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) return;
      final ratio = (limit / (width > height ? width : height)).clamp(0.0, 1.0);
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * ratio).round().clamp(1, 512),
        targetHeight: (height * ratio).round().clamp(1, 512),
      );
      if (!_current(scope, epoch)) return;
      final frame = await codec.getNextFrame();
      image = frame.image;
      if (!_current(scope, epoch)) return;
      setState(() {
        _image = image;
        image = null;
      });
    } catch (_) {
      // Failed authorization/protocol/decode never reveals a URL, raw error or
      // previous image. The neutral placeholder is not a successful avatar.
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  void dispose() {
    _dependencies?.sessionManager.removeListener(_changed);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.avatar == null) return widget.fallback;
    final active =
        !_invalidIdentity && widget.enabled && _scope?.isCurrent == true;
    return Semantics(
      image: true,
      label:
          active &&
              (_image != null || widget.avatar!.kind == UserAvatarKind.preset)
          ? '用户头像'
          : '头像不可用',
      child: SizedBox.square(
        dimension: widget.size,
        child: ClipOval(
          child: !active
              ? _unavailable()
              : widget.avatar!.kind == UserAvatarKind.preset
              ? PresetAvatarView(
                  presetId: widget.avatar!.reference,
                  size: widget.size,
                )
              : _image == null
              ? _unavailable()
              : RawImage(image: _image, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _unavailable() => const ColoredBox(
    key: Key('user-avatar-unavailable'),
    color: Color(0xFF70647D),
    child: Icon(Icons.person_outline, color: Colors.white),
  );
}
