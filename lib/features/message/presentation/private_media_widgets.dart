import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/media/media_files.dart';
import '../../../core/media/media_identity.dart';
import '../../../core/media/media_models.dart';
import '../../media/media_labels.dart';
import '../../media/private_media_host.dart';
import '../../media/private_media_native.dart';
import '../domain/message_models.dart';
import '../domain/message_repository.dart';

class PrivateMediaComposer extends StatefulWidget {
  const PrivateMediaComposer({
    required this.host,
    required this.repository,
    required this.conversation,
    required this.visible,
    required this.onSent,
    super.key,
  });
  final PrivateMediaHost host;
  final MediaPrivateMessageRepository repository;
  final ConversationSummary conversation;
  final bool visible;
  final ValueChanged<ChatMessage> onSent;
  @override
  State<PrivateMediaComposer> createState() => _PrivateMediaComposerState();
}

class _PrivateMediaComposerState extends State<PrivateMediaComposer>
    with WidgetsBindingObserver {
  PrivateMediaVisit? _visit;
  PrivateMediaIntent? _confirming;
  String? _error;
  bool _foreground = true;
  (int, int)? _identity;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.changes.addListener(_identityChanged);
    _identity = (widget.host.userId(), widget.host.generation());
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _bind();
  }

  void _bind() {
    if (!widget.visible ||
        !_foreground ||
        !widget.host.enabled ||
        widget.host.userId() <= 0)
      return;
    try {
      final visit = widget.host.visit(widget.conversation);
      _visit = visit;
      visit.addListener(_changed);
    } catch (e) {
      _error = privateMediaError(e);
    }
  }

  void _release() {
    _confirming = null;
    _visit?.removeListener(_changed);
    _visit?.dispose();
    _visit = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _identityChanged() {
    final next = (widget.host.userId(), widget.host.generation());
    if (next == _identity) return;
    _identity = next;
    _release();
    if (mounted)
      setState(() {
        _error = '登录状态已改变，请重新进入会话；原发送记录仍由原账号保留';
      });
  }

  @override
  void didUpdateWidget(PrivateMediaComposer old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host ||
        old.conversation.targetUserId != widget.conversation.targetUserId ||
        old.visible != widget.visible) {
      old.host.changes.removeListener(_identityChanged);
      widget.host.changes.addListener(_identityChanged);
      _release();
      _error = null;
      _bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // The native gallery temporarily covers the App. Its result is selection
    // only, never upload/send. Route or identity changes still dispose it.
    if (!_foreground && _visit?.picking != true) _release();
    if (_foreground && _visit == null && _error == null) _bind();
    _changed();
  }

  Future<void> _run(Future<void> Function(PrivateMediaVisit) action) async {
    final visit = _visit;
    if (visit == null || !visit.current || !_foreground || !widget.visible)
      return;
    setState(() => _error = null);
    try {
      await action(visit);
    } catch (e) {
      if (mounted && identical(_visit, visit) && visit.current)
        setState(() => _error = privateMediaError(e));
    }
  }

  Future<void> _cancelRecording() async {
    final old = _visit;
    final identity = _identity;
    if (old == null) return;
    _release();
    setState(() {});
    try {
      await old.cleanup;
    } catch (e) {
      if (mounted) setState(() => _error = privateMediaError(e));
      return;
    }
    if (!mounted ||
        _visit != null ||
        identity != _identity ||
        identity != (widget.host.userId(), widget.host.generation()))
      return;
    _bind();
    setState(() {});
  }

  Future<void> _send(PrivateMediaVisit visit, {bool confirmed = false}) async {
    final frozen = visit.intent;
    if (frozen == null) return;
    if (!confirmed) {
      setState(() => _confirming = frozen);
      return;
    }
    if (!identical(_confirming, frozen) ||
        !mounted ||
        !identical(_visit, visit) ||
        !visit.current ||
        !widget.visible ||
        !_foreground ||
        !identical(visit.intent, frozen))
      return;
    final receipt = await visit.send(widget.repository);
    if (mounted &&
        identical(_visit, visit) &&
        visit.current &&
        widget.visible &&
        _foreground) {
      setState(() => _confirming = null);
      widget.onSent(receipt);
    }
  }

  @override
  void dispose() {
    widget.host.changes.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit, intent = visit?.intent;
    final enabled =
        visit?.current == true &&
        visit?.busy == false &&
        widget.visible &&
        _foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: const Key('pm-pick-image'),
                onPressed:
                    enabled && intent == null && visit?.recording == false
                    ? () => _run((v) => v.pick(MediaPurpose.privateImage))
                    : null,
                icon: const Icon(Icons.image_outlined),
                label: const Text('图片'),
              ),
              TextButton.icon(
                key: const Key('pm-pick-video'),
                onPressed:
                    enabled && intent == null && visit?.recording == false
                    ? () => _run((v) => v.pick(MediaPurpose.privateVideo))
                    : null,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('视频'),
              ),
              TextButton.icon(
                key: const Key('pm-record'),
                onPressed: enabled && intent == null
                    ? () => _run(
                        (v) => v.recording
                            ? v.finishRecording()
                            : v.startRecording(),
                      )
                    : null,
                icon: Icon(
                  visit?.recording == true
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none,
                ),
                label: Text(visit?.recording == true ? '完成录音' : '录制语音'),
              ),
            ],
          ),
          if (visit?.recording == true)
            const Text('正在录音，最长60秒；离开或进入后台会取消录音，不会发送。'),
          if (visit?.recording == true)
            TextButton(
              onPressed: enabled ? _cancelRecording : null,
              child: const Text('取消录音'),
            ),
          if (_error != null || visit?.error != null)
            Text(_error ?? visit!.error!, key: const Key('pm-error')),
          if (!widget.host.enabled) const Text('演示环境不上传或发送媒体'),
          if (widget.host.enabled && intent == null && visit?.recording != true)
            const Text('图片≤10MB；语音≤60秒/10MB；视频≤30秒/100MB。'),
          if (intent != null) ...[
            if (identical(_confirming, intent)) ...[
              Text(
                intent.sendAttempted
                    ? '确认向本会话对象恢复原请求？不会更换文件或创建新请求。'
                    : '确认发送给 ${widget.conversation.title}？',
              ),
              Wrap(
                children: [
                  TextButton(
                    key: const Key('pm-confirm-send'),
                    onPressed: enabled
                        ? () => _run((v) => _send(v, confirmed: true))
                        : null,
                    child: const Text('确认发送'),
                  ),
                  TextButton(
                    onPressed: enabled
                        ? () => setState(() => _confirming = null)
                        : null,
                    child: const Text('暂不发送'),
                  ),
                ],
              ),
            ],
            Text(
              intent.sendAttempted
                  ? '发送结果待确认，已保留原请求'
                  : mediaStateLabel(
                      intent.status?.state,
                      attempted: intent.allocationAttempted,
                    ),
            ),
            Wrap(
              spacing: 6,
              children: [
                if (!intent.sendAttempted)
                  TextButton(
                    onPressed: enabled
                        ? () => _run(
                            (v) =>
                                v.upload(readOnly: intent.allocationAttempted),
                          )
                        : null,
                    child: Text(intent.allocationAttempted ? '检查上传状态' : '上传媒体'),
                  ),
                if (!intent.sendAttempted &&
                    {
                      MediaAssetState.uploading,
                      MediaAssetState.quarantined,
                    }.contains(intent.status?.state))
                  TextButton(
                    onPressed: enabled ? () => _run((v) => v.upload()) : null,
                    child: const Text('继续安全检查'),
                  ),
                if (intent.status?.state == MediaAssetState.ready ||
                    intent.sendAttempted)
                  TextButton(
                    key: const Key('pm-send'),
                    onPressed: enabled ? () => _run(_send) : null,
                    child: Text(intent.sendAttempted ? '恢复原发送' : '发送媒体'),
                  ),
                if (intent.canDiscard)
                  TextButton(
                    onPressed: enabled ? () => _run((v) => v.discard()) : null,
                    child: const Text('取消选择'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PrivateMediaBubble extends StatefulWidget {
  const PrivateMediaBubble({
    required this.message,
    required this.host,
    required this.visible,
    super.key,
  });
  final ChatMessage message;
  final PrivateMediaHost host;
  final bool visible;
  @override
  State<PrivateMediaBubble> createState() => _PrivateMediaBubbleState();
}

class _PrivateMediaBubbleState extends State<PrivateMediaBubble>
    with WidgetsBindingObserver {
  MediaIdentityScope? _scope;
  MediaTemporaryFile? _temporary;
  File? _file;
  PrivateLocalPlayer? _player;
  bool _busy = false, _foreground = true;
  String? _error;
  int _epoch = 0;
  void Function()? _unregister;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PrivateMediaBubble old) {
    super.didUpdateWidget(old);
    if (!widget.visible ||
        old.message.id != widget.message.id ||
        old.host != widget.host)
      _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _clear();
      if (mounted) setState(() {});
    }
  }

  void _clear() {
    _epoch++;
    _unregister?.call();
    _unregister = null;
    _scope?.dispose();
    _scope = null;
    final player = _player, temporary = _temporary, file = _file;
    _player = null;
    _temporary = null;
    _file = null;
    _busy = false;
    if (file != null && widget.message.messageType == ChatMessageType.image)
      unawaited(FileImage(file).evict());
    if (player != null) {
      player.removeListener(_changed);
      unawaited(player.close().catchError((Object _) {}));
    }
    if (temporary != null)
      unawaited(temporary.dispose().catchError((Object _) {}));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (_busy || !widget.visible || !_foreground || !widget.host.enabled)
      return;
    _clear();
    final epoch = _epoch;
    final media = widget.message.media;
    if (media == null ||
        media.purpose != widget.message.messageType.mediaPurpose) {
      setState(() => _error = '消息媒体数据不符合约定');
      return;
    }
    MediaTemporaryFile? temporary;
    PrivateLocalPlayer? player;
    try {
      final scope = MediaIdentityScope(
        currentUserId: widget.host.userId,
        identityGeneration: widget.host.generation,
        changes: widget.host.changes,
      );
      _scope = scope;
      _unregister = scope.onCancel(() {
        _clear();
        _changed();
      });
      setState(() {
        _busy = true;
        _error = null;
      });
      temporary = await widget.host.download(media, scope);
      scope.check();
      if (!mounted || epoch != _epoch || !widget.visible || !_foreground)
        throw MediaIdentityScope.invalid;
      var file = File(temporary.path);
      if (widget.message.messageType != ChatMessageType.image) {
        // AVFoundation uses the local extension for demuxing. Rename only the
        // App-owned controlled download; the directory remains scope-owned.
        final extension = switch (media.mediaType) {
          'audio/aac' => 'aac',
          'audio/mp4' => 'm4a',
          'audio/mpeg' => 'mp3',
          'audio/ogg' => 'ogg',
          'audio/wav' => 'wav',
          'video/mp4' => 'mp4',
          _ => throw mediaProtocol(),
        };
        file = await file.rename('${file.path}.$extension');
        scope.check();
        player = widget.host.playerFactory(media.purpose);
        _player = player;
        player.addListener(_changed);
        await player.open(file);
        scope.check();
        if (!mounted || epoch != _epoch || !widget.visible || !_foreground)
          throw MediaIdentityScope.invalid;
        await player.play();
        scope.check();
      }
      if (!mounted || epoch != _epoch || !widget.visible || !_foreground)
        throw MediaIdentityScope.invalid;
      _temporary = temporary;
      temporary = null;
      _file = file;
      setState(() => _busy = false);
    } catch (e) {
      await player?.close();
      if (mounted && epoch == _epoch) {
        _player = null;
        setState(() {
          _busy = false;
          _error = privateMediaError(e);
        });
      }
    } finally {
      await temporary?.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.message.messageType;
    final label = switch (type) {
      ChatMessageType.image => '查看私信图片',
      ChatMessageType.voice => '播放私信语音',
      ChatMessageType.video => '播放私信视频',
      _ => '媒体不可用',
    };
    return DefaultTextStyle.merge(
      style: TextStyle(color: widget.message.isMine ? Colors.white : null),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_file != null && type == ChatMessageType.image)
            Image.file(
              _file!,
              width: 230,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text('图片无法解码，请重新检查'),
            ),
          if (_player?.video != null)
            SizedBox(width: 230, child: _player!.video!),
          if (_player != null)
            Text(
              '${_player!.position.inSeconds}s / ${_player!.duration.inSeconds}s',
            ),
          TextButton(
            style: widget.message.isMine
                ? TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                  )
                : null,
            onPressed: _busy || !widget.visible || !widget.host.enabled
                ? null
                : () async {
                    if (_player != null) {
                      try {
                        _scope!.check();
                        if (_player!.playing) {
                          await _player!.pause();
                        } else {
                          await _player!.play();
                        }
                        _scope?.check();
                      } catch (e) {
                        _clear();
                        if (mounted)
                          setState(() => _error = privateMediaError(e));
                      }
                    } else {
                      await _open();
                    }
                  },
            child: Text(
              _busy
                  ? '正在读取…'
                  : _player != null
                  ? (_player!.playing ? '暂停' : '继续播放')
                  : _error != null
                  ? '重试读取媒体'
                  : label,
            ),
          ),
          if (widget.message.media != null && type != ChatMessageType.image)
            Text('${(widget.message.media!.durationMillis + 999) ~/ 1000}秒'),
          if (_error != null) Text(_error!),
          if (_player?.error != null) Text(_player!.error!),
        ],
      ),
    );
  }
}
