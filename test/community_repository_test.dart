import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';

void main() {
  test(
    'guild operations target exact applications and member records',
    () async {
      final MockCommunityRepository repository = MockCommunityRepository();
      final GuildHomeSnapshot home = await repository.fetchGuildHome();
      final String guildId = home.currentGuild!.id;
      final List<GuildApplication> applications = await repository
          .fetchGuildApplications(guildId);
      final String secondId = applications[1].id;

      await repository.resolveGuildApplication(
        applicationId: secondId,
        accepted: true,
      );
      final List<GuildApplication> remaining = await repository
          .fetchGuildApplications(guildId);
      expect(
        remaining.any((GuildApplication item) => item.id == secondId),
        isFalse,
      );
      expect(
        remaining.any(
          (GuildApplication item) => item.id == applications.first.id,
        ),
        isTrue,
      );

      final GuildMember target = (await repository.fetchGuildMembers(
        guildId,
      )).firstWhere((GuildMember item) => item.recordId == 'member-3');
      await repository.setGuildMemberMuted(
        memberRecordId: target.recordId,
        muted: true,
      );
      expect(
        (await repository.fetchGuildMembers(guildId))
            .firstWhere((GuildMember item) => item.recordId == target.recordId)
            .isMuted,
        isTrue,
      );
    },
  );

  test(
    'CP, guardian, task, and activity state remains authoritative',
    () async {
      final MockCommunityRepository repository = MockCommunityRepository();
      final List<CpInvitation> invitations = await repository
          .fetchPendingCpInvitations();
      expect(invitations, hasLength(2));
      final CpInvitation invitation = invitations.first;
      await repository.resolveCpInvitation(
        invitationId: invitation.invitationId,
        accepted: true,
      );
      expect(
        (await repository.fetchCpRelations()).any(
          (CpRelation relation) => relation.userId == invitation.userId,
        ),
        isTrue,
      );
      final CpInvitation rejected = invitations.last;
      await repository.resolveCpInvitation(
        invitationId: rejected.invitationId,
        accepted: false,
      );
      expect(
        (await repository.fetchPendingCpInvitations()).where(
          (CpInvitation value) => value.invitationId == rejected.invitationId,
        ),
        isEmpty,
      );
      expect(
        (await repository.fetchCpRelations()).where(
          (CpRelation relation) => relation.userId == rejected.userId,
        ),
        isEmpty,
      );

      final String outgoingId = await repository.requestCp(20011);
      expect(outgoingId, startsWith('cp-outgoing-'));
      expect((await repository.checkCpEligibility(20011)).allowed, isFalse);
      expect(() => repository.requestCp(20011), throwsA(isA<ApiException>()));

      final GuardianFanSnapshot before = await repository.fetchGuardianFan(
        20001,
      );
      await repository.becomeGuardian(
        anchorUserId: 20001,
        levelId: before.guardianLevels.first.id,
      );
      expect(
        (await repository.fetchGuardianFan(20001)).currentGuardianLevel,
        isNotNull,
      );

      final TaskCenterSnapshot tasks = await repository.fetchTaskCenter();
      final TaskItem claimable = tasks.tasks.firstWhere(
        (TaskItem item) => item.state == TaskState.claimable,
      );
      final TaskCenterSnapshot claimed = await repository.claimTask(
        claimable.id,
      );
      expect(
        claimed.tasks
            .firstWhere((TaskItem item) => item.id == claimable.id)
            .state,
        TaskState.claimed,
      );
      expect(await repository.fetchActivities(), isNotEmpty);
    },
  );

  test(
    'duplicate or stale community actions fail instead of faking success',
    () async {
      final MockCommunityRepository repository = MockCommunityRepository();
      await repository.applyToJoinGuild('guild-2');
      expect(
        () => repository.applyToJoinGuild('guild-2'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
