import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/media/media_files.dart';
import '../../core/media/media_identity.dart';
import '../../core/media/media_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'native_image_selection.dart';

String _key() =>
    'image-${List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';

/// App-lifetime, account-indexed command journal. No token or picker path is
/// retained in the journal. On identity loss owned bytes are deleted, while
/// original keys/asset IDs remain recoverable by that account in a new scope.
class AppImageMediaHost extends ChangeNotifier {
  AppImageMediaHost({
    required this.api,
    required this.userId,
    required this.generation,
    required this.changes,
    required this.picker,
    required this.temporaryParent,
    this.enabled = true,
  }) {
    _observedIdentity = identity;
    changes.addListener(_changed);
  }
  final ApiClient api;
  final int Function() userId;
  final int Function() generation;
  final Listenable changes;
  final ImageSelection picker;
  final Future<Directory> Function() temporaryParent;
  final bool enabled;
  final _drafts = <(int, String), ImageDraft>{};
  MediaIdentityScope? _scope;
  bool _disposed = false;
  late (int, int) _observedIdentity;
  final _cleanups = <Future<void>>[];
  final _downloads = <MediaTemporaryFile>[];
  Future<void> get cleanup async {
    await Future.wait(_cleanups);
  }

  void _disposeSource(MediaUploadFile? source) {
    if (source == null) return;
    final cleanup = source.dispose();
    _cleanups.add(cleanup);
    unawaited(cleanup.catchError((Object _) {}));
  }

  (int, int) get identity => (userId(), generation());
  MediaIdentityScope get scope {
    if (_disposed) throw MediaIdentityScope.invalid;
    if (_scope?.isCurrent != true) {
      _scope?.dispose();
      _scope = MediaIdentityScope(
        currentUserId: userId,
        identityGeneration: generation,
        changes: changes,
      );
    }
    return _scope!;
  }

  ImageDraft draft(String key, MediaPurpose purpose) {
    if (purpose != MediaPurpose.dynamicImage &&
        purpose != MediaPurpose.supportImage) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前图片草稿仅接入动态与反馈工单',
      );
    }
    final actor = scope.userId;
    final draft = _drafts.putIfAbsent((
      actor,
      key,
    ), () => ImageDraft._(actor, purpose));
    if (draft.purpose != purpose) throw mediaProtocol();
    return draft;
  }

  void _check(ImageDraft draft, MediaIdentityScope scope) {
    scope.check();
    if (_disposed ||
        scope.userId != userId() ||
        scope.generation != generation() ||
        draft.actor != scope.userId)
      throw MediaIdentityScope.invalid;
  }

  void _changed() {
    if (_observedIdentity != identity) {
      _observedIdentity = identity;
      _scope?.dispose();
      _scope = null;
      for (final draft in _drafts.values) {
        draft.flight = null;
        draft.picking = false;
        for (final image in draft._images) {
          _disposeSource(image.source);
          image.source = null;
          image.flight = null;
        }
      }
      notifyListeners();
    }
  }

  void touch() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pick(ImageDraft draft) async {
    final bound = scope;
    _check(draft, bound);
    if (!enabled)
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '演示环境不上传图片，请使用文字；不会生成虚假媒体回执',
      );
    if (draft.locked || draft.picking) return;
    final remaining = draft.purpose.maximumCount - draft.images.length;
    if (remaining <= 0) throw mediaProtocol();
    draft.picking = true;
    touch();
    final captured = <ImageUpload>[];
    try {
      final files = await bound.wait(picker.pick(remaining));
      if (files.length > remaining) throw mediaProtocol();
      final parent = await bound.wait(temporaryParent());
      for (final file in files) {
        final size = await bound.wait(file.length());
        MediaLimits.validateSelection(
          draft.purpose,
          bytes: size,
          durationMillis: 0,
        );
        final copy = await MediaUploadFile.capture(
          identity: bound,
          temporaryParent: parent,
          purpose: draft.purpose,
          bytes: size,
          durationMillis: 0,
          content: file.openRead(),
        );
        _check(draft, bound);
        captured.add(ImageUpload._(_key(), size, copy));
      }
      _check(draft, bound);
      draft._images.addAll(captured);
      captured.clear();
    } finally {
      for (final image in captured) {
        _disposeSource(image.source);
      }
      if (bound.isCurrent) {
        draft.picking = false;
        touch();
      }
    }
  }

  /// First explicit upload only. After an uncertain result the UI uses recover
  /// (GET same ID); no retry ever repeats a PUT, even if status is ALLOCATED.
  Future<void> upload(
    ImageDraft draft,
    ImageUpload image, {
    bool recover = false,
  }) {
    final bound = scope;
    _check(draft, bound);
    if (!draft._images.contains(image) ||
        (draft.locked && !image.cancelled) ||
        (image.cancelled && !recover))
      throw mediaProtocol();
    if (image.flight != null) return image.flight!;
    late Future<void> operation;
    operation = _upload(draft, image, bound, recover).whenComplete(() {
      if (identical(image.flight, operation)) {
        image.flight = null;
        touch();
      }
    });
    image.flight = operation;
    touch();
    return operation;
  }

  Future<void> _upload(
    ImageDraft draft,
    ImageUpload image,
    MediaIdentityScope bound,
    bool recover,
  ) async {
    image.error = null;
    try {
      if (image.status == null) {
        image.attempted = true;
        final result = await api.mediaAssetJson(
          action: MediaAssetAction.allocate,
          purpose: draft.purpose,
          requestId: image.key,
          identity: bound,
        );
        _check(draft, bound);
        _accept(draft, image, result.data);
      } else {
        final result = await api.mediaAssetJson(
          action: MediaAssetAction.status,
          assetId: image.status!.assetId,
          identity: bound,
        );
        _check(draft, bound);
        _accept(draft, image, result.data);
      }
      if (recover) return;
      var current = image.status!;
      if (current.isExpired(DateTime.now()) ||
          current.state == MediaAssetState.ready ||
          current.state == MediaAssetState.rejected ||
          current.state == MediaAssetState.revoked)
        return;
      if (current.state == MediaAssetState.allocated && !image.putAttempted) {
        final source = image.source;
        if (source == null || !source.identity.isCurrent) {
          throw const ApiException(
            kind: ApiFailureKind.conflict,
            message: '原文件已随身份变化清理；只可检查上传状态，不能替换文件续传',
          );
        }
        image.putAttempted = true;
        final result = await api.putMediaAssetContent(
          assetId: current.assetId,
          expectedVersion: current.version,
          purpose: draft.purpose,
          bytes: image.bytes,
          content: source.openRead(),
          identity: bound,
        );
        _check(draft, bound);
        _accept(draft, image, result.data);
        current = image.status!;
      }
      if (current.state == MediaAssetState.uploading ||
          current.state == MediaAssetState.quarantined) {
        final result = await api.mediaAssetJson(
          action: MediaAssetAction.complete,
          assetId: current.assetId,
          expectedVersion: current.version,
          identity: bound,
        );
        _check(draft, bound);
        _accept(draft, image, result.data);
      }
    } catch (error) {
      if (bound.isCurrent) image.error = imageError(error);
      rethrow;
    } finally {
      if (bound.isCurrent) touch();
    }
  }

  void _accept(ImageDraft draft, ImageUpload image, Object? raw) {
    final value = MediaAssetStatus.fromJson(raw);
    final old = image.status;
    if (value.purpose != draft.purpose ||
        (value.bytes != null && value.bytes != image.bytes) ||
        (old != null &&
            (value.assetId != old.assetId ||
                value.expiresAt != old.expiresAt ||
                value.version < old.version ||
                (value.version == old.version &&
                    (value.state != old.state ||
                        value.bytes != old.bytes ||
                        value.mediaType != old.mediaType ||
                        value.durationMillis != old.durationMillis)) ||
                (value.state.index < old.state.index &&
                    value.state != MediaAssetState.revoked) ||
                (old.state == MediaAssetState.ready &&
                    value.state != MediaAssetState.ready &&
                    value.state != MediaAssetState.revoked))))
      throw mediaProtocol();
    image.status = value;
  }

  void remove(ImageDraft draft, ImageUpload image) {
    _check(draft, scope);
    if (draft.locked || image.flight != null) return;
    if (image.attempted &&
        image.status?.state != MediaAssetState.ready &&
        image.status?.state != MediaAssetState.rejected &&
        image.status?.state != MediaAssetState.revoked) {
      _disposeSource(image.source);
      image.source = null;
      image.cancelled = true;
      touch();
      return;
    }
    _disposeSource(image.source);
    draft._images.remove(image);
    touch();
  }

  /// The immutable command and original key outlive pages and uncertain results.
  /// An identity change discards the Future, not the command. Only an explicit
  /// action by the original actor can replay it; ABA cannot consume an old Future.
  Future<T> submit<T extends Object>(
    ImageDraft draft,
    Map<String, Object?> fields,
    Future<T> Function(String key, List<MediaReference> images) send,
  ) {
    final bound = scope;
    _check(draft, bound);
    final references = draft.command?.images ?? draft.ready;
    final fingerprint = jsonEncode([
      fields,
      references.map((m) => m.assetId).toList(),
    ]);
    final command = draft.command;
    if (command != null && command.fingerprint != fingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '上次提交结果未知，请先恢复原内容，不可换内容重用请求',
      );
    }
    if (draft.flight != null) return draft.flight!.then((value) => value as T);
    if (draft.receipt != null) return Future.value(draft.receipt as T);
    final frozen = draft.command ??= _ImageCommand(
      _key(),
      fingerprint,
      references,
    );
    late Future<T> operation;
    operation = Future<T>.sync(() => send(frozen.key, frozen.images))
        .then(
          (value) {
            _check(draft, bound);
            draft.receipt = value;
            return value;
          },
          onError: (Object error, StackTrace stack) {
            if (bound.isCurrent &&
                error is ApiException &&
                error.httpStatus == 400) {
              draft.command =
                  null; // An explicit validation rejection, not an unknown/409.
            }
            Error.throwWithStackTrace(error, stack);
          },
        )
        .whenComplete(() {
          if (identical(draft.flight, operation)) {
            draft.flight = null;
            touch();
          }
        });
    draft.flight = operation;
    touch();
    return operation;
  }

  void acknowledge(ImageDraft draft) {
    _check(draft, scope);
    if (draft.receipt == null) return;
    for (final image in draft.images) {
      _disposeSource(image.source);
    }
    draft._images.removeWhere((image) => !image.cancelled);
    draft.fields.clear();
    draft.command = null;
    draft.receipt = null;
    touch();
  }

  Future<MediaTemporaryFile> download(
    MediaReference media,
    MediaIdentityScope bound,
  ) async {
    bound.check();
    if (_disposed ||
        bound.userId != userId() ||
        bound.generation != generation())
      throw MediaIdentityScope.invalid;
    final parent = await bound.wait(temporaryParent());
    final file = await MediaBinaryFiles(
      api,
    ).download(media: media, identity: bound, temporaryParent: parent);
    if (_disposed || !bound.isCurrent) {
      await file.dispose();
      throw MediaIdentityScope.invalid;
    }
    _downloads.add(file);
    return file;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    changes.removeListener(_changed);
    _scope?.dispose();
    for (final file in _downloads) {
      final cleanup = file.dispose();
      _cleanups.add(cleanup);
      unawaited(cleanup.catchError((Object _) {}));
    }
    _downloads.clear();
    for (final draft in _drafts.values) {
      for (final image in draft._images) {
        _disposeSource(image.source);
      }
    }
    _drafts.clear();
    super.dispose();
  }
}

class ImageDraft {
  ImageDraft._(this.actor, this.purpose);
  final int actor;
  final MediaPurpose purpose;
  final fields = <String, String>{};
  final _images = <ImageUpload>[];
  List<ImageUpload> get images =>
      List.unmodifiable(_images.where((image) => !image.cancelled));
  List<ImageUpload> get retainedUploads =>
      List.unmodifiable(_images.where((image) => image.cancelled));
  bool picking = false;
  _ImageCommand? command;
  Future<Object>? flight;
  Object? receipt;
  bool get locked => command != null;
  List<MediaReference> get ready {
    if (picking ||
        images.any(
          (image) =>
              image.flight != null ||
              image.status?.state != MediaAssetState.ready ||
              image.status!.isExpired(DateTime.now()),
        )) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '请先完成每张图片上传并确认就绪，再提交',
      );
    }
    return List.unmodifiable(images.map((image) => image.status!.ready!));
  }
}

class ImageUpload {
  ImageUpload._(this.key, this.bytes, this.source);
  final String key;
  final int bytes;
  MediaUploadFile? source;
  MediaAssetStatus? status;
  bool attempted = false;
  bool putAttempted = false;
  bool cancelled = false;
  Future<void>? flight;
  String? error;
}

class _ImageCommand {
  _ImageCommand(this.key, this.fingerprint, this.images);
  final String key;
  final String fingerprint;
  final List<MediaReference> images;
}

String imageError(Object error) =>
    error is ApiException ? error.message : '图片操作未完成，请检查照片权限或网络后重试；未知上传会保留原请求';
