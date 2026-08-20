import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.userId,
    required this.mobile,
    required this.roles,
    this.refreshToken = '',
    DateTime? refreshExpiresAt,
    this.deviceId = '',
    this.clientId = '',
    this.boundRoomId,
  }) : refreshExpiresAt = refreshExpiresAt ?? expiresAt;

  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String deviceId;
  final String clientId;
  final int userId;
  final String mobile;
  final String roles;
  final String? boundRoomId;

  bool get isAccessExpired => !expiresAt.isAfter(DateTime.now());
  bool get isRefreshExpired => !refreshExpiresAt.isAfter(DateTime.now());
  bool get canRefresh => refreshToken.isNotEmpty && !isRefreshExpired;
  bool get shouldRefreshAccess =>
      !expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)));

  /// Backward-compatible alias for code that only reasons about access tokens.
  bool get isExpired => isAccessExpired;

  String get authorizationHeader =>
      '${tokenType.isEmpty ? 'Bearer' : tokenType} $accessToken';

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 2,
    'accessToken': accessToken,
    'tokenType': tokenType,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'refreshToken': refreshToken,
    'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'clientId': clientId,
    'userId': userId,
    'mobile': mobile,
    'roles': roles,
    'boundRoomId': boundRoomId,
  };

  String encode() => jsonEncode(toJson());

  static AuthSession? decode(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final String? accessToken = decoded['accessToken']?.toString();
    final DateTime? expiresAt = DateTime.tryParse(
      decoded['expiresAt']?.toString() ?? '',
    );
    final int? userId = int.tryParse(decoded['userId']?.toString() ?? '');
    if (accessToken == null ||
        accessToken.isEmpty ||
        expiresAt == null ||
        userId == null) {
      return null;
    }
    final String refreshToken = decoded['refreshToken']?.toString() ?? '';
    final DateTime refreshExpiresAt =
        DateTime.tryParse(decoded['refreshExpiresAt']?.toString() ?? '') ??
        expiresAt;
    return AuthSession(
      accessToken: accessToken,
      tokenType: decoded['tokenType']?.toString() ?? 'Bearer',
      expiresAt: expiresAt,
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt,
      deviceId: decoded['deviceId']?.toString() ?? '',
      clientId: decoded['clientId']?.toString() ?? '',
      userId: userId,
      mobile: decoded['mobile']?.toString() ?? '',
      roles: decoded['roles']?.toString() ?? '',
      boundRoomId: _nullableString(decoded['boundRoomId']),
    );
  }

  static String? _nullableString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

class SmsChallenge {
  const SmsChallenge({
    required this.challengeId,
    required this.expiresAt,
    required this.retryAfter,
    this.developmentCode,
  });

  final String challengeId;
  final DateTime expiresAt;
  final int retryAfter;
  final String? developmentCode;

  SmsChallenge copyWith({String? developmentCode}) => SmsChallenge(
    challengeId: challengeId,
    expiresAt: expiresAt,
    retryAfter: retryAfter,
    developmentCode: developmentCode ?? this.developmentCode,
  );
}

class ClientDevice {
  const ClientDevice({
    required this.deviceType,
    required this.deviceId,
    required this.mobileKind,
    required this.appMarketType,
    required this.isEmulator,
    required this.smDeviceId,
  });

  final int deviceType;
  final String deviceId;
  final String mobileKind;
  final int appMarketType;
  final int isEmulator;
  final String smDeviceId;
}

enum AuthOutcomeType { authenticated, registrationRequired }

class AuthOutcome {
  const AuthOutcome._({required this.type, this.session});

  const AuthOutcome.authenticated(AuthSession session)
    : this._(type: AuthOutcomeType.authenticated, session: session);

  const AuthOutcome.registrationRequired()
    : this._(type: AuthOutcomeType.registrationRequired);

  final AuthOutcomeType type;
  final AuthSession? session;
}

class RegistrationProfile {
  const RegistrationProfile({
    required this.nickname,
    required this.sex,
    this.birthday,
    this.inviteCode = '',
  });

  final String nickname;
  final int sex;
  final String? birthday;
  final String inviteCode;
}
