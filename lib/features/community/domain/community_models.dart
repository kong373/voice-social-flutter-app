enum GuildRole {
  visitor,
  member,
  manager,
  owner,
}

extension GuildRoleLabel on GuildRole {
  String get label => switch (this) {
        GuildRole.visitor => '未加入',
        GuildRole.member => '成员',
        GuildRole.manager => '管理员',
        GuildRole.owner => '会长',
      };

  bool get canManage => this == GuildRole.manager || this == GuildRole.owner;
}

class GuildRoom {
  const GuildRoom({
    required this.roomId,
    required this.name,
    this.onlineUsers = 0,
  });

  final String roomId;
  final String name;
  final int onlineUsers;
}

class GuildSummary {
  const GuildSummary({
    required this.id,
    required this.code,
    required this.name,
    this.avatarUrl,
    this.description = '',
    this.memberCount = 0,
    this.ownerUserId = 0,
    this.ownerName = '',
    this.role = GuildRole.visitor,
    this.joined = false,
    this.applicationPending = false,
    this.hasNewApplications = false,
    this.hasSignedToday = false,
    this.rooms = const <GuildRoom>[],
  });

  final String id;
  final String code;
  final String name;
  final String? avatarUrl;
  final String description;
  final int memberCount;
  final int ownerUserId;
  final String ownerName;
  final GuildRole role;
  final bool joined;
  final bool applicationPending;
  final bool hasNewApplications;
  final bool hasSignedToday;
  final List<GuildRoom> rooms;

  GuildSummary copyWith({
    GuildRole? role,
    bool? joined,
    bool? applicationPending,
    bool? hasNewApplications,
    bool? hasSignedToday,
    int? memberCount,
  }) {
    return GuildSummary(
      id: id,
      code: code,
      name: name,
      avatarUrl: avatarUrl,
      description: description,
      memberCount: memberCount ?? this.memberCount,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      role: role ?? this.role,
      joined: joined ?? this.joined,
      applicationPending: applicationPending ?? this.applicationPending,
      hasNewApplications: hasNewApplications ?? this.hasNewApplications,
      hasSignedToday: hasSignedToday ?? this.hasSignedToday,
      rooms: rooms,
    );
  }
}

class GuildHomeSnapshot {
  const GuildHomeSnapshot({
    this.currentGuild,
    this.recommended = const <GuildSummary>[],
  });

  final GuildSummary? currentGuild;
  final List<GuildSummary> recommended;
}

class GuildMember {
  const GuildMember({
    required this.recordId,
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.role = GuildRole.member,
    this.isMuted = false,
    this.isSigned = false,
    this.roomId,
  });

  final String recordId;
  final int userId;
  final String nickname;
  final String? avatarUrl;
  final GuildRole role;
  final bool isMuted;
  final bool isSigned;
  final String? roomId;

  GuildMember copyWith({
    GuildRole? role,
    bool? isMuted,
  }) {
    return GuildMember(
      recordId: recordId,
      userId: userId,
      nickname: nickname,
      avatarUrl: avatarUrl,
      role: role ?? this.role,
      isMuted: isMuted ?? this.isMuted,
      isSigned: isSigned,
      roomId: roomId,
    );
  }
}

enum GuildApplicationStatus {
  pending,
  accepted,
  rejected,
  expired,
}

class GuildApplication {
  const GuildApplication({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.appliedAt,
    this.message = '',
    this.status = GuildApplicationStatus.pending,
  });

  final String id;
  final int userId;
  final String nickname;
  final String appliedAt;
  final String message;
  final GuildApplicationStatus status;
}

class InviteAttribution {
  const InviteAttribution({
    required this.available,
    this.inviteCode = '',
    this.channelName = '',
    this.boundAt = '',
    this.invitedUsers = 0,
    this.message = '',
  });

  final bool available;
  final String inviteCode;
  final String channelName;
  final String boundAt;
  final int invitedUsers;
  final String message;
}

class CpRelation {
  const CpRelation({
    required this.relationId,
    required this.userId,
    required this.nickname,
    required this.days,
    this.avatarUrl,
    this.boundAt = '',
  });

  final String relationId;
  final int userId;
  final String nickname;
  final String? avatarUrl;
  final int days;
  final String boundAt;
}

class CpInvitation {
  const CpInvitation({
    required this.invitationId,
    required this.userId,
    required this.nickname,
    required this.createdAt,
    this.avatarUrl,
  });

  final String invitationId;
  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String createdAt;
}

class CpEligibility {
  const CpEligibility({
    required this.allowed,
    required this.message,
  });

  final bool allowed;
  final String message;
}

class GuardianLevel {
  const GuardianLevel({
    required this.id,
    required this.name,
    required this.price,
    required this.durationDays,
    this.iconUrl,
  });

  final String id;
  final String name;
  final int price;
  final int durationDays;
  final String? iconUrl;
}

class FansTask {
  const FansTask({
    required this.id,
    required this.title,
    required this.progress,
    required this.target,
    required this.reward,
    this.claimed = false,
  });

  final String id;
  final String title;
  final int progress;
  final int target;
  final String reward;
  final bool claimed;
}

class GuardianFanSnapshot {
  const GuardianFanSnapshot({
    required this.anchorUserId,
    required this.anchorName,
    required this.guardianLevels,
    this.currentGuardianLevel,
    this.fansTeamName = '',
    this.fansLevel = 0,
    this.intimacy = 0,
    this.joinedFansTeam = false,
    this.tasks = const <FansTask>[],
  });

  final int anchorUserId;
  final String anchorName;
  final List<GuardianLevel> guardianLevels;
  final GuardianLevel? currentGuardianLevel;
  final String fansTeamName;
  final int fansLevel;
  final int intimacy;
  final bool joinedFansTeam;
  final List<FansTask> tasks;

  GuardianFanSnapshot copyWith({
    GuardianLevel? currentGuardianLevel,
    bool? joinedFansTeam,
    int? fansLevel,
    int? intimacy,
  }) {
    return GuardianFanSnapshot(
      anchorUserId: anchorUserId,
      anchorName: anchorName,
      guardianLevels: guardianLevels,
      currentGuardianLevel:
          currentGuardianLevel ?? this.currentGuardianLevel,
      fansTeamName: fansTeamName,
      fansLevel: fansLevel ?? this.fansLevel,
      intimacy: intimacy ?? this.intimacy,
      joinedFansTeam: joinedFansTeam ?? this.joinedFansTeam,
      tasks: tasks,
    );
  }
}

enum TaskState {
  inProgress,
  claimable,
  claimed,
  expired,
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.progress,
    required this.target,
    required this.reward,
    required this.state,
    this.description = '',
  });

  final String id;
  final String title;
  final String description;
  final int progress;
  final int target;
  final String reward;
  final TaskState state;

  TaskItem copyWith({TaskState? state}) {
    return TaskItem(
      id: id,
      title: title,
      description: description,
      progress: progress,
      target: target,
      reward: reward,
      state: state ?? this.state,
    );
  }
}

class CheckInDay {
  const CheckInDay({
    required this.day,
    required this.reward,
    required this.completed,
    this.today = false,
  });

  final int day;
  final String reward;
  final bool completed;
  final bool today;
}

class TaskCenterSnapshot {
  const TaskCenterSnapshot({
    required this.signedToday,
    required this.checkInDays,
    required this.tasks,
    this.continuousDays = 0,
  });

  final bool signedToday;
  final int continuousDays;
  final List<CheckInDay> checkInDays;
  final List<TaskItem> tasks;

  TaskCenterSnapshot copyWith({
    bool? signedToday,
    int? continuousDays,
    List<CheckInDay>? checkInDays,
    List<TaskItem>? tasks,
  }) {
    return TaskCenterSnapshot(
      signedToday: signedToday ?? this.signedToday,
      continuousDays: continuousDays ?? this.continuousDays,
      checkInDays: checkInDays ?? this.checkInDays,
      tasks: tasks ?? this.tasks,
    );
  }
}

enum ThemeActivityStatus {
  upcoming,
  active,
  ended,
}

extension ThemeActivityStatusLabel on ThemeActivityStatus {
  String get label => switch (this) {
        ThemeActivityStatus.upcoming => '即将开始',
        ThemeActivityStatus.active => '进行中',
        ThemeActivityStatus.ended => '已结束',
      };
}

class ThemeActivity {
  const ThemeActivity({
    required this.id,
    required this.title,
    required this.summary,
    required this.period,
    required this.status,
    this.rules = const <String>[],
    this.routeTarget,
    this.externalUrl,
  });

  final String id;
  final String title;
  final String summary;
  final String period;
  final ThemeActivityStatus status;
  final List<String> rules;
  final String? routeTarget;
  final String? externalUrl;
}
