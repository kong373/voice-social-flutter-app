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
      expect(home.currentGuildAuthority, GuildCurrentAuthority.authoritative);
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
        remaining
            .firstWhere((GuildApplication item) => item.id == secondId)
            .status,
        GuildApplicationStatus.accepted,
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
        guildId: guildId,
        userId: target.userId,
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
