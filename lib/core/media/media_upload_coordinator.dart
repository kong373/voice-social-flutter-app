import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'media_files.dart';
import 'media_identity.dart';
import 'media_models.dart';

/// One selected file, one original allocation key, one server asset. Retain this
/// instance above presentation lifetimes; it is not a process-persistent journal.
/// Losing an allocation response retries only the same key/purpose. Once an ID
/// is known, recovery never allocates another ID or substitutes another file.
class MediaUploadCoordinator {
  static final _byScope = Expando<Map<String, MediaUploadCoordinator>>();

  factory MediaUploadCoordinator({
    required ApiClient api,
    required MediaIdentityScope identity,
    required MediaUploadFile source,
    required String requestId,
    DateTime Function()? now,
  }) {
    identity.check();
    if (!identical(source.identity, identity) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId))
      throw mediaProtocol();
    final entries = _byScope[identity] ??= <String, MediaUploadCoordinator>{};
    final existing = entries[requestId];
    if (existing != null) {
      if (!identical(existing.source, source) || !identical(existing.api, api))
        throw mediaProtocol();
      existing._check();
      return existing;
    }
    if (entries.values.any((value) => identical(value.source, source)))
      throw mediaProtocol();
    final result = MediaUploadCoordinator._(
      api: api,
      identity: identity,
      source: source,
      requestId: requestId,
      now: now,
    );
    entries[requestId] = result;
    return result;
  }

  MediaUploadCoordinator._({
    required this.api,
    required this.identity,
    required this.source,
    required this.requestId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final ApiClient api;
  final MediaIdentityScope identity;
  final MediaUploadFile source;
  final String requestId;
  final DateTime Function() _now;
  MediaAssetStatus? _latest;
  MediaAssetStatus? get latest =>
      identity.isCurrent && !_disposed ? _latest : null;
  bool _putAttempted = false;
  bool _disposed = false;
  Future<MediaAssetStatus>? _flight;

  /// Explicit caller action. On subsequent attempts GET current metadata first;
  /// never retry an uncertain PUT, including a still-ALLOCATED response.
  Future<MediaAssetStatus> advance() => _singleFlight(() async {
    if (_latest == null) {
      final response = await identity.wait(
        api.mediaAssetJson(
          action: MediaAssetAction.allocate,
          identity: identity,
          purpose: source.purpose,
          requestId: requestId,
        ),
      );
      _accept(response.data);
    } else {
      await _read();
    }
    _check();
    var current = _latest!;
    if (current.isExpired(_now()) ||
        current.state == MediaAssetState.rejected ||
        current.state == MediaAssetState.revoked)
      return current;
    if (current.state == MediaAssetState.allocated && !_putAttempted) {
      if (current.version != 0) throw mediaProtocol();
      _putAttempted = true; // Before opening a connection, not after success.
      final response = await identity.wait(
        api.putMediaAssetContent(
          assetId: current.assetId,
          expectedVersion: current.version,
          purpose: source.purpose,
          bytes: source.bytes,
          content: source.openRead(),
          identity: identity,
        ),
      );
      _accept(response.data);
      current = _latest!;
    }
    _check();
    if (current.state == MediaAssetState.uploading ||
        current.state == MediaAssetState.quarantined) {
      final response = await identity.wait(
        api.mediaAssetJson(
          action: MediaAssetAction.complete,
          identity: identity,
          assetId: current.assetId,
          expectedVersion: current.version,
        ),
      );
      _accept(response.data);
    }
    _check();
    return _latest!;
  });

  /// Read-only recovery. No polling runner, PUT, scan, revoke or allocate.
  Future<MediaAssetStatus> recover() => _singleFlight(_read);

  Future<MediaAssetStatus> _read() async {
    _check();
    final previous = _latest;
    if (previous == null)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '尚未获得资产ID，请保留原请求键恢复分配',
      );
    final response = await identity.wait(
      api.mediaAssetJson(
        action: MediaAssetAction.status,
        identity: identity,
        assetId: previous.assetId,
      ),
    );
    _accept(response.data);
    return _latest!;
  }

  Future<MediaAssetStatus> _singleFlight(
    Future<MediaAssetStatus> Function() action,
  ) {
    _check();
    if (_flight != null) return _flight!;
    late final Future<MediaAssetStatus> operation;
    operation = Future<MediaAssetStatus>.sync(action).whenComplete(() {
      if (identical(_flight, operation)) _flight = null;
    });
    _flight = operation;
    return operation;
  }

  void _check() {
    identity.check();
    if (_disposed) throw MediaIdentityScope.invalid;
  }

  void _accept(Object? data) {
    _check();
    final value = MediaAssetStatus.fromJson(data);
    final previous = _latest;
    if (value.purpose != source.purpose ||
        (value.bytes != null && value.bytes != source.bytes) ||
        (previous != null &&
            (value.assetId != previous.assetId ||
                value.expiresAt != previous.expiresAt ||
                value.version < previous.version)))
      throw mediaProtocol();
    if (previous != null) {
      if (value.version == previous.version &&
          (value.state != previous.state ||
              value.bytes != previous.bytes ||
              value.mediaType != previous.mediaType ||
              value.durationMillis != previous.durationMillis))
        throw mediaProtocol();
      final allowed = switch (previous.state) {
        MediaAssetState.allocated => MediaAssetState.values.toSet(),
        MediaAssetState.uploading => {
          MediaAssetState.uploading,
          MediaAssetState.quarantined,
          MediaAssetState.ready,
          MediaAssetState.rejected,
          MediaAssetState.revoked,
        },
        MediaAssetState.quarantined => {
          MediaAssetState.quarantined,
          MediaAssetState.ready,
          MediaAssetState.rejected,
          MediaAssetState.revoked,
        },
        MediaAssetState.ready => {
          MediaAssetState.ready,
          MediaAssetState.revoked,
        },
        MediaAssetState.rejected => {
          MediaAssetState.rejected,
          MediaAssetState.revoked,
        },
        MediaAssetState.revoked => {MediaAssetState.revoked},
      };
      if (!allowed.contains(value.state)) throw mediaProtocol();
    }
    _latest = value;
  }

  Future<void> dispose() async {
    _disposed = true;
    await source.dispose();
  }
}
