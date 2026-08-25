import 'package:voice_social_app/features/room/domain/room_models.dart';

enum RoomMemberPresence { onMic, listener }

enum MicCoordinationMode { direct, approval, unavailable }

/// The persisted first-party microphone queue distinguishes a member's
/// REQUEST from a manager-created INVITE. Keep [accepted] as a source
/// compatible legacy value for mocks; live APPROVED responses map to
/// [approved].
enum MicRequestType { request, invite }

enum MicRequestStatus {
  pending,
  approved,
  accepted,
  rejected,
  expired,
  cancelled,
}

/// Action available to the authenticated target after the server returned a
/// queue record. Management code must still gate REQUEST resolution by role;
/// an INVITE is always accepted/rejected by its subject.
enum MicRequestTargetAction { none, cancel, resolve, accept, reject }

class RoomMember {
  const RoomMember({
    required this.userId,
    required this.name,
    required this.role,
    required this.presence,
    this.avatarUrl,
    this.seatNumber,
    this.isMuted = false,
    this.wealthLevel = 0,
    this.charmLevel = 0,
  });

  final int userId;
  final String name;
  final String? avatarUrl;
  final RoomRole role;
  final RoomMemberPresence presence;
  final int? seatNumber;
  final bool isMuted;
  final int wealthLevel;
  final int charmLevel;

  bool get isOnMic => presence == RoomMemberPresence.onMic;
  bool get isManager =>
      role == RoomRole.owner ||
      role == RoomRole.moderator ||
      role == RoomRole.platformModerator;

  RoomMember copyWith({
    RoomRole? role,
    RoomMemberPresence? presence,
    int? seatNumber,
    bool clearSeatNumber = false,
    bool? isMuted,
  }) {
    return RoomMember(
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
      role: role ?? this.role,
      presence: presence ?? this.presence,
      seatNumber: clearSeatNumber ? null : seatNumber ?? this.seatNumber,
      isMuted: isMuted ?? this.isMuted,
      wealthLevel: wealthLevel,
      charmLevel: charmLevel,
    );
  }
}

class RoomMemberPage {
  const RoomMemberPage({
    required this.items,
    required this.page,
    required this.total,
    required this.pages,
  });

  final List<RoomMember> items;
  final int page;
  final int total;
  final int pages;

  bool get hasMore => page < pages;
}

class RoomTopic {
  const RoomTopic({required this.title, required this.content, this.version});

  final String title;
  final String content;
  // Null remains source-compatible with old mocks. The live backend fills it
  // from the topic snapshot and rejects writes that do not carry it.
  final int? version;
}

class MicAccessRequest {
  const MicAccessRequest({
    required this.id,
    required this.member,
    required this.seatNumber,
    required this.status,
    required this.createdAt,
    this.roomId,
    this.type = MicRequestType.request,
    this.requestedByUserId,
    this.subjectUserId,
    this.expiresAt,
    this.resolvedAt,
    this.resolvedByUserId,
    this.targetAction = MicRequestTargetAction.none,
  });

  final String id;
  final String? roomId;
  final RoomMember member;
  final int seatNumber;
  final MicRequestStatus status;
  final DateTime createdAt;
  final MicRequestType type;
  final int? requestedByUserId;
  final int? subjectUserId;
  final DateTime? expiresAt;
  final DateTime? resolvedAt;
  final int? resolvedByUserId;
  final MicRequestTargetAction targetAction;

  /// Compatibility aliases used by older presentation code and fixtures.
  MicRequestType get requestType => type;
  String get requestTypeValue =>
      type == MicRequestType.invite ? 'INVITE' : 'REQUEST';
  String get requestId => id;
  bool get isRequest => type == MicRequestType.request;
  bool get isInvite => type == MicRequestType.invite;
  bool get isPending => status == MicRequestStatus.pending;
  bool get isApproved =>
      status == MicRequestStatus.approved ||
      status == MicRequestStatus.accepted;
  bool get canCancel => targetAction == MicRequestTargetAction.cancel;
  bool get canAccept => targetAction == MicRequestTargetAction.accept;
  bool get canReject => targetAction == MicRequestTargetAction.reject;
}

/// A persisted request to enter an approval-only room.
///
/// This is intentionally separate from [MicAccessRequest].  Approval-room
/// membership is a first-party HTTP workflow, while microphone coordination
/// is a different room capability and may remain direct or vendor-blocked.
enum RoomJoinRequestStatus { pending, cancelled, approved, rejected }

class RoomJoinRequest {
  const RoomJoinRequest({
    required this.id,
    required this.member,
    required this.status,
    this.message,
    this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final RoomMember member;
  final RoomJoinRequestStatus status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == RoomJoinRequestStatus.pending;
}

/// The applicant-facing, privacy-preserving view of one approval-room
/// request.  Unlike [RoomJoinRequest], this model intentionally contains no
/// applicant identity fields: the backend only returns the authenticated
/// user's own request.
class RoomJoinRequestApplicantStatus {
  const RoomJoinRequestApplicantStatus({
    required this.roomId,
    required this.joinRequestId,
    required this.status,
    required this.roomState,
    required this.banned,
    required this.canCancel,
    this.message,
    this.createdAt,
    this.resolvedAt,
  });

  final String roomId;
  final String joinRequestId;
  final RoomJoinRequestStatus status;
  final String roomState;
  final bool banned;
  final bool canCancel;
  final String? message;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == RoomJoinRequestStatus.pending;
}

/// The authoritative result of the applicant cancel mutation.  The cancel
/// endpoint deliberately returns only mutation fields; callers should read
/// [RoomJoinRequestApplicantStatus] afterwards for the full state.
class RoomJoinRequestCancellation {
  const RoomJoinRequestCancellation({
    required this.roomId,
    required this.joinRequestId,
    required this.status,
    required this.cancelled,
    required this.alreadyCancelled,
  });

  final String roomId;
  final String joinRequestId;
  final RoomJoinRequestStatus status;
  final bool cancelled;
  final bool alreadyCancelled;
}

class RoomJoinRequestPage {
  const RoomJoinRequestPage({
    required this.items,
    required this.page,
    required this.total,
    required this.pages,
  });

  final List<RoomJoinRequest> items;
  final int page;
  final int total;
  final int pages;

  bool get hasMore => page < pages;
}

class RoomBannedUser {
  const RoomBannedUser({
    required this.member,
    this.reason,
    this.bannedAt,
    this.expiresAt,
  });

  final RoomMember member;
  final String? reason;
  final DateTime? bannedAt;
  final DateTime? expiresAt;
}

class RoomBannedUserPage {
  const RoomBannedUserPage({
    required this.items,
    required this.page,
    required this.total,
    required this.pages,
  });

  final List<RoomBannedUser> items;
  final int page;
  final int total;
  final int pages;

  bool get hasMore => page < pages;
}

enum RoomAudioRoute { speaker, earpiece, bluetooth, wiredHeadset }

enum RoomConnectionGrade { excellent, good, fair, poor, unknown }

class RoomAudioSnapshot {
  const RoomAudioSnapshot({
    required this.configured,
    required this.route,
    required this.availableRoutes,
    required this.microphonePermissionGranted,
    required this.microphoneEnabled,
    required this.rtcConnected,
    required this.realtimeConnected,
    required this.grade,
    required this.latencyMs,
    required this.packetLossPercent,
    required this.updatedAt,
  });

  final bool configured;
  final RoomAudioRoute route;
  final Set<RoomAudioRoute> availableRoutes;
  final bool microphonePermissionGranted;
  final bool microphoneEnabled;
  final bool rtcConnected;
  final bool realtimeConnected;
  final RoomConnectionGrade grade;
  final int? latencyMs;
  final double? packetLossPercent;
  final DateTime updatedAt;

  RoomAudioSnapshot copyWith({
    RoomAudioRoute? route,
    bool? microphonePermissionGranted,
    bool? microphoneEnabled,
    bool? rtcConnected,
    bool? realtimeConnected,
    RoomConnectionGrade? grade,
    int? latencyMs,
    double? packetLossPercent,
    DateTime? updatedAt,
  }) {
    return RoomAudioSnapshot(
      configured: configured,
      route: route ?? this.route,
      availableRoutes: availableRoutes,
      microphonePermissionGranted:
          microphonePermissionGranted ?? this.microphonePermissionGranted,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      rtcConnected: rtcConnected ?? this.rtcConnected,
      realtimeConnected: realtimeConnected ?? this.realtimeConnected,
      grade: grade ?? this.grade,
      latencyMs: latencyMs ?? this.latencyMs,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
