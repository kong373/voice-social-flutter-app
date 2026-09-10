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
import '../../core/storage/key_value_store.dart';
import '../message/domain/message_models.dart';
import '../message/domain/message_repository.dart';
import 'private_media_native.dart';

String _key() =>
    'pm-${List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';

/// Small write-ahead journal, not a background sender. Storage contains only
/// protocol intent metadata. No source path, bearer, title or media bytes.
class PrivateMediaHost {
  PrivateMediaHost({
    required this.api,
    required this.store,
    required this.userId,
    required this.generation,
    required this.changes,
    required this.temporaryParent,
    required this.inputFactory,
    required this.playerFactory,
    this.enabled = true,
  });
  final ApiClient api;
  final KeyValueStore store;
  final int Function() userId;
  final int Function() generation;
  final Listenable changes;
  final Future<Directory> Function() temporaryParent;
  final PrivateMediaInput Function() inputFactory;
  final PrivateLocalPlayer Function(MediaPurpose) playerFactory;
  final bool enabled;
  final _visits = <PrivateMediaVisit>{};
  final _loads = <(int, int), Future<PrivateMediaIntent?>>{};
  final _entries = <(int, int), PrivateMediaIntent?>{};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  final _cleanups = <Future<void>>[];
  Future<void> get cleanup async {
    await Future.wait(_cleanups);
    await _writes;
  }

  String _storageKey(int actor, int receiver) =>
      's13.private-media.v1.$actor.$receiver';

  PrivateMediaVisit visit(ConversationSummary conversation) {
    if (_disposed ||
        conversation.targetUserId <= 0 ||
        conversation.targetUserId == userId())
      throw mediaProtocol();
    final scope = MediaIdentityScope(
      currentUserId: userId,
      identityGeneration: generation,
      changes: changes,
    );
    // A new route to the same peer cannot share an old in-flight Future.
    for (final old in _visits.toList()) {
      if (old.scope.userId == scope.userId &&
          old.receiver == conversation.targetUserId)
        old.dispose();
    }
    final visit = PrivateMediaVisit._(
      this,
      scope,
      conversation,
      inputFactory(),
    );
    _visits.add(visit);
    return visit;
  }

  Future<PrivateMediaIntent?> _load(int actor, int receiver) =>
      _loads.putIfAbsent((actor, receiver), () async {
        final raw = await store.read(_storageKey(actor, receiver));
        final entry = raw == null
            ? null
            : PrivateMediaIntent.decode(raw, actor, receiver);
        _entries[(actor, receiver)] = entry;
        return entry;
      });
  Future<void> _save(PrivateMediaIntent entry) {
    final encoded = entry.encode();
    _entries[(entry.actor, entry.receiver)] = entry;
    final operation = _writes.then(
      (_) => store.write(_storageKey(entry.actor, entry.receiver), encoded),
    );
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _remove(PrivateMediaIntent entry) async {
    final operation = _writes.then(
      (_) => store.delete(_storageKey(entry.actor, entry.receiver)),
    );
    _writes = operation.catchError((Object _) {});
    await operation;
    if (identical(_entries[(entry.actor, entry.receiver)], entry))
      _entries[(entry.actor, entry.receiver)] = null;
  }

  Future<void> _abandon(PrivateMediaIntent entry, MediaIdentityScope scope) {
    void check() {
      scope.check();
      if (!entry.canDiscard ||
          !identical(_entries[(entry.actor, entry.receiver)], entry))
        throw mediaProtocol();
    }

    check();
    final encoded = entry.encode();
    final operation = _writes.then((_) async {
      check();
      if (entry.allocationAttempted) {
        // Explicit local abandonment is not server revocation. Retain the
        // original allocation identity even when its response was lost. This
        // record is never loaded into the active sender or automatically sent.
        await store.write(
          's13.private-media.abandoned.v1.${entry.actor}.${entry.receiver}.${entry.allocationKey}',
          encoded,
        );
      }
      check();
      await store.delete(_storageKey(entry.actor, entry.receiver));
      if (identical(_entries[(entry.actor, entry.receiver)], entry))
        _entries[(entry.actor, entry.receiver)] = null;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<MediaTemporaryFile> download(
    MediaReference media,
    MediaIdentityScope scope,
  ) async {
    scope.check();
    if (_disposed ||
        scope.userId != userId() ||
        scope.generation != generation())
      throw MediaIdentityScope.invalid;
    final parent = await scope.wait(temporaryParent());
    return MediaBinaryFiles(
      api,
    ).download(media: media, identity: scope, temporaryParent: parent);
  }

  void dispose() {
    _disposed = true;
    for (final visit in _visits.toList()) {
      visit.dispose();
    }
  }
}

class PrivateMediaIntent {
  PrivateMediaIntent._(
    this.actor,
    this.receiver,
    this.purpose,
    this.bytes,
    this.durationMillis,
    this.allocationKey,
    this.requestId,
  );
  final int actor, receiver, bytes, durationMillis;
  final MediaPurpose purpose;
  final String allocationKey, requestId;
  bool allocationAttempted = false;
  bool putAttempted = false;
  bool sendAttempted = false;
  MediaAssetStatus? status;
  MediaReference? commandMedia;
  // An upload alone cannot create a private message. Only the user's explicit
  // abandon action may free this slot; an attempted send is never discardable.
  bool get canDiscard => !sendAttempted && commandMedia == null;
  static Map<String, Object?>? _status(MediaAssetStatus? s) => s == null
      ? null
      : {
          'assetId': s.assetId,
          'purpose': s.purpose.wire,
          'state': s.state.wire,
          'version': s.version,
          'maximumBytes': s.maximumBytes,
          'expiresAt': s.expiresAt.toIso8601String(),
          'mediaType': s.mediaType,
          'bytes': s.bytes,
          'durationMillis': s.durationMillis,
        };
  String encode() => jsonEncode({
    'schema': 1,
    'actor': actor,
    'receiver': receiver,
    'purpose': purpose.wire,
    'bytes': bytes,
    'durationMillis': durationMillis,
    'allocationKey': allocationKey,
    'requestId': requestId,
    'allocationAttempted': allocationAttempted,
    'putAttempted': putAttempted,
    'sendAttempted': sendAttempted,
    'status': _status(status),
    'commandMedia': commandMedia?.toJson(),
  });
  static PrivateMediaIntent decode(String raw, int actor, int receiver) {
    if (raw.length > 8192) throw mediaProtocol();
    final m = mediaMap(jsonDecode(raw), const {
      'schema',
      'actor',
      'receiver',
      'purpose',
      'bytes',
      'durationMillis',
      'allocationKey',
      'requestId',
      'allocationAttempted',
      'putAttempted',
      'sendAttempted',
      'status',
      'commandMedia',
    });
    if (m['schema'] is! int ||
        m['actor'] is! int ||
        m['receiver'] is! int ||
        m['schema'] != 1 ||
        m['actor'] != actor ||
        m['receiver'] != receiver ||
        actor <= 0 ||
        receiver <= 0 ||
        actor == receiver)
      throw mediaProtocol();
    final purpose = MediaPurpose.parse(m['purpose']);
    if (!{
      MediaPurpose.privateImage,
      MediaPurpose.privateVoice,
      MediaPurpose.privateVideo,
    }.contains(purpose))
      throw mediaProtocol();
    final bytes = mediaInteger(m['bytes']),
        duration = mediaInteger(m['durationMillis']);
    MediaLimits.validateSelection(
      purpose,
      bytes: bytes,
      durationMillis: duration,
    );
    for (final key in ['allocationKey', 'requestId']) {
      if (m[key] is! String ||
          !RegExp(r'^pm-[0-9a-f]{32}$').hasMatch(m[key] as String))
        throw mediaProtocol();
    }
    for (final key in [
      'allocationAttempted',
      'putAttempted',
      'sendAttempted',
    ]) {
      if (m[key] is! bool) throw mediaProtocol();
    }
    final entry =
        PrivateMediaIntent._(
            actor,
            receiver,
            purpose,
            bytes,
            duration,
            m['allocationKey'] as String,
            m['requestId'] as String,
          )
          ..allocationAttempted = m['allocationAttempted'] as bool
          ..putAttempted = m['putAttempted'] as bool
          ..sendAttempted = m['sendAttempted'] as bool;
    if (m['status'] != null) entry.accept(m['status']);
    if (m['commandMedia'] != null) {
      entry.commandMedia = MediaReference.fromJson(m['commandMedia']);
      if (entry.commandMedia!.purpose != purpose ||
          entry.commandMedia!.bytes != bytes ||
          entry.commandMedia!.assetId != entry.status?.assetId)
        throw mediaProtocol();
    }
    if ((entry.putAttempted && !entry.allocationAttempted) ||
        (entry.sendAttempted && entry.commandMedia == null) ||
        (entry.status != null && !entry.allocationAttempted))
      throw mediaProtocol();
    return entry;
  }

  void accept(Object? raw) {
    final next = MediaAssetStatus.fromJson(raw), old = status;
    if (next.purpose != purpose ||
        (next.bytes != null && next.bytes != bytes) ||
        (old != null &&
            (next.assetId != old.assetId ||
                next.expiresAt != old.expiresAt ||
                next.version < old.version ||
                (next.version == old.version &&
                    jsonEncode(_status(next)) != jsonEncode(_status(old))) ||
                next.state.index < old.state.index ||
                (old.state == MediaAssetState.ready &&
                    next.state != MediaAssetState.ready &&
                    next.state != MediaAssetState.revoked))))
      throw mediaProtocol();
    status = next;
  }
}

class PrivateMediaVisit extends ChangeNotifier {
  PrivateMediaVisit._(this.host, this.scope, this.conversation, this.input) {
    _unregister = scope.onCancel(dispose);
    loaded = _load();
  }
  final PrivateMediaHost host;
  final MediaIdentityScope scope;
  final ConversationSummary conversation;
  final PrivateMediaInput input;
  int get receiver => conversation.targetUserId;
  late final Future<void> loaded;
  late final void Function() _unregister;
  PrivateMediaIntent? intent;
  MediaUploadFile? _source;
  bool _disposed = false;
  bool busy = false, picking = false, recording = false;
  bool _loadFailed = false;
  String? error;
  Timer? _recordLimit;
  Future<void>? _cleanup;
  Future<void> get cleanup => _cleanup ?? Future.value();
  bool get current => !_disposed && scope.isCurrent;
  void check() {
    scope.check();
    if (_disposed || host._disposed) throw MediaIdentityScope.invalid;
  }

  void _notify() {
    if (current) notifyListeners();
  }

  Future<void> _load() async {
    try {
      await scope.wait(host._load(scope.userId, receiver));
      check();
      intent = host._entries[(scope.userId, receiver)];
    } catch (e) {
      if (current) {
        _loadFailed = true;
        error = '未能读取原媒体发送记录，请重新进入会话；不会覆盖原请求';
      }
    }
    _notify();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    check();
    await loaded;
    check();
    if (_loadFailed) throw mediaProtocol();
    if (busy)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '请等待当前媒体操作完成',
      );
    if (!host.enabled)
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '演示环境不上传或发送媒体，不会生成虚假回执',
      );
    busy = true;
    error = null;
    _notify();
    try {
      final result = await action();
      check();
      return result;
    } catch (e) {
      if (current) error = privateMediaError(e);
      rethrow;
    } finally {
      if (current) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> pick(MediaPurpose purpose) => _run(() async {
    if (intent != null || recording) throw mediaProtocol();
    picking = true;
    _notify();
    try {
      // Native selection owns its late-result cleanup; don't race away from it.
      final selection = await input.pick(purpose, scope);
      if (selection != null) await _capture(selection, purpose);
      check();
    } finally {
      if (current) picking = false;
    }
  });
  Future<void> _capture(
    PrivateMediaSelection selection,
    MediaPurpose purpose,
  ) async {
    MediaUploadFile? source;
    try {
      check();
      final bytes = await scope.wait(selection.file.length());
      MediaLimits.validateSelection(
        purpose,
        bytes: bytes,
        durationMillis: selection.durationMillis,
      );
      final parent = await scope.wait(host.temporaryParent());
      source = await MediaUploadFile.capture(
        identity: scope,
        temporaryParent: parent,
        purpose: purpose,
        bytes: bytes,
        durationMillis: selection.durationMillis,
        content: selection.file.openRead(),
      );
      check();
      final entry = PrivateMediaIntent._(
        scope.userId,
        receiver,
        purpose,
        bytes,
        selection.durationMillis,
        _key(),
        _key(),
      );
      intent = entry;
      await host._save(entry);
      check();
      _source = source;
      source = null;
    } finally {
      await source?.dispose();
      await selection.dispose();
    }
  }

  Future<void> startRecording() => _run(() async {
    if (intent != null || recording) throw mediaProtocol();
    await input.startRecording(scope);
    check();
    recording = true;
    // A UI-bound one-shot limit, not a background runner. Finishing never sends.
    _recordLimit = Timer(const Duration(seconds: 60), () {
      if (current && recording)
        unawaited(finishRecording().catchError((Object _) {}));
    });
  });
  Future<void> finishRecording() => _run(() async {
    if (!recording) throw mediaProtocol();
    _recordLimit?.cancel();
    recording = false;
    final selection = await input.finishRecording(scope);
    if (selection != null) await _capture(selection, MediaPurpose.privateVoice);
    check();
  });
  Future<void> upload({bool readOnly = false}) => _run(() async {
    final entry = intent;
    if (entry == null || entry.sendAttempted) throw mediaProtocol();
    if (entry.status == null) {
      entry.allocationAttempted = true;
      await host._save(entry);
      check();
      final result = await host.api.mediaAssetJson(
        action: MediaAssetAction.allocate,
        identity: scope,
        purpose: entry.purpose,
        requestId: entry.allocationKey,
      );
      check();
      entry.accept(result.data);
      await host._save(entry);
      check();
    } else {
      final result = await host.api.mediaAssetJson(
        action: MediaAssetAction.status,
        identity: scope,
        assetId: entry.status!.assetId,
      );
      check();
      entry.accept(result.data);
      await host._save(entry);
      check();
    }
    if (readOnly) return;
    var status = entry.status!;
    if (status.isExpired(DateTime.now()))
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '媒体已过期，可放弃本次上传后重新选择；不会删除服务器文件',
      );
    if (status.state == MediaAssetState.allocated && !entry.putAttempted) {
      final source = _source;
      if (source == null)
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          message: '原文件已清理；只可检查上传状态，不会用新文件替换原上传',
        );
      entry.putAttempted = true;
      await host._save(entry);
      check();
      final result = await host.api.putMediaAssetContent(
        assetId: status.assetId,
        expectedVersion: status.version,
        purpose: entry.purpose,
        bytes: entry.bytes,
        content: source.openRead(),
        identity: scope,
      );
      check();
      entry.accept(result.data);
      await host._save(entry);
      check();
      status = entry.status!;
    }
    if (status.state == MediaAssetState.uploading ||
        status.state == MediaAssetState.quarantined) {
      final result = await host.api.mediaAssetJson(
        action: MediaAssetAction.complete,
        assetId: status.assetId,
        expectedVersion: status.version,
        identity: scope,
      );
      check();
      entry.accept(result.data);
      await host._save(entry);
      check();
    }
  });
  Future<ChatMessage> send(MediaPrivateMessageRepository repository) => _run(
    () async {
      final entry = intent;
      if (entry == null) throw mediaProtocol();
      final media = entry.commandMedia ?? entry.status?.ready;
      if (media == null ||
          (!entry.sendAttempted && entry.status!.isExpired(DateTime.now())))
        throw mediaProtocol();
      entry.commandMedia = media;
      entry.sendAttempted = true;
      await host._save(entry);
      check();
      final receipt = await scope.wait(
        repository.sendPrivateMediaMessage(
          conversation: conversation,
          media: media,
          identity: scope,
          requestId: entry.requestId,
        ),
      );
      check();
      // Even test/mock opt-in adapters must produce a matching stored receipt.
      if (!receipt.isMine ||
          receipt.senderUserId != scope.userId ||
          receipt.content.isNotEmpty ||
          receipt.messageType.mediaPurpose != media.purpose ||
          jsonEncode(receipt.media?.toJson()) != jsonEncode(media.toJson()) ||
          !{
            ChatMessageStatus.sent,
            ChatMessageStatus.storedPendingDelivery,
          }.contains(receipt.status))
        throw mediaProtocol();
      await host._remove(entry);
      check();
      intent = null;
      await _source?.dispose();
      _source = null;
      check();
      return receipt;
    },
  );
  Future<void> discard() => _run(() async {
    final entry = intent;
    if (entry == null || !entry.canDiscard)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '结果未知，原请求已保留；请先恢复，不能丢弃后换键重发',
      );
    await host._abandon(entry, scope);
    check();
    intent = null;
    await _source?.dispose();
    _source = null;
    check();
  });
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unregister();
    scope.dispose();
    _recordLimit?.cancel();
    host._visits.remove(this);
    _cleanup = Future.wait([
      input.dispose(),
      if (_source != null) _source!.dispose(),
    ]).then((_) {});
    host._cleanups.add(_cleanup!);
    unawaited(_cleanup!.catchError((Object _) {}));
    super.dispose();
  }
}

String privateMediaError(Object e) =>
    e is ApiException ? e.message : '媒体操作未完成，请检查权限或网络；未知结果保留原请求，可明确恢复';
