import 'package:voice_social_app/features/community/domain/community_models.dart';

abstract interface class CommunityRepository {
  bool get supportsInviteAttribution;
  bool get supportsActivityCatalog;

  Future<GuildHomeSnapshot> fetchGuildHome();

  Future<List<GuildSummary>> searchGuilds(String keyword);

  Future<GuildSummary> fetchGuild(String guildId);

  Future<void> applyToJoinGuild(String guildId);

  Future<void> quitGuild(String guildId);

  Future<void> signGuild(String guildId);

  Future<List<GuildMember>> fetchGuildMembers(String guildId);

  Future<List<GuildApplication>> fetchGuildApplications(String guildId);

  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  });

  Future<void> setGuildMemberMuted({
    required String guildId,
    required int userId,
    required bool muted,
  });

  Future<void> removeGuildMember({
    required String guildId,
    required int userId,
  });

  Future<InviteAttribution> fetchInviteAttribution();

  Future<List<CpRelation>> fetchCpRelations();

  Future<List<CpInvitation>> fetchPendingCpInvitations();

  Future<CpEligibility> checkCpEligibility(int targetUserId);

  Future<String> requestCp(int targetUserId);

  Future<void> resolveCpInvitation({
    required String invitationId,
    required bool accepted,
  });

  Future<void> endCpRelation(String relationId);

  Future<GuardianFanSnapshot> fetchGuardianFan(int anchorUserId);

  Future<void> becomeGuardian({
    required int anchorUserId,
    required String levelId,
  });

  Future<void> joinFansTeam(int anchorUserId);

  Future<TaskCenterSnapshot> fetchTaskCenter();

  Future<TaskCenterSnapshot> completeDailyCheckIn();

  Future<TaskCenterSnapshot> claimTask(String taskId);

  Future<List<ThemeActivity>> fetchActivities();
}

/// Permanent compatibility tombstones for product removals on 2026-09-09.
/// No transport, state mutation, or feature switch is available here.
mixin RemovedCommunityOperations {
  Future<void> signGuild(String guildId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<List<CpRelation>> fetchCpRelations() async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<List<CpInvitation>> fetchPendingCpInvitations() async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<CpEligibility> checkCpEligibility(int targetUserId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<String> requestCp(int targetUserId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<void> resolveCpInvitation({
    required String invitationId,
    required bool accepted,
  }) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<void> endCpRelation(String relationId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<GuardianFanSnapshot> fetchGuardianFan(int anchorUserId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<void> becomeGuardian({
    required int anchorUserId,
    required String levelId,
  }) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<void> joinFansTeam(int anchorUserId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<TaskCenterSnapshot> fetchTaskCenter() async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<TaskCenterSnapshot> completeDailyCheckIn() async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<TaskCenterSnapshot> claimTask(String taskId) async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }

  Future<List<ThemeActivity>> fetchActivities() async {
    throw UnsupportedError('REMOVED_BY_PRODUCT');
  }
}
