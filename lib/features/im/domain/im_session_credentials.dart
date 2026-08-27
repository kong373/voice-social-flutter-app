/// The only credential shape accepted by the Tencent IM session boundary.
///
/// The server is the sole issuer of [sdkAppId] and [userSig].  This value is
/// deliberately not serializable to app storage; it is held by an adapter only
/// for the lifetime of the in-memory IM session.
class ImSessionCredentials {
  const ImSessionCredentials({
    required this.provider,
    required this.sdkAppId,
    required this.userId,
    required this.userSig,
    required this.expiresAt,
    required this.ttlSeconds,
    required this.imStatus,
    this.systemAccount = '',
  });

  static const String expectedProvider = 'tencent-im';
  static const String readyStatus = 'READY';
  static final RegExp canonicalUserIdPattern = RegExp(r'^u-[1-9]\d{0,29}$');
  static final RegExp userSigPattern = RegExp(r'^[A-Za-z0-9*_\-]+$');

  /// Public system sender metadata used only to authenticate refresh hints.
  /// It is not signing material and must stay within Tencent's 32-byte
  /// identifier boundary.
  static final RegExp systemAccountPattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
  static const int minimumTtlSeconds = 60;
  static const int maximumTtlSeconds = 7 * 24 * 60 * 60;
  static const Duration expiryClockTolerance = Duration(minutes: 5);
  static const Duration renewalThreshold = Duration(minutes: 5);
  static const int minimumUserSigLength = 16;
  static const int maximumUserSigLength = 4096;

  /// The backend data allow-list is intentionally closed.  Adding a response
  /// field requires an explicit contract review rather than silently accepting
  /// data that might contain a secret or a client-controlled identity.
  static const Set<String> allowedFields = <String>{
    'provider',
    'sdkAppId',
    'userId',
    'userSig',
    'expiresAt',
    'ttlSeconds',
    'imStatus',
    'systemAccount',
  };

  final String provider;
  final int sdkAppId;
  final String userId;
  final String userSig;
  final DateTime expiresAt;
  final int ttlSeconds;
  final String imStatus;
  final String systemAccount;

  /// Parses the `data` member of the authenticated credential response.
  ///
  /// The parser accepts only the fixed response contract.  In particular it
  /// does not accept a client uid, an app id from configuration, or aliases for
  /// UserSig fields.
  factory ImSessionCredentials.fromBackendData(Object? raw, {DateTime? now}) {
    if (raw is! Map) {
      throw const ImCredentialException(ImCredentialFailure.invalidShape);
    }
    final Map<Object?, Object?> source = Map<Object?, Object?>.from(raw);
    final Set<Object?> unknown = source.keys
        .where((Object? key) => !allowedFields.contains(key))
        .toSet();
    if (unknown.isNotEmpty) {
      throw const ImCredentialException(ImCredentialFailure.unknownField);
    }

    Object? requiredValue(String key) {
      if (!source.containsKey(key) || source[key] == null) {
        throw const ImCredentialException(ImCredentialFailure.missingField);
      }
      return source[key];
    }

    final Object? providerValue = requiredValue('provider');
    final Object? sdkAppIdValue = requiredValue('sdkAppId');
    final Object? userIdValue = requiredValue('userId');
    final Object? userSigValue = requiredValue('userSig');
    final Object? expiresAtValue = requiredValue('expiresAt');
    final Object? ttlSecondsValue = requiredValue('ttlSeconds');
    final Object? imStatusValue = requiredValue('imStatus');
    final Object? systemAccountValue = requiredValue('systemAccount');

    if (providerValue is! String || providerValue != expectedProvider) {
      throw const ImCredentialException(ImCredentialFailure.invalidProvider);
    }
    if (sdkAppIdValue is! int || sdkAppIdValue <= 0) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    if (userIdValue is! String || !isCanonicalUserId(userIdValue)) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    if (userSigValue is! String || !isValidUserSig(userSigValue)) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    if (imStatusValue is! String || imStatusValue != readyStatus) {
      throw const ImCredentialException(ImCredentialFailure.invalidStatus);
    }
    if (systemAccountValue is! String ||
        !isValidSystemAccount(systemAccountValue)) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    if (ttlSecondsValue is! int || !isValidTtlSeconds(ttlSecondsValue)) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    if (expiresAtValue is! String || !_looksLikeIso8601(expiresAtValue)) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    final DateTime? parsedExpiresAt = DateTime.tryParse(expiresAtValue);
    if (parsedExpiresAt == null) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }
    final DateTime normalizedNow = (now ?? DateTime.now()).toUtc();
    final DateTime normalizedExpiresAt = parsedExpiresAt.toUtc();
    if (!normalizedExpiresAt.isAfter(normalizedNow)) {
      throw const ImCredentialException(ImCredentialFailure.expired);
    }
    if (!isExpiryConsistent(
      expiresAt: normalizedExpiresAt,
      ttlSeconds: ttlSecondsValue,
      now: normalizedNow,
    )) {
      throw const ImCredentialException(ImCredentialFailure.invalidValue);
    }

    return ImSessionCredentials(
      provider: providerValue,
      sdkAppId: sdkAppIdValue,
      userId: userIdValue,
      userSig: userSigValue,
      expiresAt: normalizedExpiresAt,
      ttlSeconds: ttlSecondsValue,
      imStatus: imStatusValue,
      systemAccount: systemAccountValue,
    );
  }

  /// A parser alias useful at repository boundaries and in contract tests.
  static ImSessionCredentials parse(Object? raw, {DateTime? now}) =>
      ImSessionCredentials.fromBackendData(raw, now: now);

  bool isExpired([DateTime? now]) =>
      !expiresAt.isAfter((now ?? DateTime.now()).toUtc());

  bool isWithinRenewalWindow([DateTime? now]) =>
      !expiresAt.isAfter((now ?? DateTime.now()).toUtc().add(renewalThreshold));

  bool get isReady => imStatus == readyStatus && !isExpired();

  /// Deterministic mapping required by the first-party IM contract.  The
  /// platform user id remains the source of truth; callers cannot choose a
  /// different provider identity.
  static String userIdForPlatformUserId(int userId) {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId', '必须为正整数');
    }
    final String mapped = 'u-$userId';
    if (!isCanonicalUserId(mapped)) {
      throw ArgumentError.value(userId, 'userId', '超出 IM 用户标识长度');
    }
    return mapped;
  }

  static bool isCanonicalUserId(String value) =>
      canonicalUserIdPattern.hasMatch(value);

  static bool isValidSystemAccount(String value) =>
      systemAccountPattern.hasMatch(value);

  static bool isValidTtlSeconds(int value) =>
      value >= minimumTtlSeconds && value <= maximumTtlSeconds;

  static bool isValidUserSig(String value) {
    if (value.length < minimumUserSigLength ||
        value.length > maximumUserSigLength ||
        value.trim() != value) {
      return false;
    }
    return userSigPattern.hasMatch(value);
  }

  static bool isExpiryConsistent({
    required DateTime expiresAt,
    required int ttlSeconds,
    required DateTime now,
  }) {
    if (!isValidTtlSeconds(ttlSeconds)) {
      return false;
    }
    final DateTime expected = now.toUtc().add(Duration(seconds: ttlSeconds));
    final Duration delta = expiresAt.toUtc().difference(expected);
    return delta >= -expiryClockTolerance && delta <= expiryClockTolerance;
  }

  /// Safe diagnostics only.  None of the identity or signing material is
  /// returned, including the SDK app id.
  Map<String, Object?> toRedactedJson() => <String, Object?>{
    'provider': provider,
    'imStatus': imStatus,
    'ttlSeconds': ttlSeconds,
    'hasUserId': userId.isNotEmpty,
    'hasUserSig': userSig.isNotEmpty,
    'expired': isExpired(),
  };

  @override
  String toString() => 'ImSessionCredentials(${toRedactedJson()})';

  static bool _looksLikeIso8601(String value) {
    // Require a timestamp and an explicit timezone.  Parsing a local-time
    // string would make an expiry depend on the device's timezone.
    return value.contains('T') &&
        RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  }
}

enum ImCredentialFailure {
  invalidShape,
  unknownField,
  missingField,
  invalidProvider,
  invalidStatus,
  invalidValue,
  expired,
  userMismatch,
}

class ImCredentialException implements Exception {
  const ImCredentialException(this.failure);

  final ImCredentialFailure failure;

  String get message => switch (failure) {
    ImCredentialFailure.invalidShape => 'IM 凭证响应结构无效',
    ImCredentialFailure.unknownField => 'IM 凭证响应包含不支持的字段',
    ImCredentialFailure.missingField => 'IM 凭证响应字段不完整',
    ImCredentialFailure.invalidProvider => 'IM 凭证供应商不受支持',
    ImCredentialFailure.invalidStatus => 'IM 凭证状态不可用',
    ImCredentialFailure.invalidValue => 'IM 凭证字段值无效',
    ImCredentialFailure.expired => 'IM 凭证已过期',
    ImCredentialFailure.userMismatch => 'IM 凭证用户与登录会话不匹配',
  };

  @override
  String toString() => 'ImCredentialException(${failure.name})';
}

// Compatibility aliases keep the provider-neutral model easy to discover for
// later realtime workers without creating a second credential representation.
typedef ImCredentials = ImSessionCredentials;
typedef TencentImCredentials = ImSessionCredentials;
typedef ImSessionCredentialException = ImCredentialException;
