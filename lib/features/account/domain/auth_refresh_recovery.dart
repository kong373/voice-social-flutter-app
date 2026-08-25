import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

const int _pendingAuthRefreshSchema = 1;
final RegExp _pendingRequestIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,80}$');
final RegExp _sessionFingerprintPattern = RegExp(r'^[a-f0-9]{64}$');

/// The server binds refresh recovery to this exact tuple. Keep only its hash
/// on the client so a pending record never becomes a second secret store.
String authRefreshSessionFingerprint({
  required AuthSession session,
  required String clientId,
}) => sha256
    .convert(
      utf8.encode(
        '${session.refreshToken}\u0000${session.deviceId}\u0000$clientId',
      ),
    )
    .toString();

class PendingAuthRefresh {
  const PendingAuthRefresh({
    required this.requestId,
    required this.sessionFingerprint,
    required this.createdAt,
    required this.expiresAt,
  });

  final String requestId;
  final String sessionFingerprint;
  final DateTime createdAt;
  final DateTime expiresAt;

  static bool isValidRequestId(String value) =>
      _pendingRequestIdPattern.hasMatch(value);

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': _pendingAuthRefreshSchema,
    'requestId': requestId,
    'sessionFingerprint': sessionFingerprint,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  static PendingAuthRefresh? decode(String source) {
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map) {
        return null;
      }
      final int? schema = int.tryParse(decoded['schema']?.toString() ?? '');
      final String requestId = decoded['requestId']?.toString().trim() ?? '';
      final String fingerprint =
          decoded['sessionFingerprint']?.toString().trim() ?? '';
      final DateTime? createdAt = DateTime.tryParse(
        decoded['createdAt']?.toString() ?? '',
      );
      final DateTime? expiresAt = DateTime.tryParse(
        decoded['expiresAt']?.toString() ?? '',
      );
      if (schema != _pendingAuthRefreshSchema ||
          !_pendingRequestIdPattern.hasMatch(requestId) ||
          !_sessionFingerprintPattern.hasMatch(fingerprint) ||
          createdAt == null ||
          expiresAt == null ||
          !expiresAt.isAfter(createdAt)) {
        return null;
      }
      return PendingAuthRefresh(
        requestId: requestId,
        sessionFingerprint: fingerprint,
        createdAt: createdAt.toUtc(),
        expiresAt: expiresAt.toUtc(),
      );
    } on FormatException {
      return null;
    }
  }
}

enum AuthRefreshRecoveryFailure { malformed, expired, sessionChanged }

class AuthRefreshRecoveryException implements Exception {
  const AuthRefreshRecoveryException(this.reason);

  final AuthRefreshRecoveryFailure reason;

  String get message => switch (reason) {
    AuthRefreshRecoveryFailure.malformed => '刷新恢复状态无效，请重新登录',
    AuthRefreshRecoveryFailure.expired => '刷新恢复窗口已过期，请重新登录',
    AuthRefreshRecoveryFailure.sessionChanged => '刷新会话已变化，请重新登录',
  };

  @override
  String toString() => 'AuthRefreshRecoveryException: $message';
}
