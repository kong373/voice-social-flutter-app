import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import '../../core/media/media_identity.dart';
import '../../core/media/media_models.dart';
import '../../core/network/api_exception.dart';

/// The only selection boundary allowed to expose a local path. Paths never
/// enter the command journal or the Backend JSON. External picker files are
/// never removed; only directories created by this adapter are owned.
class PrivateMediaSelection {
  PrivateMediaSelection(this.file, this.durationMillis, {this.release});
  final XFile file;
  final int durationMillis;
  final Future<void> Function()? release;
  Future<void> dispose() async => release?.call();
}

abstract interface class PrivateMediaInput {
  Future<PrivateMediaSelection?> pick(
    MediaPurpose purpose,
    MediaIdentityScope scope,
  );
  Future<void> startRecording(MediaIdentityScope scope);
  Future<PrivateMediaSelection?> finishRecording(MediaIdentityScope scope);
  Future<void> dispose();
}

abstract class PrivateLocalPlayer extends ChangeNotifier {
  String? get error => null;
  bool get playing;
  Duration get position;
  Duration get duration;
  Widget? get video;
  Future<void> open(File file);
  Future<void> play();
  Future<void> pause();
  Future<void> close();
}

class NativePrivateMediaInput implements PrivateMediaInput {
  NativePrivateMediaInput({required this.temporaryParent, ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final Future<Directory> Function() temporaryParent;
  final ImagePicker _picker;
  AudioRecorder? _recorder;
  Directory? _recordingDirectory;
  bool _disposed = false;
  bool _checkedLost = false;
  Future<void>? _closing;
  void _check(MediaIdentityScope scope) {
    scope.check();
    if (_disposed) throw MediaIdentityScope.invalid;
  }

  @override
  Future<PrivateMediaSelection?> pick(
    MediaPurpose purpose,
    MediaIdentityScope scope,
  ) async {
    _check(scope);
    if (purpose != MediaPurpose.privateImage &&
        purpose != MediaPurpose.privateVideo)
      throw mediaProtocol();
    try {
      if (Platform.isAndroid && !_checkedLost) {
        _checkedLost = true;
        final lost = await _picker.retrieveLostData();
        _check(scope);
        if (!lost.isEmpty)
          throw const ApiException(
            kind: ApiFailureKind.conflict,
            message: '上次选择已中断，请重新选择；不会自动上传恢复的文件',
          );
      }
      final file = purpose == MediaPurpose.privateImage
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              requestFullMetadata: false,
            )
          : await _picker.pickVideo(source: ImageSource.gallery);
      _check(scope);
      if (file == null) return null;
      final bytes = await file.length();
      _check(scope);
      if (bytes <= 0 || bytes > purpose.maximumBytes) throw mediaProtocol();
      if (purpose == MediaPurpose.privateImage)
        return PrivateMediaSelection(file, 0);
      // pickVideo's maxDuration is ignored for gallery selection. Probe the
      // local file, without network constructors, before accepting it.
      final player = VideoPlayerController.file(File(file.path));
      try {
        await player.initialize();
        _check(scope);
        final duration = player.value.duration.inMilliseconds;
        MediaLimits.validateSelection(
          purpose,
          bytes: bytes,
          durationMillis: duration,
        );
        return PrivateMediaSelection(file, duration);
      } finally {
        await player.dispose();
      }
    } on PlatformException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.forbidden,
        message: error.code == 'already_active'
            ? '系统选择器已打开，请先完成或取消'
            : '无法访问所选媒体，请检查系统照片权限后重试',
      );
    }
  }

  @override
  Future<void> startRecording(MediaIdentityScope scope) async {
    _check(scope);
    if (_recorder != null) throw mediaProtocol();
    final recorder = _recorder = AudioRecorder();
    try {
      final permission = await recorder.hasPermission();
      _check(scope);
      if (!permission)
        throw const ApiException(
          kind: ApiFailureKind.forbidden,
          message: '未获得麦克风权限，请在系统设置中允许后重试',
        );
      final parent = await temporaryParent();
      _check(scope);
      final directory = await parent.createTemp('s13-private-record-');
      _recordingDirectory = directory;
      _check(scope);
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: '${directory.path}/voice.m4a',
      );
      _check(scope);
    } catch (_) {
      await _stopRecording();
      rethrow;
    }
  }

  @override
  Future<PrivateMediaSelection?> finishRecording(
    MediaIdentityScope scope,
  ) async {
    _check(scope);
    final recorder = _recorder;
    final directory = _recordingDirectory;
    if (recorder == null || directory == null) throw mediaProtocol();
    try {
      final path = await recorder.stop();
      _check(scope);
      if (path != '${directory.path}/voice.m4a') throw mediaProtocol();
      final file = XFile(path!);
      final bytes = await file.length();
      _check(scope);
      if (bytes <= 0 || bytes > MediaPurpose.privateVoice.maximumBytes)
        throw mediaProtocol();
      final player = AudioPlayer();
      try {
        final duration = await player.setFilePath(path);
        _check(scope);
        if (duration == null) throw mediaProtocol();
        MediaLimits.validateSelection(
          MediaPurpose.privateVoice,
          bytes: bytes,
          durationMillis: duration.inMilliseconds,
        );
        _recordingDirectory = null;
        return PrivateMediaSelection(
          file,
          duration.inMilliseconds,
          release: () async {
            if (await directory.exists())
              await directory.delete(recursive: true);
          },
        );
      } finally {
        await player.dispose();
      }
    } finally {
      await _stopRecording(cancel: false);
    }
  }

  Future<void> _stopRecording({bool cancel = true}) async {
    final recorder = _recorder;
    _recorder = null;
    final directory = _recordingDirectory;
    _recordingDirectory = null;
    try {
      if (cancel) await recorder?.cancel();
    } finally {
      await recorder?.dispose();
      if (directory != null && await directory.exists())
        await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _closing ??= _stopRecording();
  }
}

class NativePrivateLocalPlayer extends PrivateLocalPlayer {
  NativePrivateLocalPlayer(this.purpose);
  final MediaPurpose purpose;
  AudioPlayer? _audio;
  VideoPlayerController? _video;
  StreamSubscription<Object?>? _state;
  StreamSubscription<Duration>? _position;
  StreamSubscription<PlayerException>? _errors;
  String? _error;
  @override
  String? get error =>
      _error ??
      (_video?.value.hasError == true ? '视频无法播放，请重新读取或选择支持的文件' : null);
  bool _closed = false;
  Future<void>? _closing;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  bool get playing => _audio?.playing ?? _video?.value.isPlaying ?? false;
  @override
  Duration get position =>
      _audio?.position ?? _video?.value.position ?? Duration.zero;
  @override
  Duration get duration =>
      _audio?.duration ?? _video?.value.duration ?? Duration.zero;
  @override
  Widget? get video => _video == null
      ? null
      : AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        );
  @override
  Future<void> open(File file) async {
    if (_closed || !file.isAbsolute) throw mediaProtocol();
    if (purpose == MediaPurpose.privateVoice) {
      final audio = _audio = AudioPlayer();
      _errors = audio.errorStream.listen((_) {
        _error = '语音无法播放，请重新读取';
        _changed();
      });
      _state = audio.playerStateStream.listen((_) => _changed());
      _position = audio.positionStream.listen((_) => _changed());
      await audio.setFilePath(file.path);
    } else if (purpose == MediaPurpose.privateVideo) {
      final video = _video = VideoPlayerController.file(file);
      video.addListener(_changed);
      await video.initialize();
    } else {
      throw mediaProtocol();
    }
    if (_closed) throw MediaIdentityScope.invalid;
  }

  @override
  Future<void> play() async {
    if (_closed) throw MediaIdentityScope.invalid;
    if (position >= duration) {
      await _audio?.seek(Duration.zero);
      await _video?.seekTo(Duration.zero);
    }
    if (_closed) throw MediaIdentityScope.invalid;
    if (_audio != null) {
      unawaited(
        _audio!.play().catchError((Object _) {
          _changed();
        }),
      );
    }
    await _video?.play();
  }

  @override
  Future<void> pause() async {
    await _audio?.pause();
    await _video?.pause();
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _state?.cancel();
    await _position?.cancel();
    await _errors?.cancel();
    await _audio?.dispose();
    await _video?.dispose();
    super.dispose();
  }
}
