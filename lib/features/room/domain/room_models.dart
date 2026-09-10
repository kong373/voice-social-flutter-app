import 'package:voice_social_app/features/commerce/domain/gift_coin_precision.dart';
import '../../commerce/display/domain/equipped_decoration.dart';
import '../../account/domain/user_avatar_descriptor.dart';
import '../../../core/media/media_models.dart';
import 'package:voice_social_app/features/room/domain/room_audio_mute_state.dart';
export 'package:voice_social_app/features/room/domain/room_audio_mute_state.dart';

enum RoomRole { guest, listener, speaker, moderator, owner, platformModerator }

enum RoomSessionStatus {
  idle,
  joining,
  joined,
  reconnecting,
  leaving,
  left,
  closed,
  kicked,
  failed,
}

enum MicSeatState { available, locked, mutedAvailable, occupied, occupiedMuted }

enum RtcSolution { agora, zego, unknown }

/// Agora's native numeric uid is carried through the backend's signed Java
/// integer user-id contract. A server that adopts account-string tokens can
/// widen this in a future provider-specific adapter without changing the
/// provider-neutral model.
const int rtcUidMax = 0x7FFFFFFF;

enum RoomTransportMode { interactive, snapshotOnly }

enum RoomEntrySource {
  home(0),
  follow(1),
  search(2),
  loginRestore(3),
  share(4),
  campaign(5),
  guild(6),
  registrationRecommendation(7),
  groupMembers(8),
  friends(9),
  discoveryPost(10),
  leaderboard(11),
  guildRoomList(12),
  hotRanking(13),
  giftContext(14),
  publicProfile(15),
  message(19);

  const RoomEntrySource(this.backendCode);

  final int backendCode;
}

class RtcCredentials {
  const RtcCredentials({
    this.solution = RtcSolution.unknown,
    this.provider = '',
    this.appId = '',
    required this.token,
    required this.channelId,
    int? uid,
    int? userId,
    this.role = '',
    this.expiresAt,
    Duration? ttl,
    int? ttlSeconds,
  }) : uid = uid ?? userId ?? 0,
       _ttl = ttl,
       _ttlSeconds = ttlSeconds;

  final RtcSolution solution;

  /// Provider name returned by the first-party token endpoint.
  ///
  /// This is a public routing value (currently `agora`), not a provider
  /// credential. Provider signing secrets must never be present in this
  /// model.
  final String provider;

  /// Public Agora App ID. The backend supplies this value at runtime; it is
  /// intentionally not a build-time define or a source constant.
  final String appId;
  final String token;
  final String channelId;

  /// Numeric provider user ID. The current backend token contract uses the
  /// positive signed Java integer range even though the native SDK accepts a
  /// wider unsigned value.
  final int uid;

  /// Backend role (for example `audience` or `broadcaster`).
  final String role;

  /// Absolute token expiry, when supplied by the backend.
  final DateTime? expiresAt;

  /// Token lifetime. The backend's canonical field is `ttlSeconds`; a
  /// Duration is retained as a convenience for callers that already use
  /// Dart time values.
  final Duration? _ttl;
  final int? _ttlSeconds;

  Duration? get ttl {
    final int? seconds = _ttlSeconds;
    return _ttl ?? (seconds == null ? null : Duration(seconds: seconds));
  }

  int? get ttlSeconds => _ttlSeconds ?? _ttl?.inSeconds;

  /// Compatibility alias used by the existing room domain/controller code.
  int get userId => uid;

  /// The provider value normalized for old local/mock fixtures that only set
  /// the historical [solution] enum.
  String get effectiveProvider {
    final String normalized = provider.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return switch (solution) {
      RtcSolution.agora => 'agora',
      RtcSolution.zego => 'zego',
      RtcSolution.unknown => '',
    };
  }

  bool get hasUsablePublicCredentials =>
      provider.trim().toLowerCase() == 'agora' &&
      appId.trim().isNotEmpty &&
      token.trim().isNotEmpty &&
      channelId.trim().isNotEmpty &&
      uid > 0 &&
      uid <= rtcUidMax &&
      role.trim().isNotEmpty &&
      (expiresAt != null || (ttlSeconds ?? 0) > 0);

  /// Safe diagnostics representation. Ephemeral token material is omitted.
  Map<String, Object?> toRedactedJson() => <String, Object?>{
    'provider': effectiveProvider,
    'appId': appId,
    'channelId': channelId,
    'uid': uid,
    'role': role,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'ttlSeconds': ttlSeconds,
  };
}

class MicSeat {
  const MicSeat({
    required this.number,
    required this.backendIndex,
    required this.state,
    this.userId,
    this.userName,
    this.avatarUrl,
    this.isSpeaking = false,
    this.isOnline = true,
    this.userRole = RoomRole.listener,
    this.audioMute,
    this.occupantJoinedAt,
    this.equippedDecorations = const [],
    this.avatar,
  });

  final int number;
  final int backendIndex;
  final MicSeatState state;
  final int? userId;
  final String? userName;
  final String? avatarUrl;
  final bool isSpeaking;

  /// Server seat presence; occupancy survives a disconnected lease.
  final bool isOnline;
  final RoomRole userRole;
  final RoomAudioMuteState? audioMute;
  final String? occupantJoinedAt;
  final List<EquippedDecoration> equippedDecorations;
  final UserAvatarDescriptor? avatar;

  bool get isAvailable => state == MicSeatState.available;

  bool get isSpecial => number == 1;
  bool canUse(RoomRole role) =>
      !isSpecial || role == RoomRole.owner || role == RoomRole.moderator;

  bool get isOccupied =>
      state == MicSeatState.occupied || state == MicSeatState.occupiedMuted;

  MicSeat copyWith({
    int? backendIndex,
    MicSeatState? state,
    int? userId,
    bool clearUserId = false,
    String? userName,
    bool clearUserName = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? isSpeaking,
    bool? isOnline,
    RoomRole? userRole,
    RoomAudioMuteState? audioMute,
    String? occupantJoinedAt,
    List<EquippedDecoration>? equippedDecorations,
    UserAvatarDescriptor? avatar,
  }) {
    return MicSeat(
      number: number,
      backendIndex: backendIndex ?? this.backendIndex,
      state: state ?? this.state,
      userId: clearUserId ? null : userId ?? this.userId,
      userName: clearUserName ? null : userName ?? this.userName,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      avatar:
          clearUserId ||
              !(isOnline ?? this.isOnline) ||
              !const [
                MicSeatState.occupied,
                MicSeatState.occupiedMuted,
              ].contains(state ?? this.state)
          ? null
          : avatar ??
                ((userId != null && userId != this.userId)
                    ? null
                    : this.avatar),
      isSpeaking:
          (isOnline ?? this.isOnline) && (isSpeaking ?? this.isSpeaking),
      isOnline: isOnline ?? this.isOnline,
      userRole: userRole ?? this.userRole,
      audioMute:
          audioMute ??
          (clearUserId || (userId != null && userId != this.userId)
              ? null
              : this.audioMute),
      occupantJoinedAt:
          occupantJoinedAt ??
          (clearUserId || (userId != null && userId != this.userId)
              ? null
              : this.occupantJoinedAt),
      equippedDecorations:
          clearUserId ||
              !(isOnline ?? this.isOnline) ||
              !const [
                MicSeatState.occupied,
                MicSeatState.occupiedMuted,
              ].contains(state ?? this.state)
          ? const []
          : equippedDecorations ??
                ((userId != null && userId != this.userId)
                    ? const []
                    : this.equippedDecorations),
    );
  }
}

class RoomMessage {
  const RoomMessage({
    required this.sender,
    required this.content,
    this.roomId,
    this.messageId,
    this.senderId,
    this.type,
    this.isSystem = false,
    this.createdAt,
    this.deliveryMode,
    this.realtimeStatus,
    this.eventVersion,
  });

  final String? roomId;
  final String? messageId;
  final int? senderId;
  final String sender;
  final String? type;
  final String content;
  final bool isSystem;
  final DateTime? createdAt;
  final String? deliveryMode;
  final String? realtimeStatus;

  /// Server-issued signed 64-bit ordering for metadata-only realtime hints.
  /// The room UI never treats it as provider authorization.
  final int? eventVersion;
}

/// Authenticated viewer authority returned by the first-party room read API.
class RoomAuthorityProjection {
  const RoomAuthorityProjection({
    required this.snapshot,
    required this.viewerUserId,
    required this.memberActive,
    required this.roomMuted,
    required this.version,
  });

  final RoomSnapshot snapshot;
  final int viewerUserId;
  final bool memberActive;
  final bool roomMuted;
  final int version;
}

/// First-party membership lease. Provider connectivity is not lease evidence.
class RoomSessionLease {
  const RoomSessionLease({
    required this.sessionId,
    required this.sequence,
    required this.serverTime,
    required this.expiresAt,
    required this.heartbeatIntervalSeconds,
    required this.leaseDurationSeconds,
  });

  final String sessionId;
  final int sequence;
  final DateTime serverTime;
  final DateTime expiresAt;
  final int heartbeatIntervalSeconds;
  final int leaseDurationSeconds;

  Duration get remaining => expiresAt.difference(serverTime);
  bool get isValid =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(sessionId) &&
      sequence >= 0 &&
      sequence <= 9007199254740991 &&
      serverTime.isUtc &&
      expiresAt.isUtc &&
      heartbeatIntervalSeconds == 20 &&
      leaseDurationSeconds == 90 &&
      remaining >= Duration.zero &&
      remaining <= const Duration(seconds: 90);
}

class RoomSnapshot {
  const RoomSnapshot({
    required this.roomId,
    required this.roomCode,
    required this.title,
    required this.topic,
    required this.ownerId,
    required this.role,
    required this.seats,
    required this.rtc,
    required this.publicScreenEnabled,
    required this.pictureMessagesAllowed,
    required this.autoLockMic,
    required this.giftCatalogAvailable,
    required this.giftBalance,
    this.accessMode = '',
    this.transportMode = RoomTransportMode.interactive,
    this.onlineCount,
    this.coverUrl,
    this.backgroundUrl,
    this.coverMedia,
    this.backgroundMedia,
    this.sessionId,
    this.roomLease,
    this.ownerClosedAccess = false,
    this.platformStaff = false,
    this.closedRoomAccess = false,
    this.canControlRoomLifecycle = false,
    this.version,
  });

  final String roomId;
  final String roomCode;
  final String title;
  final String topic;
  final int ownerId;
  final RoomRole role;
  final List<MicSeat> seats;
  final RtcCredentials rtc;
  final RoomTransportMode transportMode;
  final bool publicScreenEnabled;
  final bool pictureMessagesAllowed;
  final bool autoLockMic;
  final bool giftCatalogAvailable;
  final int? giftBalance;

  /// Entry configuration only; microphone approval is determined by role.
  final String accessMode;

  /// Owner management access without active membership or a session lease.
  final bool ownerClosedAccess;
  final bool platformStaff;
  final bool closedRoomAccess;
  final bool canControlRoomLifecycle;
  final int? version;
  bool get isClosedManagementView => ownerClosedAccess || closedRoomAccess;
  final int? onlineCount;
  final String? coverUrl;
  final String? backgroundUrl;
  final MediaReference? coverMedia;
  final MediaReference? backgroundMedia;

  /// First-party membership identifier, never an RTC or authentication token.
  final String? sessionId;
  final RoomSessionLease? roomLease;

  bool get isSnapshotOnly => transportMode == RoomTransportMode.snapshotOnly;

  RoomSnapshot copyWith({
    String? title,
    String? topic,
    RoomRole? role,
    List<MicSeat>? seats,
    RtcCredentials? rtc,
    RoomTransportMode? transportMode,
    bool? publicScreenEnabled,
    bool? pictureMessagesAllowed,
    bool? autoLockMic,
    bool? giftCatalogAvailable,
    int? giftBalance,
    String? accessMode,
    int? onlineCount,
    String? sessionId,
    RoomSessionLease? roomLease,
  }) {
    return RoomSnapshot(
      roomId: roomId,
      ownerClosedAccess: ownerClosedAccess,
      platformStaff: platformStaff,
      closedRoomAccess: closedRoomAccess,
      canControlRoomLifecycle: canControlRoomLifecycle,
      version: version,
      sessionId: sessionId ?? this.sessionId,
      roomLease: roomLease ?? this.roomLease,
      roomCode: roomCode,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      ownerId: ownerId,
      role: role ?? this.role,
      seats: seats ?? this.seats,
      rtc: rtc ?? this.rtc,
      transportMode: transportMode ?? this.transportMode,
      publicScreenEnabled: publicScreenEnabled ?? this.publicScreenEnabled,
      pictureMessagesAllowed:
          pictureMessagesAllowed ?? this.pictureMessagesAllowed,
      autoLockMic: autoLockMic ?? this.autoLockMic,
      giftCatalogAvailable: giftCatalogAvailable ?? this.giftCatalogAvailable,
      giftBalance: giftBalance ?? this.giftBalance,
      accessMode: accessMode ?? this.accessMode,
      onlineCount: onlineCount ?? this.onlineCount,
      coverUrl: coverUrl ?? this.coverUrl,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      coverMedia: coverMedia,
      backgroundMedia: backgroundMedia,
    );
  }
}

class GiftReceipt {
  const GiftReceipt({
    required this.success,
    required this.remainingBalance,
    this.transferId,
    this.roomId,
    this.senderUserId,
    this.receiverUserId,
    this.giftId,
    this.giftName,
    this.quantity,
    this.source,
    this.deliveryMode,
    this.providerInvocation,
    this.providerStatus,
    this.status,
    this.requestId,
    this.creatorIncomeMinor,
    this.creatorIncomeCurrency,
    this.coinPrecision,
    this.charmValue,
    this.reconciled,
    this.createdAt,
  });

  final bool success;
  final int? remainingBalance;
  final String? transferId;
  final String? roomId;
  final int? senderUserId;
  final int? receiverUserId;
  final String? giftId;
  final String? giftName;
  final int? quantity;
  final String? source;
  final String? deliveryMode;
  final bool? providerInvocation;
  final String? providerStatus;
  final String? status;
  final String? requestId;
  final int? creatorIncomeMinor;

  /// Null on historical receipts is unknown, never presumed to be cash.
  final String? creatorIncomeCurrency;
  final GiftCoinBalance? coinPrecision;
  final int? charmValue;
  final bool? reconciled;
  final DateTime? createdAt;
}
