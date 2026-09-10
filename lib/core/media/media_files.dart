import 'dart:async';
import 'dart:io';
import '../network/api_client.dart';
import 'media_identity.dart';
import 'media_models.dart';

/// Owns only its freshly-created temporary directory, never the user's input
/// file or a caller's root. Access is permanently fenced by the captured tuple.
class MediaTemporaryFile {
  MediaTemporaryFile._(this.identity, this._directory)
    : _file = File('${_directory.path}/content') {
    _unregister = identity.onCancel(() {
      // Observe the error here; cleanup remains available for the owner to
      // await/report. A failed unlink does not make the old scope usable.
      unawaited(dispose().catchError((Object _) {}));
    });
  }
  final MediaIdentityScope identity;
  final Directory _directory;
  final File _file;
  late final void Function() _unregister;
  Future<void>? _cleanup;
  bool _disposed = false;
  Future<void> get cleanup => _cleanup ?? Future<void>.value();
  String get path {
    _check();
    return _file.path;
  }

  void _check() {
    identity.check();
    if (_disposed) throw MediaIdentityScope.invalid;
  }

  static Future<MediaTemporaryFile> _create(
    MediaIdentityScope identity,
    Directory parent,
  ) async {
    identity.check();
    final directory = await parent.createTemp('s13-media-');
    try {
      identity.check();
      return MediaTemporaryFile._(identity, directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Stream<List<int>> openRead() async* {
    _check();
    await for (final chunk in _file.openRead()) {
      _check();
      yield chunk;
    }
    _check();
  }

  Future<void> dispose() {
    _disposed = true;
    _unregister();
    return _cleanup ??= _delete();
  }

  Future<void> _delete() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}

/// An app-owned immutable copy, not an external path or caller-supplied MIME.
/// Local duration is preflight only; READY metadata remains server-authoritative.
class MediaUploadFile {
  MediaUploadFile._(
    this._temporary,
    this.purpose,
    this.bytes,
    this.durationMillis,
  );
  final MediaTemporaryFile _temporary;
  final MediaPurpose purpose;
  final int bytes;
  final int durationMillis;
  MediaIdentityScope get identity => _temporary.identity;
  Future<void> get cleanup => _temporary.cleanup;

  static Future<MediaUploadFile> capture({
    required MediaIdentityScope identity,
    required Directory temporaryParent,
    required MediaPurpose purpose,
    required int bytes,
    required int durationMillis,
    required Stream<List<int>> content,
  }) async {
    MediaLimits.validateSelection(
      purpose,
      bytes: bytes,
      durationMillis: durationMillis,
    );
    final file = await MediaTemporaryFile._create(identity, temporaryParent);
    identity.check();
    RandomAccessFile? handle;
    final iterator = StreamIterator<List<int>>(content);
    final unregister = identity.onCancel(() {
      unawaited(iterator.cancel());
    });
    try {
      handle = await file._file.open(mode: FileMode.writeOnly);
      identity.check();
      int total = 0;
      while (await identity.wait(iterator.moveNext())) {
        identity.check();
        final chunk = iterator.current;
        total += chunk.length;
        if (total > bytes || total > purpose.maximumBytes)
          throw mediaProtocol();
        await handle.writeFrom(chunk);
        identity.check();
      }
      if (total != bytes) throw mediaProtocol();
      await handle.close();
      handle = null;
      identity.check();
      return MediaUploadFile._(file, purpose, bytes, durationMillis);
    } catch (_) {
      await file.dispose();
      rethrow;
    } finally {
      unregister();
      await iterator.cancel();
      await handle?.close();
    }
  }

  Stream<List<int>> openRead() => _temporary.openRead();
  Future<void> dispose() => _temporary.dispose();
}

class MediaBinaryFiles {
  const MediaBinaryFiles(this.api);
  final ApiClient api;

  /// Not a live-playback claim: the Backend GET is still an integration gate.
  /// Return a file only after the controlled stream's exact MIME/size passed.
  Future<MediaTemporaryFile> download({
    required MediaReference media,
    required MediaIdentityScope identity,
    required Directory temporaryParent,
  }) async {
    final file = await MediaTemporaryFile._create(identity, temporaryParent);
    RandomAccessFile? handle;
    try {
      final output = await file._file.open(mode: FileMode.writeOnly);
      handle = output;
      identity.check();
      await api.readMediaAssetContent(
        media: media,
        identity: identity,
        onChunk: (chunk) async {
          identity.check();
          await output.writeFrom(chunk);
          identity.check();
        },
      );
      identity.check();
      await output.close();
      handle = null;
      identity.check();
      return file;
    } catch (_) {
      await file.dispose();
      rethrow;
    } finally {
      await handle?.close();
    }
  }
}
