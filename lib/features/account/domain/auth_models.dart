import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.userId,
    required this.mobile,
    required this.roles,
    this.boundRoomId,
  });

  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;
  final int userId;
  final String mobile;
  final String roles;
  final String? boundRoomId;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  String get authorizationHeader =>
      '${tokenType.isEmpty ? 'Bearer' : tokenType} $accessToken';

  Map<String, Object?> toJson() => <String, Object?>{
        'accessToken': accessToken,
        'tokenType': tokenType,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
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
    final DateTime? expiresAt =
        DateTime.tryParse(decoded['expiresAt']?.toString() ?? '');
    final int? userId = int.tryParse(decoded['userId']?.toString() ?? '');
    if (accessToken == null ||
        accessToken.isEmpty ||
        expiresAt == null ||
        userId == null) {
      return null;
    }
    return AuthSession(
      accessToken: accessToken,
      tokenType: decoded['tokenType']?.toString() ?? 'Bearer',
      expiresAt: expiresAt,
      userId: userId,
      mobile: decoded['mobile']?.toString() ?? '',
      roles: decoded['roles']?.toString() ?? '',
      boundRoomId: decoded['boundRoomId']?.toString(),
    );
  }
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
