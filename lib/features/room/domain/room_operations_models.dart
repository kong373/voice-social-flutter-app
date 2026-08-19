import 'package:voice_social_app/features/room/domain/room_models.dart';

enum RoomMemberPresence { onMic, listener }

enum MicCoordinationMode { direct, approval, unavailable }

enum MicRequestStatus { pending, accepted, rejected, expired, cancelled }

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
  const RoomTopic({required this.title, required this.content});

  final String title;
  final String content;
}

class MicAccessRequest {
  const MicAccessRequest({
    required this.id,
    required this.member,
    required this.seatNumber,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final RoomMember member;
  final int seatNumber;
  final MicRequestStatus status;
  final DateTime createdAt;
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
