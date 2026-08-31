/// Strict, provider-neutral representation of the server-authorized
/// AVChatRoom join result.
///
/// This model intentionally contains no room-scoped UserSig. Tencent IM is
/// account-scoped in this client: the already authenticated
/// [ImSessionCredentials] supplies the only login material. The room enter
/// response authorizes a group and a first-party session handle; it does not
/// authorize a second provider identity.
class TencentImRealtimeGroup {
  const TencentImRealtimeGroup({
    required this.provider,
    required this.type,
    required this.groupId,
    required this.groupType,
    required this.status,
    required this.messageMode,
    required this.contentAuthority,
  });

  static const String expectedProvider = 'tencent-im';
  static const String expectedType = 'AVCHATROOM';
  static const String expectedGroupType = 'AVChatRoom';
  static const String readyStatus = 'READY';
  static const String pendingStatus = 'PENDING';
  static const String expectedMessageMode = 'METADATA_HINT';
  static const String expectedContentAuthority = 'HTTP';
  static const Set<String> allowedFields = <String>{
    'provider',
    'type',
    'groupId',
    'groupType',
    'status',
    'messageMode',
    'contentAuthority',
  };

  final String provider;
  final String type;
  final String groupId;
  final String groupType;
  final String status;
  final String messageMode;
  final String contentAuthority;
}

/// A successful first-party room enter result required before joining a
/// Tencent AVChatRoom.
class TencentImAvChatRoomSession {
  const TencentImAvChatRoomSession({
    required this.roomId,
    required this.sessionId,
    required this.version,
    required this.realtimeGroup,
  });

  static const Set<String> allowedFields = <String>{
    'roomId',
    'sessionId',
    'version',
    'realtimeGroup',
  };
  static const int maximumIdentifierLength = 128;
  static const int maximumVersion = 0x7fffffffffffffff;
  static final RegExp identifierPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
  );

  final String roomId;
  final String sessionId;

  /// Server-authoritative room version, retained as a signed 64-bit Dart int.
  final int version;
  final TencentImRealtimeGroup realtimeGroup;

  String get groupId => realtimeGroup.groupId;

  String get groupType => realtimeGroup.groupType;

  String get groupStatus => realtimeGroup.status;

  bool get isReady =>
      realtimeGroup.status == TencentImRealtimeGroup.readyStatus;

  /// V8 does not expose a client-visible expiry. A non-empty, server-issued
  /// session ID is the active lease handle; navigation/generation fences
  /// invalidate it on leave or switch. The optional clock is retained for
  /// compatibility with the pre-V8 draft shape.
  bool hasActiveLease([DateTime? _]) => sessionId.isNotEmpty;

  /// Parses the `data` member of the authenticated room-enter response.
  ///
  /// The enter response can carry ordinary room snapshot fields. This parser
  /// extracts only the exact room/session/version/realtimeGroup security
  /// projection and rejects unknown fields inside the provider-owned group
  /// object. Unknown aliases, nested UserSig fields, omitted group status,
  /// non-READY groups, and mismatched provider/group type all fail closed.
  factory TencentImAvChatRoomSession.fromBackendData(
    Object? raw, {
    DateTime? now,
    String? expectedRoomId,
    bool allowPending = false,
  }) {
    // `now` is intentionally accepted for compatibility with the earlier
    // draft contract. V8 has no client-visible expiry; sessionId plus the
    // coordinator generation/navigation fence is the active-room lease.
    final Map<String, Object?> source = _strictMap(
      raw,
      failure: TencentImRoomCredentialFailure.invalidShape,
    );
    final String roomId = _requiredIdentifier(source, 'roomId');
    final String sessionId = _requiredIdentifier(source, 'sessionId');
    final int version = _requiredVersion(source, 'version');
    if (expectedRoomId != null && expectedRoomId.trim() != roomId) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.roomMismatch,
      );
    }
    final Map<String, Object?> groupSource = _strictMap(
      source['realtimeGroup'],
      failure: TencentImRoomCredentialFailure.invalidShape,
    );
    _requireExactFields(
      groupSource,
      TencentImRealtimeGroup.allowedFields,
      failure: TencentImRoomCredentialFailure.unknownField,
    );
    final String provider = _requiredString(groupSource, 'provider');
    final String type = _requiredString(groupSource, 'type');
    final String groupId = _requiredGroupId(groupSource, 'groupId');
    final String groupType = _requiredString(groupSource, 'groupType');
    final String status = _requiredString(groupSource, 'status');
    final String messageMode = _requiredString(groupSource, 'messageMode');
    final String contentAuthority = _requiredString(
      groupSource,
      'contentAuthority',
    );
    if (provider != TencentImRealtimeGroup.expectedProvider) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidProvider,
      );
    }
    if (groupType != TencentImRealtimeGroup.expectedGroupType) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidGroupType,
      );
    }
    if (status != TencentImRealtimeGroup.readyStatus &&
        !(allowPending && status == TencentImRealtimeGroup.pendingStatus)) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.groupNotReady,
      );
    }
    if (type != TencentImRealtimeGroup.expectedType) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidGroupType,
      );
    }
    if (messageMode != TencentImRealtimeGroup.expectedMessageMode ||
        contentAuthority != TencentImRealtimeGroup.expectedContentAuthority) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidMessageAuthority,
      );
    }

    return TencentImAvChatRoomSession(
      roomId: roomId,
      sessionId: sessionId,
      version: version,
      realtimeGroup: TencentImRealtimeGroup(
        provider: provider,
        type: type,
        groupId: groupId,
        groupType: groupType,
        status: status,
        messageMode: messageMode,
        contentAuthority: contentAuthority,
      ),
    );
  }

  static TencentImAvChatRoomSession parse(
    Object? raw, {
    DateTime? now,
    String? expectedRoomId,
  }) => TencentImAvChatRoomSession.fromBackendData(
    raw,
    now: now,
    expectedRoomId: expectedRoomId,
  );

  /// Reads the optional provider projection from a full room snapshot. A
  /// snapshot without `realtimeGroup` is the normal provider-blocked/HTTP-only
  /// response and therefore returns null. A present but malformed projection
  /// is also fail-closed to HTTP-only; callers that need a hard contract error
  /// should use [fromBackendData] directly.
  static TencentImAvChatRoomSession? tryParseFromRoomData(
    Object? raw, {
    String? expectedRoomId,
  }) {
    if (raw is! Map || !raw.containsKey('realtimeGroup')) {
      return null;
    }
    try {
      return TencentImAvChatRoomSession.fromBackendData(
        raw,
        expectedRoomId: expectedRoomId,
      );
    } on TencentImRoomCredentialException {
      return null;
    }
  }

  /// Parses the same exact projection while retaining the server's transient
  /// `PENDING` state. Callers must still gate provider join on [isReady]. This
  /// enables a bounded, background readiness poll after HTTP room entry.
  static TencentImAvChatRoomSession? tryParseRoomReadinessFromRoomData(
    Object? raw, {
    String? expectedRoomId,
  }) {
    if (raw is! Map || !raw.containsKey('realtimeGroup')) {
      return null;
    }
    try {
      return TencentImAvChatRoomSession.fromBackendData(
        raw,
        expectedRoomId: expectedRoomId,
        allowPending: true,
      );
    } on TencentImRoomCredentialException {
      return null;
    }
  }

  /// Safe diagnostics omit the session and provider group identifiers. The
  /// room layer can log its own opaque request id separately if needed.
  Map<String, Object?> toRedactedJson() => <String, Object?>{
    'hasRoomId': roomId.isNotEmpty,
    'hasSessionId': sessionId.isNotEmpty,
    'version': version,
    'provider': realtimeGroup.provider,
    'type': realtimeGroup.type,
    'groupType': realtimeGroup.groupType,
    'groupStatus': realtimeGroup.status,
    'messageMode': realtimeGroup.messageMode,
    'contentAuthority': realtimeGroup.contentAuthority,
    'hasGroupId': realtimeGroup.groupId.isNotEmpty,
  };

  @override
  String toString() => 'TencentImAvChatRoomSession(${toRedactedJson()})';

  static Map<String, Object?> _strictMap(
    Object? raw, {
    required TencentImRoomCredentialFailure failure,
  }) {
    if (raw is! Map) {
      throw TencentImRoomCredentialException(failure);
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      if (entry.key is! String) {
        throw TencentImRoomCredentialException(failure);
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static void _requireExactFields(
    Map<String, Object?> source,
    Set<String> allowed, {
    required TencentImRoomCredentialFailure failure,
  }) {
    if (source.length != allowed.length ||
        source.keys.any((String key) => !allowed.contains(key))) {
      throw TencentImRoomCredentialException(failure);
    }
  }

  static String _requiredIdentifier(Map<String, Object?> source, String key) {
    final Object? raw = source[key];
    if (raw is! String ||
        raw.length > maximumIdentifierLength ||
        !identifierPattern.hasMatch(raw)) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidValue,
      );
    }
    return raw;
  }

  static int _requiredVersion(Map<String, Object?> source, String key) {
    final Object? raw = source[key];
    // Room optimistic-lock versions start at zero in V8. Unlike a message
    // eventVersion, zero is a valid room snapshot version; the signed 64-bit
    // upper bound is still enforced exactly.
    if (raw is! int || raw < 0 || raw > maximumVersion) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidVersion,
      );
    }
    return raw;
  }

  static String _requiredString(Map<String, Object?> source, String key) {
    final Object? raw = source[key];
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidValue,
      );
    }
    return raw;
  }

  static String _requiredGroupId(Map<String, Object?> source, String key) {
    final String value = _requiredString(source, key);
    if (value.length > 48 || value.startsWith('@TGS#')) {
      throw const TencentImRoomCredentialException(
        TencentImRoomCredentialFailure.invalidGroupId,
      );
    }
    for (final int codeUnit in value.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) {
        throw const TencentImRoomCredentialException(
          TencentImRoomCredentialFailure.invalidGroupId,
        );
      }
    }
    return value;
  }
}

enum TencentImRoomCredentialFailure {
  invalidShape,
  unknownField,
  invalidValue,
  invalidProvider,
  invalidGroupType,
  invalidGroupId,
  groupNotReady,
  invalidVersion,
  invalidMessageAuthority,
  roomMismatch,
}

class TencentImRoomCredentialException implements Exception {
  const TencentImRoomCredentialException(this.failure);

  final TencentImRoomCredentialFailure failure;

  String get message => switch (failure) {
    TencentImRoomCredentialFailure.invalidShape => '房间实时群组响应结构无效',
    TencentImRoomCredentialFailure.unknownField => '房间实时群组响应包含不支持的字段',
    TencentImRoomCredentialFailure.invalidValue => '房间实时群组字段值无效',
    TencentImRoomCredentialFailure.invalidProvider => '房间实时群组供应商不受支持',
    TencentImRoomCredentialFailure.invalidGroupType => '房间实时群组类型不受支持',
    TencentImRoomCredentialFailure.invalidGroupId => '房间实时群组 ID 无效',
    TencentImRoomCredentialFailure.groupNotReady => '房间实时群组尚未就绪',
    TencentImRoomCredentialFailure.invalidVersion => '房间版本无效',
    TencentImRoomCredentialFailure.invalidMessageAuthority => '房间实时群组消息权威范围无效',
    TencentImRoomCredentialFailure.roomMismatch => '房间实时群组与请求房间不一致',
  };

  @override
  String toString() => 'TencentImRoomCredentialException(${failure.name})';
}

// Naming aliases make the strict contract discoverable without creating a
// second model or accepting a second wire shape.
typedef ImAvChatRoomSession = TencentImAvChatRoomSession;
typedef ImRoomSession = TencentImAvChatRoomSession;
typedef TencentImRoomSession = TencentImAvChatRoomSession;
typedef ImRealtimeGroup = TencentImRealtimeGroup;
typedef ImRoomCredentialException = TencentImRoomCredentialException;

/// Optional source capability implemented by HTTP room repositories. It
/// keeps the legacy [RoomRepository] return type stable while allowing the
/// room controller to hand the exact provider projection to the IM
/// coordinator after a successful enter/reconnect response.
abstract interface class TencentImRoomSessionSource {
  TencentImAvChatRoomSession? get lastTencentImRoomSession;

  /// Atomically consumes the latest provider projection for one room. A room
  /// keyed read prevents an older controller awaiting its own HTTP enter from
  /// accidentally binding a newer room's session.
  TencentImAvChatRoomSession? takeTencentImRoomSession(String roomId) {
    final TencentImAvChatRoomSession? session = lastTencentImRoomSession;
    return session?.roomId == roomId.trim() ? session : null;
  }
}

/// Optional first-party, authenticated readiness projection for an already
/// entered room.  A successful room enter may return `realtimeGroup.status`
/// as `PENDING`; the room controller can poll this read-only capability in
/// the background and only hand a subsequent `READY` projection to the
/// provider coordinator.  The capability is intentionally separate from
/// [TencentImRoomSessionSource] so older repositories remain HTTP-only.
abstract interface class TencentImRoomReadinessSource {
  Future<TencentImAvChatRoomSession?> fetchTencentImRoomReadiness(
    String roomId,
  );
}
