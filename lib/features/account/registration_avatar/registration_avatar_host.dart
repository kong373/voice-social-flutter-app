import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/key_value_store.dart';
import '../../media/native_image_selection.dart';
import 'registration_avatar_models.dart';
import 'registration_avatar_transport_adapter.dart';

typedef RegistrationAvatarUploadHost = RegistrationAvatarHost;

/// Retain above page/sheet lifetimes. Production MUST inject secure storage.
/// Persisted metadata contains no SMS code, Token, picker path or image bytes.
class RegistrationAvatarHost extends ChangeNotifier {
  RegistrationAvatarHost({
    required this.context,
    required this.transport,
    required this.store,
    required this.picker,
    required this.temporaryParent,
  }) {
    context.check();
    context.addListener(_contextChanged);
    _queue = _queues[store] ??= _StoreQueue();
  }
  final RegistrationAvatarContext context;
  final RegistrationAvatarTransport transport;
  final KeyValueStore store;
  final ImageSelection picker;
  final Future<Directory> Function() temporaryParent;
  static final _queues = Expando<_StoreQueue>();
  late final _StoreQueue _queue;
  _Intent? _intent;
  Directory? _ownedDirectory;
  File? _source;
  Uint8List? _previewBytes;
  final _cleanups = <Future<void>>[];
  Future<void>? _flight;
  bool _restored = false, _disposed = false, _authoritative = false;
  String? _error;
  bool get busy => !_disposed && _flight != null;
  bool get hasSelection => !_disposed && context.isCurrent && _intent != null;
  bool get hasPendingUpload =>
      hasSelection &&
      ready == null &&
      _intent!.status?.state != RegistrationAvatarState.rejected &&
      _intent!.status?.state != RegistrationAvatarState.bound;

  /// Read-only, context-scoped RAM. Never persisted; upload cleanup does not
  /// remove the current page's preview, while context loss always does.
  Uint8List? get previewBytes =>
      !_disposed && context.isCurrent ? _previewBytes : null;
  String? get error => context.isCurrent && !_disposed ? _error : '注册验证已变化或过期';
  RegistrationAvatarStatus? get status =>
      context.isCurrent && !_disposed ? _intent?.status : null;
  bool get sourceUnavailable =>
      context.isCurrent &&
      _intent != null &&
      _source == null &&
      _intent!.status?.state != RegistrationAvatarState.ready;
  RegistrationAvatarReady? get ready {
    final current = status;
    if (busy ||
        !_authoritative ||
        current == null ||
        current.state != RegistrationAvatarState.ready ||
        !DateTime.now().isBefore(current.expiresAt))
      return null;
    return RegistrationAvatarReady(
      assetId: current.assetId,
      version: current.version,
      requestId: _intent!.requestId,
      capability: _intent!.capability,
    );
  }

  String get _storeKey =>
      'registration-avatar-v1-${sha256.convert(utf8.encode(jsonEncode([context.challengeId, context.deviceId, context.clientId])))}';
  void _check() {
    context.check();
    if (_disposed) throw registrationAvatarContextExpired;
  }

  Future<void> get cleanup async {
    await Future.wait(_cleanups);
  }

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  void _contextChanged() {
    _authoritative = false;
    _previewBytes = null;
    _cleanSource();
    _touch();
  }

  void _cleanSource() {
    final owned = _ownedDirectory;
    _source = null;
    _ownedDirectory = null;
    if (owned == null) return;
    final cleaning = owned.delete(recursive: true).then<void>((_) {});
    _cleanups.add(cleaning);
    unawaited(cleaning.catchError((Object _) {}));
  }

  Future<void> _single(Future<void> Function() action) {
    _check();
    if (_flight != null) return _flight!;
    late Future<void> operation;
    operation =
        Future<void>.sync(() async {
          _error = null;
          try {
            await action();
            _check();
          } catch (_) {
            if (context.isCurrent && !_disposed) {
              _authoritative = false;
              _error = '头像操作尚未完成，请检查上传状态；不会自动重新上传';
            }
            rethrow;
          }
        }).whenComplete(() {
          if (identical(_flight, operation)) {
            _flight = null;
            _touch();
          }
        });
    _flight = operation;
    _touch();
    return operation;
  }

  Future<void> restore() => _single(_restore);
  Future<void> _restore() async {
    _check();
    if (_restored) return;
    final saved = await context.wait(
      _queue.run(() {
        _check();
        return store.read(_storeKey);
      }),
    );
    _check();
    if (saved != null) {
      try {
        final value = jsonDecode(saved);
        if (value is! Map<String, Object?> ||
            value['schema'] is! int ||
            value['schema'] != 1 ||
            value['capability'] is! String ||
            value['requestId'] is! String ||
            value['allocationAttempted'] is! bool ||
            value['putAttempted'] is! bool ||
            value['selectionBytes'] is! int)
          throw registrationAvatarInvalid;
        final capability = value['capability']! as String;
        if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(capability) ||
            base64Url
                    .encode(base64Url.decode('$capability='))
                    .replaceAll('=', '') !=
                capability ||
            value['binding'] != context.binding(capability) ||
            value['challengeId'] != context.challengeId ||
            value['deviceId'] != context.deviceId ||
            value['clientId'] != context.clientId ||
            value['expiresAt'] != context.expiresAt.toIso8601String() ||
            !RegExp(
              r'^registration-avatar-[0-9a-f]{32}$',
            ).hasMatch(value['requestId']! as String))
          throw registrationAvatarInvalid;
        final size = value['selectionBytes']! as int;
        if (size <= 0 || size > registrationAvatarMaximumBytes)
          throw registrationAvatarInvalid;
        final intent = _Intent(value['requestId']! as String, capability, size)
          ..allocationAttempted = value['allocationAttempted']! as bool
          ..putAttempted = value['putAttempted']! as bool;
        final data = value['status'];
        if (data != null) {
          intent.status = RegistrationAvatarStatus.fromData(data);
          if (!intent.allocationAttempted ||
              intent.status!.expiresAt.isAfter(context.expiresAt))
            throw registrationAvatarInvalid;
        }
        if (intent.putAttempted &&
            (intent.status == null || !intent.allocationAttempted))
          throw registrationAvatarInvalid;
        _intent = intent;
      } on FormatException {
        throw registrationAvatarInvalid;
      }
    }
    _restored = true;
    _authoritative = false; // A stored READY is not current server authority.
  }

  Future<void> _persist() async {
    _check();
    final intent = _intent!;
    final encoded = jsonEncode({
      'schema': 1,
      'binding': context.binding(intent.capability),
      'challengeId': context.challengeId,
      'deviceId': context.deviceId,
      'clientId': context.clientId,
      'expiresAt': context.expiresAt.toIso8601String(),
      'requestId': intent.requestId,
      'capability': intent.capability,
      'selectionBytes': intent.bytes,
      'allocationAttempted': intent.allocationAttempted,
      'putAttempted': intent.putAttempted,
      'status': intent.status?.toData(),
    });
    await context.wait(
      _queue.run(() {
        _check();
        return store.write(_storeKey, encoded);
      }),
    );
    _check();
  }

  Future<void> choose() => _single(() async {
    await _restore();
    if (_intent?.allocationAttempted == true)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '已有上传待确认，请检查原头像状态，不能替换文件',
      );
    final files = await context.wait(picker.pick(1));
    _check();
    if (files.isEmpty) return;
    if (files.length != 1) throw registrationAvatarInvalid;
    final size = await context.wait(files.single.length());
    if (size <= 0 || size > registrationAvatarMaximumBytes)
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择不超过10MB的一张图片',
      );
    final parent = await context.wait(temporaryParent());
    // Await directory creation to completion even on cancellation, so a late
    // createTemp result is always reclaimed by this owner.
    final owned = await parent.createTemp('registration-avatar-');
    RandomAccessFile? output;
    final iterator = StreamIterator<List<int>>(files.single.openRead());
    try {
      _check();
      final copy = File('${owned.path}/content');
      output = await copy.open(mode: FileMode.writeOnly);
      _check();
      var total = 0;
      final preview = BytesBuilder(copy: false);
      while (await context.wait(iterator.moveNext())) {
        final chunk = iterator.current;
        total += chunk.length;
        if (total > size) throw registrationAvatarInvalid;
        preview.add(chunk);
        await output.writeFrom(chunk);
        _check();
      }
      if (total != size) throw registrationAvatarInvalid;
      await output.close();
      output = null;
      _check();
      _cleanSource();
      _ownedDirectory = owned;
      _source = copy;
      _previewBytes = null;
      final random = Random.secure();
      final capability = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final key =
          'registration-avatar-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      _intent = _Intent(key, capability, size);
      _authoritative = false;
      await _persist();
      _previewBytes = preview.takeBytes().asUnmodifiableView();
    } catch (_) {
      await output?.close();
      output = null;
      if (identical(_ownedDirectory, owned)) {
        _ownedDirectory = null;
        _source = null;
      }
      if (await owned.exists()) await owned.delete(recursive: true);
      rethrow;
    } finally {
      await iterator.cancel();
      await output?.close();
    }
  });

  Future<Object?> _exchange(
    RegistrationAvatarAction action, {
    Stream<List<int>>? content,
  }) {
    _check();
    final intent = _intent!;
    return context.wait(
      transport.exchange(
        action: action,
        context: context,
        requestId: intent.requestId,
        capability: intent.capability,
        assetId: action == RegistrationAvatarAction.allocate
            ? null
            : intent.status!.assetId,
        expectedVersion:
            action == RegistrationAvatarAction.upload ||
                action == RegistrationAvatarAction.complete
            ? intent.status!.version
            : null,
        bytes: content == null ? null : intent.bytes,
        content: content,
      ),
    );
  }

  Future<void> _accept(Object? raw) async {
    _check();
    final next = RegistrationAvatarStatus.fromData(raw);
    final previous = _intent!.status;
    if (next.expiresAt.isAfter(context.expiresAt) ||
        (previous != null &&
            (next.assetId != previous.assetId ||
                next.expiresAt != previous.expiresAt ||
                next.version < previous.version ||
                !_follows(previous.state, next.state) ||
                (next.version == previous.version &&
                    jsonEncode(next.toData()) !=
                        jsonEncode(previous.toData())))) ||
        (next.bytes != null && next.bytes != _intent!.bytes))
      throw registrationAvatarInvalid;
    _intent!.status = next;
    _authoritative = false;
    await _persist();
    _authoritative = true;
  }

  static bool _follows(
    RegistrationAvatarState before,
    RegistrationAvatarState after,
  ) => switch (before) {
    RegistrationAvatarState.allocated => true,
    RegistrationAvatarState.uploading =>
      after != RegistrationAvatarState.allocated,
    RegistrationAvatarState.quarantined =>
      after != RegistrationAvatarState.allocated &&
          after != RegistrationAvatarState.uploading,
    RegistrationAvatarState.ready =>
      after == RegistrationAvatarState.ready ||
          after == RegistrationAvatarState.bound,
    RegistrationAvatarState.rejected =>
      after == RegistrationAvatarState.rejected,
    RegistrationAvatarState.bound => after == RegistrationAvatarState.bound,
  };

  Future<void> _allocate() async {
    _intent!.allocationAttempted = true;
    await _persist(); // Stable cap/key reach secure storage BEFORE allocation.
    await _accept(await _exchange(RegistrationAvatarAction.allocate));
  }

  Future<void> _read() async =>
      _accept(await _exchange(RegistrationAvatarAction.status));
  Future<void> _complete() async {
    final current = _intent!.status!;
    if (!DateTime.now().isBefore(current.expiresAt)) return;
    if (current.state == RegistrationAvatarState.uploading ||
        current.state == RegistrationAvatarState.quarantined ||
        (current.state == RegistrationAvatarState.allocated &&
            _intent!.putAttempted)) {
      await _accept(await _exchange(RegistrationAvatarAction.complete));
    }
  }

  Future<void> upload() => _single(() async {
    await _restore();
    if (_intent == null) throw registrationAvatarInvalid;
    final alreadyAttempted = _intent!.allocationAttempted;
    if (_intent!.status == null) await _allocate();
    if (alreadyAttempted) await _read();
    final current = _intent!.status!;
    if (!DateTime.now().isBefore(current.expiresAt))
      throw registrationAvatarContextExpired;
    if (current.state == RegistrationAvatarState.allocated &&
        !_intent!.putAttempted) {
      final source = _source;
      if (source == null)
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: '原图片已不可恢复，请重新获取验证码后选择；不会替换原上传',
        );
      _intent!.putAttempted = true;
      await _persist(); // Also before opening a socket or consuming the stream.
      try {
        await _accept(
          await _exchange(
            RegistrationAvatarAction.upload,
            content: source.openRead(),
          ),
        );
      } finally {
        _cleanSource();
      }
    }
    await _complete();
  });
  Future<void> recover() => _single(() async {
    await _restore();
    if (_intent == null || !_intent!.allocationAttempted) return;
    if (_intent!.status == null) await _allocate();
    await _read();
    await _complete();
  });

  /// Explicit scan recovery, never a second content upload.
  Future<void> complete() => recover();

  /// Stop this host without deleting its server asset or durable unknown
  /// command. A fresh context/host may explicitly restore the same challenge.
  Future<void> discard() async {
    _authoritative = false;
    context.invalidate();
    _cleanSource();
    _touch();
    await cleanup;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _previewBytes = null;
    context.removeListener(_contextChanged);
    context.invalidate();
    _cleanSource();
    super.dispose();
  }
}

class _Intent {
  _Intent(this.requestId, this.capability, this.bytes);
  final String requestId, capability;
  final int bytes;
  bool allocationAttempted = false, putAttempted = false;
  RegistrationAvatarStatus? status;
}

class _StoreQueue {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
