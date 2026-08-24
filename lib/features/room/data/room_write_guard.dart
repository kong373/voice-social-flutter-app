import 'dart:math';

import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

/// Serializes room mutations and coordinates one request id for concurrent
/// calls representing the same logical intent. The first-party room
/// endpoints are stateful writes; sending two overlapping commands can
/// otherwise make a later response overwrite a newer user intent.
class RoomWriteGuard {
  RoomWriteGuard({this.scope = 'room'});

  final String scope;
  final Map<String, _InFlightWrite> _inFlight = <String, _InFlightWrite>{};
  final Map<String, String> _ambiguousRetryIds = <String, String>{};
  final Map<String, String> _requestIdFingerprints = <String, String>{};
  final Map<String, String> _requestIdOwners = <String, String>{};
  Future<void> _tail = Future<void>.value();
  static final Random _secureRandom = Random.secure();

  Future<T> run<T>({
    required String intent,
    String? requestId,
    String? fingerprint,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    final String resolvedFingerprint = fingerprint ?? intent;
    final String? explicitRequestId = _normalizeRequestId(requestId);
    final _InFlightWrite? existing = _inFlight[intent];
    if (existing != null) {
      _assertRequestCompatibility(
        requestId: explicitRequestId,
        fingerprint: resolvedFingerprint,
        existing: existing,
      );
      return existing.future.then((Object? value) => value as T);
    }

    final String? retainedRequestId = _ambiguousRetryIds[intent];
    if (explicitRequestId != null &&
        retainedRequestId != null &&
        explicitRequestId != retainedRequestId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '同一房间操作仍在待确认中，不能更换请求幂等 ID',
      );
    }
    final String selectedRequestId =
        explicitRequestId ?? retainedRequestId ?? _newRequestId();
    final String? previousFingerprint =
        _requestIdFingerprints[selectedRequestId];
    if (previousFingerprint != null &&
        previousFingerprint != resolvedFingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '请求幂等 ID 已绑定到另一种房间操作',
      );
    }
    final String? previousOwner = _requestIdOwners[selectedRequestId];
    if (previousOwner != null && previousOwner != intent) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '请求幂等 ID 已绑定到另一种未完成的房间操作',
      );
    }
    _requestIdFingerprints[selectedRequestId] = resolvedFingerprint;
    _requestIdOwners[selectedRequestId] = intent;
    _ambiguousRetryIds.remove(intent);
    final Future<T> operation = _tail.then<T>((_) async {
      try {
        final T value = await action(<String, String>{
          'X-Request-Id': selectedRequestId,
        });
        // A successful replay or a definitive failure closes this logical
        // submission. A later identical user action gets a fresh id.
        _ambiguousRetryIds.remove(intent);
        return value;
      } catch (error, stackTrace) {
        if (_isAmbiguous(error)) {
          // The server may have committed the write before the response was
          // lost. Keep this id for the next same-intent submission so the
          // backend can safely replay its authoritative result.
          _ambiguousRetryIds[intent] = selectedRequestId;
        } else {
          _ambiguousRetryIds.remove(intent);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    final Future<Object?> tracked = operation.then<Object?>((T value) => value);
    final _InFlightWrite submission = _InFlightWrite(
      requestId: selectedRequestId,
      fingerprint: resolvedFingerprint,
      future: tracked,
    );
    _inFlight[intent] = submission;
    tracked.then<void>(
      (_) => _removeIfCurrent(intent, submission),
      onError: (Object _, StackTrace __) =>
          _removeIfCurrent(intent, submission),
    );
    // A failed mutation must not poison the queue for later, independent
    // intents. The original operation still carries the failure to its caller.
    _tail = tracked.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static String? _normalizeRequestId(String? requestId) {
    if (requestId == null) {
      return null;
    }
    final String normalized = requestId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(normalized)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请求幂等 ID 格式无效',
      );
    }
    return normalized;
  }

  static void _assertRequestCompatibility({
    required String? requestId,
    required String fingerprint,
    required _InFlightWrite existing,
  }) {
    if (requestId != null && requestId != existing.requestId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '同一并发房间操作不能更换请求幂等 ID',
      );
    }
    if (fingerprint != existing.fingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '同一并发房间操作的请求指纹不一致',
      );
    }
  }

  void _removeIfCurrent(String intent, _InFlightWrite tracked) {
    if (identical(_inFlight[intent], tracked)) {
      _inFlight.remove(intent);
      if (!_ambiguousRetryIds.containsKey(intent)) {
        _requestIdFingerprints.remove(tracked.requestId);
        if (_requestIdOwners[tracked.requestId] == intent) {
          _requestIdOwners.remove(tracked.requestId);
        }
      }
    }
  }

  String _newRequestId() {
    final String normalizedScope = scope.replaceAll(
      RegExp(r'[^A-Za-z0-9._:-]'),
      '-',
    );
    final String safeScope = normalizedScope.substring(
      0,
      min(normalizedScope.length, 40),
    );
    final StringBuffer random = StringBuffer();
    for (int index = 0; index < 32; index++) {
      random.write(_hexAlphabet[_secureRandom.nextInt(_hexAlphabet.length)]);
    }
    return '$safeScope-${random.toString()}';
  }

  static const String _hexAlphabet = '0123456789abcdef';

  static bool _isAmbiguous(Object error) {
    if (error is! ApiException) {
      // An unclassified transport/client exception does not prove that the
      // backend skipped the mutation. Reusing the same key is safer than
      // accidentally executing a room or wallet write twice.
      return true;
    }
    // The frozen backend idempotency service uses 40901 when the persisted
    // operation state cannot yet be replayed and 40902 while the original
    // request is still in progress. Both outcomes must keep the original key;
    // rotating it could execute the same room/economic write twice. A 40903
    // fingerprint mismatch is definitive and intentionally rotates.
    if (error.code == 40901 || error.code == 40902) {
      return true;
    }
    if (error.code == 40903) {
      return false;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.conflict => false,
      _ => false,
    };
  }

  /// Accepts legacy endpoints' null data while rejecting an explicit
  /// negative mutation result hidden behind HTTP 200. Callers that have a
  /// response identity/state contract should validate those fields in their
  /// repository before returning to the UI.
  static void validateMutationResponse(
    ApiResponse response, {
    required String operation,
    Iterable<String> requiredFields = const <String>[],
  }) {
    final Object? data = response.data;
    if (data == null) {
      if (requiredFields.isNotEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 响应缺少权威字段',
        );
      }
      return;
    }
    if (data is bool) {
      if (!data) {
        throw ApiException(
          kind: ApiFailureKind.business,
          message: '$operation 未被服务端接受',
        );
      }
      if (requiredFields.isNotEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 响应结构无法识别',
        );
      }
      return;
    }
    if (data is! Map) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应结构无法识别',
      );
    }
    for (final String field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 响应缺少权威字段 $field',
        );
      }
    }
    final Object? successValue = data.containsKey('success')
        ? data['success']
        : data.containsKey('isSuccess')
        ? data['isSuccess']
        : null;
    if (data.containsKey('success') || data.containsKey('isSuccess')) {
      final bool? success = _asNullableBool(successValue);
      if (success == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 成功字段无法识别',
        );
      }
      if (!success) {
        throw ApiException(
          kind: ApiFailureKind.business,
          message: '$operation 未被服务端接受',
        );
      }
    }
    final String? status = data['status']?.toString().trim().toUpperCase();
    if (status == null || status.isEmpty) {
      return;
    }
    if (_failureStatuses.contains(status) ||
        status.contains('BLOCKED') ||
        status.contains('UNAVAILABLE') ||
        status.contains('REJECT')) {
      throw ApiException(
        kind: ApiFailureKind.business,
        message: '$operation 未被服务端接受',
      );
    }
  }

  static const Set<String> _failureStatuses = <String>{
    'FAILED',
    'FAILURE',
    'DECLINED',
    'CANCELLED',
    'CANCELED',
    'ERROR',
  };

  static bool? _asNullableBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => null,
    };
  }
}

class _InFlightWrite {
  const _InFlightWrite({
    required this.requestId,
    required this.fingerprint,
    required this.future,
  });

  final String requestId;
  final String fingerprint;
  final Future<Object?> future;
}
