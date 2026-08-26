import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

/// First-party capability used to obtain short-lived RTC credentials.
///
/// Implementations must return provider credentials issued for the current
/// authenticated room session. No provider secret is accepted by this API.
abstract interface class RtcTokenRepository {
  Future<RtcCredentials> buildRtcToken({
    required String roomId,
    required int currentUserId,
    String? requestId,
  });
}

/// Authenticated client for the first-party Agora token endpoint.
class BackendRtcTokenRepository implements RtcTokenRepository {
  BackendRtcTokenRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
    DateTime Function()? now,
  }) : _apiClient = apiClient,
       _routes = routes,
       _now = now ?? DateTime.now;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final DateTime Function() _now;

  @override
  Future<RtcCredentials> buildRtcToken({
    required String roomId,
    required int currentUserId,
    String? requestId,
  }) async {
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '构建 RTC 凭证缺少房间 ID',
      );
    }
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '构建 RTC 凭证缺少用户 ID',
      );
    }

    final ApiResponse response = await _apiClient.get(
      _routes.buildRtcToken,
      query: <String, String>{'roomId': normalizedRoomId},
      headers: <String, String>{
        if (requestId != null && requestId.trim().isNotEmpty)
          'X-Request-Id': requestId.trim(),
      },
    );
    final RtcCredentials credentials = RtcCredentialsParser.fromBackendData(
      response.data,
      now: _now().toUtc(),
    );
    if (credentials.uid != currentUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证 uid 与当前用户不一致',
      );
    }
    final String? responseRoomId = RtcCredentialsParser.roomIdFromBackendData(
      response.data,
    );
    if ((responseRoomId != null && responseRoomId != normalizedRoomId) ||
        (responseRoomId == null && credentials.channelId != normalizedRoomId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证房间与请求不一致',
      );
    }
    return credentials;
  }
}

/// Strict parser for the public subset of the token response.
///
/// The backend response is intentionally treated as an allow-list. Unknown
/// keys are ignored, so an accidentally included provider signing secret is
/// neither copied into [RtcCredentials] nor exposed by a diagnostic
/// representation.
class RtcCredentialsParser {
  const RtcCredentialsParser._();

  static const Set<String> _supportedRoles = <String>{
    'audience',
    'listener',
    'guest',
    'subscriber',
    'broadcaster',
    'publisher',
    'host',
    'speaker',
    'anchor',
  };

  /// Returns an optional explicit room identity for repository-level
  /// correlation. Older responses omit this field and use channelId as the
  /// room identity fallback.
  static String? roomIdFromBackendData(Object? raw) {
    final Map<String, Object?> envelopeOrData = _asMap(raw);
    final Object? nestedData = envelopeOrData['data'];
    final Map<String, Object?> data = nestedData is Map
        ? _asMap(nestedData)
        : envelopeOrData;
    String? resolved;
    for (final String key in <String>['roomId', 'roomIdStr', 'room']) {
      final String? value = _optionalString(data[key]);
      if (value != null) {
        if (resolved != null && resolved != value) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: 'RTC 凭证包含冲突的房间 ID',
          );
        }
        resolved = value;
      }
    }
    return resolved;
  }

  static RtcCredentials fromBackendData(Object? raw, {DateTime? now}) {
    final Map<String, Object?> envelopeOrData = _asMap(raw);
    final Object? nestedData = envelopeOrData['data'];
    final Map<String, Object?> data = nestedData is Map
        ? _asMap(nestedData)
        : envelopeOrData;
    final String provider = _requiredString(data, 'provider').toLowerCase();
    if (provider != 'agora') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证 provider 不是 agora',
      );
    }

    final String appId = _requiredString(data, 'appId');
    _assertMatchingStringAliases(data, 'channelId', 'channelName');
    final String channelId = _requiredString(
      data,
      'channelId',
      aliases: <String>['channelName'],
    );
    final String token = _requiredString(data, 'token');
    _assertMatchingIntAliases(data, 'uid', 'userId');
    final int uid = _requiredInt(data, 'uid', aliases: <String>['userId']);
    if (uid <= 0 || uid > rtcUidMax) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证 uid 必须是有效的正整数',
      );
    }
    final String role = _requiredString(data, 'role');
    if (!_supportedRoles.contains(role.toLowerCase())) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证 role 无法识别',
      );
    }

    final DateTime current = (now ?? DateTime.now()).toUtc();
    DateTime? expiresAt = _dateTimeValue(
      data['expiresAt'] ?? data['expireAt'] ?? data['expireTime'],
    );
    int? ttlSeconds = _positiveInt(
      data['ttlSeconds'] ?? data['ttl'] ?? data['expiresIn'],
    );
    if (expiresAt == null && ttlSeconds == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证缺少 expiresAt 或 ttlSeconds',
      );
    }
    if (expiresAt == null && ttlSeconds != null) {
      expiresAt = current.add(Duration(seconds: ttlSeconds));
    }
    if (expiresAt != null && !expiresAt.isAfter(current)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证已过期',
      );
    }
    if (ttlSeconds == null && expiresAt != null) {
      final int derived = expiresAt.difference(current).inSeconds;
      if (derived <= 0) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'RTC 凭证有效期无效',
        );
      }
      ttlSeconds = derived;
    }

    return RtcCredentials(
      solution: RtcSolution.agora,
      provider: provider,
      appId: appId,
      token: token,
      channelId: channelId,
      uid: uid,
      role: role,
      expiresAt: expiresAt,
      ttlSeconds: ttlSeconds,
    );
  }

  static Map<String, Object?> _asMap(Object? raw) {
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in raw.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: 'RTC 凭证响应结构无法识别',
    );
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final Iterable<String> keys = <String>[key, ...aliases];
    for (final String candidate in keys) {
      final Object? value = data[candidate];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw ApiException(kind: ApiFailureKind.protocol, message: 'RTC 凭证缺少 $key');
  }

  static void _assertMatchingStringAliases(
    Map<String, Object?> data,
    String primary,
    String alias,
  ) {
    final String? primaryValue = _optionalString(data[primary]);
    final String? aliasValue = _optionalString(data[alias]);
    if (primaryValue != null &&
        aliasValue != null &&
        primaryValue != aliasValue) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证包含冲突的频道 ID',
      );
    }
  }

  static void _assertMatchingIntAliases(
    Map<String, Object?> data,
    String primary,
    String alias,
  ) {
    final int? primaryValue = _integerValue(data[primary]);
    final int? aliasValue = _integerValue(data[alias]);
    if (primaryValue != null &&
        aliasValue != null &&
        primaryValue != aliasValue) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'RTC 凭证包含冲突的 uid',
      );
    }
  }

  static String? _optionalString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static int _requiredInt(
    Map<String, Object?> data,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final Iterable<String> keys = <String>[key, ...aliases];
    for (final String candidate in keys) {
      final Object? value = data[candidate];
      final int? parsed = _integerValue(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: 'RTC 凭证缺少有效的 $key',
    );
  }

  static int? _positiveInt(Object? value) {
    final int? parsed = _integerValue(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static int? _integerValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    final int? numeric = _integerValue(value);
    if (numeric != null) {
      // Unix timestamps in backend contracts are usually seconds, while
      // millisecond timestamps are accepted when the value is unambiguous.
      final bool milliseconds = numeric.abs() >= 100000000000;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds ? numeric : numeric * 1000,
        isUtc: true,
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim())?.toUtc();
    }
    return null;
  }
}
