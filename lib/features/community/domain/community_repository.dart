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
